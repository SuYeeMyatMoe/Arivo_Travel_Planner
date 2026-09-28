"""Persistence boundary. Services depend on `Store`; MemoryStore runs tests/demos, PostgresStore runs Supabase.

Trips are stored as versioned documents (optimistic concurrency via `version`); bookings, payments, audit and
webhook events are append-mostly records with unique constraints that make idempotency enforceable.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Protocol

from app.budget.brain import Expense
from app.domain.models import Trip, TripChange


class VersionConflict(Exception):
    """Someone else changed the trip since the caller read it. The client re-reads and retries."""


@dataclass
class AuditEvent:
    actor: str
    action: str
    target: str
    result: str
    request_id: str | None
    at: datetime
    meta: dict[str, Any] = field(default_factory=dict)  # never card data, never secrets


class Store(Protocol):
    async def put_trip(self, trip: Trip, expected_version: int | None = None) -> Trip: ...
    async def get_trip(self, trip_id: str) -> Trip | None: ...
    async def trips_for_user(self, user_id: str) -> list[Trip]: ...
    async def put_change(self, change: TripChange) -> None: ...
    async def get_change(self, change_id: str) -> TripChange | None: ...
    async def list_changes(self, trip_id: str) -> list[TripChange]: ...
    async def add_expense(self, e: Expense) -> None: ...
    async def list_expenses(self, trip_id: str) -> list[Expense]: ...
    async def audit(self, ev: AuditEvent) -> None: ...
    async def list_audit(self, target_prefix: str | None = None) -> list[AuditEvent]: ...
    # generic keyed collections for bookings/payments/pulse/crew (typed wrappers live in their domains)
    async def kv_put(self, collection: str, key: str, value: Any, *, unique: bool = False) -> bool: ...
    async def kv_get(self, collection: str, key: str) -> Any | None: ...
    async def kv_list(self, collection: str, prefix: str = "") -> list[Any]: ...
