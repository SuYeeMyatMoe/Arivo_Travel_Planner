"""SANDBOX providers — used when partner APIs aren't approved/configured, and in tests.

They are deterministic (hash-seeded), refuse to run in production, and every offer is `sandbox=True` so the UI shows
the SANDBOX badge on search, checkout and confirmation. Hotels are real places (OpenStreetMap) with sandbox rates;
flights use a clearly fictional carrier. No money or real inventory is involved.
"""

from __future__ import annotations

import hashlib
from datetime import date, datetime, time, timedelta

from app.bookings.models import OfferType, PriceLine, Segment, Traveller, TravelOffer
from app.bookings.providers.base import CancelQuote, OrderResult, PaymentAuth, Revalidation, SupplierAmbiguous, SupplierRejected
from app.domain.models import Money, new_id
from app.places.providers import PlaceProvider


def _h(*parts: object) -> int:
    return int(hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()[:12], 16)


class _Orders:
    """Shared order book with failure injection for chaos tests (fail_next = "reject" | "timeout")."""

    def __init__(self) -> None:
        self.orders: dict[str, OrderResult] = {}
        self.cancelled: set[str] = set()
        self.fail_next: str | None = None
        self.price_bump_next: float = 0.0

    def create(self, prefix: str, key: str) -> OrderResult:
        if key in self.orders:  # supplier-side idempotency
            return self.orders[key]
        if self.fail_next == "reject":
            self.fail_next = None
            raise SupplierRejected("No longer available")
        res = OrderResult(supplier_ref=new_id(prefix), booking_reference=f"{prefix.upper()[:2]}{_h(key) % 10**6:06d}", status="confirmed")
        self.orders[key] = res
        if self.fail_next == "timeout":  # order DID get created, but the response is lost
            self.fail_next = None
            raise SupplierAmbiguous("timeout after send")
        return res

    def find(self, key: str) -> OrderResult | None:
        return self.orders.get(key)


class SandboxFlightProvider:
    name = "sandbox-air"
    sandbox = True

    def __init__(self) -> None:
        self.book = _Orders()

    async def search(self, origin: str, destination: str, depart: date, adults: int, cabin: str = "economy",
                     return_date: date | None = None) -> list[TravelOffer]:
        o, d = origin.upper()[:3], destination.upper()[:3]
        o = {"KUA": "KUL"}.get(o, o)
        d = {"TOK": "NRT", "TYO": "NRT"}.get(d, d)
        out = []
        variants = [("direct", 0, 7 * 60 + 5, 0), ("via BKK", 1, 9 * 60 + 50, -160), ("red-eye", 0, 6 * 60 + 55, -60), ("via TPE", 1, 11 * 60 + 20, -210)]
        for i, (label, stops, dur, delta) in enumerate(variants):
            dep_t = [time(7, 30), time(10, 15), time(23, 45), time(6, 10)][i]
            dep = datetime.combine(depart, dep_t)
            arr = dep + timedelta(minutes=dur + 60)  # +1h time zone KUL→JP
            per = 1180 + (_h(o, d, depart, i) % 260) + delta
            base, tax = round(per * 0.82), round(per * 0.18)
            total = Money.of(per * adults, "MYR")
            segs = [Segment(origin=o, destination=d, departure=dep, arrival=arr, carrier="Arivo Sandbox Air", number=f"ZZ {800 + i * 7}")]
            out.append(TravelOffer(
                offer_id=f"sbx_off_{_h(o, d, depart, i, adults):x}", provider=self.name, type=OfferType.FLIGHT, origin=o, destination=d,
                departure=dep, arrival=arr, duration_min=dur, segments=segs, price=total,
                base=Money.of(base * adults, "MYR"), taxes=Money.of(tax * adults, "MYR"),
                lines=[PriceLine(label="Base fare", amount=Money.of(base * adults, "MYR")), PriceLine(label="Taxes", amount=Money.of(tax * adults, "MYR")),
                       PriceLine(label="Checked bag 23 kg", amount=Money.zero("MYR")), PriceLine(label="Booking fee", amount=Money.zero("MYR"))],
                baggage="1× 23 kg checked, 1× 7 kg cabin", refundable=i % 2 == 0, changeable=True,
                cancellation_policy="Refundable minus RM 150 fee" if i % 2 == 0 else "Non-refundable (taxes returned)",
                change_policy="Changes allowed · RM 150 + fare difference", expires_at=datetime.utcnow() + timedelta(minutes=30),
                sandbox=True, title=f"{o} → {d}", subtitle=f"Arivo Sandbox Air · {'Direct' if not stops else '1 stop'} · {label}",
                meta={"stops": stops, "passenger_ids": [f"pas_{k}" for k in range(adults)]}))
        return sorted(out, key=lambda x: x.price.amount_minor)

    async def revalidate(self, offer: TravelOffer) -> Revalidation:
        bump = self.book.price_bump_next
        self.book.price_bump_next = 0.0
        if bump:
            fresh = offer.model_copy(update={"price": offer.price.scale(1 + bump)})
            return Revalidation(offer=fresh, changed=True)
        return Revalidation(offer=offer, changed=False)

    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult:
        return self.book.create("fl", idempotency_key)

    async def find_order(self, idempotency_key: str) -> OrderResult | None:
        return self.book.find(idempotency_key)

    async def cancel_quote(self, supplier_ref: str) -> CancelQuote:
        return CancelQuote(refund=Money.zero("MYR"), fee=Money.of(150, "MYR"), note="Sandbox: fee RM 150 per ticket")

    async def cancel(self, supplier_ref: str) -> Money:
        self.book.cancelled.add(supplier_ref)
        return Money.zero("MYR")


