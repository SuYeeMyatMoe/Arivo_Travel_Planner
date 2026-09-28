"""Core domain models shared by planning, recommendations, bookings and the AI layer.

Money is always integer minor units + ISO currency. Every number shown to a traveller carries a Provenance.
"""

from __future__ import annotations

from datetime import date, datetime
from enum import StrEnum
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field

# ---------------------------------------------------------------------------------------------------------- basics

MINOR_UNITS = {"JPY": 0, "KRW": 0, "VND": 0, "IDR": 0, "MYR": 2, "USD": 2, "EUR": 2, "GBP": 2, "SGD": 2, "THB": 2, "CHF": 2}


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex[:20]}"


class Provenance(StrEnum):
    LIVE = "live"  # came from a provider (weather, supplier price, opening hours) with a timestamp
    EST = "est"  # Arivo computed it (travel-time estimate, forecast, heuristic)
    YOU = "you"  # the traveller entered or confirmed it


class Money(BaseModel):
    model_config = ConfigDict(frozen=True)

    amount_minor: int
    currency: str = Field(min_length=3, max_length=3)

    @classmethod
    def of(cls, amount: float, currency: str) -> "Money":
        digits = MINOR_UNITS.get(currency.upper(), 2)
        return cls(amount_minor=round(amount * 10**digits), currency=currency.upper())

    @classmethod
    def zero(cls, currency: str) -> "Money":
        return cls(amount_minor=0, currency=currency.upper())

    @property
    def amount(self) -> float:
        return self.amount_minor / 10 ** MINOR_UNITS.get(self.currency, 2)

    def __add__(self, other: "Money") -> "Money":
        self._same(other)
        return Money(amount_minor=self.amount_minor + other.amount_minor, currency=self.currency)

    def __sub__(self, other: "Money") -> "Money":
        self._same(other)
        return Money(amount_minor=self.amount_minor - other.amount_minor, currency=self.currency)

    def scale(self, factor: float) -> "Money":
        return Money(amount_minor=round(self.amount_minor * factor), currency=self.currency)

    def _same(self, other: "Money") -> None:
        if other.currency != self.currency:
            raise ValueError(f"currency mismatch {self.currency} vs {other.currency}")

    def display(self) -> str:
        sym = {"MYR": "RM ", "JPY": "¥", "USD": "$", "EUR": "€", "GBP": "£"}.get(self.currency, f"{self.currency} ")
        digits = MINOR_UNITS.get(self.currency, 2)
        return f"{sym}{self.amount:,.{digits if self.amount % 1 else 0}f}"


class Evidence(BaseModel):
    """One reason behind a recommendation or change. Rendered in Why This? / Pulse evidence."""

    text: str
    provenance: Provenance = Provenance.EST
    source: str | None = None
    url: str | None = None
    updated_at: datetime | None = None
    weight: float | None = None  # contribution to the score, when the reason is a score component


# ---------------------------------------------------------------------------------------------------------- travellers

DNA_DIMENSIONS = (
    "food", "culture", "history", "nature", "shopping", "nightlife", "architecture", "photography", "adventure",
    "relaxation", "luxury", "localDiscovery", "anime",
)
DNA_TRAITS = ("budgetSensitivity", "crowdTolerance", "walkingTolerance", "travelPace", "touristTolerance")


class TravelerDNA(BaseModel):
    """Interests (0..1) + travel traits (0..1). Learned gradually from actions; always editable by the traveller."""

    food: float = 0.5
    culture: float = 0.5
    history: float = 0.4
    nature: float = 0.4
    shopping: float = 0.3
    nightlife: float = 0.3
    architecture: float = 0.4
    photography: float = 0.4
    adventure: float = 0.3
    relaxation: float = 0.4
    luxury: float = 0.2
    localDiscovery: float = 0.5
    anime: float = 0.0
    budgetSensitivity: float = 0.5
    crowdTolerance: float = 0.5
    walkingTolerance: float = 0.6
    travelPace: float = 0.5  # 0 = slow, 1 = packed
    touristTolerance: float = 0.5  # 0 = avoid tourist spots, 1 = happy with icons

    def interests(self) -> dict[str, float]:
        return {k: getattr(self, k) for k in DNA_DIMENSIONS}

    def nudge(self, dims: dict[str, float], rate: float) -> "TravelerDNA":
        """Move interests toward (+) or away from (−) the dims a place serves. rate ∈ [-1, 1]."""
        data = self.model_dump()
        for k, w in dims.items():
            if k in data:
                data[k] = min(1.0, max(0.0, data[k] + rate * w * 0.12))
        return TravelerDNA(**data)


