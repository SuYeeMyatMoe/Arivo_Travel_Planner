"""Recommendation, trend and hotel scoring. Deterministic, explainable, unit-tested with the spec's exact weights.

    RecommendationScore = 0.30·PreferenceMatch + 0.17·ScheduleFit + 0.13·GeographicFit + 0.10·BudgetFit
                        + 0.08·WeatherFit + 0.07·CrewFit + 0.15·TrendScore

Every component is 0..1. `explain()` turns the largest contributors into Why-This evidence.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from app.core.geo import estimate_leg, haversine_km
from app.domain.models import CrewMember, Evidence, Money, Place, Provenance, TravelerDNA
from app.places.hours import OpenState, parse

WEIGHTS = {
    "preference": 0.30,
    "schedule": 0.17,
    "geographic": 0.13,
    "budget": 0.10,
    "weather": 0.08,
    "crew": 0.07,
    "trend": 0.15,
}
assert abs(sum(WEIGHTS.values()) - 1.0) < 1e-9


@dataclass
class ScoreContext:
    dna: TravelerDNA
    anchor: tuple[float, float] | None = None  # previous stop / zone centroid
    slot_start: datetime | None = None
    duration_min: int | None = None
    activity_budget: Money | None = None  # what this slot can spend
    rain_prob: int | None = None  # 0..100 for the slot
    crew: list[CrewMember] = field(default_factory=list)
    trend: dict[str, float] = field(default_factory=dict)  # place_id → TrendScore 0..100 (only with evidence)
    iconic_local: float = 0.0  # −1 iconic … 0 balanced … +1 local
    country: str = "DEFAULT"
    geo_scale_km: float = 2.5


@dataclass
class Scored:
    place: Place
    total: float
    components: dict[str, float]
    notes: dict[str, str]

    @property
    def match_pct(self) -> int:
        return round(self.total * 100)


def preference_match(dna: TravelerDNA, place: Place, iconic_local: float = 0.0) -> float:
    """Weighted mean of the traveller's interest in the dimensions this place serves, blended with Iconic↔Local fit."""
    interests = dna.interests()
    dims = {k: w for k, w in place.dna.items() if k in interests}
    if not dims:
        interest = 0.35
    else:
        interest = sum(interests[k] * w for k, w in dims.items()) / sum(dims.values())
        # a strong single interest (e.g. anime=1.0) should dominate, not be averaged away
        interest = max(interest, max(interests[k] * w for k, w in dims.items()))
    target_iconic = (1 - iconic_local) / 2  # −1 → 1.0 (iconic), +1 → 0.0 (local)
    tol = dna.touristTolerance
    iconic_fit = 1 - abs(place.iconic - target_iconic)
    if place.iconic > 0.6 and tol < 0.3:
        iconic_fit *= 0.6
    return max(0.0, min(1.0, 0.78 * interest + 0.22 * iconic_fit))


def schedule_fit(place: Place, start: datetime | None, duration_min: int | None) -> tuple[float, str]:
    if not start or not duration_min:
        return 0.75, "no slot yet"
    hours = parse(place.tags.get("opening_hours"))
    state = hours.open_between(start, start + timedelta(minutes=duration_min))
    if state == OpenState.OPEN:
        closes = hours.closes_at(start)
        return 1.0, f"open until {closes.strftime('%H:%M')}" if closes else "open during your visit"
    if state == OpenState.CLOSED:
        return 0.0, "closed at that time"
    # unknown hours: parks/viewpoints/shrine grounds are usually accessible in daytime, indoor venues less certain
    daytime = 8 <= start.hour <= 17
    return (0.75 if (not place.indoor and daytime) else 0.6), "hours not verified"


def geographic_fit(place: Place, anchor: tuple[float, float] | None, scale_km: float) -> tuple[float, float | None]:
    if not anchor:
        return 0.7, None
    d = haversine_km(anchor[0], anchor[1], place.lat, place.lon)
    return math.exp(-d / scale_km), d


