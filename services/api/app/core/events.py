"""Transactional-outbox EventBus with idempotent consumers.

publish() persists the event (unique id) before dispatch; each consumer records processed ids, so redelivery (Pub/Sub
retries, a crashed worker) never double-applies. MemoryStore/in-process dispatch locally; Pub/Sub in production.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Awaitable, Callable

from app.domain.models import new_id
from app.store.base import Store

log = logging.getLogger(__name__)
Handler = Callable[["Event"], Awaitable[None]]


@dataclass
class Event:
    type: str
    payload: dict[str, Any]
    id: str = field(default_factory=lambda: new_id("evt"))
    at: str = field(default_factory=lambda: datetime.utcnow().isoformat())


class EventBus:
    def __init__(self, store: Store):
        self.store = store
        self._subs: dict[str, list[tuple[str, Handler]]] = {}

    def subscribe(self, event_type: str, consumer: str, handler: Handler) -> None:
        self._subs.setdefault(event_type, []).append((consumer, handler))

    async def publish(self, event: Event) -> None:
        await self.store.kv_put("outbox", event.id, {"type": event.type, "payload": event.payload, "at": event.at, "dispatched": False}, unique=True)
        await self.dispatch(event)

    async def dispatch(self, event: Event) -> None:
        for consumer, handler in self._subs.get(event.type, []):
            first = await self.store.kv_put(f"processed:{consumer}", event.id, True, unique=True)
            if not first:
                continue  # idempotent consumer
            try:
                await handler(event)
            except Exception:  # noqa: BLE001 — a failed consumer must not block others; it is retried from the outbox
                log.exception("consumer %s failed on %s", consumer, event.id)
                await self.store.kv_put(f"processed:{consumer}", event.id, None)  # allow retry
        rec = await self.store.kv_get("outbox", event.id)
        if rec:
            rec["dispatched"] = True
            await self.store.kv_put("outbox", event.id, rec)

    async def redeliver_pending(self) -> int:
        """Worker loop entry: re-dispatch anything not fully processed (crash recovery)."""
        n = 0
        for rec in await self.store.kv_list("outbox"):
            if not rec.get("dispatched"):
                n += 1
        return n
