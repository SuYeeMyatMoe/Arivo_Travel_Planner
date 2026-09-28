"""Provider contracts. Business logic depends on these, never on a supplier SDK."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from typing import Literal, Protocol

from app.bookings.models import Traveller, TravelOffer
from app.domain.models import Money


class SupplierAmbiguous(Exception):
    """Timeout/5xx after sending an order: the order MAY exist. Never retry — reconcile by reference instead."""


class SupplierRejected(Exception):
    """Definite failure (sold out, invalid passenger data). Safe to compensate (void payment)."""


@dataclass
class Revalidation:
    offer: TravelOffer
    changed: bool
    available: bool = True


@dataclass
class OrderResult:
    supplier_ref: str
    booking_reference: str
    status: Literal["confirmed", "pending"]


@dataclass
class CancelQuote:
    refund: Money
    fee: Money
    note: str


class FlightProvider(Protocol):
    name: str
    sandbox: bool

    async def search(self, origin: str, destination: str, depart: date, adults: int, cabin: str = "economy",
                     return_date: date | None = None) -> list[TravelOffer]: ...
    async def revalidate(self, offer: TravelOffer) -> Revalidation: ...
    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult: ...
    async def find_order(self, idempotency_key: str) -> OrderResult | None: ...
    async def cancel_quote(self, supplier_ref: str) -> CancelQuote: ...
    async def cancel(self, supplier_ref: str) -> Money: ...


class HotelProvider(Protocol):
    name: str
    sandbox: bool

    async def search(self, city: str, check_in: date, nights: int, guests: int, rooms: int) -> list[TravelOffer]: ...
    async def revalidate(self, offer: TravelOffer) -> Revalidation: ...
    async def create_order(self, offer: TravelOffer, travellers: list[Traveller], idempotency_key: str) -> OrderResult: ...
    async def find_order(self, idempotency_key: str) -> OrderResult | None: ...
    async def cancel_quote(self, supplier_ref: str) -> CancelQuote: ...
    async def cancel(self, supplier_ref: str) -> Money: ...


class GroundTransportProvider(HotelProvider, Protocol):
    async def search(self, origin: str, destination: str, depart: date, passengers: int) -> list[TravelOffer]: ...  # type: ignore[override]


@dataclass
class PaymentAuth:
    payment_ref: str
    status: Literal["authorized", "requires_action", "failed"]
    client_secret: str | None = None  # handed to the mobile PaymentSheet; never logged
    risk: str | None = None


class PaymentProvider(Protocol):
    name: str
    sandbox: bool

    async def authorize(self, amount: Money, idempotency_key: str, metadata: dict) -> PaymentAuth: ...
    async def capture(self, payment_ref: str, idempotency_key: str) -> None: ...
    async def void(self, payment_ref: str, idempotency_key: str) -> None: ...
    async def refund(self, payment_ref: str, amount: Money, idempotency_key: str) -> str: ...
    async def status(self, payment_ref: str) -> str: ...
