"""Arivo Guide tools (LangChain StructuredTools) with permission scopes.

Scopes: READ_TRIP · EDIT_TRIP · READ_BOOKINGS · SEARCH_BOOKINGS · CREATE_BOOKING_DRAFT · READ_LOCATION · READ_BUDGET · USE_CAMERA
There is deliberately NO tool with CHARGE_CARD / FINALIZE_* scope: the agent can prepare checkout, a human confirms and pays.
Mutating tools never execute directly — they return an ActionProposal the app shows in a ConfirmSheet.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from typing import Any, Literal

from langchain_core.tools import StructuredTool
from pydantic import BaseModel, Field

from app.domain.models import CrewRole, Money, Trip
from app.planning.replan import ReplanRequest, Trigger

ROLE_SCOPES = {
    CrewRole.VIEWER: {"READ_TRIP", "READ_BUDGET", "READ_BOOKINGS"},
    CrewRole.MEMBER: {"READ_TRIP", "READ_BUDGET", "READ_BOOKINGS", "SEARCH_BOOKINGS", "EDIT_TRIP", "CREATE_BOOKING_DRAFT"},
    CrewRole.EDITOR: {"READ_TRIP", "READ_BUDGET", "READ_BOOKINGS", "SEARCH_BOOKINGS", "EDIT_TRIP", "CREATE_BOOKING_DRAFT"},
    CrewRole.OWNER: {"READ_TRIP", "READ_BUDGET", "READ_BOOKINGS", "SEARCH_BOOKINGS", "EDIT_TRIP", "CREATE_BOOKING_DRAFT"},
}
FORBIDDEN_SCOPES = {"CHARGE_CARD", "FINALIZE_FLIGHT", "FINALIZE_HOTEL", "FINALIZE_BUS"}


@dataclass
class ActionProposal:
    kind: Literal["trip_change", "move_item", "checkout"]
    summary: str
    confirm: dict[str, Any]  # what the app calls after the human confirms (endpoint + body); never auto-called
    data: dict[str, Any] = field(default_factory=dict)


@dataclass
class GuideContext:
    container: Any
    user_id: str
    role: CrewRole
    trip: Trip
    now: datetime
    proposals: list[ActionProposal] = field(default_factory=list)
    cards: list[dict] = field(default_factory=list)  # UI cards to render alongside Ari's reply (places, offers, budget)

    @property
    def scopes(self) -> set[str]:
        return ROLE_SCOPES[self.role]


# ---------------------------------------------------------------------------------------------------- arg schemas
class DayArg(BaseModel):
    day_index: int | None = Field(default=None, description="0-based trip day; omit for today")


class NoArgs(BaseModel):
    pass


class SearchPlacesArgs(BaseModel):
    kind: Literal["food", "coffee", "sight", "night", "indoor"] = Field(description="What to look for")
    near: Literal["next_stop", "current_stop", "hotel"] = "next_stop"
    query: str | None = Field(default=None, max_length=40, description="Optional name or cuisine filter, e.g. ramen")


class MoveItemArgs(BaseModel):
    item_query: str = Field(max_length=60, description="Which stop, e.g. 'dinner' or a place name")
    new_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$", description="HH:MM, or omit with shift_minutes")
    shift_minutes: int | None = Field(default=None, ge=-240, le=240)


class RescueArgs(BaseModel):
    trigger: Literal["rain", "late", "fatigue", "closed", "budget", "more_food", "skip_category", "nightlife", "delay"]
    day_index: int | None = None
    minutes_late: int | None = Field(default=None, ge=0, le=600)
    category: str | None = Field(default=None, max_length=20)


class FlightArgs(BaseModel):
    depart: date
    origin: str = Field(default="KUL", max_length=40)
    destination: str | None = Field(default=None, max_length=40)


class StayArgs(BaseModel):
    sort: Literal["best_location", "cheapest"] = "best_location"


class GroundArgs(BaseModel):
    destination: str = Field(max_length=40)
    depart: date | None = None


class OfferArgs(BaseModel):
    offer_id: str = Field(max_length=120)


class StoryArgs(BaseModel):
    place: Literal["next_stop", "current_stop"] = "current_stop"
    length: Literal["30s", "1min", "deep"] = "1min"


# ---------------------------------------------------------------------------------------------------- helpers
def _day(ctx: GuideContext, day_index: int | None):
    if day_index is not None and 0 <= day_index < len(ctx.trip.days):
        return ctx.trip.days[day_index]
    return next((d for d in ctx.trip.days if d.date == ctx.now.date()), ctx.trip.days[0])


def _next_item(ctx: GuideContext):
    day = _day(ctx, None)
    now = ctx.now if ctx.now.date() == day.date else datetime.combine(day.date, ctx.now.time())
    upcoming = [i for i in day.items if i.start >= now]
    current = next((i for i in day.items if i.start <= now < i.end), None)
    return day, current, (upcoming[0] if upcoming else None)


def build_tools(ctx: GuideContext) -> list[StructuredTool]:
    c = ctx.container

    async def read_day(day_index: int | None = None) -> str:
        d = _day(ctx, day_index)
        return json.dumps({"day": d.index + 1, "date": d.date.isoformat(), "title": d.title, "weather": d.weather,
                           "stops": [{"id": i.id, "time": f"{i.start:%H:%M}", "name": i.name, "kind": i.kind, "min": i.duration_min,
                                      "booked": i.locked} for i in d.items]})

    async def whats_next() -> str:
        day, current, nxt = _next_item(ctx)
        if not nxt:
            return json.dumps({"next": None, "note": "Nothing else planned today."})
        ctx.cards.append({"type": "stop", "item": nxt.model_dump(mode="json")})
        return json.dumps({"now": f"{ctx.now:%H:%M}", "current": current.name if current else None, "next": nxt.name,
                           "at": f"{nxt.start:%H:%M}", "leg": nxt.leg.model_dump() if nxt.leg else None, "why": nxt.reason})

    async def budget_status() -> str:
        from app.api.routes_trips import _reservations
        from app.budget.brain import budget_view

        v = await budget_view(ctx.trip, await c.store.list_expenses(ctx.trip.id), await _reservations(c, ctx.trip), c.fx)
        ctx.cards.append({"type": "budget", "budget": v.__dict__})
        return json.dumps({"currency": v.currency, "total": v.total, "spent": v.spent, "reserved": v.reserved,
                           "forecast": v.forecast, "remaining": v.remaining, "state": v.state})

    async def search_places(kind: str, near: str = "next_stop", query: str | None = None) -> str:
        day, current, nxt = _next_item(ctx)
        anchor = (current or nxt or (day.items[0] if day.items else None))
        if near == "next_stop" and nxt:
            anchor = nxt
        if not anchor:
            return json.dumps({"results": [], "note": "No stop to search near."})
        city = ctx.trip.cities[0]
        cats = {"food": {"restaurant", "food_court", "market"}, "coffee": {"cafe"}, "night": {"bar", "pub"},
                "indoor": {"museum", "gallery", "aquarium", "shopping"}, "sight": None}[kind]
        from app.recommendations.scoring import ScoreContext, score

        pool = c.places.search(city, categories=cats, near=(anchor.lat, anchor.lon), radius_km=1.2, text=query, limit=40)
        ranked = sorted((score(p, ScoreContext(dna=ctx.trip.dna, anchor=(anchor.lat, anchor.lon), slot_start=ctx.now, duration_min=45,
                                               geo_scale_km=0.6), ctx.trip.currency) for p in pool), key=lambda s: -s.total)[:5]
        for s in ranked:
            ctx.cards.append({"type": "place", "place_id": s.place.id, "name": s.place.name, "match": s.match_pct, "notes": s.notes})
        return json.dumps({"near": anchor.name, "results": [{"id": s.place.id, "name": s.place.name, "category": s.place.category,
                                                             "match_pct": s.match_pct, "notes": s.notes} for s in ranked]})

    async def propose_move(item_query: str, new_time: str | None = None, shift_minutes: int | None = None) -> str:
        day = _day(ctx, None)
        q = item_query.lower()
        target = next((i for i in day.items if q in i.name.lower()), None) or next(
            (i for i in reversed(day.items) if ("dinner" in q and i.kind == "meal" and i.start.hour >= 16) or ("lunch" in q and i.kind == "meal" and i.start.hour < 16)), None)
        if not target:
            return json.dumps({"error": f"No stop matching '{item_query}' today."})
        if target.locked:
            return json.dumps({"error": f"{target.name} is a booking — change it in My Bookings."})
        when = new_time or (target.start + timedelta(minutes=shift_minutes or 60)).strftime("%H:%M")
        ctx.proposals.append(ActionProposal(kind="move_item", summary=f"Move {target.name} from {target.start:%H:%M} to {when}?",
                                            confirm={"method": "POST", "path": f"/v1/trips/{ctx.trip.id}/items/{target.id}", "body": {"action": "move", "new_start": when}},
                                            data={"item_id": target.id}))
        return json.dumps({"proposed": True, "item": target.name, "from": f"{target.start:%H:%M}", "to": when, "needs_confirmation": True})

    async def propose_rescue(trigger: str, day_index: int | None = None, minutes_late: int | None = None, category: str | None = None) -> str:
        d = _day(ctx, day_index)
        now = ctx.now if ctx.now.date() == d.date else datetime.combine(d.date, ctx.now.time())
        change = await c.trips.propose_replan(ctx.trip, ReplanRequest(trigger=Trigger(trigger), day_index=d.index, now=now,
                                                                      minutes_late=minutes_late or 0, category=category), ctx.user_id)
        ctx.proposals.append(ActionProposal(kind="trip_change", summary=change.explanation,
                                            confirm={"method": "POST", "path": f"/v1/trips/{ctx.trip.id}/changes/{change.id}/apply"},
                                            data={"change": change.model_dump(mode="json", exclude={"new_items"})}))
        return json.dumps({"proposed": True, "kept": len(change.kept), "moved": len(change.moved), "removed": len(change.removed),
                           "added": [a.name for a in change.added], "explanation": change.explanation, "needs_confirmation": True})

    async def search_flights(depart: date, origin: str = "KUL", destination: str | None = None) -> str:
        dest = destination or ctx.trip.cities[0]
        arrive_by = datetime.combine(ctx.trip.days[0].date, time(10)) if ctx.trip.days and dest == ctx.trip.cities[0] else None
        offers = await c.bookings.search_flights(ctx.user_id, origin, dest, depart, ctx.trip.intent.crew_size, arrive_by=arrive_by)
        top = offers[:3]
        ctx.cards.extend({"type": "offer", "offer": o.model_dump(mode="json")} for o in top)
        return json.dumps({"sandbox": any(o.sandbox for o in top), "offers": [{"id": o.offer_id, "title": o.title, "subtitle": o.subtitle,
                            "price": o.price.display(), "depart": o.departure.isoformat() if o.departure else None,
                            "arrive": o.arrival.isoformat() if o.arrival else None, "badges": o.badges} for o in top]})

    async def search_stays(sort: str = "best_location") -> str:
        d0 = ctx.trip.start_date
        nights = max(1, len(ctx.trip.days) - 1)
        offers = await c.bookings.search_stays(ctx.user_id, ctx.trip.cities[0], d0, nights, ctx.trip.intent.crew_size,
                                               max(1, (ctx.trip.intent.crew_size + 1) // 2))
        offers = sorted(offers, key=lambda o: o.price.amount_minor)[:3] if sort == "cheapest" else offers[:3]
        ctx.cards.extend({"type": "offer", "offer": o.model_dump(mode="json")} for o in offers)
        return json.dumps({"sandbox": True, "offers": [{"id": o.offer_id, "title": o.title, "price": o.price.display()} for o in offers]})

    async def search_ground(destination: str, depart: date | None = None) -> str:
        when = depart or ctx.now.date() + timedelta(days=1)
        offers = await c.bookings.search_ground(ctx.user_id, ctx.trip.cities[0], destination.lower(), when, ctx.trip.intent.crew_size)
        from app.bookings.service import compare_sentence

        ctx.cards.extend({"type": "offer", "offer": o.model_dump(mode="json")} for o in offers)
        fastest = min(offers, key=lambda o: o.meta.get("door_to_door_min", 10**6)) if offers else None
        return json.dumps({"sandbox": True, "offers": [{"id": o.offer_id, "title": o.title, "price": o.price.display(),
                                                        "door_to_door_min": o.meta.get("door_to_door_min")} for o in offers],
                           "insights": [compare_sentence(o, fastest) for o in offers if fastest and o is not fastest]})

    async def prepare_checkout(offer_id: str) -> str:
        rec = await c.store.kv_get("offers", f"{ctx.user_id}:{offer_id}")
        if not rec:
            return json.dumps({"error": "That offer isn't from a recent search. Search again first."})
        o = rec["offer"]
        ctx.proposals.append(ActionProposal(kind="checkout", summary=f"Review {o['title']} — {Money(**o['price']).display()} (final price is re-checked before you pay)",
                                            confirm={"method": "OPEN_CHECKOUT", "offer_id": offer_id, "trip_id": ctx.trip.id},
                                            data={"offer": o}))
        return json.dumps({"checkout_prepared": True, "note": "The traveller reviews the price and presses Confirm & pay. You cannot pay."})

    async def tell_story(place: str = "current_stop", length: str = "1min") -> str:
        from app.ai.story import StoryTeller

        _, current, nxt = _next_item(ctx)
        item = current if place == "current_stop" and current else nxt or current
        p = c.places.get(item.place_id) if item else None
        if not p:
            return json.dumps({"error": "No place to tell a story about."})
        story = await StoryTeller(c.router).tell(p, length)  # type: ignore[arg-type]
        data = story.model_dump() if hasattr(story, "model_dump") else story
        ctx.cards.append({"type": "story", "story": data})
        return json.dumps({"title": data.get("title"), "text": data.get("text") or data.get("message"), "sources": data.get("sources")})

    specs = [
        ("read_day", "Read a day of the trip (stops, times, bookings, weather).", DayArg, read_day, "READ_TRIP"),
        ("whats_next", "What's the next stop, when, and how to get there.", NoArgs, whats_next, "READ_TRIP"),
        ("budget_status", "Budget Brain: total, spent, reserved, forecast, remaining.", NoArgs, budget_status, "READ_BUDGET"),
        ("search_places", "Find food, coffee, sights, nightlife or indoor places near the current/next stop.", SearchPlacesArgs, search_places, "READ_TRIP"),
        ("propose_move_item", "Propose moving a stop to another time. Needs the traveller's confirmation.", MoveItemArgs, propose_move, "EDIT_TRIP"),
        ("propose_rescue", "Propose a replan of a day (rain, late, tired, closed, budget, more food, skip a category, nightlife). Needs confirmation.", RescueArgs, propose_rescue, "EDIT_TRIP"),
        ("search_flights", "Search real/test flight inventory. Never invent flights.", FlightArgs, search_flights, "SEARCH_BOOKINGS"),
        ("search_stays", "Search stays ranked by where this trip goes, or by price.", StayArgs, search_stays, "SEARCH_BOOKINGS"),
        ("search_ground", "Compare train/bus/flight to another city.", GroundArgs, search_ground, "SEARCH_BOOKINGS"),
        ("prepare_checkout", "Open checkout for an offer from a recent search. Cannot pay.", OfferArgs, prepare_checkout, "CREATE_BOOKING_DRAFT"),
        ("tell_story", "Tell the verified story of the current or next stop (sourced).", StoryArgs, tell_story, "READ_TRIP"),
    ]
    tools = []
    for name, desc, schema, fn, scope in specs:
        assert scope not in FORBIDDEN_SCOPES
        if scope not in ctx.scopes:
            continue
        tools.append(StructuredTool.from_function(coroutine=fn, name=name, description=desc, args_schema=schema, metadata={"scope": scope}))
    return tools


def to_anthropic(tools: list[StructuredTool]) -> list[dict]:
    """LangChain tool → Anthropic tool param (strict JSON schema from the Pydantic args model)."""
    out = []
    for t in tools:
        schema = t.args_schema.model_json_schema()
        schema.pop("title", None)
        out.append({"name": t.name, "description": t.description, "input_schema": schema})
    return out
