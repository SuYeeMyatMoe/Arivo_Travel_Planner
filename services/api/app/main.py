"""FastAPI entrypoint: `uvicorn app.main:app --port 8787` (8080 inside the container)."""

from __future__ import annotations

import logging
import time
import uuid
from collections import defaultdict, deque

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import Settings, get_settings
from app.container import Container, build_container

log = logging.getLogger("arivo")


class RateLimiter:
    """Sliding-window limiter per user (or IP when anonymous). Redis-backed in production; in-process here."""

    def __init__(self, per_minute: int):
        self.per_minute = per_minute
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, key: str, cost: int = 1) -> bool:
        now = time.monotonic()
        q = self.hits[key]
        while q and now - q[0] > 60:
            q.popleft()
        if len(q) + cost > self.per_minute:
            return False
        for _ in range(cost):
            q.append(now)
        return True


def create_app(settings: Settings | None = None, container: Container | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    app = FastAPI(title="Arivo API", version="0.1.0", docs_url=None if settings.is_production else "/docs",
                  redoc_url=None, openapi_url=None if settings.is_production else "/openapi.json")
    app.state.container = container or build_container(settings)
    limiter = RateLimiter(settings.rate_limit_per_minute)
    expensive = ("/v1/trips", "/v1/guide", "/v1/bookings/search")

    app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins, allow_credentials=False,
                       allow_methods=["GET", "POST", "PUT", "DELETE"], allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-Id"])

    @app.middleware("http")
    async def edge(request: Request, call_next):
        rid = request.headers.get("X-Request-Id") or uuid.uuid4().hex
        request.state.request_id = rid
        auth = request.headers.get("authorization", "")
        key = auth[-40:] if auth else (request.client.host if request.client else "anon")
        cost = 5 if request.method == "POST" and request.url.path.startswith(expensive) else 1
        if not limiter.allow(key, cost):
            return JSONResponse({"code": "rate_limited", "message": "Too many requests. Slow down a little."}, status_code=429,
                                headers={"Retry-After": "30", "X-Request-Id": rid})
        started = time.perf_counter()
        response = await call_next(request)
        response.headers["X-Request-Id"] = rid
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
        log.info("%s %s %s %dms rid=%s", request.method, request.url.path, response.status_code,
                 int((time.perf_counter() - started) * 1000), rid)
        return response

    @app.exception_handler(Exception)
    async def unhandled(request: Request, exc: Exception):
        log.exception("unhandled rid=%s", getattr(request.state, "request_id", "?"))
        return JSONResponse({"code": "internal", "message": "Something went wrong on our side. Your trip is safe.",
                             "request_id": getattr(request.state, "request_id", None)}, status_code=500)

    @app.get("/health")
    async def health():
        c: Container = app.state.container
        return {"ok": True, "env": settings.env, "ai": c.router.available, "cities": [x["key"] for x in c.places.cities()],
                "providers": {"flights": getattr(c.bookings.flights, "name", None), "payments": getattr(c.bookings.payments, "name", None),
                              "sandbox": bool(getattr(c.bookings.flights, "sandbox", True) or getattr(c.bookings.payments, "sandbox", True))}}

    from app.api import routes_bookings, routes_places, routes_trips

    app.include_router(routes_trips.router)
    app.include_router(routes_bookings.router)
    app.include_router(routes_places.router)
    for extra in ("routes_guide", "routes_pulse", "routes_crew", "routes_lens"):
        try:
            mod = __import__(f"app.api.{extra}", fromlist=["router"])
            app.include_router(mod.router)
        except ModuleNotFoundError:
            pass
    return app


app = create_app()
