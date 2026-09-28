"""WeatherProvider: Open-Meteo (free, no key). Returns hourly precipitation/temperature for trip days."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timezone
from typing import Protocol

from app.core.resilience import ProviderUnavailable, ResilientClient


@dataclass
class HourWeather:
    time: datetime  # local wall time (naive) in the destination timezone
    temp_c: float
    precip_prob: int
    precip_mm: float
    code: int

    @property
    def rainy(self) -> bool:
        return self.precip_prob >= 60 or self.precip_mm >= 1.0


@dataclass
class DayWeather:
    date: date
    hours: list[HourWeather]
    fetched_at: datetime
    source: str = "Open-Meteo"

    def rain_window(self) -> tuple[int, int] | None:
        wet = [h.time.hour for h in self.hours if h.rainy and 8 <= h.time.hour <= 22]
        return (min(wet), max(wet) + 1) if wet else None

    def summary(self) -> dict:
        day = [h for h in self.hours if 8 <= h.time.hour <= 21] or self.hours
        return {
            "date": self.date.isoformat(),
            "max_c": round(max(h.temp_c for h in day), 1),
            "min_c": round(min(h.temp_c for h in day), 1),
            "max_precip_prob": max(h.precip_prob for h in day),
            "rain_window": self.rain_window(),
            "source": self.source,
            "fetched_at": self.fetched_at.isoformat(),
            "provenance": "live",
        }


class WeatherProvider(Protocol):
    async def forecast(self, lat: float, lon: float, tz: str, start: date, days: int) -> list[DayWeather]: ...


class OpenMeteoProvider:
    def __init__(self, client: ResilientClient | None = None):
        self.client = client or ResilientClient("open-meteo", "https://api.open-meteo.com", timeout_s=6)

    async def forecast(self, lat: float, lon: float, tz: str, start: date, days: int) -> list[DayWeather]:
        end = date.fromordinal(start.toordinal() + max(0, days - 1))
        data = await self.client.get_json("/v1/forecast", {
            "latitude": round(lat, 3), "longitude": round(lon, 3), "timezone": tz,
            "hourly": "temperature_2m,precipitation_probability,precipitation,weather_code",
            "start_date": start.isoformat(), "end_date": end.isoformat(),
        }, cache_ttl_s=1800)
        h = data.get("hourly") or {}
        if not h.get("time"):
            raise ProviderUnavailable("open-meteo", "no hourly data (dates beyond forecast range?)")
        now = datetime.now(timezone.utc)
        by_day: dict[date, list[HourWeather]] = {}
        for i, t in enumerate(h["time"]):
            ts = datetime.fromisoformat(t)
            by_day.setdefault(ts.date(), []).append(HourWeather(
                time=ts, temp_c=h["temperature_2m"][i] or 0.0, precip_prob=int(h["precipitation_probability"][i] or 0),
                precip_mm=h["precipitation"][i] or 0.0, code=int(h["weather_code"][i] or 0)))
        return [DayWeather(date=d, hours=hs, fetched_at=now) for d, hs in sorted(by_day.items())]
