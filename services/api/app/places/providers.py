"""PlaceProvider adapters.

- SeedPlaceProvider: real OSM + Wikidata places fetched by tools/seed/fetch_places.py (offline-capable, the default).
- PostgisPlaceProvider: the same data served from Supabase/PostGIS (production path; see supabase/migrations).
- OverpassPlaceProvider: live OSM lookup for cities not seeded yet (rate-limited, cached).

Providers never invent places: every Place carries its sources.
"""

from __future__ import annotations

import json
import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Protocol

from app.core.geo import haversine_km
from app.domain.models import Place

log = logging.getLogger(__name__)

# Building-part names from OSM ("Main Shrine" = 本殿 of Meiji Jingu) are useless to a traveller on their own; the named
# parent place is in the seed too, so these are dropped rather than shown with a name nobody can search for.
_GENERIC_NAME = re.compile(r"^(main|inner|outer|east|west|north|south)?\s*(shrine|hall|building|gate|temple|sanctuary|garden|museum|park)$"
                           r"|^(honden|haiden|hondo|hondō|kondo|kondō)$", re.I)


def is_generic_name(name: str) -> bool:
    return bool(_GENERIC_NAME.match(name.strip()))


_BLOCK_SUFFIX = re.compile(r"(?:[\s-]*\d+(?:-?ch[oō]me)?)+$", re.I)


def area_label(name: str) -> str:
    """'Atago 1-chome' → 'Atago', 'Roppongi 6' → 'Roppongi': block numbers mean nothing to a traveller."""
    return _BLOCK_SUFFIX.sub("", name).strip(" -") or name


class CityInfo(dict):
    """{key, name, country, tz, currency, bbox}"""


class PlaceProvider(Protocol):
    name: str

    def cities(self) -> list[CityInfo]: ...

    def city(self, key: str) -> CityInfo | None: ...

    def search(self, city: str, *, categories: set[str] | None = None, near: tuple[float, float] | None = None,
               radius_km: float | None = None, text: str | None = None, limit: int = 200) -> list[Place]: ...

    def get(self, place_id: str) -> Place | None: ...


CITY_ALIASES = {
    "tokyo": "tokyo", "東京": "tokyo", "kyoto": "kyoto", "京都": "kyoto", "kuala lumpur": "kuala-lumpur", "kl": "kuala-lumpur",
    "kuala-lumpur": "kuala-lumpur",
}


def resolve_city_key(name: str) -> str | None:
    return CITY_ALIASES.get(name.strip().lower())


class SeedPlaceProvider:
    name = "seed"

    def __init__(self, seed_dir: Path):
        self._cities: dict[str, CityInfo] = {}
        self._places: dict[str, Place] = {}
        self._by_city: dict[str, list[Place]] = {}
        for f in sorted(seed_dir.glob("*.json")):
            doc = json.loads(f.read_text(encoding="utf-8"))
            key = doc["city"]["key"]
            self._cities[key] = CityInfo(doc["city"], attribution=doc.get("attribution"))
            places = [Place(**{k: v for k, v in p.items() if k in Place.model_fields}) for p in doc["places"] if not is_generic_name(p["name"])]
            self._by_city[key] = places
            for p in places:
                self._places[p.id] = p
        self._areas: dict[str, list[dict]] = {}
        areas_dir = seed_dir.parent / "areas"
        for f in sorted(areas_dir.glob("*.json")) if areas_dir.exists() else []:
            doc = json.loads(f.read_text(encoding="utf-8"))
            self._areas[doc["city"]] = doc["areas"]
        log.info("seed places loaded: %s", {k: len(v) for k, v in self._by_city.items()})

    def nearest_area(self, city: str, lat: float, lon: float, max_km: float = 1.5) -> str | None:
        """Neighbourhood name for a day zone. Prefers well-known areas (with Wikidata) within reach."""
        best, best_d = None, max_km
        for a in self._areas.get(city, []):
            d = haversine_km(lat, lon, a["lat"], a["lon"]) * (0.7 if a.get("wikidata") else 1.0) * (0.85 if a["kind"] != "neighbourhood" else 1.0)
            if d < best_d:
                best, best_d = a["name"], d
        return area_label(best) if best else None

    def cities(self) -> list[CityInfo]:
        return list(self._cities.values())

    def city(self, key: str) -> CityInfo | None:
        return self._cities.get(key)

    def get(self, place_id: str) -> Place | None:
        return self._places.get(place_id)

    def search(self, city: str, *, categories=None, near=None, radius_km=None, text=None, limit=200) -> list[Place]:
        out = self._by_city.get(city, [])
        if categories:
            out = [p for p in out if p.category in categories]
        if text:
            t = text.lower()
            out = [p for p in out if t in p.name.lower() or (p.name_local and t in p.name_local.lower())]
        if near:
            lat, lon = near
            scored = [(haversine_km(lat, lon, p.lat, p.lon), p) for p in out]
            if radius_km:
                scored = [s for s in scored if s[0] <= radius_km]
            scored.sort(key=lambda s: s[0])
            out = [p for _, p in scored]
        return out[:limit]


@lru_cache
def default_provider(seed_dir: str) -> SeedPlaceProvider:
    return SeedPlaceProvider(Path(seed_dir))