class CrewType(StrEnum):
    SOLO = "solo"
    COUPLE = "couple"
    FRIENDS = "friends"
    FAMILY = "family"


class CrewRole(StrEnum):
    OWNER = "owner"
    EDITOR = "editor"
    MEMBER = "member"
    VIEWER = "viewer"


class CrewMember(BaseModel):
    user_id: str
    display_name: str
    role: CrewRole = CrewRole.MEMBER
    color_index: int = 0
    dna: TravelerDNA = Field(default_factory=TravelerDNA)
    must_do: list[str] = Field(default_factory=list)  # place ids
    dietary: list[str] = Field(default_factory=list)
    private_prefs: bool = False  # hide individual votes from other members


# ---------------------------------------------------------------------------------------------------------- places

class Place(BaseModel):
    id: str
    name: str
    name_local: str | None = None
    category: str
    lat: float
    lon: float
    city: str
    indoor: bool = False
    dna: dict[str, float] = Field(default_factory=dict)
    duration_min: tuple[int, int, int] | None = None  # quick, normal, deep
    tags: dict[str, str] = Field(default_factory=dict)
    iconic: float = 0.0  # 0 local … 1 world-famous (log Wikidata sitelinks)
    notability: int = 0
    quality: int = 0  # 0..5 verifiable-information richness (wikidata, website, hours, English name, description)
    summary: str | None = None
    wikipedia_en: str | None = None
    photo: dict | None = None
    sources: list[dict] = Field(default_factory=list)

    @property
    def is_food(self) -> bool:
        return self.category in {"restaurant", "cafe", "fast_food", "food_court", "market"}

    @property
    def is_stay(self) -> bool:
        return self.category in {"hotel", "hostel", "guest_house"}

    @property
    def is_night(self) -> bool:
        return self.category in {"bar", "pub", "nightclub"}


# ---------------------------------------------------------------------------------------------------------- intent

class Pace(StrEnum):
    SLOW = "slow"
    BALANCED = "balanced"
    PACKED = "packed"


class TripIntent(BaseModel):
    """What the traveller asked for, extracted from one natural-language sentence (+ optional quick controls)."""

    raw_text: str = ""
    destinations: list[str] = Field(default_factory=list, description="City names in visiting order")
    origin: str | None = Field(default=None, description="Home city if mentioned, e.g. Kuala Lumpur")
    start_date: date | None = None
    days: int | None = Field(default=None, ge=1, le=60)
    budget_amount: float | None = Field(default=None, ge=0)
    budget_currency: str | None = None
    budget_per_person: bool = True
    crew_type: CrewType = CrewType.SOLO
    crew_size: int = Field(default=1, ge=1, le=20)
    interests: list[str] = Field(default_factory=list, description="TravelerDNA dimension names")
    avoid: list[str] = Field(default_factory=list)
    pace: Pace = Pace.BALANCED
    dietary: list[str] = Field(default_factory=list)
    must_do: list[str] = Field(default_factory=list, description="Named places the traveller insists on")
    missing: list[str] = Field(default_factory=list, description="Fields that materially change the plan and are unknown")
    confidence: float = Field(default=0.7, ge=0, le=1)
    parser: Literal["ai", "heuristic"] = "heuristic"


# ---------------------------------------------------------------------------------------------------------- itinerary

class Leg(BaseModel):
    mode: Literal["walk", "transit", "taxi", "train", "bus", "flight"] = "walk"
    minutes: int
    distance_m: int
    provenance: Provenance = Provenance.EST
    note: str | None = None


class ItemStatus(StrEnum):
    PLANNED = "planned"
    BOOKED = "booked"  # hard constraint
    DONE = "done"
    SKIPPED = "skipped"
    CLOSED = "closed"


