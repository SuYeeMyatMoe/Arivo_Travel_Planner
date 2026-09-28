"""TripService: the Living Trip's single write path.

Every change is a TripChange (proposed → applied/rejected), version-checked against the trip, and audited.
Bookings become hard constraints here (BOOKING_CONFIRMED consumer).
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta

from app.ai.graphs.plan_trip import build_plan_graph
from app.ai.router import ModelRouter
from app.bookings.models import BookingTransaction, OfferType
from app.core.events import Event, EventBus
from app.domain.models import (
    CrewMember, CrewRole, Evidence, ItemStatus, ItineraryItem, Money, Provenance, TravelerDNA, Trip, TripChange,
)
from app.planning.engine import TripPlanner
from app.planning.replan import Replanner, ReplanRequest, Trigger
from app.store.base import AuditEvent, Store, VersionConflict

log = logging.getLogger(__name__)
AIRPORT_EXIT_MIN = 75  # immigration + baggage, conservative


class TripError(Exception):
    def __init__(self, code: str, message: str, status: int = 400, extra: dict | None = None):
        super().__init__(message)
        self.code, self.status, self.extra = code, status, extra or {}


class TripService:
    def __init__(self, store: Store, planner: TripPlanner, replanner: Replanner, router: ModelRouter, bus: EventBus):
        self.store, self.planner, self.replanner, self.router, self.bus = store, planner, replanner, router, bus
        self.graph = build_plan_graph(planner, router, replanner)
        bus.subscribe("BOOKING_CONFIRMED", "itinerary", self._on_booking_confirmed)
        bus.subscribe("BOOKING_CANCELLED", "itinerary", self._on_booking_cancelled)

    # ------------------------------------------------------------------------------------------------ create
    async def create_from_text(self, owner_id: str, owner_name: str, text: str, overrides: dict | None = None,
                               iconic_local: float = 0.0, today: date | None = None) -> dict:
        state = await self.graph.ainvoke({"text": text, "owner_id": owner_id, "overrides": overrides or {}, "iconic_local": iconic_local,
                                          "today": today or date.today(), "trace": []})
        if state.get("question"):
            return {"status": "needs_input", "question": state["question"], "intent": state["intent"].model_dump(mode="json")}
        if state.get("error"):
            return {"status": "error", "error": state["error"], "intent": state["intent"].model_dump(mode="json")}
        trip: Trip = state["trip"]
        trip.crew = [CrewMember(user_id=owner_id, display_name=owner_name, role=CrewRole.OWNER, color_index=0, dna=trip.dna)]
        stored = await self.store.put_trip(trip)
        await self._audit(owner_id, "trip.created", stored.id, "ok", {"parser": trip.intent.parser, "trace": state.get("trace")})
        return {"status": "ok", "trip": stored, "trace": state.get("trace", [])}

    # ------------------------------------------------------------------------------------------------ changes
    async def propose_replan(self, trip: Trip, req: ReplanRequest, actor: str) -> TripChange:
        change = self.replanner.replan(trip, req)
        if self.router.available and (change.removed or change.added):
            from app.ai.router import ChangeNarration

            summary = (f"Trigger: {req.trigger.value}. Kept: {[k.name for k in change.kept]}. Moved: {[(m.name, m.from_time, m.to_time) for m in change.moved]}. "
                       f"Removed: {[(r.name, r.reason) for r in change.removed]}. Added: {[(a.name, a.detail) for a in change.added]}. "
                       f"Time delta {change.time_delta_min} min. Budget delta {change.budget_delta.display() if change.budget_delta else '0'}.")
            out, _ = await self.router.structured("plan", EXPLAIN_SYSTEM, summary, ChangeNarration, max_tokens=300)
            if out and 20 <= len(out.explanation) <= 400:
                change.explanation = out.explanation
        await self.store.put_change(change)
        await self._audit(actor, "trip.change_proposed", trip.id, req.trigger.value, {"change": change.id})
        return change

    async def apply_change(self, trip_id: str, change_id: str, actor: str) -> Trip:
        change = await self.store.get_change(change_id)
        if not change or change.trip_id != trip_id:
            raise TripError("not_found", "Change not found", 404)
        if change.status != "proposed":
            raise TripError("not_pending", f"This change was already {change.status}.", 409)
        trip = await self.store.get_trip(trip_id)
        if trip.version != change.base_version:
            raise TripError("stale", "The trip changed since this proposal. Rescue again for a fresh plan.", 409)
        day = trip.days[change.day_index]
        day.items = change.new_items
        try:
            day.plan_b = self.replanner.plan_b(trip, change.day_index)
        except Exception:  # noqa: BLE001
            day.plan_b = []
        try:
            stored = await self.store.put_trip(trip, expected_version=change.base_version)
        except VersionConflict as e:
            raise TripError("stale", "The trip changed since this proposal. Rescue again for a fresh plan.", 409) from e
        change.status = "applied"
        await self.store.put_change(change)
        await self._audit(actor, "trip.change_applied", trip_id, "ok", {"change": change_id, "trigger": change.trigger})
        await self.bus.publish(Event("TRIP_CHANGED", {"trip_id": trip_id, "version": stored.version, "change_id": change_id}))
        return stored

    async def reject_change(self, trip_id: str, change_id: str, actor: str) -> None:
        change = await self.store.get_change(change_id)
        if not change or change.trip_id != trip_id:
            raise TripError("not_found", "Change not found", 404)
        change.status = "rejected"
        await self.store.put_change(change)
        await self._audit(actor, "trip.change_rejected", trip_id, "ok", {"change": change_id})

    async def edit_item(self, trip: Trip, item_id: str, action: str, actor: str, *, new_start: str | None = None) -> Trip:
        """Direct traveller edits (the human is deciding): remove, move to a time, mark done. Bookings can't be edited here."""
        for day in trip.days:
            for it in day.items:
                if it.id != item_id:
                    continue
                if it.locked and action != "done":
                    raise TripError("locked", "This is a booking. Change or cancel it in My Bookings.", 409)
                if action == "remove":
                    day.items.remove(it)
                elif action == "done":
                    it.status = ItemStatus.DONE
                elif action == "move" and new_start:
                    hh, mm = map(int, new_start.split(":"))
                    it.start = it.start.replace(hour=hh, minute=mm)
                    day.items.sort(key=lambda x: x.start)
                else:
                    raise TripError("bad_action", "Unknown edit", 422)
                stored = await self.store.put_trip(trip, expected_version=trip.version)
                await self._audit(actor, f"trip.item_{action}", trip.id, "ok", {"item": item_id})
                return stored
        raise TripError("not_found", "Item not found", 404)

    # ------------------------------------------------------------------------------------------------ bookings → constraints
    async def _on_booking_confirmed(self, ev: Event) -> None:
        rec = await self.store.kv_get("txns", ev.payload["txn_id"])
        txn = BookingTransaction(**rec)
        for attempt in range(3):
            trip = await self.store.get_trip(txn.trip_id)
            if not trip:
                return
            changes = self._apply_booking(trip, txn)
            try:
                await self.store.put_trip(trip, expected_version=trip.version)
            except VersionConflict:
                continue
            for ch in changes:
                await self.store.put_change(ch)  # auditable, reversible record of what the booking changed
            await self._audit("system", "trip.booking_constraint", trip.id, "ok", {"txn": txn.id})
            return

    def _apply_booking(self, trip: Trip, txn: BookingTransaction) -> list[TripChange]:
        o = txn.offer
        cat = {"flight": "flights", "stay": "accommodation"}.get(o.type.value, "transport")
        if trip.budget:  # reserved money shows in Budget Brain
            for line in trip.budget.lines:
                if line.category == cat and o.price.currency == line.reserved.currency:
                    line.reserved = line.reserved + o.price
                    line.provenance = Provenance.LIVE
        if o.type == OfferType.STAY and o.place_id:
            trip.hotel_place_id = o.place_id
            day = next((d for d in trip.days if d.date == (o.departure.date() if o.departure else None)), None)
            if day:
                day.items.append(ItineraryItem(place_id=o.place_id, name=f"Check in · {o.title}", category="hotel", lat=o.lat or 0, lon=o.lon or 0,
                                               start=o.departure, duration_min=30, kind="stay", locked=True, status=ItemStatus.BOOKED,
                                               booking_id=txn.id, reason=f"Booked · ref {txn.booking_reference}",
                                               evidence=[Evidence(text=o.cancellation_policy, provenance=Provenance.LIVE, source=o.provider)]))
                day.items.sort(key=lambda i: i.start)
            return []
        if o.arrival and o.type in (OfferType.FLIGHT, OfferType.RAIL, OfferType.BUS):
            day_idx = next((d.index for d in trip.days if d.date == o.arrival.date()), None)
            if day_idx is None:
                if trip.days and o.arrival.date() == trip.days[0].date - timedelta(days=1):
                    # Landing the evening before day 1: nothing to reschedule, but the booking belongs at the top of day 1.
                    first = trip.days[0]
                    first.items.insert(0, ItineraryItem(
                        place_id=f"booking:{txn.id}", name=f"Landed {o.destination} the night before · {o.arrival:%a %H:%M}", category="transfer",
                        lat=first.items[0].lat if first.items else 0, lon=first.items[0].lon if first.items else 0, start=o.arrival, duration_min=15,
                        kind="transfer", locked=True, status=ItemStatus.BOOKED, booking_id=txn.id,
                        reason=f"Booked · ref {txn.booking_reference}" + (" · SANDBOX" if o.sandbox else ""),
                        evidence=[Evidence(text=f"{o.subtitle}", provenance=Provenance.LIVE, source=o.provider)]))
                return []
            day = trip.days[day_idx]
            label = f"Arrive {o.destination}" if o.type == OfferType.FLIGHT else f"{o.title}"
            fixed = ItineraryItem(place_id=f"booking:{txn.id}", name=label, category="transfer", lat=day.items[0].lat if day.items else 0,
                                  lon=day.items[0].lon if day.items else 0, start=o.departure if o.departure and o.departure.date() == day.date else o.arrival,
                                  duration_min=max(15, int(((o.arrival - o.departure).total_seconds() // 60) if o.departure and o.departure.date() == day.date else 15)),
                                  kind="transfer", locked=True, status=ItemStatus.BOOKED, booking_id=txn.id,
                                  reason=f"Booked · ref {txn.booking_reference}" + (" · SANDBOX" if o.sandbox else ""),
                                  evidence=[Evidence(text=f"{o.subtitle}", provenance=Provenance.LIVE, source=o.provider)])
            ready = o.arrival + timedelta(minutes=AIRPORT_EXIT_MIN if o.type == OfferType.FLIGHT else 20)
            # nothing may be scheduled before the traveller can actually be there
            change = self.replanner.replan(trip, ReplanRequest(trigger=Trigger.DELAY, day_index=day_idx, now=ready, minutes_late=0))
            kept_items = [i for i in change.new_items if i.start >= ready or i.locked]
            day.items = sorted([fixed, *kept_items], key=lambda i: i.start)
            change.status = "applied"
            change.explanation = f"Your {o.type.value} arrives {o.arrival:%H:%M}; the day now starts after {ready:%H:%M}."
            change.trigger = "booking"
            return [change]
        return []

    async def _on_booking_cancelled(self, ev: Event) -> None:
        trip = await self.store.get_trip(ev.payload["trip_id"])
        if not trip:
            return
        for d in trip.days:
            d.items = [i for i in d.items if i.booking_id != ev.payload["txn_id"]]
        await self.store.put_trip(trip, expected_version=trip.version)

    # ------------------------------------------------------------------------------------------------ helpers
    async def _audit(self, actor: str, action: str, trip_id: str, result: str, meta: dict | None = None) -> None:
        await self.store.audit(AuditEvent(actor=actor, action=action, target=f"trip:{trip_id}", result=result, request_id=None,
                                          at=datetime.utcnow(), meta=meta or {}))


EXPLAIN_SYSTEM = """You explain an itinerary change to a traveller in 1–2 short sentences, second person, calm and specific.
Use only the facts given (names, times, deltas). Mention that bookings stayed fixed if any were kept. No emoji."""


def learn_from(dna: TravelerDNA, place_dna: dict[str, float], action: str) -> TravelerDNA:
    """Progressive personalisation: saves/completions nudge up, removals/skips nudge down."""
    rate = {"save": 0.6, "done": 0.4, "like": 0.8, "book": 1.0, "remove": -0.5, "skip": -0.3, "not_for_me": -1.0}.get(action, 0.0)
    return dna.nudge(place_dna, rate) if rate else dna


__all__ = ["TripService", "TripError", "learn_from", "Money"]
