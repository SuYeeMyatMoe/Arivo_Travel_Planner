"""Rescue My Day / Plan B: recompute only the affected part of a day, never touching bookings or the past.

Every call returns a TripChange (Kept · Moved · Removed · Added + time and budget deltas). It is a *proposal*:
nothing is applied until the traveller confirms (see TripService.apply_change).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta
from enum import StrEnum

from app.core.geo import haversine_km
from app.domain.models import (
    DiffEntry, Evidence, ItemStatus, ItineraryDay, ItineraryItem, Money, Place, PlanB, Provenance, Trip, TripChange,
)
from app.places.hours import OpenState, parse
from app.places.providers import PlaceProvider
from app.planning.scheduler import Stop, timeline, solve_order
from app.recommendations.scoring import ScoreContext, estimated_cost, explain, score

INDOOR_SIGHTS = {"museum", "gallery", "aquarium", "shopping", "market"}
CALM = {"cafe", "park", "garden", "gallery"}


class Trigger(StrEnum):
    RAIN = "rain"
    LATE = "late"
    FATIGUE = "fatigue"
    CLOSED = "closed"
    BUDGET = "budget"
    MORE_FOOD = "more_food"
    SKIP = "skip_category"
    NIGHTLIFE = "nightlife"
    DELAY = "delay"
    ADD = "add_place"  # traveller adds a place (Explore, Pulse, a social post) → fit it into the day


@dataclass
class ReplanRequest:
    trigger: Trigger
    day_index: int
    now: datetime  # local wall-clock time in the trip timezone
    minutes_late: int = 0
    place_id: str | None = None  # CLOSED: which stop closed
    category: str | None = None  # SKIP: e.g. "museum"
    rain_until: time | None = None  # RAIN without forecast data: assume this long
    note: str | None = None


class Replanner:
    def __init__(self, places: PlaceProvider):
        self.places = places

    def replan(self, trip: Trip, req: ReplanRequest) -> TripChange:
        day = trip.days[req.day_index]
        city = self._city_of(trip, day)
        cinfo = self.places.city(city)
        country = cinfo["country"]
        past = [i for i in day.items if i.status == ItemStatus.DONE or i.end <= req.now]
        future = [i for i in day.items if i not in past]
        locked = [i for i in future if i.locked or i.status == ItemStatus.BOOKED]
        flexible = [i for i in future if i not in locked and i.kind != "transfer"]
        in_trip = {i.place_id for i in trip.all_items()}
        dna = trip.dna
        walking = dna.walkingTolerance
        buffer_min = 10
        removed: list[tuple[ItineraryItem, str]] = []
        added: list[tuple[Place, str, str]] = []  # place, kind, why
        start_at = max([req.now] + [i.end for i in past])
        if req.trigger in (Trigger.LATE, Trigger.DELAY):
            start_at = max(start_at, req.now + timedelta(minutes=req.minutes_late))
        anchor = past[-1] if past else None
        anchor_ll = (anchor.lat, anchor.lon) if anchor else self._hotel_ll(trip, flexible)

        if req.trigger == Trigger.RAIN:
            wx = day.weather or {}
            window = wx.get("rain_window")
            rain_from = req.now.hour if window is None else max(window[0], req.now.hour)
            rain_to = (req.rain_until.hour if req.rain_until else (window[1] if window else req.now.hour + 4))
            for it in list(flexible):
                overlaps = it.start.hour < rain_to and it.end.hour >= rain_from
                if overlaps and not it.indoor and it.kind == "sight":
                    flexible.remove(it)
                    removed.append((it, f"Heavy rain {rain_from:02d}:00–{rain_to:02d}:00"))
            for it, _ in removed:
                alt = self._alternative(trip, city, (it.lat, it.lon), in_trip, lambda p: p.indoor and p.category in INDOOR_SIGHTS | {"attraction"}, req.now, rain=True)
                if alt:
                    in_trip.add(alt.id)
                    added.append((alt, "sight", "Indoors, near where you'd have been"))
        elif req.trigger == Trigger.FATIGUE:
            walking, buffer_min = 0.25, 20
            sights = [i for i in flexible if i.kind == "sight"]
            if sights and anchor_ll:
                far = max(sights, key=lambda i: (haversine_km(anchor_ll[0], anchor_ll[1], i.lat, i.lon) * (1.2 - i.priority)))
                if far.priority < 0.95:
                    flexible.remove(far)
                    removed.append((far, "Farthest, lowest-priority stop — saved for a fresher day"))
            for it in flexible:
                it.duration_min = int(it.duration_min * 1.1)
            calm = self._alternative(trip, city, anchor_ll, in_trip, lambda p: p.category in CALM, req.now)
            if calm:
                in_trip.add(calm.id)
                added.append((calm, "sight", "A slow stop to recharge"))
        elif req.trigger == Trigger.CLOSED and req.place_id:
            closed = next((i for i in flexible if i.place_id == req.place_id), None)
            if closed:
                flexible.remove(closed)
                removed.append((closed, "Closed today"))
                orig = self.places.get(closed.place_id)
                similar = (lambda p: p.category == orig.category or bool(set(p.dna) & set(orig.dna))) if orig else (lambda p: True)
                alt = self._alternative(trip, city, (closed.lat, closed.lon), in_trip, similar, req.now)
                if alt:
                    in_trip.add(alt.id)
                    added.append((alt, closed.kind, f"Similar to {closed.name}, open now"))
        elif req.trigger == Trigger.BUDGET:
            for it in list(flexible):
                if it.kind == "sight" and it.cost and it.cost.amount_minor > 0:
                    flexible.remove(it)
                    removed.append((it, f"Saves {it.cost.display()} per person"))
                    alt = self._alternative(trip, city, (it.lat, it.lon), in_trip, lambda p: estimated_cost(p, trip.currency).amount_minor == 0 and not p.is_food, req.now)
                    if alt:
                        in_trip.add(alt.id)
                        added.append((alt, "sight", "Free entry nearby"))
        elif req.trigger == Trigger.SKIP and req.category:
            for it in list(flexible):
                if it.category == req.category or (req.category == "museum" and it.category in {"museum", "gallery"}):
                    flexible.remove(it)
                    removed.append((it, f"You asked to skip {req.category}s"))
                    alt = self._alternative(trip, city, (it.lat, it.lon), in_trip, lambda p: p.category not in {req.category, "gallery"} and not p.is_food and not p.is_stay, req.now)
                    if alt:
                        in_trip.add(alt.id)
                        added.append((alt, "sight", "Replaces it without a museum"))
        elif req.trigger == Trigger.MORE_FOOD:
            spot = self._alternative(trip, city, anchor_ll, in_trip, lambda p: p.category in {"market", "food_court"} or (p.category == "restaurant" and p.iconic < 0.2), req.now)
            if spot:
                in_trip.add(spot.id)
                added.append((spot, "meal", "Extra food stop on your route"))
        elif req.trigger == Trigger.ADD and req.place_id:
            place = self.places.get(req.place_id)
            if place and place.id not in {i.place_id for i in day.items}:
                kind = "meal" if place.is_food else "night" if place.is_night else "sight"
                added.append((place, kind, "You added this"))
        elif req.trigger == Trigger.NIGHTLIFE:
            dinner = next((i for i in reversed(future) if i.kind == "meal"), None)
            near = (dinner.lat, dinner.lon) if dinner else anchor_ll
            bar = self._alternative(trip, city, near, in_trip, lambda p: p.is_night, req.now.replace(hour=max(req.now.hour, 20)))
            if bar:
                in_trip.add(bar.id)
                added.append((bar, "night", "Your crew voted for nightlife tonight"))

        # schedule remaining day: locked items fixed, meals keep a window around their old time
        day_start = datetime.combine(day.date, time(0, 0))
        start_min = int((start_at - day_start).total_seconds() // 60)
        day_len = 22 * 60
        origin = Stop("origin", anchor_ll[0], anchor_ll[1], 0, (start_min, day_len)) if anchor_ll else Stop("origin", None, None, 0, (start_min, day_len))
        stops: list[Stop] = []
        for it in locked:
            m = int((it.start - day_start).total_seconds() // 60)
            stops.append(Stop(it.id, it.lat, it.lon, it.duration_min, (m, m + it.duration_min), 1.0, True, fixed_at=m, payload=it))
        for it in flexible:
            m = int((it.start - day_start).total_seconds() // 60)
            win = (max(start_min, m - 90), min(day_len, m + it.duration_min + 120)) if it.kind == "meal" else (start_min, day_len)
            stops.append(Stop(it.id, it.lat, it.lon, it.duration_min, win, it.priority, it.kind == "meal", payload=it))
        for place, kind, why in added:
            dur = (place.duration_min or (40, 60, 90))[1]
            win = (start_min, day_len)
            if kind == "night":
                win = (max(start_min, 20 * 60), day_len)
            stops.append(Stop(place.id, place.lat, place.lon, dur, win, 0.7, False, payload=(place, kind, why)))
        # the scheduler works in minutes-after-midnight here: shift into its "after origin" frame
        for s in stops:
            s.window = (max(0, s.window[0] - start_min), max(0, s.window[1] - start_min))
            if s.fixed_at is not None:
                s.fixed_at -= start_min
        origin.window = (0, day_len - start_min)
        ordered, dropped, _ = solve_order(origin, stops, day_len - start_min, country, walking, buffer_min)
        plan = timeline(origin, ordered, start_at, day_len - start_min, country, walking, buffer_min)
        new_items: list[ItineraryItem] = list(past)
        for sch in plan.scheduled:
            p = sch.stop.payload
            if isinstance(p, ItineraryItem):
                item = p.model_copy(update={"start": sch.start, "leg": sch.leg, "leg_cost": sch.leg_cost})
            else:
                place, kind, why = p
                sc = score(place, ScoreContext(dna=dna, slot_start=sch.start, duration_min=sch.stop.duration,
                                               rain_prob=100 if req.trigger == Trigger.RAIN else None, country=country), trip.currency)
                ev = [Evidence(text=why, provenance=Provenance.EST), *explain(sc, dna)]
                item = ItineraryItem(place_id=place.id, name=place.name, category=place.category, lat=place.lat, lon=place.lon,
                                     start=sch.start, duration_min=sch.stop.duration, leg=sch.leg, leg_cost=sch.leg_cost,
                                     cost=estimated_cost(place, trip.currency), reason=why, evidence=ev[:5], score=sc.total,
                                     indoor=place.indoor, kind=kind, priority=0.7)
            new_items.append(item)
        for s, why in [*[(s, "not enough time left today") for s in dropped], *plan.dropped]:
            p = s.payload
            if isinstance(p, ItineraryItem) and not any(r[0].id == p.id for r in removed):
                if p.locked:
                    continue  # bookings are never removed; timeline flags conflicts instead
                removed.append((p, why))
        return self._diff(trip, day, req, future, new_items, removed)

    # ------------------------------------------------------------------------------------------------ Plan B
    def plan_b(self, trip: Trip, day_index: int) -> list[PlanB]:
        day = trip.days[day_index]
        if not day.items:
            return []
        start = min(i.start for i in day.items) - timedelta(minutes=1)
        out = []
        for trig in (Trigger.RAIN, Trigger.FATIGUE):
            ch = self.replan(trip, ReplanRequest(trigger=trig, day_index=day_index, now=start, rain_until=time(21, 0)))
            if ch.removed or ch.added:
                out.append(PlanB(trigger=trig.value, items=ch.new_items, summary=ch.explanation,
                                 time_delta_min=ch.time_delta_min, budget_delta=ch.budget_delta))
        return out

    # ------------------------------------------------------------------------------------------------ helpers
    def _alternative(self, trip: Trip, city: str, near: tuple[float, float] | None, exclude: set[str], pred, when: datetime,
                     rain: bool = False) -> Place | None:
        if not near:
            return None
        cands = [p for p in self.places.search(city, near=near, radius_km=2.5, limit=400) if p.id not in exclude and pred(p)]
        open_ok = []
        for p in cands:
            state = parse(p.tags.get("opening_hours")).state_at(when)
            if state != OpenState.CLOSED:
                open_ok.append(p)
        ctx = ScoreContext(dna=trip.dna, anchor=near, slot_start=when, duration_min=60, rain_prob=100 if rain else None,
                           crew=trip.crew, geo_scale_km=1.2)
        ranked = sorted((score(p, ctx, trip.currency) for p in open_ok), key=lambda s: -s.total)
        return ranked[0].place if ranked else None

    def _city_of(self, trip: Trip, day: ItineraryDay) -> str:
        for c in trip.cities:
            info = self.places.city(c)
            if info and day.zone == info["name"]:
                return c
        return trip.cities[0]

    def _hotel_ll(self, trip: Trip, items: list[ItineraryItem]) -> tuple[float, float] | None:
        if trip.hotel_place_id and (h := self.places.get(trip.hotel_place_id)):
            return h.lat, h.lon
        return (items[0].lat, items[0].lon) if items else None

    def _diff(self, trip: Trip, day: ItineraryDay, req: ReplanRequest, before: list[ItineraryItem], after: list[ItineraryItem],
              removed: list[tuple[ItineraryItem, str]]) -> TripChange:
        before_by_place = {i.place_id: i for i in before}
        after_future = [i for i in after if i.place_id in before_by_place or i not in day.items]
        after_by_place = {i.place_id: i for i in after_future}
        ch = TripChange(trip_id=trip.id, day_index=req.day_index, trigger=req.trigger.value, base_version=trip.version)
        for pid, old in before_by_place.items():
            new = after_by_place.get(pid)
            if new is None:
                why = next((w for r, w in removed if r.place_id == pid), "no longer fits")
                ch.removed.append(DiffEntry(item_id=old.id, name=old.name, from_time=f"{old.start:%H:%M}", reason=why))
            elif abs((new.start - old.start).total_seconds()) <= 5 * 60:
                ch.kept.append(DiffEntry(item_id=old.id, name=old.name + (" (booked)" if old.locked else ""), from_time=f"{old.start:%H:%M}"))
            else:
                ch.moved.append(DiffEntry(item_id=old.id, name=old.name, from_time=f"{old.start:%H:%M}", to_time=f"{new.start:%H:%M}"))
        for new in after_future:
            if new.place_id not in before_by_place:
                ch.added.append(DiffEntry(item_id=new.id, name=new.name, to_time=f"{new.start:%H:%M}", detail=new.reason))
        old_end = max((i.end for i in before), default=req.now)
        new_end = max((i.end for i in after if i not in day.items or i.place_id in before_by_place), default=req.now)
        ch.time_delta_min = int((new_end - old_end).total_seconds() // 60)
        crew = trip.intent.crew_size
        old_cost = sum((i.cost.amount if i.cost else 0) + (i.leg_cost.amount if i.leg_cost else 0) for i in before) * crew
        new_cost = sum((i.cost.amount if i.cost else 0) + (i.leg_cost.amount if i.leg_cost else 0) for i in after_future) * crew
        ch.budget_delta = Money.of(new_cost - old_cost, trip.currency)
        ch.new_items = sorted(after, key=lambda i: i.start)
        ch.explanation = self._explain(req, ch)
        return ch

    def _explain(self, req: ReplanRequest, ch: TripChange) -> str:
        parts = []
        lead = {
            Trigger.RAIN: "Rain changes the afternoon, so outdoor stops moved indoors",
            Trigger.LATE: f"You're starting {req.minutes_late} min later, so the day is compressed",
            Trigger.DELAY: f"A {req.minutes_late} min delay pushes the rest of the day",
            Trigger.FATIGUE: "Slow mode: less walking, longer stops, one stop saved for later",
            Trigger.CLOSED: "A stop is closed today, so it's swapped for a similar one nearby",
            Trigger.BUDGET: "Budget mode: paid entries swapped for free ones nearby",
            Trigger.SKIP: f"No {req.category}s today",
            Trigger.MORE_FOOD: "More food: a food stop added on your route",
            Trigger.NIGHTLIFE: "Evening updated for nightlife",
            Trigger.ADD: "Added to the day where it fits the route best",
        }[req.trigger]
        parts.append(lead)
        if any("(booked)" in k.name for k in ch.kept):
            parts.append("your bookings stay exactly as they are")
        if ch.budget_delta and ch.budget_delta.amount_minor:
            verb = "saves" if ch.budget_delta.amount_minor < 0 else "adds"
            parts.append(f"{verb} about {Money(amount_minor=abs(ch.budget_delta.amount_minor), currency=ch.budget_delta.currency).display()} for the group")
        if ch.time_delta_min:
            parts.append(f"the day ends {abs(ch.time_delta_min)} min {'earlier' if ch.time_delta_min < 0 else 'later'}")
        return "; ".join(parts) + "."
