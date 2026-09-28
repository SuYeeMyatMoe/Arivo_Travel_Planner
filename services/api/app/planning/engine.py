"""TripPlanner: TripIntent → a route-aware, budget-aware Living Trip.

Pipeline (each step deterministic; the LLM only narrates on top):
  resolve cities → TravelerDNA → candidate places → score + diversity → hotel by HotelTripFit →
  geographic day zones (k-means) → weather-aware zone/day assignment → per-day orienteering (OR-Tools) →
  meals near the route → timeline → budget allocation → evidence on every item.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from typing import Callable

import numpy as np

from app.core.geo import haversine_km
from app.domain.models import (
    Budget, BudgetLine, CrewMember, CrewType, Evidence, ItineraryDay, ItineraryItem, Money, Pace, Place, Provenance,
    TravelerDNA, Trip, TripIntent,
)
from app.places.providers import PlaceProvider, resolve_city_key
from app.planning.scheduler import Stop, solve_order, timeline
from app.recommendations.scoring import (
    ScoreContext, Scored, estimate_nightly, estimated_cost, explain, hotel_trip_fit, meal_adjustment, rerank_diverse,
    rough_convert, score,
)
from app.weather.providers import DayWeather, WeatherProvider

log = logging.getLogger(__name__)

SIGHTS = {"museum", "gallery", "viewpoint", "theme_park", "zoo", "aquarium", "temple", "shrine", "mosque", "landmark",
          "park", "market", "shopping", "attraction"}
FOOD = {"restaurant", "cafe", "fast_food", "food_court"}
NIGHT = {"bar", "pub", "nightclub"}
STAYS = {"hotel", "hostel", "guest_house"}

PACE = {
    Pace.SLOW: {"sights": 3, "start": time(10, 0), "buffer": 15, "dur": "deep"},
    Pace.BALANCED: {"sights": 4, "start": time(9, 30), "buffer": 10, "dur": "normal"},
    Pace.PACKED: {"sights": 6, "start": time(8, 30), "buffer": 5, "dur": "quick"},
}
DAY_END = {CrewType.FAMILY: time(20, 0)}
DEFAULT_END = time(21, 45)

# Share of a total budget by style (international trip). Domestic trips drop flights and renormalise.
BUDGET_SHARES = {"flights": 0.30, "accommodation": 0.28, "food": 0.17, "transport": 0.07, "activities": 0.08,
                 "shopping": 0.05, "buffer": 0.05}


class PlanningError(Exception):
    def __init__(self, code: str, message: str, detail: dict | None = None):
        super().__init__(message)
        self.code = code
        self.detail = detail or {}


@dataclass
class PlannerDeps:
    places: PlaceProvider
    weather: WeatherProvider | None = None
    trends: dict[str, float] = field(default_factory=dict)  # place_id → TrendScore (only with evidence)
    today: Callable[[], date] = date.today


def dna_from_intent(intent: TripIntent, base: TravelerDNA | None = None) -> TravelerDNA:
    d = (base or TravelerDNA()).model_dump()
    for k in intent.interests:
        if k in d:
            d[k] = max(d[k], 0.9)
    for k in intent.avoid:
        if k in d:
            d[k] = 0.05
    d["travelPace"] = {Pace.SLOW: 0.2, Pace.BALANCED: 0.5, Pace.PACKED: 0.85}[intent.pace]
    if intent.crew_type == CrewType.FAMILY:
        d["walkingTolerance"] = min(d["walkingTolerance"], 0.4)
        d["nightlife"] = min(d["nightlife"], 0.15)
    if intent.crew_type == CrewType.FRIENDS and "nightlife" not in intent.avoid:
        d["nightlife"] = max(d["nightlife"], 0.45)
    if intent.budget_amount is not None and intent.budget_currency == "MYR" and intent.budget_amount / max(1, intent.days or 3) < 250:
        d["budgetSensitivity"] = max(d["budgetSensitivity"], 0.8)
    return TravelerDNA(**d)


def allocate_budget(total: Money, international: bool) -> Budget:
    shares = dict(BUDGET_SHARES)
    if not international:
        shares.pop("flights")
    s = sum(shares.values())
    lines = [BudgetLine(category=k, planned=total.scale(v / s), reserved=Money.zero(total.currency),
                        spent=Money.zero(total.currency), provenance=Provenance.EST) for k, v in shares.items()]
    return Budget(total=total, lines=lines)


def kmeans_zones(places: list[Place], k: int, seed: int = 7) -> list[list[Place]]:
    """Geographic day zones. Balanced-ish k-means on an equirectangular projection."""
    if k <= 1 or len(places) <= k:
        return [places] if k <= 1 else [[p] for p in places] + [[] for _ in range(k - len(places))]
    lat0 = math.radians(sum(p.lat for p in places) / len(places))
    pts = np.array([[p.lat, p.lon * math.cos(lat0)] for p in places])
    rng = np.random.default_rng(seed)
    # k-means++ seeding weighted towards high-value (iconic) places so zones form around anchors
    centers = [pts[int(np.argmax([p.iconic for p in places]))]]
    while len(centers) < k:
        d2 = np.min([((pts - c) ** 2).sum(axis=1) for c in centers], axis=0)
        centers.append(pts[rng.choice(len(pts), p=d2 / d2.sum())])
    c = np.array(centers)
    cap = math.ceil(len(places) / k) + 1
    for _ in range(25):
        dist = ((pts[:, None, :] - c[None, :, :]) ** 2).sum(axis=2)
        assign = -np.ones(len(pts), dtype=int)
        counts = np.zeros(k, dtype=int)
        for i in np.argsort(dist.min(axis=1)):  # capacity-aware greedy assignment keeps days balanced
            for j in np.argsort(dist[i]):
                if counts[j] < cap:
                    assign[i], counts[j] = j, counts[j] + 1
                    break
        new_c = np.array([pts[assign == j].mean(axis=0) if (assign == j).any() else c[j] for j in range(k)])
        if np.allclose(new_c, c):
            break
        c = new_c
    return [[places[i] for i in range(len(places)) if assign[i] == j] for j in range(k)]


class TripPlanner:
    def __init__(self, deps: PlannerDeps):
        self.deps = deps
        self._lanes: dict[str, str] = {}

    # ---------------------------------------------------------------------------------------------------- discovery
    @staticmethod
    def _worthy(p: Place) -> bool:
        """A stop needs verifiable information behind it: notability, or a proper venue type with details."""
        visitor_tagged = bool(p.tags.get("tourism")) or p.category in {"temple", "shrine", "mosque", "park", "market", "shopping"}
        if p.category in {"attraction", "landmark"} and not visitor_tagged:
            return p.notability >= 12  # e.g. survey benchmarks or office towers with wiki pages aren't sights
        if p.iconic > 0:
            return True
        if p.category in {"museum", "gallery", "viewpoint", "theme_park", "aquarium", "zoo", "market"}:
            return p.quality >= 2 or p.dna.get("anime", 0) > 0
        return p.quality >= 3 or (p.dna.get("anime", 0) > 0 and p.quality >= 2)

    @staticmethod
    def _core(places: list[Place]) -> tuple[float, float] | None:
        """Weighted centre of the city's most notable places — where first-time visitors spend their days."""
        top = sorted(places, key=lambda p: -p.iconic)[:40]
        if not top:
            return None
        w = [0.2 + p.iconic for p in top]
        return (sum(p.lat * x for p, x in zip(top, w)) / sum(w), sum(p.lon * x for p, x in zip(top, w)) / sum(w))

    def _select_lanes(self, scored: list[Scored], k: int, iconic_local: float) -> tuple[list[Scored], dict[str, str]]:
        """ICONIC · LOCAL · PULSE · FOR YOU, mixed on purpose. The Iconic↔Local slider (−1…1) moves the quotas."""
        s = max(-1.0, min(1.0, iconic_local))
        q_iconic = max(0, round(k * (0.40 - 0.28 * s)))
        q_local = max(0, round(k * (0.22 + 0.28 * s)))
        q_pulse = min(2, sum(1 for x in scored if x.components["trend"] > 0))
        lanes: dict[str, str] = {}
        chosen: list[Scored] = []

        def take(pool: list[Scored], n: int, lane: str) -> None:
            pool = [x for x in pool if x.place.id not in lanes]
            for x in rerank_diverse(pool, n):
                lanes[x.place.id] = lane
                chosen.append(x)

        take(sorted((x for x in scored if x.place.iconic >= 0.5), key=lambda x: -(0.65 * x.place.iconic + 0.35 * x.total))[: q_iconic * 2], q_iconic, "iconic")
        take(sorted((x for x in scored if x.components["trend"] > 0), key=lambda x: -x.total), q_pulse, "pulse")
        take(sorted((x for x in scored if x.place.iconic < 0.2), key=lambda x: -x.total)[: q_local * 4], q_local, "local")
        take(sorted(scored, key=lambda x: -(x.total + 0.12 * x.place.iconic))[: k * 4], k - len(chosen), "for_you")
        return chosen, lanes

    # ---------------------------------------------------------------------------------------------------- public
    async def build(self, intent: TripIntent, owner_id: str, *, base_dna: TravelerDNA | None = None,
                    crew: list[CrewMember] | None = None, iconic_local: float = 0.0) -> Trip:
        cities = self._resolve_cities(intent)
        warnings: list[str] = []
        total_days = intent.days or 3
        if intent.days is None:
            warnings.append("Trip length not given — planned 3 days. Change it any time.")
        start = intent.start_date or (self.deps.today() + timedelta(days=21))
        if intent.start_date is None:
            warnings.append("Dates not set — using a placeholder start date; weather and hours will refresh once you pick dates.")
        city_days = self._allocate_days(cities, total_days, warnings)
        dna = dna_from_intent(intent, base_dna)
        info = self.deps.places.city(cities[0])
        currency_home = intent.budget_currency or ("MYR" if (intent.origin or "").lower() in {"kuala lumpur", ""} else "USD")
        local_currency = info["currency"]
        international = (intent.origin or "Kuala Lumpur").lower() not in {c.lower() for c in intent.destinations} and info["country"] != "MY"
        crew_size = intent.crew_size
        budget = None
        if intent.budget_amount:
            total = Money.of(intent.budget_amount * (crew_size if intent.budget_per_person else 1), currency_home)
            budget = allocate_budget(total, international)
        else:
            warnings.append("No budget given — costs are shown as estimates without a cap.")

        trip = Trip(owner_id=owner_id, title=self._title(intent, cities, total_days), intent=intent, cities=cities,
                    start_date=start, timezone=info["tz"], currency=local_currency, home_currency=currency_home, dna=dna,
                    crew=crew or [], crew_type=intent.crew_type, budget=budget, warnings=warnings)

        day_cursor = 0
        for ci, (city, n_days) in enumerate(city_days):
            cinfo = self.deps.places.city(city)
            weather = await self._weather(cinfo, start + timedelta(days=day_cursor), n_days)
            days, hotel_id = self._plan_city(trip, city, cinfo, n_days, day_cursor, weather, iconic_local)
            if ci == 0:
                trip.hotel_place_id = hotel_id
            if ci > 0 and days:  # inter-city transfer at the start of the first day in the new city
                prev = cities[ci - 1]
                days[0].items.insert(0, self._transfer_item(prev, city, days[0]))
                days[0].title = f"{self.deps.places.city(prev)['name']} → {cinfo['name']} · {days[0].title}"
            trip.days.extend(days)
            day_cursor += n_days
        self._rollup_budget(trip)
        return trip

    # ---------------------------------------------------------------------------------------------------- steps
    def _resolve_cities(self, intent: TripIntent) -> list[str]:
        if not intent.destinations:
            raise PlanningError("need_destination", "Where should we go?", {"ask": "destination"})
        keys, unknown = [], []
        for d in intent.destinations:
            k = resolve_city_key(d)
            if k and self.deps.places.city(k):
                if k not in keys:
                    keys.append(k)
            elif d.lower() == "japan":
                keys.extend([x for x in ("tokyo", "kyoto") if x not in keys])
            else:
                unknown.append(d)
        if not keys:
            supported = [c["name"] for c in self.deps.places.cities()]
            raise PlanningError("coverage", f"Arivo doesn't have verified place data for {', '.join(unknown)} yet.",
                                {"unsupported": unknown, "supported": supported})
        return keys

    def _allocate_days(self, cities: list[str], total: int, warnings: list[str]) -> list[tuple[str, int]]:
        if len(cities) == 1:
            return [(cities[0], total)]
        if total < 2 * len(cities):
            keep = max(1, total // 2)
            warnings.append(f"{len(cities)} cities in {total} days means more time on trains than exploring — "
                            f"planned {', '.join(cities[:keep])} and moved the rest to 'maybe'.")
            cities = cities[:keep]
            if len(cities) == 1:
                return [(cities[0], total)]
        base = total // len(cities)
        extra = total - base * len(cities)
        return [(c, base + (1 if i < extra else 0)) for i, c in enumerate(cities)]

    async def _weather(self, cinfo: dict, start: date, days: int) -> dict[date, DayWeather]:
        if not self.deps.weather:
            return {}
        s, w, n, e = cinfo["bbox"]
        horizon = self.deps.today() + timedelta(days=15)
        if start > horizon:
            return {}
        try:
            got = await self.deps.weather.forecast((s + n) / 2, (w + e) / 2, cinfo["tz"], start, min(days, (horizon - start).days + 1))
            return {d.date: d for d in got}
        except Exception as e:  # noqa: BLE001 — weather is an enhancement, never a blocker
            log.warning("weather unavailable: %s", e)
            return {}

    def _plan_city(self, trip: Trip, city: str, cinfo: dict, n_days: int, day_offset: int,
                   weather: dict[date, DayWeather], iconic_local: float) -> tuple[list[ItineraryDay], str | None]:
        intent, dna = trip.intent, trip.dna
        pace = PACE[intent.pace]
        country = cinfo["country"]
        per_day = pace["sights"]
        # 1) candidates: only places with verifiable information; focus on the city's dense core so days stay walkable
        sights = [p for p in self.deps.places.search(city, categories=SIGHTS, limit=5000) if self._worthy(p)]
        if country != "MY":
            sights = [p for p in sights if p.category != "mosque" or p.iconic > 0.3]
        core = self._core(sights)
        ctx = ScoreContext(dna=dna, anchor=core, crew=trip.crew, trend=self.deps.trends, iconic_local=iconic_local,
                           country=country, geo_scale_km=7.0)
        scored = [score(p, ctx, trip.currency) for p in sights]
        picks, lanes = self._select_lanes(scored, n_days * per_day + max(2, n_days), iconic_local)
        must_names = [m.lower() for m in intent.must_do]
        for m in must_names:
            hit = next((s for s in scored if m in s.place.name.lower()), None)
            if hit and hit not in picks:
                picks.append(hit)
                lanes[hit.place.id] = "for_you"
        self._lanes.update(lanes)
        by_id = {s.place.id: s for s in picks}
        # 2) hotel by where the trip actually goes, within the accommodation budget
        stays = self.deps.places.search(city, categories=STAYS, limit=2000)
        stations = self.deps.places.search(city, categories={"station"}, limit=2000)
        hotel = None
        nightly_budget = None
        rooms = max(1, math.ceil(intent.crew_size / 2))
        if trip.budget:
            acc = next(line for line in trip.budget.lines if line.category == "accommodation").planned
            nights = max(1, (intent.days or 3) - 1)
            nightly_budget = rough_convert(acc, trip.currency).scale(1 / (nights * rooms))
        if stays:
            affordable = [h for h in stays if not nightly_budget or estimate_nightly(h, trip.currency).amount_minor <= nightly_budget.amount_minor * 1.4] or stays
            ranked = sorted((hotel_trip_fit(h, [s.place for s in picks], stations, dna, country, nightly_budget=nightly_budget) for h in affordable),
                            key=lambda f: -f.score)
            hotel = ranked[0].place
            est = estimate_nightly(hotel, trip.currency)
            trip.warnings.append(f"Stay suggestion: {hotel.name} — {ranked[0].sentence} (Location Fit {ranked[0].location_fit}%, "
                                 f"≈{est.display()}/room/night estimate).")
        # 3) zones, weather-aware day assignment
        zones = kmeans_zones([s.place for s in picks], n_days)
        # top up thin zones with the best unused sights near the zone, so no day is half-empty
        used = {s.place.id for s in picks}
        for z in zones:
            if not z or len(z) >= per_day:
                continue
            cz = (sum(p.lat for p in z) / len(z), sum(p.lon for p in z) / len(z))
            near = sorted((s for s in scored if s.place.id not in used and haversine_km(cz[0], cz[1], s.place.lat, s.place.lon) <= 2.2),
                          key=lambda s: -s.total)
            for s in rerank_diverse(near[:20], per_day - len(z)):
                z.append(s.place)
                used.add(s.place.id)
                by_id[s.place.id] = s
                self._lanes.setdefault(s.place.id, "for_you")
        dates = [trip.start_date + timedelta(days=day_offset + i) for i in range(n_days)]
        rain = {d: (weather[d].summary()["max_precip_prob"] if d in weather else None) for d in dates}
        indoor_share = [sum(p.indoor for p in z) / len(z) if z else 0 for z in zones]
        order_days = sorted(range(n_days), key=lambda i: -(rain[dates[i]] or 0))
        order_zones = sorted(range(len(zones)), key=lambda j: -indoor_share[j])
        zone_for_day = {d: order_zones[i] for i, d in enumerate(order_days)}
        used_food: set[str] = set()
        days: list[ItineraryDay] = []
        for i, d in enumerate(dates):
            zone = sorted(zones[zone_for_day[i]], key=lambda p: -by_id[p.id].total)[: per_day + 1]
            day = self._plan_day(trip, city, cinfo, d, day_offset + i, zone, by_id, hotel, weather.get(d), used_food, iconic_local)
            days.append(day)
        return days, hotel.id if hotel else None

    def _plan_day(self, trip: Trip, city: str, cinfo: dict, d: date, index: int, zone: list[Place], by_id: dict,
                  hotel: Place | None, wx: DayWeather | None, used_food: set[str], iconic_local: float) -> ItineraryDay:
        intent, dna, country = trip.intent, trip.dna, cinfo["country"]
        pace = PACE[intent.pace]
        day_start = datetime.combine(d, pace["start"])
        end_t = DAY_END.get(intent.crew_type, DEFAULT_END)
        day_len = int((datetime.combine(d, end_t) - day_start).total_seconds() // 60)
        origin_place = hotel or (zone[0] if zone else None)
        origin = Stop("origin", origin_place.lat, origin_place.lon, 0, (0, day_len)) if origin_place else Stop("origin", None, None, 0, (0, day_len))
        stops: list[Stop] = []
        for p in zone:
            dur = self._duration(p, pace["dur"], intent.crew_type)
            win = self._window(p, d, day_start, day_len)
            s = by_id[p.id]
            stops.append(Stop(p.id, p.lat, p.lon, dur, win, priority=min(1.0, s.total + 0.3 * p.iconic),
                              must=any(m.lower() in p.name.lower() for m in intent.must_do), payload=p))
        # meal/night slots are placed at the zone's centre while routing (so they cost realistic travel),
        # then resolved to a real venue near wherever the traveller actually is at that time
        zc = (sum(p.lat for p in zone) / len(zone), sum(p.lon for p in zone) / len(zone)) if zone else (origin.lat, origin.lon)
        offset_h = pace["start"].hour + pace["start"].minute / 60
        lunch = Stop("meal:lunch", zc[0], zc[1], 60 if intent.pace != Pace.PACKED else 45,
                     (int((11.75 - offset_h) * 60), int((14.0 - offset_h) * 60)), priority=0.9, must=True)
        dinner_open = int((18.25 - offset_h) * 60)
        dinner = Stop("meal:dinner", zc[0], zc[1], 75, (dinner_open, dinner_open + 150), priority=0.9, must=True)
        extra = [lunch, dinner]
        wants_night = dna.nightlife >= 0.6 and intent.crew_type != CrewType.FAMILY
        if wants_night:
            extra.append(Stop("night", zc[0], zc[1], 75, (dinner_open + 120, day_len), priority=0.6))
        ordered, dropped, solver = solve_order(origin, stops + extra, day_len, country, dna.walkingTolerance, pace["buffer"])
        # resolve virtual stops to real venues near where the traveller will be
        resolved: list[Stop] = []
        last = origin
        for s in ordered:
            if s.payload is None and s.key.startswith(("meal", "night")):
                when = day_start + timedelta(minutes=s.window[0])
                venue = self._pick_venue(city, last, when, used_food, trip, iconic_local, night=s.key == "night")
                if venue:
                    used_food.add(venue.id)
                    s = Stop(s.key, venue.lat, venue.lon, s.duration, s.window, s.priority, s.must, payload=venue)
                else:
                    continue
            resolved.append(s)
            if s.lat is not None:
                last = s
        plan = timeline(origin, resolved, day_start, day_len, country, dna.walkingTolerance, pace["buffer"])
        items: list[ItineraryItem] = []
        rain_prob = wx.summary()["max_precip_prob"] if wx else None
        for sch in plan.scheduled:
            p: Place = sch.stop.payload
            kind = "meal" if sch.stop.key.startswith("meal") else "night" if sch.stop.key == "night" else "sight"
            ctx = ScoreContext(dna=dna, anchor=None, slot_start=sch.start, duration_min=sch.stop.duration, rain_prob=rain_prob,
                               crew=trip.crew, trend=self.deps.trends, iconic_local=iconic_local, country=country)
            sc = score(p, ctx, trip.currency)
            ev = explain(sc, dna)
            if sch.leg:
                ev.insert(0, Evidence(text=f"{sch.leg.minutes} min {'walk' if sch.leg.mode == 'walk' else 'by transit'} from previous stop", provenance=Provenance.EST))
            items.append(ItineraryItem(
                place_id=p.id, name=p.name, category=p.category, lat=p.lat, lon=p.lon, start=sch.start,
                duration_min=sch.stop.duration, leg=sch.leg, leg_cost=sch.leg_cost, cost=estimated_cost(p, trip.currency), reason=self._reason(p, kind, sc, ev),
                evidence=ev[:5], score=sc.total, indoor=p.indoor, kind=kind, priority=sch.stop.priority,
                lane=self._lanes.get(p.id) if kind == "sight" else None,
            ))
        centroid = (sum(i.lat for i in items) / len(items), sum(i.lon for i in items) / len(items)) if items else (origin.lat, origin.lon)
        area = getattr(self.deps.places, "nearest_area", lambda *a, **k: None)(city, *centroid) if items else None
        anchors = sorted([i for i in items if i.kind == "sight"], key=lambda i: -(by_id[i.place_id].place.iconic if i.place_id in by_id else 0))
        title = area or (f"Around {anchors[0].name}" if anchors else cinfo["name"])
        if area and anchors:
            second = getattr(self.deps.places, "nearest_area", lambda *a, **k: None)(city, anchors[-1].lat, anchors[-1].lon, 1.2)
            if second and second != area:
                title = f"{area} / {second}"
        day = ItineraryDay(index=index, date=d, zone=cinfo["name"], title=title, route_color=index % 8, items=items,
                           weather=wx.summary() if wx else None)
        for s, why in plan.dropped:
            if isinstance(s.payload, Place) and s.must:
                trip.warnings.append(f"Couldn't fit must-do {s.payload.name} on day {index + 1}: {why}.")
        return day

    # ---------------------------------------------------------------------------------------------------- helpers
    def _duration(self, p: Place, mode: str, crew: CrewType) -> int:
        q, n, dp = p.duration_min or (40, 60, 90)
        base = {"quick": (q + n) / 2, "normal": n, "deep": min(dp, n * 1.2)}[mode]
        if crew == CrewType.FAMILY:
            base *= 1.1
        return int(round(base / 5) * 5)

    def _window(self, p: Place, d: date, day_start: datetime, day_len: int) -> tuple[int, int]:
        from app.places.hours import parse

        hours = parse(p.tags.get("opening_hours"))
        if hours.by_day is None:
            # unverified hours: assume typical opening, never evenings (the UI marks these "hours not verified")
            typical = {"museum": (time(10), time(17)), "gallery": (time(10), time(18)), "aquarium": (time(10), time(18)),
                       "zoo": (time(9, 30), time(16, 30)), "shopping": (time(10), time(20)), "market": (time(9), time(18))}
            open_t, close_t = typical.get(p.category, (time(9), time(18, 30)))
            lo = max(0, int((datetime.combine(d, open_t) - day_start).total_seconds() // 60))
            hi = min(day_len, int((datetime.combine(d, close_t) - day_start).total_seconds() // 60))
            return lo, max(lo, hi)
        ranges = hours.by_day.get(d.weekday(), [])
        if not ranges:
            return day_len, day_len  # closed today → solver drops it
        start_min = day_start.hour * 60 + day_start.minute
        lo = max(0, ranges[0][0] - start_min)
        hi = min(day_len, ranges[-1][1] - start_min)
        return lo, max(lo, hi)

    def _pick_venue(self, city: str, near: Stop, when: datetime, used: set[str], trip: Trip, iconic_local: float,
                    night: bool = False) -> Place | None:
        if near.lat is None:
            return None
        if night:
            cats = NIGHT
        elif when.hour < 15:
            cats = {"restaurant", "food_court", "fast_food"} | ({"cafe"} if trip.dna.relaxation > 0.7 else set())
        else:
            cats = {"restaurant", "food_court"}
        cand = [p for p in self.deps.places.search(city, categories=cats, near=(near.lat, near.lon), radius_km=0.9, limit=80) if p.id not in used]
        if len(cand) < 5:
            cand = [p for p in self.deps.places.search(city, categories=cats, near=(near.lat, near.lon), radius_km=2.0, limit=120) if p.id not in used]
        diet = set(trip.intent.dietary)
        if diet:
            key = {"vegetarian": "diet:vegetarian", "vegan": "diet:vegan", "halal": "diet:halal", "gluten_free": "diet:gluten_free"}
            ok = [p for p in cand if all(p.tags.get(key[x]) in {"yes", "only"} for x in diet if x in key)]
            if ok:
                cand = ok
            else:
                trip.warnings.append(f"No verified {', '.join(sorted(diet))} venue near a meal on {when.date():%a %d %b} — check tags before you go.")
        if not night and when.hour < 15:
            cand = [p for p in cand if p.category != "bar"] or cand
        meal_budget = None
        if trip.budget:  # per-person, per-meal share of the food line (≈2.2 paid meals a day)
            food = next(line for line in trip.budget.lines if line.category == "food").planned
            meal_budget = rough_convert(food, trip.currency).scale(1 / (max(1, trip.intent.days or 3) * 2.2 * trip.intent.crew_size))
        ctx = ScoreContext(dna=trip.dna, anchor=(near.lat, near.lon), slot_start=when, duration_min=60, crew=trip.crew,
                           trend=self.deps.trends, iconic_local=iconic_local, geo_scale_km=0.8, activity_budget=meal_budget)
        country = (self.deps.places.city(city) or {}).get("country", "DEFAULT")
        ranked = sorted(((score(p, ctx, trip.currency), p) for p in cand), key=lambda sp: -(sp[0].total + meal_adjustment(sp[1], trip.dna, country)))
        return ranked[0][1] if ranked else None

    def _reason(self, p: Place, kind: str, sc, ev: list[Evidence]) -> str:
        if kind == "meal":
            cuisine = p.tags.get("cuisine", "").replace(";", ", ").replace("_", " ")
            base = f"{cuisine.title()} near your route" if cuisine else "Near your route"
            return f"{base} · {sc.notes.get('schedule', '')}".strip(" ·")
        if kind == "night":
            return "Evening pick for your crew's nightlife interest"
        top = next((e.text for e in ev if e.provenance in (Provenance.YOU, Provenance.LIVE)), ev[0].text if ev else "")
        return top

    def _transfer_item(self, from_city: str, to_city: str, day: ItineraryDay) -> ItineraryItem:
        a, b = self.deps.places.city(from_city), self.deps.places.city(to_city)
        (s1, w1, n1, e1), (s2, w2, n2, e2) = a["bbox"], b["bbox"]
        km = haversine_km((s1 + n1) / 2, (w1 + e1) / 2, (s2 + n2) / 2, (w2 + e2) / 2)
        minutes = int(km / 200 * 60 + 60) if a["country"] == b["country"] == "JP" else int(km / 80 * 60 + 45)
        first = day.items[0].start if day.items else datetime.combine(day.date, time(10))
        start = first - timedelta(minutes=minutes + 30)
        return ItineraryItem(place_id=f"transfer:{from_city}:{to_city}", name=f"{a['name']} → {b['name']}", category="transfer",
                             lat=(s2 + n2) / 2, lon=(w2 + e2) / 2, start=start, duration_min=minutes, kind="transfer",
                             reason="Compare train, bus and flight in Book → Bus/Train", priority=1.0,
                             evidence=[Evidence(text=f"≈{round(km)} km; door-to-door estimate", provenance=Provenance.EST)])

    def _title(self, intent: TripIntent, cities: list[str], days: int) -> str:
        names = [self.deps.places.city(c)["name"] for c in cities]
        who = {CrewType.SOLO: "", CrewType.COUPLE: " for two", CrewType.FRIENDS: f" with {intent.crew_size - 1} friends",
               CrewType.FAMILY: " with family"}[intent.crew_type]
        return f"{' → '.join(names)} · {days} days{who}"

    def _rollup_budget(self, trip: Trip) -> None:
        """Nothing to do here: the Budget Brain (app.budget.brain) forecasts with live FX when the trip is read."""
        return None