def estimated_cost(place: Place, currency: str) -> Money:
    """Coarse per-person estimate by category when no live price exists (always shown as EST.)."""
    table_jpy = {"museum": 1200, "gallery": 1000, "theme_park": 8500, "zoo": 600, "aquarium": 2500, "viewpoint": 2000,
                 "restaurant": 2500, "cafe": 900, "fast_food": 900, "food_court": 1300, "bar": 2500, "pub": 2500,
                 "nightclub": 3500, "market": 1500, "shopping": 3000, "attraction": 800}
    fee = place.tags.get("fee")
    if fee == "no" and not place.is_food:
        return Money.zero(currency)
    base = table_jpy.get(place.category, 0)
    if place.category in {"temple", "shrine", "park", "landmark", "mosque"} and fee != "yes":
        base = 0
    fine = any(w in place.tags.get("cuisine", "").lower() for w in ("haute", "fine_dining", "kaiseki", "french", "omakase"))
    if place.category == "restaurant" and (place.iconic > 0.3 or fine):
        base = 15000  # restaurants famous enough for Wikipedia are usually fine dining (and need reservations)
    elif place.category == "restaurant" and place.tags.get("brand"):
        base = 1300  # chain restaurants
    rates = {"JPY": 1.0, "MYR": 0.0295, "USD": 0.0067}
    return Money.of(base * rates.get(currency, 0.0067), currency)


ROUGH_TO_JPY = {"JPY": 1.0, "MYR": 34.0, "USD": 150.0, "EUR": 162.0, "SGD": 112.0}


def rough_convert(m: Money, currency: str) -> Money:
    """Planning-time conversion for comparisons only (shown as EST). Checkout always uses supplier prices."""
    if m.currency == currency:
        return m
    jpy = m.amount * ROUGH_TO_JPY.get(m.currency, 150.0)
    return Money.of(jpy / ROUGH_TO_JPY.get(currency, 150.0), currency)


def estimate_nightly(place: Place, currency: str) -> Money:
    """Per-room nightly estimate by stay type and OSM stars (EST until a supplier quotes a real rate)."""
    stars = float(place.tags.get("stars", "0") or 0)
    if place.city in {"tokyo", "kyoto"}:
        jpy = {"hostel": 4200, "guest_house": 7800}.get(place.category, 11000 + stars * 4200)
    else:
        jpy = {"hostel": 45, "guest_house": 95}.get(place.category, 160 + stars * 70) * ROUGH_TO_JPY["MYR"]
    name = place.name.lower()
    if not stars and place.category == "hotel":
        jpy *= 1 + min(2.0, place.notability / 10)  # famous hotels without a stars tag are rarely budget hotels
    if any(w in name for w in ("aman", "ritz", "four seasons", "mandarin oriental", "peninsula", "park hyatt", "palace hotel", "bulgari")):
        jpy = max(jpy, 90000)  # luxury flagships rarely carry a stars tag in OSM
    return rough_convert(Money.of(jpy, "JPY"), currency)


LOCAL_CUISINE = {
    "JP": {"ramen", "sushi", "japanese", "izakaya", "yakitori", "tempura", "soba", "udon", "tonkatsu", "okonomiyaki",
           "yakiniku", "kaiseki", "gyoza", "curry", "donburi", "takoyaki", "monjayaki", "wagashi", "unagi"},
    "MY": {"malaysian", "malay", "nasi_lemak", "mamak", "chinese", "indian", "nyonya", "peranakan", "satay", "hawker", "dim_sum"},
}


def meal_adjustment(place: Place, dna: TravelerDNA, country: str) -> float:
    """Food lovers get the local kitchen, not the chain they have at home."""
    cuisines = {c.strip().lower() for c in place.tags.get("cuisine", "").split(";") if c.strip()}
    adj = 0.0
    if cuisines & LOCAL_CUISINE.get(country, set()):
        adj += 0.06 + 0.06 * dna.food
    if place.tags.get("brand"):
        adj -= 0.04 + 0.06 * max(dna.food, dna.localDiscovery)
    if place.iconic > 0.2:
        adj += 0.04
    if place.category == "fast_food":
        adj -= 0.05 * dna.food
    return adj


def budget_fit(cost: Money, budget: Money | None, sensitivity: float) -> float:
    if not budget or budget.amount_minor <= 0:
        return 0.8
    ratio = cost.amount_minor / budget.amount_minor
    if ratio <= 1:
        return 1.0 - 0.15 * ratio * sensitivity
    return max(0.0, 1.0 - (ratio - 1) * (0.8 + sensitivity))


def weather_fit(place: Place, rain_prob: int | None) -> float:
    if rain_prob is None:
        return 0.8
    wet = rain_prob / 100
    return 1.0 - 0.1 * wet if place.indoor else 1.0 - 0.9 * wet


