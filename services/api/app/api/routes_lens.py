"""Look Around: Receipt Lens (+ group split) and Landmark Lens (GPS + nearby verified POIs, optional vision model)."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.deps import get_container, trip_access
from app.container import Container
from app.core.geo import haversine_km
from app.core.security import Principal, current_user
from app.domain.models import CrewRole, Trip
from app.vision.receipt import parse_receipt, split_items

router = APIRouter(prefix="/v1/lens", tags=["lens"])


class ReceiptText(BaseModel):
    text: str = Field(min_length=3, max_length=8000, description="On-device OCR output; images never leave the phone for this")
    currency_hint: str | None = Field(default=None, pattern=r"^[A-Z]{3}$")


@router.post("/receipt")
async def receipt(body: ReceiptText, _: Principal = Depends(current_user)):
    d = parse_receipt(body.text, body.currency_hint)
    return {"draft": d.to_json(), "requires_confirmation": True,
            "next": "Show the draft; on confirm, POST /v1/trips/{trip_id}/expenses with source=receipt_lens"}


class SplitBody(ReceiptText):
    assignment: dict[int, list[str]] = Field(default_factory=dict)


@router.post("/receipt/split/{trip_id}")
async def split(body: SplitBody, trip: Trip = Depends(trip_access(CrewRole.MEMBER))):
    d = parse_receipt(body.text, body.currency_hint)
    members = [m.user_id for m in trip.crew] or [trip.owner_id]
    owed = split_items(d, body.assignment, members)
    names = {m.user_id: m.display_name for m in trip.crew}
    return {"draft": d.to_json(), "owed": [{"user_id": k, "name": names.get(k, k), "amount": v, "currency": d.currency} for k, v in owed.items()]}


class Landmark(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    heading: float | None = Field(default=None, ge=0, lt=360)
    labels: list[str] = Field(default_factory=list, max_length=10, description="On-device image labels (ML Kit), optional")


@router.post("/landmark")
async def landmark(body: Landmark, _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    """Likely landmark from GPS + known POIs (+ on-device labels). No face recognition; the photo stays on the phone."""
    best_city = min(c.places.cities(), key=lambda x: haversine_km(body.lat, body.lon, (x["bbox"][0] + x["bbox"][2]) / 2, (x["bbox"][1] + x["bbox"][3]) / 2))
    near = [p for p in c.places.search(best_city["key"], near=(body.lat, body.lon), radius_km=0.4, limit=40)
            if not p.is_food and not p.is_stay and p.category != "station"]
    labels = {x.lower() for x in body.labels}
    cands = []
    for p in near:
        d = haversine_km(body.lat, body.lon, p.lat, p.lon)
        conf = 0.35 * max(0.0, 1 - d / 0.4) + 0.4 * p.iconic + (0.2 if labels & {p.category, "temple", "shrine", "tower", "building", "pagoda"} else 0)
        cands.append((round(min(0.95, conf), 2), p, d))
    cands.sort(key=lambda x: -x[0])
    if not cands:
        return {"status": "unknown", "message": "No verified landmark within 400 m of you."}
    conf, p, d = cands[0]
    return {"status": "ok" if conf >= 0.6 else "uncertain",
            "message": f"Looks like {p.name}." if conf >= 0.6 else f"Maybe {p.name} ({round(conf * 100)}% sure).",
            "place": p.model_dump(mode="json"), "confidence": conf, "distance_m": round(d * 1000),
            "alternatives": [{"place_id": q.id, "name": q.name, "confidence": cf} for cf, q, _ in cands[1:4]],
            "method": "gps+verified-places" + ("+on-device-labels" if labels else "")}