class ItineraryItem(BaseModel):
    id: str = Field(default_factory=lambda: new_id("itm"))
    place_id: str
    name: str
    category: str
    lat: float
    lon: float
    start: datetime
    duration_min: int
    leg: Leg | None = None
    leg_cost: Money | None = None  # fare for the leg into this stop (per person)
    cost: Money | None = None  # per person
    cost_provenance: Provenance = Provenance.EST
    reason: str = ""
    evidence: list[Evidence] = Field(default_factory=list)
    score: float | None = None
    status: ItemStatus = ItemStatus.PLANNED
    locked: bool = False  # bookings and reservations: Rescue/Plan B never move them
    booking_id: str | None = None
    indoor: bool = False
    kind: Literal["sight", "meal", "night", "stay", "transfer"] = "sight"
    lane: Literal["iconic", "local", "for_you", "pulse"] | None = None  # why it was picked (Discovery lanes)
    priority: float = 0.5  # 1 = must-do

    @property
    def end(self) -> datetime:
        from datetime import timedelta

        return self.start + timedelta(minutes=self.duration_min)


class PlanB(BaseModel):
    trigger: Literal["rain", "fatigue", "closure", "delay", "budget", "transport"]
    items: list[ItineraryItem]
    summary: str
    time_delta_min: int = 0
    budget_delta: Money | None = None


class ItineraryDay(BaseModel):
    index: int
    date: date
    zone: str = ""
    title: str = ""
    route_color: int = 0
    items: list[ItineraryItem] = Field(default_factory=list)
    plan_b: list[PlanB] = Field(default_factory=list)
    weather: dict | None = None


class BudgetLine(BaseModel):
    category: Literal["flights", "accommodation", "food", "transport", "activities", "shopping", "buffer"]
    planned: Money
    reserved: Money
    spent: Money
    provenance: Provenance = Provenance.EST


class Budget(BaseModel):
    total: Money
    lines: list[BudgetLine]
    style: Literal["save", "balanced", "comfort", "premium"] = "balanced"

    @property
    def spent(self) -> Money:
        out = Money.zero(self.total.currency)
        for line in self.lines:
            out = out + line.spent
        return out

    @property
    def reserved(self) -> Money:
        out = Money.zero(self.total.currency)
        for line in self.lines:
            out = out + line.reserved
        return out


class Trip(BaseModel):
    id: str = Field(default_factory=lambda: new_id("trp"))
    owner_id: str
    title: str
    intent: TripIntent
    cities: list[str]
    start_date: date
    timezone: str
    currency: str
    home_currency: str = "MYR"
    dna: TravelerDNA = Field(default_factory=TravelerDNA)
    crew: list[CrewMember] = Field(default_factory=list)
    crew_type: CrewType = CrewType.SOLO
    days: list[ItineraryDay] = Field(default_factory=list)
    budget: Budget | None = None
    hotel_place_id: str | None = None
    mode: Literal["planner", "live"] = "planner"
    version: int = 1
    created_at: datetime = Field(default_factory=datetime.utcnow)
    warnings: list[str] = Field(default_factory=list)

    def all_items(self) -> list[ItineraryItem]:
        return [i for d in self.days for i in d.items]


class DiffEntry(BaseModel):
    item_id: str
    name: str
    from_time: str | None = None
    to_time: str | None = None
    reason: str | None = None
    detail: str | None = None


class TripChange(BaseModel):
    """What an AI/replan change did. Never applied silently: status goes proposed → applied | rejected."""

    id: str = Field(default_factory=lambda: new_id("chg"))
    trip_id: str
    day_index: int
    trigger: str
    kept: list[DiffEntry] = Field(default_factory=list)
    moved: list[DiffEntry] = Field(default_factory=list)
    removed: list[DiffEntry] = Field(default_factory=list)
    added: list[DiffEntry] = Field(default_factory=list)
    time_delta_min: int = 0
    budget_delta: Money | None = None
    explanation: str = ""
    new_items: list[ItineraryItem] = Field(default_factory=list)
    status: Literal["proposed", "applied", "rejected"] = "proposed"
    base_version: int = 1
    created_at: datetime = Field(default_factory=datetime.utcnow)
