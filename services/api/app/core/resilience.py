"""Backpressure for third-party providers: timeout, bounded concurrency, circuit breaker, GET-only retries, TTL cache.

A failing provider degrades its own feature ("Hotel availability temporarily unavailable") and never cascades.
Booking/payment POSTs are NEVER retried here — ambiguous outcomes go to reconciliation instead.
"""

from __future__ import annotations

import asyncio
import time
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Any

import httpx


class ProviderUnavailable(Exception):
    def __init__(self, provider: str, reason: str):
        super().__init__(f"{provider} unavailable: {reason}")
        self.provider = provider
        self.reason = reason


class TTLCache:
    """Small in-process cache (Redis replaces it when REDIS_URL is set). Never a source of truth."""

    def __init__(self, max_items: int = 2048):
        self._data: OrderedDict[str, tuple[float, Any]] = OrderedDict()
        self._max = max_items

    def get(self, key: str) -> Any | None:
        hit = self._data.get(key)
        if not hit:
            return None
        expires, value = hit
        if expires < time.monotonic():
            self._data.pop(key, None)
            return None
        self._data.move_to_end(key)
        return value

    def set(self, key: str, value: Any, ttl_s: float) -> None:
        self._data[key] = (time.monotonic() + ttl_s, value)
        self._data.move_to_end(key)
        while len(self._data) > self._max:
            self._data.popitem(last=False)


@dataclass
class CircuitBreaker:
    failure_threshold: int = 5
    reset_after_s: float = 30.0
    failures: int = 0
    opened_at: float | None = None

    def allow(self) -> bool:
        if self.opened_at is None:
            return True
        if time.monotonic() - self.opened_at >= self.reset_after_s:
            return True  # half-open: let one probe through
        return False

    def success(self) -> None:
        self.failures = 0
        self.opened_at = None

    def failure(self) -> None:
        self.failures += 1
        if self.failures >= self.failure_threshold:
            self.opened_at = time.monotonic()

    @property
    def state(self) -> str:
        if self.opened_at is None:
            return "closed"
        return "half-open" if self.allow() else "open"


@dataclass
class ResilientClient:
    provider: str
    base_url: str = ""
    timeout_s: float = 8.0
    max_concurrency: int = 8
    get_retries: int = 2
    headers: dict[str, str] = field(default_factory=dict)
    cache: TTLCache = field(default_factory=TTLCache)
    breaker: CircuitBreaker = field(default_factory=CircuitBreaker)
    transport: httpx.AsyncBaseTransport | None = None

    def __post_init__(self) -> None:
        self._sem = asyncio.Semaphore(self.max_concurrency)
        self._client = httpx.AsyncClient(base_url=self.base_url, timeout=self.timeout_s, transport=self.transport,
                                         headers={"User-Agent": "Arivo/0.1", **self.headers}, follow_redirects=True)

    async def get_json(self, path: str, params: dict | None = None, *, cache_ttl_s: float | None = None) -> Any:
        key = f"{self.provider}:{path}:{sorted((params or {}).items())}"
        if cache_ttl_s:
            cached = self.cache.get(key)
            if cached is not None:
                return cached
        data = await self._request("GET", path, params=params)
        if cache_ttl_s:
            self.cache.set(key, data, cache_ttl_s)
        return data

    async def post_json(self, path: str, json: Any, headers: dict | None = None) -> Any:
        """Single attempt. Callers that create side effects (bookings, payments) must pass idempotency keys."""
        return await self._request("POST", path, json=json, headers=headers, retries=0)

    async def _request(self, method: str, path: str, *, retries: int | None = None, **kw: Any) -> Any:
        if not self.breaker.allow():
            raise ProviderUnavailable(self.provider, "circuit open")
        attempts = (self.get_retries if retries is None else retries) + 1
        last: Exception | None = None
        async with self._sem:
            for attempt in range(attempts):
                try:
                    r = await self._client.request(method, path, **kw)
                    if r.status_code >= 500 or r.status_code == 429:
                        raise httpx.HTTPStatusError(f"{r.status_code}", request=r.request, response=r)
                    r.raise_for_status()
                    self.breaker.success()
                    return r.json()
                except httpx.HTTPStatusError as e:
                    last = e
                    if e.response.status_code < 500 and e.response.status_code != 429:
                        self.breaker.success()  # client errors are not provider health problems
                        raise
                except (httpx.TimeoutException, httpx.TransportError) as e:
                    last = e
                if attempt < attempts - 1:
                    await asyncio.sleep(0.4 * (2**attempt))
        self.breaker.failure()
        raise ProviderUnavailable(self.provider, str(last))

    async def aclose(self) -> None:
        await self._client.aclose()