class SandboxHotelProvider:
    """Real hotels (OpenStreetMap) with deterministic sandbox nightly rates. Not bookable for real."""

    name = "sandbox-stays"
    sandbox = True

    def __init__(self, places: PlaceProvider):
        self.places = places
        self.book = _Orders()

    async def search(self, city: str, check_in: date, nights: int, guests: int, rooms: int) -> list[TravelOffer]:
        info = self.places.city(city)
        if not info:
            return []
        cur = info["currency"]
        out = []
        from app.recommendations.scoring import estimate_nightly

        for p in self.places.search(city, categories={"hotel", "hostel", "guest_house"}, limit=500):
            stars = float(p.tags.get("stars", "0") or 0)
            base = estimate_nightly(p, cur).amount  # same model the planner estimates with, so sandbox ≈ plan
            nightly = base * (0.85 + (_h(p.id, check_in) % 40) / 100) * max(1, rooms)
            total = Money.of(nightly * nights, cur)
            tax = total.scale(0.10)
            refundable = _h(p.id) % 3 != 0
            out.append(TravelOffer(
                offer_id=f"sbx_stay_{_h(p.id, check_in, nights, guests, rooms):x}", provider=self.name, type=OfferType.STAY,
                price=total + tax, base=total, taxes=tax,
                lines=[PriceLine(label=f"{nights} night{'s' if nights > 1 else ''} × {rooms} room", amount=total),
                       PriceLine(label="Taxes and service", amount=tax), PriceLine(label="Booking fee", amount=Money.zero(cur))],
                refundable=refundable,
                cancellation_policy=f"Free cancellation until {check_in - timedelta(days=3):%d %b}" if refundable else "Non-refundable",
                change_policy="Date changes subject to availability", departure=datetime.combine(check_in, time(15)),
                arrival=datetime.combine(check_in + timedelta(days=nights), time(11)), sandbox=True, title=p.name,
                subtitle=f"{p.category.replace('_', ' ').title()}{f' · {int(stars)}★' if stars else ''} · Pay now (sandbox)",
                place_id=p.id, lat=p.lat, lon=p.lon,
                meta={"nightly": Money.of(nightly, cur).model_dump(), "nights": nights, "check_in": "15:00", "check_out": "11:00",
                      "rating_source": "OpenStreetMap stars tag" if stars else None}))
        return out

    async def revalidate(self, offer: TravelOffer) -> Revalidation:
        bump = self.book.price_bump_next
        self.book.price_bump_next = 0.0
        if bump:
            return Revalidation(offer=offer.model_copy(update={"price": offer.price.scale(1 + bump)}), changed=True)
        return Revalidation(offer=offer, changed=False)

    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult:
        return self.book.create("st", idempotency_key)

    async def find_order(self, idempotency_key: str) -> OrderResult | None:
        return self.book.find(idempotency_key)

    async def cancel_quote(self, supplier_ref: str) -> CancelQuote:
        return CancelQuote(refund=Money.zero("MYR"), fee=Money.zero("MYR"), note="Sandbox: policy shown on the offer applies")

    async def cancel(self, supplier_ref: str) -> Money:
        self.book.cancelled.add(supplier_ref)
        return Money.zero("MYR")


# Door-to-door options between seeded cities. Durations include getting to/from stations/airports.
GROUND_ROUTES = {
    ("tokyo", "kyoto"): [
        ("rail", "Tokaido Shinkansen (Nozomi)", "Tokyo Station", "Kyoto Station", 135, 50, 14170, "Reserved seat · 2 large bags"),
        ("bus", "Overnight highway bus", "Busta Shinjuku", "Kyoto Station Hachijo Exit", 480, 40, 6200, "Reclining seat · 1 bag"),
        ("flight", "HND → ITM + limousine bus", "Haneda Airport", "Itami Airport", 70, 170, 19800, "Includes airport transfers"),
    ],
    ("kuala-lumpur", "melaka"): [("bus", "Express coach", "TBS Bandar Tasik Selatan", "Melaka Sentral", 135, 45, 13.5, "Assigned seat")],
    ("kuala-lumpur", "ipoh"): [("rail", "KTM ETS", "KL Sentral", "Ipoh Station", 150, 35, 46, "Assigned seat")],
}


