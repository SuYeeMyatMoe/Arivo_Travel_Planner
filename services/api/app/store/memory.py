"""In-memory Store: same contract as PostgresStore (including version checks and unique keys)."""

from __future__ import annotations

import asyncio
import copy
from typing import Any

from app.budget.brain import Expense
from app.domain.models import Trip, TripChange
from app.store.base import AuditEvent, VersionConflict


class MemoryStore:
    def __init__(self) -> None:
        self._trips: dict[str, Trip] = {}
        self._changes: dict[str, TripChange] = {}
        self._expenses: dict[str, list[Expense]] = {}
        self._audit: list[AuditEvent] = []
        self._kv: dict[str, dict[str, Any]] = {}
        self._lock = asyncio.Lock()

    async def put_trip(self, trip: Trip, expected_version: int | None = None) -> Trip:
        async with self._lock:
            cur = self._trips.get(trip.id)
            if expected_version is not None and cur is not None and cur.version != expected_version:
                raise VersionConflict(f"trip {trip.id} is at v{cur.version}, not v{expected_version}")
            stored = trip.model_copy(deep=True, update={"version": (cur.version + 1) if cur else trip.version})
            self._trips[trip.id] = stored
            return stored.model_copy(deep=True)

    async def get_trip(self, trip_id: str) -> Trip | None:
        t = self._trips.get(trip_id)
        return t.model_copy(deep=True) if t else None

    async def trips_for_user(self, user_id: str) -> list[Trip]:
        return [t.model_copy(deep=True) for t in self._trips.values() if t.owner_id == user_id or any(m.user_id == user_id for m in t.crew)]

    async def put_change(self, change: TripChange) -> None:
        self._changes[change.id] = change.model_copy(deep=True)

    async def get_change(self, change_id: str) -> TripChange | None:
        c = self._changes.get(change_id)
        return c.model_copy(deep=True) if c else None

    async def list_changes(self, trip_id: str) -> list[TripChange]:
        return [c.model_copy(deep=True) for c in self._changes.values() if c.trip_id == trip_id]

    async def add_expense(self, e: Expense) -> None:
        self._expenses.setdefault(e.trip_id, []).append(copy.deepcopy(e))

    async def list_expenses(self, trip_id: str) -> list[Expense]:
        return copy.deepcopy(self._expenses.get(trip_id, []))

    async def audit(self, ev: AuditEvent) -> None:
        self._audit.append(ev)

    async def list_audit(self, target_prefix: str | None = None) -> list[AuditEvent]:
        return [a for a in self._audit if target_prefix is None or a.target.startswith(target_prefix)]

    async def kv_put(self, collection: str, key: str, value: Any, *, unique: bool = False) -> bool:
        async with self._lock:
            col = self._kv.setdefault(collection, {})
            if unique and key in col:
                return False
            col[key] = copy.deepcopy(value)
            return True

    async def kv_get(self, collection: str, key: str) -> Any | None:
        v = self._kv.get(collection, {}).get(key)
        return copy.deepcopy(v)

    async def kv_list(self, collection: str, prefix: str = "") -> list[Any]:
        return [copy.deepcopy(v) for k, v in self._kv.get(collection, {}).items() if k.startswith(prefix)]
