"""Arivo Crew: CrewDNA (shared favourites, conflicts, individual must-dos) and fair, non-competitive balance.

Never averages everyone blindly and never ranks people. Private preferences only ever appear aggregated.
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta

from app.domain.models import DNA_DIMENSIONS, CrewMember, CrewRole, Trip, TravelerDNA
from app.recommendations.scoring import preference_match

LABELS = {"food": "Food", "culture": "Culture", "history": "History", "nature": "Nature", "shopping": "Shopping",
          "nightlife": "Nightlife", "architecture": "Architecture", "photography": "Photography", "adventure": "Adventure",
          "relaxation": "Relaxation", "luxury": "Luxury", "localDiscovery": "Local finds", "anime": "Anime"}
VOTE_VALUE = {"love": 0.95, "maybe": 0.55, "skip": 0.08}


@dataclass
class Invite:
    token: str
    trip_id: str
    created_by: str
    role: CrewRole
    expires_at: datetime
    max_uses: int
    uses: int = 0


def new_invite(trip: Trip, by: str, role: CrewRole = CrewRole.MEMBER, days: int = 7) -> Invite:
    return Invite(token=secrets.token_urlsafe(18), trip_id=trip.id, created_by=by, role=role,
                  expires_at=datetime.utcnow() + timedelta(days=days), max_uses=max(1, trip.intent.crew_size - len(trip.crew)))


def apply_votes(dna: TravelerDNA, votes: dict[str, str]) -> TravelerDNA:
    data = dna.model_dump()
    for dim, v in votes.items():
        if dim in DNA_DIMENSIONS and v in VOTE_VALUE:
            data[dim] = VOTE_VALUE[v]
    return TravelerDNA(**data)


def crew_dna(trip: Trip, viewer_id: str) -> dict:
    members = trip.crew
    if not members:
        return {"members": [], "shared": [], "conflicts": [], "must_dos": [], "coverage": []}
    shared, conflicts, coverage = [], [], []
    for dim in DNA_DIMENSIONS:
        vals = [getattr(m.dna, dim) for m in members]
        avg = sum(vals) / len(vals)
        coverage.append({"dimension": dim, "label": LABELS[dim], "share": round(avg * 100)})
        if min(vals) >= 0.65:
            shared.append({"dimension": dim, "label": LABELS[dim], "strength": round(avg * 100)})
        elif max(vals) >= 0.8 and min(vals) <= 0.25:
            fans = [m.display_name for m in members if getattr(m.dna, dim) >= 0.8 and (not m.private_prefs or m.user_id == viewer_id)]
            conflicts.append({"dimension": dim, "label": LABELS[dim], "fans": fans,
                              "note": f"Some of you love {LABELS[dim].lower()}, some would skip it — best as one person's pick or an optional evening."})
    return {
        "members": [{"user_id": m.user_id, "name": m.display_name, "role": m.role.value, "color_index": m.color_index,
                     "top": [] if (m.private_prefs and m.user_id != viewer_id) else
                     [LABELS[k] for k, _ in sorted(m.dna.interests().items(), key=lambda kv: -kv[1])[:3]]} for m in members],
        "shared": sorted(shared, key=lambda s: -s["strength"]),
        "conflicts": conflicts,
        "must_dos": [{"member": m.display_name, "place_ids": m.must_do} for m in members if m.must_do and (not m.private_prefs or m.user_id == viewer_id)],
        "coverage": sorted(coverage, key=lambda c: -c["share"])[:6],
    }


def crew_balance(trip: Trip, places) -> list[dict]:
    """Per day: whose interests the day's time serves. A share, not a score — no winners."""
    out = []
    for day in trip.days:
        weights = {m.user_id: 0.0 for m in trip.crew}
        served_by: dict[str, str] = {}
        for it in day.items:
            p = places.get(it.place_id)
            if not p or it.kind == "transfer":
                continue
            best, best_v = None, -1.0
            for m in trip.crew:
                v = preference_match(m.dna, p) * it.duration_min
                weights[m.user_id] += v
                if v > best_v:
                    best, best_v = m.user_id, v
            if best and best not in served_by:
                served_by[best] = f"{it.start:%H:%M} {it.name}"
        total = sum(weights.values()) or 1
        out.append({"day_index": day.index, "title": day.title,
                    "members": [{"user_id": m.user_id, "name": m.display_name, "color_index": m.color_index,
                                 "share": round(100 * weights[m.user_id] / total), "highlight": served_by.get(m.user_id)} for m in trip.crew]})
    return out


def next_color(trip: Trip) -> int:
    used = {m.color_index for m in trip.crew}
    return next((i for i in range(6) if i not in used), len(trip.crew) % 6)


def add_member(trip: Trip, user_id: str, name: str, role: CrewRole) -> CrewMember:
    existing = next((m for m in trip.crew if m.user_id == user_id), None)
    if existing:
        return existing
    m = CrewMember(user_id=user_id, display_name=name, role=role, color_index=next_color(trip), dna=trip.dna.model_copy())
    trip.crew.append(m)
    return m
