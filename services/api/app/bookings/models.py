"""Normalized booking models. Supplier payloads never leave the backend; Flutter only sees these shapes."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field

from app.domain.models import Money, new_id


class OfferType(StrEnum):
    FLIGHT = "flight"
    STAY = "stay"
    BUS = "bus"
    RAIL = "rail"


class Segment(BaseModel):
    origin: str
    destination: str
    origin_name: str | None = None
    destination_name: str | None = None
    departure: datetime
    arrival: datetime
    carrier: str
    number: str | None = None
    terminal_from: str | None = None
    terminal_to: str | None = None


class PriceLine(BaseModel):
    label: str
    amount: Money


class TravelOffer(BaseModel):
    offer_id: str
    provider: str  # duffel | sandbox-hotel | sandbox-ground | …
    type: OfferType
    origin: str | None = None
    destination: str | None = None
    departure: datetime | None = None
    arrival: datetime | None = None
    duration_min: int | None = None
    segments: list[Segment] = Field(default_factory=list)
    price: Money  # total for all travellers/nights
    base: Money | None = None
    taxes: Money | None = None
    fees: Money | None = None
    lines: list[PriceLine] = Field(default_factory=list)
    baggage: str | None = None
    refundable: bool = False
    changeable: bool = False
    cancellation_policy: str = ""
    change_policy: str = ""
    expires_at: datetime | None = None
    sandbox: bool = False  # true = no real inventory or money moves; UI must show SANDBOX
    title: str = ""
    subtitle: str = ""
    badges: list[str] = Field(default_factory=list)  # BEST FIT · CHEAPEST · FASTEST · LOWEST WALKING · BEST LOCATION
    location_fit: int | None = None
    place_id: str | None = None  # stays: the OSM place
    lat: float | None = None
    lon: float | None = None
    meta: dict = Field(default_factory=dict)  # normalized extras only (no raw supplier response)


class TxnState(StrEnum):
    DRAFT = "DRAFT"
    SELECTED = "SELECTED"
    REVALIDATING = "REVALIDATING"
    PRICE_CHANGED = "PRICE_CHANGED"
    PRICE_CONFIRMED = "PRICE_CONFIRMED"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    PAYMENT_AUTHORIZED = "PAYMENT_AUTHORIZED"
    SUPPLIER_PENDING = "SUPPLIER_PENDING"
    CONFIRMED = "CONFIRMED"
    FAILED = "FAILED"
    CANCEL_PENDING = "CANCEL_PENDING"
    CANCELLED = "CANCELLED"
    REFUND_PENDING = "REFUND_PENDING"
    REFUNDED = "REFUNDED"


TRANSITIONS: dict[TxnState, set[TxnState]] = {
    TxnState.DRAFT: {TxnState.SELECTED, TxnState.FAILED},
    TxnState.SELECTED: {TxnState.REVALIDATING, TxnState.FAILED},
    TxnState.REVALIDATING: {TxnState.PRICE_CONFIRMED, TxnState.PRICE_CHANGED, TxnState.FAILED},
    TxnState.PRICE_CHANGED: {TxnState.REVALIDATING, TxnState.PRICE_CONFIRMED, TxnState.FAILED},
    TxnState.PRICE_CONFIRMED: {TxnState.PAYMENT_PENDING, TxnState.REVALIDATING, TxnState.FAILED},
    TxnState.PAYMENT_PENDING: {TxnState.PAYMENT_AUTHORIZED, TxnState.FAILED},
    TxnState.PAYMENT_AUTHORIZED: {TxnState.SUPPLIER_PENDING, TxnState.FAILED},
    TxnState.SUPPLIER_PENDING: {TxnState.CONFIRMED, TxnState.FAILED},
    TxnState.CONFIRMED: {TxnState.CANCEL_PENDING},
    TxnState.CANCEL_PENDING: {TxnState.CANCELLED, TxnState.CONFIRMED, TxnState.REFUND_PENDING},
    TxnState.REFUND_PENDING: {TxnState.REFUNDED, TxnState.CANCELLED},
    TxnState.CANCELLED: {TxnState.REFUND_PENDING},
    TxnState.FAILED: set(),
    TxnState.REFUNDED: set(),
}


class IllegalTransition(Exception):
    pass


class Traveller(BaseModel):
    """Minimum traveller data. Stored in the restricted booking domain; masked before any AI call."""

    given_name: str = Field(min_length=1, max_length=60)
    family_name: str = Field(min_length=1, max_length=60)
    born_on: str | None = Field(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$")
    email: str | None = Field(default=None, max_length=120)
    phone: str | None = Field(default=None, max_length=30)
    title: Literal["mr", "ms", "mrs", "miss", "dr"] | None = None
    gender: Literal["m", "f"] | None = None


class BookingEvent(BaseModel):
    at: datetime
    from_state: TxnState | None
    to_state: TxnState
    note: str = ""
    actor: str = "system"


class BookingTransaction(BaseModel):
    id: str = Field(default_factory=lambda: new_id("txn"))
    idempotency_key: str
    user_id: str
    trip_id: str
    offer: TravelOffer
    accepted_total: Money | None = None
    travellers_count: int = 1
    state: TxnState = TxnState.DRAFT
    payment_ref: str | None = None  # PSP-issued id (never card data)
    supplier_ref: str | None = None
    booking_reference: str | None = None  # PNR / confirmation shown to the traveller
    needs_reconciliation: bool = False
    failure_reason: str | None = None
    refund_quote: Money | None = None
    events: list[BookingEvent] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    def transition(self, to: TxnState, note: str = "", actor: str = "system") -> None:
        if to not in TRANSITIONS[self.state]:
            raise IllegalTransition(f"{self.state} → {to}")
        self.events.append(BookingEvent(at=datetime.utcnow(), from_state=self.state, to_state=to, note=note, actor=actor))
        self.state = to
        self.updated_at = datetime.utcnow()