def crew_fit(place: Place, crew: list[CrewMember], iconic_local: float) -> tuple[float, float]:
    """Mean member match minus a spread penalty, so one person's passion can't hide three people's boredom."""
    if not crew:
        return 0.8, 0.0
    matches = [preference_match(m.dna, place, iconic_local) for m in crew]
    mean = sum(matches) / len(matches)
    spread = max(matches) - min(matches)
    return max(0.0, mean - 0.35 * spread), spread


def score(place: Place, ctx: ScoreContext, currency: str) -> Scored:
    notes: dict[str, str] = {}
    pref = preference_match(ctx.dna, place, ctx.iconic_local)
    sched, notes["schedule"] = schedule_fit(place, ctx.slot_start, ctx.duration_min)
    geo, dist = geographic_fit(place, ctx.anchor, ctx.geo_scale_km)
    if dist is not None:
        leg, _ = estimate_leg(ctx.anchor[0], ctx.anchor[1], place.lat, place.lon, ctx.country, ctx.dna.walkingTolerance)
        notes["geographic"] = f"{leg.minutes} min {'walk' if leg.mode == 'walk' else 'by transit'} from your previous stop"
    cost = estimated_cost(place, currency)
    bud = budget_fit(cost, ctx.activity_budget, ctx.dna.budgetSensitivity)
    notes["budget"] = "free entry" if cost.amount_minor == 0 else f"about {cost.display()} per person"
    wea = weather_fit(place, ctx.rain_prob)
    crew, spread = crew_fit(place, ctx.crew, ctx.iconic_local)
    trend = ctx.trend.get(place.id, 0.0) / 100
    comps = {"preference": pref, "schedule": sched, "geographic": geo, "budget": bud, "weather": wea, "crew": crew, "trend": trend}
    total = sum(WEIGHTS[k] * v for k, v in comps.items())
    if sched == 0.0:
        total *= 0.2  # hard-ish constraint: closed places sink regardless of taste
    if ctx.crew and spread > 0.45:
        notes["crew"] = "splits your crew — good as one person's pick, not a group stop"
    return Scored(place=place, total=round(total, 4), components=comps, notes=notes)


def explain(s: Scored, dna: TravelerDNA) -> list[Evidence]:
    """Top reasons, in traveller language. Only claims that the inputs support."""
    ev: list[Evidence] = []
    interests = dna.interests()
    served = sorted(((k, w * interests.get(k, 0)) for k, w in s.place.dna.items() if k in interests), key=lambda x: -x[1])
    if served and served[0][1] > 0.35:
        dims = " + ".join(k.replace("localDiscovery", "local finds") for k, _ in served[:2])
        ev.append(Evidence(text=f"Matches your interest in {dims}", provenance=Provenance.YOU, weight=WEIGHTS["preference"] * s.components["preference"]))
    if s.place.iconic >= 0.6:
        ev.append(Evidence(text=f"Iconic — documented in {s.place.notability} Wikipedia languages", provenance=Provenance.LIVE,
                           source="Wikidata", url=next((x["url"] for x in s.place.sources if x["name"] == "Wikidata"), None)))
    elif s.place.iconic <= 0.15:
        ev.append(Evidence(text="A local find rather than a tourist icon", provenance=Provenance.EST))
    if "geographic" in s.notes:
        ev.append(Evidence(text=s.notes["geographic"].capitalize(), provenance=Provenance.EST, weight=WEIGHTS["geographic"] * s.components["geographic"]))
    sched_note = s.notes.get("schedule", "")
    if sched_note.startswith("open"):
        ev.append(Evidence(text=sched_note.capitalize(), provenance=Provenance.LIVE, source="OpenStreetMap opening_hours"))
    elif sched_note == "hours not verified":
        ev.append(Evidence(text="Opening hours not verified — check before going", provenance=Provenance.EST))
    ev.append(Evidence(text=s.notes["budget"].capitalize(), provenance=Provenance.EST))
    if s.components["weather"] >= 0.9 and s.place.indoor:
        ev.append(Evidence(text="Indoors — works in any weather", provenance=Provenance.EST))
    if s.components["trend"] > 0:
        ev.append(Evidence(text=f"Arivo Pulse {round(s.components['trend'] * 100)} — see evidence", provenance=Provenance.LIVE))
    if "crew" in s.notes:
        ev.append(Evidence(text=s.notes["crew"].capitalize(), provenance=Provenance.EST))
    return ev[:5]


