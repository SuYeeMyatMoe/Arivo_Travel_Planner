"""Duffel flights (https://duffel.com/docs/api). Test tokens (duffel_test_…) book against Duffel's test environment.

Order creation is a single attempt. A timeout after sending is SupplierAmbiguous → reconciliation looks the order
up by the Arivo transaction id stored in order metadata; it never re-books.
"""

from __future__ import annotations

import re
from datetime import date, datetime

import httpx

from app.bookings.models import OfferType, PriceLine, Segment, Traveller, TravelOffer
from app.bookings.providers.base import CancelQuote, OrderResult, Revalidation, SupplierAmbiguous, SupplierRejected
from app.core.resilience import ProviderUnavailable, ResilientClient
from app.domain.models import Money

CITY_CODES = {"tokyo": "TYO", "kyoto": "OSA", "kuala-lumpur": "KUL", "kuala lumpur": "KUL", "osaka": "OSA", "singapore": "SIN", "penang": "PEN"}


def _minutes(iso: str | None) -> int | None:
    if not iso:
        return None
    m = re.match(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?", iso)
    if not m:
        return None
    d, h, mi = (int(x) if x else 0 for x in m.groups())
    return d * 1440 + h * 60 + mi


def _money(amount: str | None, currency: str | None) -> Money | None:
    return Money.of(float(amount), currency) if amount and currency else None


class DuffelProvider:
    name = "duffel"

    def __init__(self, token: str, transport: httpx.AsyncBaseTransport | None = None):
        self.sandbox = token.startswith("duffel_test_")
        self.http = ResilientClient("duffel", "https://api.duffel.com", timeout_s=25, max_concurrency=4, get_retries=1,
                                    headers={"Authorization": f"Bearer {token}", "Duffel-Version": "v2", "Accept": "application/json"},
                                    transport=transport)

    def _normalize(self, o: dict) -> TravelOffer:
        slices = o.get("slices", [])
        segs: list[Segment] = []
        for s in slices:
            for g in s.get("segments", []):
                segs.append(Segment(
                    origin=g["origin"]["iata_code"], destination=g["destination"]["iata_code"],
                    origin_name=g["origin"].get("name"), destination_name=g["destination"].get("name"),
                    departure=datetime.fromisoformat(g["departing_at"]), arrival=datetime.fromisoformat(g["arriving_at"]),
                    carrier=(g.get("marketing_carrier") or {}).get("name", "?"),
                    number=f"{(g.get('marketing_carrier') or {}).get('iata_code', '')} {g.get('marketing_carrier_flight_number', '')}".strip(),
                    terminal_from=g.get("origin_terminal"), terminal_to=g.get("destination_terminal")))
        cur = o["total_currency"]
        conditions = o.get("conditions") or {}
        refund = conditions.get("refund_before_departure") or {}
        change = conditions.get("change_before_departure") or {}
        stops = max(0, len(slices[0].get("segments", [])) - 1) if slices else 0
        bags = []
        for p in (slices[0].get("segments", [{}])[0].get("passengers", []) if slices else []):
            for b in p.get("baggages", []):
                bags.append(f"{b.get('quantity', 0)}× {b.get('type', 'bag').replace('_', ' ')}")
        lines = [PriceLine(label="Base fare", amount=_money(o.get("base_amount"), o.get("base_currency") or cur) or Money.zero(cur)),
                 PriceLine(label="Taxes and fees", amount=_money(o.get("tax_amount"), o.get("tax_currency") or cur) or Money.zero(cur))]
        return TravelOffer(
            offer_id=o["id"], provider=self.name, type=OfferType.FLIGHT,
            origin=segs[0].origin if segs else None, destination=segs[-1].destination if segs else None,
            departure=segs[0].departure if segs else None, arrival=segs[-1].arrival if segs else None,
            duration_min=_minutes(slices[0].get("duration")) if slices else None, segments=segs,
            price=Money.of(float(o["total_amount"]), cur), base=lines[0].amount, taxes=lines[1].amount, lines=lines,
            baggage=", ".join(bags) or "Check fare rules", refundable=bool(refund.get("allowed")), changeable=bool(change.get("allowed")),
            cancellation_policy=("Refundable" + (f" (fee {refund.get('penalty_amount')} {refund.get('penalty_currency')})" if refund.get("penalty_amount") else "")) if refund.get("allowed") else "Non-refundable",
            change_policy=("Changes allowed" + (f" (fee {change.get('penalty_amount')} {change.get('penalty_currency')})" if change.get("penalty_amount") else "")) if change.get("allowed") else "No changes",
            expires_at=datetime.fromisoformat(o["expires_at"]) if o.get("expires_at") else None, sandbox=self.sandbox,
            title=f"{segs[0].origin} → {segs[-1].destination}" if segs else "Flight",
            subtitle=f"{(o.get('owner') or {}).get('name', '')} · {'Direct' if stops == 0 else f'{stops} stop' + ('s' if stops > 1 else '')}",
            meta={"passenger_ids": [p["id"] for p in o.get("passengers", [])], "stops": stops,
                  "emissions_kg": o.get("total_emissions_kg"), "owner": (o.get("owner") or {}).get("name")},
        )

    async def search(self, origin: str, destination: str, depart: date, adults: int, cabin: str = "economy",
                     return_date: date | None = None) -> list[TravelOffer]:
        o = CITY_CODES.get(origin.lower(), origin.upper())
        d = CITY_CODES.get(destination.lower(), destination.upper())
        slices = [{"origin": o, "destination": d, "departure_date": depart.isoformat()}]
        if return_date:
            slices.append({"origin": d, "destination": o, "departure_date": return_date.isoformat()})
        body = {"data": {"slices": slices, "passengers": [{"type": "adult"}] * adults, "cabin_class": cabin}}
        res = await self.http.post_json("/air/offer_requests?return_offers=true&supplier_timeout=20000", body)
        offers = [self._normalize(x) for x in res["data"].get("offers", [])]
        return sorted(offers, key=lambda x: x.price.amount_minor)[:30]

    async def revalidate(self, offer: TravelOffer) -> Revalidation:
        try:
            res = await self.http.get_json(f"/air/offers/{offer.offer_id}", {"return_available_services": "false"})
        except httpx.HTTPStatusError as e:
            if e.response.status_code in (404, 422):
                return Revalidation(offer=offer, changed=True, available=False)
            raise
        fresh = self._normalize(res["data"])
        return Revalidation(offer=fresh, changed=fresh.price != offer.price)

    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult:
        ids = offer.meta.get("passenger_ids", [])
        if len(ids) != len(travellers):
            raise SupplierRejected("traveller count doesn't match the offer")
        passengers = [{
            "id": pid, "given_name": t.given_name, "family_name": t.family_name, "born_on": t.born_on, "title": t.title or "mr",
            "gender": t.gender or "m", "email": t.email, "phone_number": t.phone,
        } for pid, t in zip(ids, travellers)]
        body = {"data": {"type": "instant", "selected_offers": [offer.offer_id], "passengers": passengers,
                         "payments": [{"type": "balance", "currency": offer.price.currency, "amount": f"{offer.price.amount:.2f}"}],
                         "metadata": {"arivo_txn": idempotency_key}}}
        try:
            res = await self.http.post_json("/air/orders", body, headers={"Idempotency-Key": idempotency_key})
        except ProviderUnavailable as e:
            raise SupplierAmbiguous(str(e)) from e
        except httpx.HTTPStatusError as e:
            raise SupplierRejected(e.response.text[:300]) from e
        data = res["data"]
        return OrderResult(supplier_ref=data["id"], booking_reference=data.get("booking_reference", ""), status="confirmed")

    async def find_order(self, idempotency_key: str) -> OrderResult | None:
        res = await self.http.get_json("/air/orders", {"limit": 50})
        for o in res.get("data", []):
            if (o.get("metadata") or {}).get("arivo_txn") == idempotency_key:
                return OrderResult(supplier_ref=o["id"], booking_reference=o.get("booking_reference", ""), status="confirmed")
        return None

    async def cancel_quote(self, supplier_ref: str) -> CancelQuote:
        res = await self.http.post_json("/air/order_cancellations", {"data": {"order_id": supplier_ref}})
        d = res["data"]
        return CancelQuote(refund=Money.of(float(d.get("refund_amount") or 0), d.get("refund_currency") or "USD"),
                           fee=Money.zero(d.get("refund_currency") or "USD"), note=f"quote:{d['id']}")

    async def cancel(self, supplier_ref: str) -> Money:
        quote = await self.cancel_quote(supplier_ref)
        cid = quote.note.split(":", 1)[1]
        await self.http.post_json(f"/air/order_cancellations/{cid}/actions/confirm", {})
        return quote.refund
