"""Arivo Pulse feed, evidence, refresh, and Send-It-To-My-Trip."""

from __future__ import annotations

import asyncio

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from app.api.deps import get_container
from app.container import Container
from app.core.security import Principal, current_user
from app.pulse.engine import GdeltNews, PulseEngine, TicketmasterEvents, WikipediaPageviews, YouTubeSearch
from app.pulse.social import UnsupportedUrl, resolve

router = APIRouter(prefix="/v1/pulse", tags=["pulse"])


def engine(c: Container) -> PulseEngine:
    if "pulse" not in c.extras:
        providers = [WikipediaPageviews(), GdeltNews()]
        if c.settings.youtube_api_key:
            providers.append(YouTubeSearch(c.settings.youtube_api_key.get_secret_value()))
        if c.settings.ticketmaster_key:
            providers.append(TicketmasterEvents(c.settings.ticketmaster_key.get_secret_value()))
        c.extras["pulse"] = PulseEngine(c.store, c.places, providers, c.extras.setdefault("trends", {}))
    return c.extras["pulse"]


@router.get("")
async def feed(city: str = Query(..., max_length=40), _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    items = await engine(c).feed(city)
    return {"city": city, "items": items, "note": None if items else "No evidence collected yet for this city. Pulse only shows places with real signals.",
            "sources": [p.name for p in engine(c).providers]}


@router.post("/refresh")
async def refresh(city: str = Query(..., max_length=40), limit: int = Query(12, ge=1, le=40), _: Principal = Depends(current_user),
                  c: Container = Depends(get_container)):
    if not c.places.city(city):
        raise HTTPException(404, "Unknown city")
    running = c.extras.setdefault("pulse_jobs", {})
    if running.get(city) and not running[city].done():
        return {"status": "running"}
    running[city] = asyncio.create_task(engine(c).refresh(city, limit))  # background worker; GDELT is rate-limited
    return {"status": "started", "estimated_seconds": limit * 6}


class ResolveBody(BaseModel):
    url: str = Field(min_length=10, max_length=500)


@router.post("/resolve-url")
async def resolve_url(body: ResolveBody, _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    try:
        res = await resolve(body.url, {k["key"]: c.places.search(k["key"], limit=10000) for k in c.places.cities()})
    except UnsupportedUrl as e:
        raise HTTPException(422, {"code": "unsupported_url", "message": str(e)}) from e
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, {"code": "oembed_unavailable", "message": "Couldn't read that post right now."}) from e
    return {"note": res.note, "confidence": res.confidence, "source_title": res.source_title, "author": res.author,
            "place": res.place.model_dump(mode="json") if res.place else None,
            "candidates": [{"place_id": p.id, "name": p.name, "city": p.city, "confidence": conf} for p, conf in res.candidates]}
