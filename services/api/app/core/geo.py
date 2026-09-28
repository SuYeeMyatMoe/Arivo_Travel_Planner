"""Geography helpers: distances, travel-time estimates, geographic zones.

Estimates here are always labelled Provenance.EST. When a RouteProvider (OpenRouteService) is configured the
routing service replaces walk/drive estimates with provider data (Provenance.LIVE).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import h3

from app.domain.models import Leg, Money, Provenance

EARTH_KM = 6371.0088
DETOUR = 1.3  # street network vs straight line


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_KM * math.asin(math.sqrt(a))


@dataclass(frozen=True)
class TransitProfile:
    """City transit heuristics. Numbers are coarse public-fare/speed averages, shown as estimates."""

    currency: str
    base_fare: float
    per_km: float
    max_fare: float
    speed_kmh: float
    access_min: int  # walk to station + wait
    walk_max_km: float


PROFILES = {
    "JP": TransitProfile("JPY", 170, 18, 480, 26, 9, 1.3),
    "MY": TransitProfile("MYR", 1.3, 0.18, 6.0, 22, 11, 1.0),
    "DEFAULT": TransitProfile("USD", 1.5, 0.15, 4.0, 22, 10, 1.1),
}


def estimate_leg(lat1: float, lon1: float, lat2: float, lon2: float, country: str = "DEFAULT",
                 walking_tolerance: float = 0.6) -> tuple[Leg, Money]:
    """Cheapest sensible leg between two points. Walking tolerance (0..1) stretches the walk threshold."""
    prof = PROFILES.get(country, PROFILES["DEFAULT"])
    route_km = haversine_km(lat1, lon1, lat2, lon2) * DETOUR
    walk_limit = prof.walk_max_km * (0.6 + walking_tolerance * 0.8)
    if route_km <= walk_limit:
        minutes = max(2, round(route_km / 4.5 * 60))
        return Leg(mode="walk", minutes=minutes, distance_m=round(route_km * 1000), provenance=Provenance.EST), Money.zero(prof.currency)
    minutes = prof.access_min + round(route_km / prof.speed_kmh * 60)
    fare = min(prof.max_fare, prof.base_fare + prof.per_km * route_km)
    return (
        Leg(mode="transit", minutes=minutes, distance_m=round(route_km * 1000), provenance=Provenance.EST,
            note="Estimated from distance; check live transit before leaving"),
        Money.of(fare, prof.currency),
    )


def h3_cell(lat: float, lon: float, res: int = 8) -> str:
    return h3.latlng_to_cell(lat, lon, res)


def centroid(points: list[tuple[float, float]]) -> tuple[float, float]:
    if not points:
        raise ValueError("no points")
    return sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)
