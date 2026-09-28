"""Search → compare → select → revalidate → confirm & pay → manage. Offers are referenced by id only."""

from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, trip_access
from app.bookings.models import Traveller
from app.bookings.service import BookingError, compare_sentence
from app.container import Container
from app.core.security import Principal, current_user
from app.domain.models import CrewRole, Trip

router = APIRouter(prefix="/v1", tags=["bookings"])


def _err(e: BookingError) -> HTTPException:
    return HTTPException(e.status, {"code": e.code, "message": str(e), **e.extra})


def _offers(offers) -> list[dict]:
    return [o.model_dump(mode="json") for o in offers]


class FlightSearch(BaseModel):
    origin: str = Field(min_length=3, max_length=40)
    destination: str = Field(min_length=3, max_length=40)
    depart: date
    return_date: date | None = None
    adults: int = Field(default=1, ge=1, le=9)
    arrive_by: datetime | None = None  # local time the trip's first day starts; late landings can't be "best fit"


def _span(minutes: float) -> str:
    m = abs(int(minutes))
    return f"{m} min" if m < 60 else f"{m // 60} h" + (f" {m % 60} min" if m % 60 else "")


@router.post("/bookings/search/flights")
async def search_flights(body: FlightSearch, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        offers = await c.bookings.search_flights(p.user_id, body.origin, body.destination, body.depart, body.adults, body.return_date,
                                                 arrive_by=body.arrive_by.replace(tzinfo=None) if body.arrive_by else None)
    except BookingError as e:
        raise _err(e) from e
    except Exception as e:  # noqa: BLE001 — provider outage degrades only this feature
        raise HTTPException(503, {"code": "provider_unavailable", "message": "Flight search is temporarily unavailable. Your trip is unaffected."}) from e
    insight = None
    best = next((o for o in offers if "BEST FIT" in o.badges), None)
    cheapest = next((o for o in offers if "CHEAPEST" in o.badges), None)
    if best and cheapest and best is not cheapest:
        diff = best.price - cheapest.price
        later = ((best.arrival - cheapest.arrival).total_seconds() // 60) if best.arrival and cheapest.arrival else None
        when = "" if not later else (f" and lands {_span(later)} earlier" if later > 0 else f" but lands {_span(later)} later")
        insight = f"The cheapest option saves {diff.display()}{when}."
    return {"offers": _offers(offers), "insight": insight, "sandbox": any(o.sandbox for o in offers)}


class StaySearch(BaseModel):
    check_in: date
    nights: int = Field(ge=1, le=30)
    guests: int = Field(default=2, ge=1, le=12)
    rooms: int = Field(default=1, ge=1, le=6)
    city: str | None = None


@router.post("/trips/{trip_id}/bookings/search/stays")
async def search_stays(body: StaySearch, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user),
                       c: Container = Depends(get_container)):
    """Ranked by HotelTripFit (where this trip actually goes), not by stars."""
    from app.domain.models import Money
    from app.recommendations.scoring import hotel_trip_fit, rough_convert

    city = body.city or trip.cities[0]
    offers = await c.bookings.search_stays(p.user_id, city, body.check_in, body.nights, body.guests, body.rooms)
    stops = [c.places.get(i.place_id) for i in trip.all_items() if i.kind == "sight"]
    stops = [s for s in stops if s and s.city == city]
    stations = c.places.search(city, categories={"station"}, limit=2000)
    country = c.places.city(city)["country"]
    nightly_budget = None
    if trip.budget:
        acc = next(line for line in trip.budget.lines if line.category == "accommodation").planned
        nightly_budget = rough_convert(acc, c.places.city(city)["currency"]).scale(1 / max(1, body.nights * body.rooms))
    ranked = []
    for o in offers:
        place = c.places.get(o.place_id) if o.place_id else None
        if not place:
            continue
        per_room_night = Money(amount_minor=o.price.amount_minor // max(1, body.nights * body.rooms), currency=o.price.currency)
        fit = hotel_trip_fit(place, stops, stations, trip.dna, country, nightly=per_room_night, nightly_budget=nightly_budget)
        o.location_fit = fit.location_fit
        o.meta.update({"fit_sentence": fit.sentence, "avg_minutes": fit.avg_minutes, "station_m": fit.nearest_station_m,
                       "fit_score": fit.score})
        ranked.append((fit.score, o))
    ranked.sort(key=lambda x: -x[0])
    top = [o for _, o in ranked[:25]]
    if top:
        top[0].badges.append("BEST LOCATION")
        cheapest = min(top, key=lambda o: o.price.amount_minor)
        cheapest.badges.append("CHEAPEST")
    return {"offers": _offers(top), "sandbox": True}


class GroundSearch(BaseModel):
    origin: str
    destination: str
    depart: date
    passengers: int = Field(default=1, ge=1, le=12)


@router.post("/bookings/search/ground")
async def search_ground(body: GroundSearch, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    offers = await c.bookings.search_ground(p.user_id, body.origin, body.destination, body.depart, body.passengers)
    insights = []
    if len(offers) >= 2:
        fastest = min(offers, key=lambda o: o.meta.get("door_to_door_min", 10**6))
        for o in offers:
            if o is not fastest:
                insights.append(compare_sentence(o, fastest))
    return {"offers": _offers(offers), "insights": insights, "sandbox": any(o.sandbox for o in offers)}


class StartBooking(BaseModel):
    offer_id: str = Field(min_length=4, max_length=120)
    travellers: int = Field(default=1, ge=1, le=9)


@router.post("/trips/{trip_id}/bookings")
async def start_booking(body: StartBooking, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user),
                        c: Container = Depends(get_container), idempotency_key: str = Header(alias="Idempotency-Key", min_length=8, max_length=80)):
    try:
        txn = await c.bookings.start(p.user_id, trip.id, body.offer_id, idempotency_key, body.travellers)
        txn = await c.bookings.revalidate(p.user_id, txn.id)
        return txn.model_dump(mode="json")
    except BookingError as e:
        raise _err(e) from e


@router.get("/trips/{trip_id}/bookings")
async def trip_bookings(trip: Trip = Depends(trip_access(CrewRole.VIEWER)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    return [t.model_dump(mode="json") for t in await c.bookings.list_for_trip(p.user_id, trip.id)]


@router.get("/bookings/{txn_id}")
async def get_booking(txn_id: str, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        return (await c.bookings.get(p.user_id, txn_id)).model_dump(mode="json")
    except BookingError as e:
        raise _err(e) from e


@router.post("/bookings/{txn_id}/revalidate")
async def revalidate(txn_id: str, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        return (await c.bookings.revalidate(p.user_id, txn_id)).model_dump(mode="json")
    except BookingError as e:
        raise _err(e) from e


class ConfirmPay(BaseModel):
    accepted_total_minor: int = Field(ge=0)
    travellers: list[Traveller] = Field(min_length=1, max_length=9)


@router.post("/bookings/{txn_id}/confirm")
async def confirm(txn_id: str, body: ConfirmPay, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    """The only endpoint that moves money. Called by a human pressing 'Confirm & pay <amount>' — never by the agent."""
    try:
        txn = await c.bookings.confirm_and_pay(p.user_id, txn_id, body.accepted_total_minor, body.travellers, step_up_done=p.aal == "aal2")
        return txn.model_dump(mode="json")
    except BookingError as e:
        raise _err(e) from e


@router.post("/bookings/{txn_id}/cancel-quote")
async def cancel_quote(txn_id: str, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        return await c.bookings.cancel_quote(p.user_id, txn_id)
    except BookingError as e:
        raise _err(e) from e


class CancelBody(BaseModel):
    accepted_refund_minor: int = Field(ge=0)


@router.post("/bookings/{txn_id}/cancel")
async def cancel(txn_id: str, body: CancelBody, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        return (await c.bookings.cancel(p.user_id, txn_id, body.accepted_refund_minor)).model_dump(mode="json")
    except BookingError as e:
        raise _err(e) from e