def rerank_diverse(items: list[Scored], k: int, lam: float = 0.72) -> list[Scored]:
    """MMR rerank: avoid five near-identical cafés. Similarity = same category (+ shared dominant DNA dimension)."""
    chosen: list[Scored] = []
    pool = sorted(items, key=lambda s: -s.total)
    while pool and len(chosen) < k:
        def mmr(s: Scored) -> float:
            if not chosen:
                return s.total
            sim = max(_similar(s.place, c.place) for c in chosen)
            return lam * s.total - (1 - lam) * sim
        best = max(pool, key=mmr)
        chosen.append(best)
        pool.remove(best)
    return chosen


def _similar(a: Place, b: Place) -> float:
    if a.category == b.category:
        return 1.0
    da = max(a.dna, key=a.dna.get) if a.dna else None
    db = max(b.dna, key=b.dna.get) if b.dna else None
    return 0.5 if da and da == db else 0.0


# ------------------------------------------------------------------------------------------------ Trend Pulse score

TREND_WEIGHTS = {
    "burst": 0.28,
    "velocity": 0.20,
    "recency": 0.16,
    "source_diversity": 0.12,
    "local_event": 0.10,
    "local_relevance": 0.08,
    "engagement_quality": 0.06,
}
assert abs(sum(TREND_WEIGHTS.values()) - 1.0) < 1e-9


def trend_score(components: dict[str, float], spam_penalty: float) -> float:
    """TrendScore 0..100 = (Σ weight·component) × SpamPenalty. Components and penalty are clamped to 0..1."""
    raw = sum(w * max(0.0, min(1.0, components.get(k, 0.0))) for k, w in TREND_WEIGHTS.items())
    return round(100 * raw * max(0.0, min(1.0, spam_penalty)), 1)


# ------------------------------------------------------------------------------------------------ HotelTripFit

@dataclass
class HotelFit:
    place: Place
    score: int  # 0..100
    location_fit: int  # 0..100
    within_25: int
    total_stops: int
    avg_minutes: int
    nearest_station_m: int | None
    sentence: str
    evidence: list[Evidence]


def hotel_trip_fit(hotel: Place, stops: list[Place], stations: list[Place], dna: TravelerDNA, country: str,
                   nightly: Money | None = None, nightly_budget: Money | None = None) -> HotelFit:
    """Rank a stay by where the traveller actually plans to go, not by stars."""
    minutes = [estimate_leg(hotel.lat, hotel.lon, s.lat, s.lon, country, dna.walkingTolerance)[0].minutes for s in stops]
    within = sum(1 for m in minutes if m <= 25)
    avg = round(sum(minutes) / len(minutes)) if minutes else 0
    location_fit = round(100 * (0.65 * (within / len(stops) if stops else 0.5) + 0.35 * math.exp(-avg / 40)))
    near_station = min((haversine_km(hotel.lat, hotel.lon, s.lat, s.lon) for s in stations), default=None)
    station_m = round(near_station * 1000) if near_station is not None else None
    transit = 1.0 if station_m is not None and station_m <= 500 else 0.6 if station_m is not None and station_m <= 1000 else 0.3
    nightly = nightly or estimate_nightly(hotel, nightly_budget.currency if nightly_budget else "JPY")
    price = budget_fit(nightly, nightly_budget, max(0.6, dna.budgetSensitivity)) if nightly_budget else 0.7
    stars = float(hotel.tags.get("stars", "0") or 0)
    quality = min(1.0, 0.5 + stars / 10) if stars else 0.6
    total = round(100 * (0.4 * location_fit / 100 + 0.15 * transit + 0.3 * price + 0.15 * quality))
    sentence = f"{within} of your {len(stops)} planned stops are under 25 minutes away" + (f" · {avg} min average" if stops else "")
    ev = [Evidence(text=sentence, provenance=Provenance.EST)]
    if station_m is not None:
        ev.append(Evidence(text=f"Station {station_m} m away", provenance=Provenance.LIVE, source="OpenStreetMap"))
    if stars:
        ev.append(Evidence(text=f"{int(stars)}-star (OpenStreetMap tag)", provenance=Provenance.LIVE, source="OpenStreetMap"))
    return HotelFit(hotel, total, location_fit, within, len(stops), avg, station_m, sentence, ev)
