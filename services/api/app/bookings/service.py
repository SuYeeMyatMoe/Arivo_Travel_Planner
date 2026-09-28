"""Booking saga. The AI may search, compare and prepare; only this deterministic workflow spends money.

  SELECTED ─revalidate─▶ PRICE_CONFIRMED | PRICE_CHANGED (traveller must re-accept the new total)
  confirm & pay (accepted_total must equal the revalidated total):
    risk check → PAYMENT_PENDING → authorize (idempotent) → PAYMENT_AUTHORIZED
    → persist SUPPLIER_PENDING → supplier order (single attempt, idempotency key)
        ├─ confirmed  → capture → CONFIRMED → outbox BOOKING_CONFIRMED (itinerary + budget consumers)
        ├─ rejected   → void (compensation, logged) → FAILED
        └─ ambiguous  → stay SUPPLIER_PENDING + needs_reconciliation → Reconciler looks the order up; never re-books
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta
from typing import Any

from app.bookings.models import BookingTransaction, OfferType, Traveller, TravelOffer, TxnState
from app.bookings.providers.base import SupplierAmbiguous, SupplierRejected
from app.core.events import Event, EventBus
from app.domain.models import Money
from app.risk.engine import Decision, RiskSignals, amount_in_myr, assess, within
from app.store.base import AuditEvent, Store

log = logging.getLogger(__name__)
OFFER_TTL = timedelta(minutes=30)


class BookingError(Exception):
    def __init__(self, code: str, message: str, status: int = 400, extra: dict | None = None):
        super().__init__(message)
        self.code, self.status, self.extra = code, status, extra or {}


class BookingService:
    def __init__(self, store: Store, bus: EventBus, *, flights, hotels, ground, payments):
        self.store, self.bus = store, bus
        self.flights, self.hotels, self.ground, self.payments = flights, hotels, ground, payments

    # ------------------------------------------------------------------------------------------------ search
    def _provider(self, offer: TravelOffer):
        if offer.type == OfferType.STAY:
            return self.hotels
        if offer.provider.startswith("sandbox-ground") or offer.type in (OfferType.BUS, OfferType.RAIL) or offer.meta.get("mode"):
            return self.ground
        return self.flights

    async def _remember(self, user_id: str, offers: list[TravelOffer]) -> list[TravelOffer]:
        """Offers are cached server-side per user. Checkout takes an offer *id*; prices never come from the client."""
        for o in offers:
            await self.store.kv_put("offers", f"{user_id}:{o.offer_id}", {"offer": o.model_dump(mode="json"), "cached_at": datetime.utcnow().isoformat()})
        return offers

    async def search_flights(self, user_id: str, origin: str, destination: str, depart: date, adults: int, return_date: date | None = None,
                             arrive_by: datetime | None = None) -> list[TravelOffer]:
        if not self.flights:
            raise BookingError("not_configured", "Flight search isn't configured yet.", 503)
        offers = await self.flights.search(origin, destination, depart, adults, return_date=return_date)
        return await self._remember(user_id, badge_flights(offers, arrive_by))

    async def search_stays(self, user_id: str, city: str, check_in: date, nights: int, guests: int, rooms: int) -> list[TravelOffer]:
        offers = await self.hotels.search(city, check_in, nights, guests, rooms)
        return await self._remember(user_id, offers)

    async def search_ground(self, user_id: str, origin: str, destination: str, depart: date, passengers: int) -> list[TravelOffer]:
        offers = await self.ground.search(origin, destination, depart, passengers)
        return await self._remember(user_id, badge_ground(offers))

    async def _offer(self, user_id: str, offer_id: str) -> TravelOffer:
        rec = await self.store.kv_get("offers", f"{user_id}:{offer_id}")
        if not rec:
            raise BookingError("offer_not_found", "That offer has expired. Search again for current prices.", 404)
        if datetime.utcnow() - datetime.fromisoformat(rec["cached_at"]) > OFFER_TTL:
            raise BookingError("offer_expired", "That offer has expired. Search again for current prices.", 410)
        return TravelOffer(**rec["offer"])

    # ------------------------------------------------------------------------------------------------ saga
    async def start(self, user_id: str, trip_id: str, offer_id: str, idempotency_key: str, travellers_count: int) -> BookingTransaction:
        if not idempotency_key or len(idempotency_key) < 8:
            raise BookingError("idempotency_required", "Idempotency-Key header required", 400)
        existing_id = await self.store.kv_get("txn_by_key", f"{user_id}:{idempotency_key}")
        if existing_id:
            return await self.get(user_id, existing_id)
        offer = await self._offer(user_id, offer_id)
        txn = BookingTransaction(idempotency_key=idempotency_key, user_id=user_id, trip_id=trip_id, offer=offer, travellers_count=travellers_count)
        txn.transition(TxnState.SELECTED, f"offer {offer.offer_id} ({offer.provider})", user_id)
        # persist the key → txn mapping first; a concurrent duplicate loses the unique race and reads the winner
        if not await self.store.kv_put("txn_by_key", f"{user_id}:{idempotency_key}", txn.id, unique=True):
            return await self.get(user_id, await self.store.kv_get("txn_by_key", f"{user_id}:{idempotency_key}"))
        await self._save(txn)
        await self._audit(user_id, "booking.initiated", txn, "ok")
        return txn

    async def get(self, user_id: str, txn_id: str) -> BookingTransaction:
        rec = await self.store.kv_get("txns", txn_id)
        if not rec or rec["user_id"] != user_id:
            raise BookingError("not_found", "Booking not found", 404)  # same answer for "missing" and "not yours"
        return BookingTransaction(**rec)

    async def list_for_trip(self, user_id: str, trip_id: str) -> list[BookingTransaction]:
        return [BookingTransaction(**r) for r in await self.store.kv_list("txns") if r["trip_id"] == trip_id and r["user_id"] == user_id]

    async def revalidate(self, user_id: str, txn_id: str) -> BookingTransaction:
        txn = await self.get(user_id, txn_id)
        if txn.state not in (TxnState.SELECTED, TxnState.PRICE_CHANGED, TxnState.PRICE_CONFIRMED):
            return txn
        txn.transition(TxnState.REVALIDATING)
        rv = await self._provider(txn.offer).revalidate(txn.offer)
        if not rv.available:
            txn.transition(TxnState.FAILED, "offer no longer available")
            txn.failure_reason = "This option just sold out. Nothing was charged."
        elif rv.changed:
            old = txn.offer.price
            txn.offer = rv.offer
            txn.transition(TxnState.PRICE_CHANGED, f"price {old.display()} → {rv.offer.price.display()}")
        else:
            txn.offer = rv.offer
            txn.transition(TxnState.PRICE_CONFIRMED)
        await self._save(txn)
        return txn

    async def confirm_and_pay(self, user_id: str, txn_id: str, accepted_total_minor: int, travellers: list[Traveller],
                              step_up_done: bool = False) -> BookingTransaction:
        txn = await self.get(user_id, txn_id)
        if txn.state in (TxnState.CONFIRMED, TxnState.SUPPLIER_PENDING, TxnState.PAYMENT_AUTHORIZED, TxnState.PAYMENT_PENDING):
            return txn  # replay of the same confirm: return current state, never charge twice
        if txn.state == TxnState.PRICE_CHANGED:
            if accepted_total_minor != txn.offer.price.amount_minor:
                raise BookingError("price_changed", "The price changed. Review the new total before paying.", 409,
                                   {"new_total": txn.offer.price.model_dump(), "display": txn.offer.price.display()})
            txn.transition(TxnState.PRICE_CONFIRMED, "traveller accepted new price", user_id)
        if txn.state != TxnState.PRICE_CONFIRMED:
            raise BookingError("not_revalidated", "Check the latest price first.", 409)
        if accepted_total_minor != txn.offer.price.amount_minor:
            raise BookingError("price_mismatch", "The total you confirmed doesn't match the current price.", 409,
                               {"current_total": txn.offer.price.model_dump()})
        if len(travellers) != txn.travellers_count:
            raise BookingError("travellers", f"{txn.travellers_count} traveller(s) needed", 422)
        risk = await self._risk(user_id, txn.offer.price, step_up_done)
        if risk.decision in (Decision.BLOCK, Decision.MANUAL_REVIEW, Decision.RATE_LIMIT, Decision.CHALLENGE):
            await self._audit(user_id, "booking.risk_hold", txn, risk.decision.value, {"score": risk.score})
            code = {"CHALLENGE": "step_up_required", "RATE_LIMIT": "rate_limited"}.get(risk.decision.value, "review_required")
            raise BookingError(code, {"step_up_required": "Confirm it's you to continue.",
                                      "rate_limited": "Too many attempts. Try again later.",
                                      "review_required": "We need to review this booking. Nothing was charged."}[code],
                               {"step_up_required": 401, "rate_limited": 429}.get(code, 403), {"reasons": risk.reasons})
        await self.store.kv_put("booking_passengers", txn.id, [t.model_dump() for t in travellers])  # restricted domain
        txn.accepted_total = txn.offer.price
        txn.transition(TxnState.PAYMENT_PENDING, actor=user_id)
        await self._save(txn)
        auth = await self.payments.authorize(txn.offer.price, f"{txn.id}:auth",
                                             {"txn": txn.id, "trip": txn.trip_id, "provider": txn.offer.provider})
        if auth.status == "requires_action":
            txn.payment_ref = auth.payment_ref
            await self._save(txn)
            raise BookingError("payment_action", "Complete payment in the secure sheet.", 402, {"client_secret": auth.client_secret})
        if auth.status != "authorized":
            await self._failed_payment(user_id)
            txn.transition(TxnState.FAILED, f"payment {auth.risk or 'declined'}")
            txn.failure_reason = "Your payment was declined. Nothing was charged."
            await self._save(txn)
            return txn
        txn.payment_ref = auth.payment_ref
        txn.transition(TxnState.PAYMENT_AUTHORIZED, auth.payment_ref)
        txn.transition(TxnState.SUPPLIER_PENDING, "order sent")
        await self._save(txn)  # persisted BEFORE the supplier call
        return await self._place_order(txn, travellers)

    async def _place_order(self, txn: BookingTransaction, travellers: list[Traveller]) -> BookingTransaction:
        provider = self._provider(txn.offer)
        try:
            res = await provider.create_order(txn.offer, travellers, txn.id)
        except SupplierRejected as e:
            await self.payments.void(txn.payment_ref, f"{txn.id}:void")
            txn.transition(TxnState.FAILED, f"supplier rejected: {e}; payment voided (compensation)")
            txn.failure_reason = "The supplier couldn't confirm this booking. Your payment hold was released."
            await self._save(txn)
            await self._audit(txn.user_id, "booking.failed", txn, "compensated")
            return txn
        except SupplierAmbiguous as e:
            txn.needs_reconciliation = True
            txn.events[-1].note += f" · ambiguous: {e}"
            await self._save(txn)
            await self._audit(txn.user_id, "booking.ambiguous", txn, "reconcile")
            return txn
        return await self._confirm(txn, res.supplier_ref, res.booking_reference)

    async def _confirm(self, txn: BookingTransaction, supplier_ref: str, booking_reference: str) -> BookingTransaction:
        await self.payments.capture(txn.payment_ref, f"{txn.id}:capture")
        txn.supplier_ref, txn.booking_reference = supplier_ref, booking_reference
        txn.needs_reconciliation = False
        txn.transition(TxnState.CONFIRMED, f"ref {booking_reference}")
        await self._save(txn)
        await self._audit(txn.user_id, "booking.confirmed", txn, "ok")
        await self.bus.publish(Event("BOOKING_CONFIRMED", {"txn_id": txn.id, "trip_id": txn.trip_id, "user_id": txn.user_id}))
        return txn

    # ------------------------------------------------------------------------------------------------ reconciliation
    async def reconcile(self, txn_id: str) -> BookingTransaction:
        rec = await self.store.kv_get("txns", txn_id)
        txn = BookingTransaction(**rec)
        if txn.state != TxnState.SUPPLIER_PENDING:
            return txn
        found = await self._provider(txn.offer).find_order(txn.id)
        if found:
            return await self._confirm(txn, found.supplier_ref, found.booking_reference)
        if datetime.utcnow() - txn.updated_at > timedelta(minutes=20):
            await self.payments.void(txn.payment_ref, f"{txn.id}:void")
            txn.transition(TxnState.FAILED, "no supplier order after reconciliation window; payment voided")
            txn.failure_reason = "The supplier never confirmed. Your payment hold was released."
            await self._save(txn)
            await self._audit(txn.user_id, "booking.reconciled_failed", txn, "compensated")
        return txn

    async def reconcile_all(self) -> dict[str, int]:
        """BookingReconciler job: pending-ambiguous orders + drift between our state and supplier/payment state."""
        stats = {"checked": 0, "confirmed": 0, "failed": 0, "mismatch": 0}
        for rec in await self.store.kv_list("txns"):
            txn = BookingTransaction(**rec)
            if txn.state == TxnState.SUPPLIER_PENDING and txn.needs_reconciliation:
                stats["checked"] += 1
                out = await self.reconcile(txn.id)
                stats["confirmed" if out.state == TxnState.CONFIRMED else "failed" if out.state == TxnState.FAILED else "checked"] += 0 if out.state == TxnState.SUPPLIER_PENDING else 1
            elif txn.state == TxnState.CONFIRMED and txn.payment_ref:
                pay = await self.payments.status(txn.payment_ref)
                if pay not in {"succeeded", "requires_capture"}:
                    stats["mismatch"] += 1
                    await self._audit("system", "booking.mismatch", txn, f"payment:{pay}")
        return stats

    # ------------------------------------------------------------------------------------------------ cancellation
    async def cancel_quote(self, user_id: str, txn_id: str) -> dict:
        txn = await self.get(user_id, txn_id)
        if txn.state != TxnState.CONFIRMED:
            raise BookingError("not_cancellable", "Only confirmed bookings can be cancelled.", 409)
        q = await self._provider(txn.offer).cancel_quote(txn.supplier_ref)
        refund = q.refund if q.refund.currency == txn.offer.price.currency else Money.zero(txn.offer.price.currency)
        if txn.offer.refundable and txn.offer.sandbox:
            refund = txn.offer.price - Money.of(150, txn.offer.price.currency) if txn.offer.type == OfferType.FLIGHT else txn.offer.price
        txn.refund_quote = refund
        await self._save(txn)
        return {"refund": refund.model_dump(), "display": refund.display(), "fee": q.fee.model_dump(), "note": q.note,
                "policy": txn.offer.cancellation_policy}

    async def cancel(self, user_id: str, txn_id: str, accepted_refund_minor: int) -> BookingTransaction:
        txn = await self.get(user_id, txn_id)
        if txn.state != TxnState.CONFIRMED or txn.refund_quote is None:
            raise BookingError("quote_first", "Get the live cancellation quote first.", 409)
        if accepted_refund_minor != txn.refund_quote.amount_minor:
            raise BookingError("quote_changed", "The refund amount changed. Review it again.", 409)
        txn.transition(TxnState.CANCEL_PENDING, actor=user_id)
        await self._save(txn)
        await self._provider(txn.offer).cancel(txn.supplier_ref)
        if txn.refund_quote.amount_minor > 0:
            txn.transition(TxnState.REFUND_PENDING)
            await self.payments.refund(txn.payment_ref, txn.refund_quote, f"{txn.id}:refund")
            txn.transition(TxnState.REFUNDED, f"refund {txn.refund_quote.display()}")
        else:
            txn.transition(TxnState.CANCELLED)
        await self._save(txn)
        await self._audit(user_id, "booking.cancelled", txn, txn.state.value)
        await self.bus.publish(Event("BOOKING_CANCELLED", {"txn_id": txn.id, "trip_id": txn.trip_id, "user_id": user_id}))
        return txn

    # ------------------------------------------------------------------------------------------------ helpers
    async def _save(self, txn: BookingTransaction) -> None:
        await self.store.kv_put("txns", txn.id, txn.model_dump(mode="json"))

    async def _audit(self, actor: str, action: str, txn: BookingTransaction, result: str, meta: dict[str, Any] | None = None) -> None:
        await self.store.audit(AuditEvent(actor=actor, action=action, target=f"booking:{txn.id}", result=result, request_id=None,
                                          at=datetime.utcnow(), meta={"provider": txn.offer.provider, "state": txn.state.value,
                                                                      "amount": txn.offer.price.display(), **(meta or {})}))

    async def _risk(self, user_id: str, amount: Money, step_up_done: bool):
        txns = [BookingTransaction(**r) for r in await self.store.kv_list("txns") if r["user_id"] == user_id]
        fails = await self.store.kv_get("failed_payments", user_id) or []
        return assess(RiskSignals(
            bookings_last_hour=within([t.created_at for t in txns if t.state != TxnState.SELECTED], timedelta(hours=1)),
            failed_payments_last_hour=within([datetime.fromisoformat(x) for x in fails], timedelta(hours=1)),
            amount_home=amount_in_myr(amount), step_up_done=step_up_done))

    async def _failed_payment(self, user_id: str) -> None:
        fails = await self.store.kv_get("failed_payments", user_id) or []
        fails.append(datetime.utcnow().isoformat())
        await self.store.kv_put("failed_payments", user_id, fails[-20:])


def badge_flights(offers: list[TravelOffer], arrive_by: datetime | None = None) -> list[TravelOffer]:
    """CHEAPEST · FASTEST · BEST FIT (price/time balance). Never commission-driven; sponsored placement doesn't exist.

    With `arrive_by` (day 1 of the trip), a flight that lands after it can only be best fit if nothing lands in time.
    """
    if not offers:
        return offers
    cheapest = min(offers, key=lambda o: o.price.amount_minor)
    fastest = min(offers, key=lambda o: o.duration_min or 10**6)
    lo, hi = cheapest.price.amount_minor, max(o.price.amount_minor for o in offers) or 1
    dlo = fastest.duration_min or 1
    best = min(offers, key=lambda o: 0.55 * (o.price.amount_minor - lo) / max(1, hi - lo) + 0.45 * ((o.duration_min or dlo) - dlo) / max(1, dlo)
               + 0.1 * o.meta.get("stops", 0) + (2.0 if arrive_by and o.arrival and o.arrival.replace(tzinfo=None) > arrive_by else 0.0))
    for o in offers:
        o.badges = [b for b, cond in (("BEST FIT", o is best), ("CHEAPEST", o is cheapest), ("FASTEST", o is fastest)) if cond]
    return offers


def badge_ground(offers: list[TravelOffer]) -> list[TravelOffer]:
    if not offers:
        return offers
    cheapest = min(offers, key=lambda o: o.price.amount_minor)
    fastest = min(offers, key=lambda o: o.meta.get("door_to_door_min", 10**6))
    for o in offers:
        o.badges = [b for b, cond in (("CHEAPEST", o is cheapest), ("FASTEST", o is fastest)) if cond]
    return offers


def compare_sentence(a: TravelOffer, b: TravelOffer) -> str:
    """'Train is 40 minutes faster door-to-door.' / 'Bus saves RM 180 but arrives 2 h later.' (EST, computed)."""
    da, db = a.meta.get("door_to_door_min") or a.duration_min or 0, b.meta.get("door_to_door_min") or b.duration_min or 0
    if a.price.currency == b.price.currency:
        diff = b.price - a.price
        if diff.amount_minor > 0 and da > db:
            return f"{a.title} saves {diff.display()} but takes {(da - db) // 60} h {(da - db) % 60} min longer door-to-door."
    if da < db:
        return f"{a.title} is {db - da} minutes faster door-to-door."
    return f"{a.title} and {b.title} are close — pick by comfort."