class SandboxGroundProvider:
    name = "sandbox-ground"
    sandbox = True

    def __init__(self) -> None:
        self.book = _Orders()

    async def search(self, origin: str, destination: str, depart: date, passengers: int) -> list[TravelOffer]:
        key = (origin.lower(), destination.lower())
        rev = key not in GROUND_ROUTES
        routes = GROUND_ROUTES.get(key) or GROUND_ROUTES.get((key[1], key[0])) or []
        out = []
        for i, (mode, operator, dep_st, arr_st, ride, access, fare, seat) in enumerate(routes):
            if rev:
                dep_st, arr_st = arr_st, dep_st
            dep = datetime.combine(depart, [time(9, 33), time(22, 50), time(10, 30)][i % 3])
            arr = dep + timedelta(minutes=ride)
            cur = "JPY" if key[0] in {"tokyo", "kyoto"} or key[1] in {"tokyo", "kyoto"} else "MYR"
            total = Money.of(fare * passengers, cur)
            out.append(TravelOffer(
                offer_id=f"sbx_gnd_{_h(key, depart, i, passengers):x}", provider=self.name,
                type=OfferType.RAIL if mode == "rail" else OfferType.BUS if mode == "bus" else OfferType.FLIGHT,
                origin=dep_st, destination=arr_st, departure=dep, arrival=arr, duration_min=ride + access,
                segments=[Segment(origin=dep_st, destination=arr_st, departure=dep, arrival=arr, carrier=operator)],
                price=total, lines=[PriceLine(label=f"{passengers} × fare", amount=total), PriceLine(label="Booking fee", amount=Money.zero(cur))],
                refundable=mode != "flight", changeable=True, cancellation_policy="Refund minus 10% before departure" if mode != "flight" else "Non-refundable",
                sandbox=True, title=f"{operator}", subtitle=f"{dep_st} → {arr_st} · {seat}",
                meta={"mode": mode, "ride_min": ride, "access_min": access, "door_to_door_min": ride + access,
                      "departure_station": dep_st, "arrival_station": arr_st, "seat": seat}))
        return out

    async def revalidate(self, offer: TravelOffer) -> Revalidation:
        return Revalidation(offer=offer, changed=False)

    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult:
        return self.book.create("gt", idempotency_key)

    async def find_order(self, idempotency_key: str) -> OrderResult | None:
        return self.book.find(idempotency_key)

    async def cancel_quote(self, supplier_ref: str) -> CancelQuote:
        return CancelQuote(refund=Money.zero("MYR"), fee=Money.zero("MYR"), note="Sandbox: refund minus 10%")

    async def cancel(self, supplier_ref: str) -> Money:
        self.book.cancelled.add(supplier_ref)
        return Money.zero("MYR")


class SandboxPaymentProvider:
    """Authorisations held in memory. Used only when Stripe test keys are not configured."""

    name = "sandbox-pay"
    sandbox = True

    def __init__(self) -> None:
        self.intents: dict[str, dict] = {}
        self.by_key: dict[str, str] = {}
        self.decline_next = False

    async def authorize(self, amount: Money, idempotency_key: str, metadata: dict) -> PaymentAuth:
        if idempotency_key in self.by_key:
            ref = self.by_key[idempotency_key]
            return PaymentAuth(payment_ref=ref, status="authorized" if self.intents[ref]["status"] == "requires_capture" else "failed")
        if self.decline_next:
            self.decline_next = False
            return PaymentAuth(payment_ref="", status="failed", risk="card_declined")
        ref = new_id("pi_sbx")
        self.intents[ref] = {"amount": amount, "status": "requires_capture", "captured": 0, "refunded": 0, "meta": metadata}
        self.by_key[idempotency_key] = ref
        return PaymentAuth(payment_ref=ref, status="authorized")

    async def capture(self, payment_ref: str, idempotency_key: str) -> None:
        intent = self.intents[payment_ref]
        if intent["status"] == "requires_capture":
            intent["status"] = "succeeded"
            intent["captured"] = intent["amount"].amount_minor

    async def void(self, payment_ref: str, idempotency_key: str) -> None:
        if payment_ref in self.intents and self.intents[payment_ref]["status"] == "requires_capture":
            self.intents[payment_ref]["status"] = "canceled"

    async def refund(self, payment_ref: str, amount: Money, idempotency_key: str) -> str:
        self.intents[payment_ref]["refunded"] += amount.amount_minor
        return new_id("re_sbx")

    async def status(self, payment_ref: str) -> str:
        return self.intents.get(payment_ref, {}).get("status", "unknown")
