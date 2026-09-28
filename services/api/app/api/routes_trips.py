"""Trips, the Living Trip (Rescue / Plan B / edits), Budget Brain and expenses."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, trip_access
from app.budget.brain import Expense, budget_view
from app.bookings.models import BookingTransaction, OfferType, TxnState
from app.container import Container
from app.core.security import Principal, current_user
from app.domain.models import CrewRole, CrewType, Money, Pace, Trip, new_id
from app.planning.intent import parse_heuristic
from app.planning.replan import ReplanRequest, Trigger
from app.planning.rescue_intent import classify
from app.trips.service import TripError

router = APIRouter(prefix="/v1", tags=["trips"])


class QuickControls(BaseModel):
    start_date: date | None = None
    days: int | None = Field(default=None, ge=1, le=30)
    budget_amount: float | None = Field(default=None, ge=0, le=10_000_000)
    budget_currency: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")
    crew_type: CrewType | None = None
    crew_size: int | None = Field(default=None, ge=1, le=20)
    pace: Pace | None = None


class CreateTrip(BaseModel):
    text: str = Field(min_length=3, max_length=600)
    quick: QuickControls = Field(default_factory=QuickControls)
    iconic_local: float = Field(default=0.0, ge=-1, le=1)


def trip_json(trip: Trip) -> dict:
    return trip.model_dump(mode="json")


@router.get("/cities")
async def cities(c: Container = Depends(get_container)):
    return [{"key": x["key"], "name": x["name"], "country": x["country"], "currency": x["currency"], "tz": x["tz"],
             "bbox": x["bbox"], "attribution": x.get("attribution")} for x in c.places.cities()]


@router.post("/intent/preview")
async def intent_preview(body: CreateTrip, _: Principal = Depends(current_user)):
    """Instant, offline parse for the onboarding field (chips update as the traveller types)."""
    return parse_heuristic(body.text).model_dump(mode="json")


@router.post("/trips")
async def create_trip(body: CreateTrip, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    overrides = {k: v for k, v in body.quick.model_dump().items() if v is not None}
    res = await c.trips.create_from_text(p.user_id, p.display_name or "You", body.text, overrides, body.iconic_local)
    if res["status"] == "ok":
        return {"status": "ok", "trip": trip_json(res["trip"]), "trace": res["trace"]}
    return res


@router.get("/trips")
async def my_trips(p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    trips = await c.store.trips_for_user(p.user_id)
    return [{"id": t.id, "title": t.title, "start_date": t.start_date.isoformat(), "days": len(t.days), "cities": t.cities,
             "mode": t.mode, "version": t.version} for t in trips]


@router.get("/trips/{trip_id}")
async def get_trip(trip: Trip = Depends(trip_access(CrewRole.VIEWER))):
    return trip_json(trip)


class RescueBody(BaseModel):
    text: str | None = Field(default=None, max_length=300)
    trigger: Trigger | None = None
    day_index: int | None = Field(default=None, ge=0, le=60)
    now: datetime | None = None  # local wall time; defaults to "now" in the trip timezone
    minutes_late: int | None = Field(default=None, ge=0, le=24 * 60)
    place_id: str | None = Field(default=None, max_length=80)
    category: str | None = Field(default=None, max_length=30)


def _local_now(trip: Trip) -> datetime:
    return datetime.now(ZoneInfo(trip.timezone)).replace(tzinfo=None, second=0, microsecond=0)


@router.post("/trips/{trip_id}/rescue")
async def rescue(body: RescueBody, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user),
                 c: Container = Depends(get_container)):
    now = body.now.replace(tzinfo=None) if body.now else _local_now(trip)
    day_index = body.day_index
    if day_index is None:
        day_index = next((d.index for d in trip.days if d.date == now.date()), 0)
    if day_index >= len(trip.days):
        raise HTTPException(422, "No such day")
    day = trip.days[day_index]
    if now.date() != day.date:  # planning ahead: simulate "now" on that day
        now = now.replace(year=day.date.year, month=day.date.month, day=day.date.day)
    trigger, minutes, place_id, category = body.trigger, body.minutes_late, body.place_id, body.category
    if trigger is None and body.text:
        cls = classify(body.text, day)
        if not cls.get("trigger"):
            return {"status": "needs_input", "question": "What changed? Rain, running late, tired, a place closed, budget, or more food?",
                    "options": [t.value for t in Trigger]}
        trigger = cls["trigger"]
        minutes = minutes or cls.get("minutes_late")
        place_id = place_id or cls.get("place_id")
        category = category or cls.get("category")
    if trigger is None:
        raise HTTPException(422, "Tell us what changed")
    if trigger == Trigger.CLOSED and not place_id:
        return {"status": "needs_input", "question": "Which place is closed?", "options": [{"id": i.place_id, "name": i.name} for i in day.items if not i.locked]}
    req = ReplanRequest(trigger=trigger, day_index=day_index, now=now, minutes_late=minutes or 0, place_id=place_id, category=category, note=body.text)
    change = await c.trips.propose_replan(trip, req, p.user_id)
    return {"status": "proposed", "change": change.model_dump(mode="json")}


@router.post("/trips/{trip_id}/plan-b/{day_index}/{trigger}")
async def activate_plan_b(day_index: int, trigger: str, trip: Trip = Depends(trip_access(CrewRole.EDITOR)),
                          p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    """Plan B is a precomputed proposal; activating it goes through the same diff → confirm flow."""
    if day_index >= len(trip.days) or trigger not in {t.value for t in Trigger}:
        raise HTTPException(404, "No such Plan B")
    first = min((i.start for i in trip.days[day_index].items), default=None)
    if first is None:
        raise HTTPException(409, "Nothing planned that day")
    req = ReplanRequest(trigger=Trigger(trigger), day_index=day_index, now=first.replace(second=0) - timedelta(minutes=1))
    change = await c.trips.propose_replan(trip, req, p.user_id)
    return {"status": "proposed", "change": change.model_dump(mode="json")}


class AddPlace(BaseModel):
    place_id: str = Field(min_length=4, max_length=80)
    day_index: int | None = Field(default=None, ge=0, le=60)


@router.post("/trips/{trip_id}/add-place")
async def add_place(body: AddPlace, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user),
                    c: Container = Depends(get_container)):
    """Add a place (from Explore, Pulse or a social post) to the day it fits best geographically. Returns a proposal."""
    from app.core.geo import haversine_km

    place = c.places.get(body.place_id)
    if not place:
        raise HTTPException(404, "Place not found")
    if body.day_index is None:
        def dist(d):
            pts = [(i.lat, i.lon) for i in d.items if i.kind != "transfer"] or [(place.lat, place.lon)]
            return haversine_km(place.lat, place.lon, sum(x for x, _ in pts) / len(pts), sum(y for _, y in pts) / len(pts))
        day = min(trip.days, key=dist)
    else:
        day = trip.days[min(body.day_index, len(trip.days) - 1)]
    first = min((i.start for i in day.items), default=datetime.combine(day.date, datetime.min.time()).replace(hour=9))
    req = ReplanRequest(trigger=Trigger.ADD, day_index=day.index, now=first - timedelta(minutes=1), place_id=place.id)
    change = await c.trips.propose_replan(trip, req, p.user_id)
    return {"status": "proposed", "change": change.model_dump(mode="json")}


@router.get("/trips/{trip_id}/changes")
async def list_changes(trip: Trip = Depends(trip_access(CrewRole.VIEWER)), c: Container = Depends(get_container)):
    return [ch.model_dump(mode="json", exclude={"new_items"}) for ch in sorted(await c.store.list_changes(trip.id), key=lambda x: x.created_at, reverse=True)]


@router.post("/trips/{trip_id}/changes/{change_id}/{decision}")
async def decide_change(change_id: str, decision: Literal["apply", "reject"], trip: Trip = Depends(trip_access(CrewRole.EDITOR)),
                        p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        if decision == "apply":
            return {"status": "applied", "trip": trip_json(await c.trips.apply_change(trip.id, change_id, p.user_id))}
        await c.trips.reject_change(trip.id, change_id, p.user_id)
        return {"status": "rejected"}
    except TripError as e:
        raise HTTPException(e.status, {"code": e.code, "message": str(e)}) from e


class ItemEdit(BaseModel):
    action: Literal["remove", "move", "done"]
    new_start: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")


@router.post("/trips/{trip_id}/items/{item_id}")
async def edit_item(item_id: str, body: ItemEdit, trip: Trip = Depends(trip_access(CrewRole.EDITOR)),
                    p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        return trip_json(await c.trips.edit_item(trip, item_id, body.action, p.user_id, new_start=body.new_start))
    except TripError as e:
        raise HTTPException(e.status, {"code": e.code, "message": str(e)}) from e


# ------------------------------------------------------------------------------------------------------ Budget Brain

async def _reservations(c: Container, trip: Trip) -> list[tuple[str, Money]]:
    out = []
    for rec in await c.store.kv_list("txns"):
        if rec["trip_id"] != trip.id:
            continue
        txn = BookingTransaction(**rec)
        if txn.state == TxnState.CONFIRMED:
            cat = {OfferType.FLIGHT: "flights", OfferType.STAY: "accommodation"}.get(txn.offer.type, "transport")
            out.append((cat, txn.offer.price))
    return out


@router.get("/trips/{trip_id}/budget")
async def get_budget(trip: Trip = Depends(trip_access(CrewRole.VIEWER)), c: Container = Depends(get_container)):
    view = await budget_view(trip, await c.store.list_expenses(trip.id), await _reservations(c, trip), c.fx)
    return view.__dict__


class ExpenseIn(BaseModel):
    amount: float = Field(gt=0, le=1_000_000)
    currency: str = Field(pattern=r"^[A-Z]{3}$")
    category: Literal["food", "transport", "activities", "shopping", "accommodation", "flights", "other"]
    merchant: str | None = Field(default=None, max_length=120)
    note: str | None = Field(default=None, max_length=200)
    source: Literal["manual", "receipt_lens"] = "manual"


@router.post("/trips/{trip_id}/expenses")
async def add_expense(body: ExpenseIn, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user),
                      c: Container = Depends(get_container)):
    """Only called after the traveller confirms (Receipt Lens never writes money on its own)."""
    e = Expense(id=new_id("exp"), trip_id=trip.id, amount=Money.of(body.amount, body.currency), category=body.category, merchant=body.merchant,
                note=body.note, source=body.source, created_by=p.user_id, created_at=datetime.utcnow())
    await c.store.add_expense(e)
    view = await budget_view(trip, await c.store.list_expenses(trip.id), await _reservations(c, trip), c.fx)
    return {"expense_id": e.id, "budget": view.__dict__}
