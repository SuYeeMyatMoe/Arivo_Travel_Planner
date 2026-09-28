"""Arivo Guide (chat + voice transcripts) and Story Mode."""

from __future__ import annotations

from datetime import datetime
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.ai.graphs.guide import ask_guide
from app.ai.privacy import PolicyViolation
from app.ai.story import StoryTeller
from app.ai.tools import GuideContext
from app.api.deps import get_container, trip_access
from app.container import Container
from app.core.security import Principal, current_user, role_in_trip
from app.domain.models import CrewRole, Trip

router = APIRouter(prefix="/v1", tags=["guide"])


class Ask(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    now: datetime | None = None  # simulated local time for demos / planning ahead


@router.post("/trips/{trip_id}/guide")
async def guide(body: Ask, trip: Trip = Depends(trip_access(CrewRole.VIEWER)), p: Principal = Depends(current_user),
                c: Container = Depends(get_container)):
    now = body.now.replace(tzinfo=None) if body.now else datetime.now(ZoneInfo(trip.timezone)).replace(tzinfo=None)
    ctx = GuideContext(container=c, user_id=p.user_id, role=role_in_trip(trip, p.user_id), trip=trip, now=now)
    try:
        return await ask_guide(ctx, body.text)
    except PolicyViolation as e:
        raise HTTPException(422, {"code": "pii_policy", "message": str(e)}) from e


class StoryReq(BaseModel):
    length: Literal["30s", "1min", "deep"] = "1min"
    audience: Literal["adults", "kids", "history", "architecture", "casual"] = "adults"


@router.post("/places/{place_id}/story")
async def story(place_id: str, body: StoryReq, _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    place = c.places.get(place_id)
    if not place:
        raise HTTPException(404, "Place not found")
    try:
        out = await StoryTeller(c.router).tell(place, body.length, body.audience)
    except Exception as e:  # noqa: BLE001 — Wikipedia unreachable: say so, never improvise
        return {"status": "no_source", "message": f"I can't reach my sources right now, so I won't guess the story of {place.name}.", "error": type(e).__name__}
    return out if isinstance(out, dict) else {"status": "ok", **out.model_dump()}
