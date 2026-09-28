"""Arivo Crew endpoints: invites, preference votes, CrewDNA, balance, suggestions and votes."""

from __future__ import annotations

from dataclasses import asdict
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.api.deps import get_container, trip_access
from app.container import Container
from app.core.security import Principal, current_user
from app.crew.service import Invite, add_member, apply_votes, crew_balance, crew_dna, new_invite
from app.domain.models import CrewRole, Trip, new_id
from app.planning.replan import ReplanRequest, Trigger
from app.store.base import AuditEvent

router = APIRouter(prefix="/v1", tags=["crew"])


@router.post("/trips/{trip_id}/invites")
async def create_invite(trip: Trip = Depends(trip_access(CrewRole.EDITOR)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    inv = new_invite(trip, p.user_id)
    await c.store.kv_put("invites", inv.token, asdict(inv))
    await c.store.audit(AuditEvent(actor=p.user_id, action="crew.invite_created", target=f"trip:{trip.id}", result="ok", request_id=None, at=datetime.utcnow()))
    return {"token": inv.token, "link": f"https://arivo.app/join/{inv.token}", "expires_at": inv.expires_at.isoformat(), "max_uses": inv.max_uses}


@router.post("/invites/{token}/join")
async def join(token: str, p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    rec = await c.store.kv_get("invites", token)
    if not rec:
        raise HTTPException(404, "Invite not found or expired")
    inv = Invite(**rec)
    if inv.expires_at < datetime.utcnow() or inv.uses >= inv.max_uses:
        raise HTTPException(410, "This invite has expired. Ask for a new link.")
    for _ in range(3):
        trip = await c.store.get_trip(inv.trip_id)
        m = add_member(trip, p.user_id, p.display_name or "Traveller", inv.role)
        try:
            await c.store.put_trip(trip, expected_version=trip.version)
            break
        except Exception:  # noqa: BLE001 — concurrent join; retry on fresh copy
            continue
    inv.uses += 1
    await c.store.kv_put("invites", token, asdict(inv))
    await c.store.audit(AuditEvent(actor=p.user_id, action="crew.joined", target=f"trip:{inv.trip_id}", result="ok", request_id=None, at=datetime.utcnow()))
    return {"trip_id": inv.trip_id, "member": m.model_dump(mode="json")}


class Prefs(BaseModel):
    """Partial update: fields left out keep their current value."""
    votes: dict[str, Literal["love", "maybe", "skip"]] = Field(default_factory=dict)
    must_do: list[str] | None = Field(default=None, max_length=5)
    dietary: list[Literal["vegetarian", "vegan", "halal", "gluten_free"]] | None = None
    private: bool | None = None


@router.post("/trips/{trip_id}/crew/prefs")
async def set_prefs(body: Prefs, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    m = next(m for m in trip.crew if m.user_id == p.user_id) if any(m.user_id == p.user_id for m in trip.crew) else add_member(trip, p.user_id, p.display_name or "You", CrewRole.OWNER)
    m.dna = apply_votes(m.dna, body.votes)
    if body.must_do is not None:
        m.must_do = [pid for pid in body.must_do if c.places.get(pid)]
    if body.dietary is not None:
        m.dietary = body.dietary
    if body.private is not None:
        m.private_prefs = body.private
    stored = await c.store.put_trip(trip, expected_version=trip.version)
    return crew_dna(stored, p.user_id)


@router.get("/trips/{trip_id}/crew")
async def get_crew(trip: Trip = Depends(trip_access(CrewRole.VIEWER)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    return {**crew_dna(trip, p.user_id), "balance": crew_balance(trip, c.places),
            "suggestions": sorted(await c.store.kv_list("suggestions", f"{trip.id}:"), key=lambda s: -s["score"])}


class Suggestion(BaseModel):
    text: str = Field(min_length=2, max_length=200)
    place_id: str | None = None
    kind: Literal["place", "nightlife", "food", "other"] = "place"
    day_index: int | None = Field(default=None, ge=0, le=60)


@router.post("/trips/{trip_id}/crew/suggestions")
async def suggest(body: Suggestion, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    if body.place_id and not c.places.get(body.place_id):
        raise HTTPException(422, "Unknown place")
    sid = new_id("sug")
    rec = {"id": sid, "trip_id": trip.id, "author": p.display_name or p.user_id, "author_id": p.user_id, "text": body.text,
           "place_id": body.place_id, "kind": body.kind, "day_index": body.day_index, "votes": {p.user_id: 1}, "score": 1,
           "status": "open", "created_at": datetime.utcnow().isoformat()}
    await c.store.kv_put("suggestions", f"{trip.id}:{sid}", rec)
    return rec


class Vote(BaseModel):
    value: Literal[1, -1, 0]


@router.post("/trips/{trip_id}/crew/suggestions/{sid}/vote")
async def vote(sid: str, body: Vote, trip: Trip = Depends(trip_access(CrewRole.MEMBER)), p: Principal = Depends(current_user), c: Container = Depends(get_container)):
    rec = await c.store.kv_get("suggestions", f"{trip.id}:{sid}")
    if not rec:
        raise HTTPException(404, "Suggestion not found")
    rec["votes"][p.user_id] = body.value
    rec["score"] = sum(rec["votes"].values())
    majority = rec["score"] > len(trip.crew) / 2
    await c.store.kv_put("suggestions", f"{trip.id}:{sid}", rec)
    proposal = None
    if majority and rec["kind"] == "nightlife" and rec["status"] == "open":
        # crew agreed: Arivo proposes (never applies) an evening update
        day_index = rec["day_index"] if rec["day_index"] is not None else 0
        day = trip.days[day_index]
        now = datetime.combine(day.date, datetime.min.time()).replace(hour=17)
        change = await c.trips.propose_replan(trip, ReplanRequest(trigger=Trigger.NIGHTLIFE, day_index=day_index, now=now), p.user_id)
        rec["status"] = "proposed"
        await c.store.kv_put("suggestions", f"{trip.id}:{sid}", rec)
        proposal = change.model_dump(mode="json", exclude={"new_items"})
    return {"suggestion": rec, "majority": majority, "proposal": proposal}
