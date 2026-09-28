"""Places: search, detail with Why This?, Explore lanes, and weather."""

from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query

from app.api.deps import get_container
from app.container import Container
from app.core.security import Principal, current_user
from app.domain.models import TravelerDNA
from app.places.hours import OpenState, parse
from app.recommendations.scoring import ScoreContext, estimated_cost, explain, rerank_diverse, score

router = APIRouter(prefix="/v1", tags=["places"])

LANE_FILTERS = {
    "iconic": lambda p: p.iconic >= 0.45,
    "local": lambda p: p.iconic < 0.2 and not p.is_stay,
    "food": lambda p: p.is_food,
    "stay": lambda p: p.is_stay,
    "night": lambda p: p.is_night,
}
SIGHTS = {"museum", "gallery", "viewpoint", "theme_park", "zoo", "aquarium", "temple", "shrine", "mosque", "landmark", "park", "market", "shopping", "attraction"}


def place_card(p, s=None, dna: TravelerDNA | None = None) -> dict:
    hours = parse(p.tags.get("opening_hours"))
    d = p.model_dump(mode="json")
    d["hours"] = {"raw": hours.raw or None, "verified": hours.by_day is not None}
    if s is not None:
        d["match_pct"] = s.match_pct
        d["why"] = [e.model_dump(mode="json") for e in explain(s, dna or TravelerDNA())]
        d["cost_estimate"] = estimated_cost(p, "JPY" if p.city in {"tokyo", "kyoto"} else "MYR").model_dump()
    return d


@router.get("/places/search")
async def search(city: str = Query(..., max_length=40), lane: str = Query("for_you", pattern="^(for_you|iconic|local|food|stay|night|pulse)$"),
                 q: str | None = Query(None, max_length=60), lat: float | None = Query(None, ge=-90, le=90), lon: float | None = Query(None, ge=-180, le=180),
                 radius_km: float = Query(3.0, gt=0, le=30), iconic_local: float = Query(0.0, ge=-1, le=1), limit: int = Query(30, ge=1, le=100),
                 _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    if not c.places.city(city):
        raise HTTPException(404, {"code": "coverage", "message": "No verified place data for this city yet.",
                                  "supported": [x["key"] for x in c.places.cities()]})
    near = (lat, lon) if lat is not None and lon is not None else None
    cats = None if lane in LANE_FILTERS and lane != "iconic" and lane != "local" else SIGHTS
    pool = c.places.search(city, categories=cats, near=near, radius_km=radius_km if near else None, text=q, limit=3000)
    trends = c.extras.get("trends", {})
    if lane == "pulse":
        pool = [p for p in pool if p.id in trends]
    elif lane in LANE_FILTERS:
        pool = [p for p in pool if LANE_FILTERS[lane](p)]
    dna = TravelerDNA()
    ctx = ScoreContext(dna=dna, anchor=near, iconic_local=iconic_local, trend=trends, geo_scale_km=2.0)
    scored = [score(p, ctx, "JPY" if city in {"tokyo", "kyoto"} else "MYR") for p in pool]
    picked = rerank_diverse(scored, limit)
    return {"city": city, "lane": lane, "results": [place_card(s.place, s, dna) for s in picked],
            "attribution": c.places.city(city).get("attribution")}


@router.get("/places/{place_id}")
async def detail(place_id: str, _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    p = c.places.get(place_id)
    if not p:
        raise HTTPException(404, "Place not found")
    return place_card(p)


@router.get("/places/{place_id}/open")
async def open_now(place_id: str, at: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$"), _: Principal = Depends(current_user),
                   c: Container = Depends(get_container)):
    from datetime import datetime

    p = c.places.get(place_id)
    if not p:
        raise HTTPException(404, "Place not found")
    state = parse(p.tags.get("opening_hours")).state_at(datetime.fromisoformat(at))
    return {"state": state.value, "verified": state != OpenState.UNKNOWN, "source": "OpenStreetMap opening_hours"}


@router.get("/weather")
async def weather(city: str, start: date, days: int = Query(3, ge=1, le=14), _: Principal = Depends(current_user), c: Container = Depends(get_container)):
    info = c.places.city(city)
    if not info or not c.weather:
        raise HTTPException(404, "Unknown city")
    s, w, n, e = info["bbox"]
    try:
        out = await c.weather.forecast((s + n) / 2, (w + e) / 2, info["tz"], start, days)
    except Exception as ex:  # noqa: BLE001
        raise HTTPException(503, {"code": "weather_unavailable", "message": "Forecast unavailable right now."}) from ex
    return [d.summary() for d in out]
