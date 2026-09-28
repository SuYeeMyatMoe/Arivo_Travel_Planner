"""Arivo Pulse — an independent trend data system (never "ask the LLM what's trending").

  sources → normalise → place resolution (by id, not by name guessing) → de-duplicate → temporal analysis
         → quality/spam → TrendScore (exact baseline formula) → TravelerDNA re-ranking (in the planner) → evidence

Sources (TrendProvider): Wikipedia pageviews (attention; free), GDELT DOC news (coverage, source diversity,
recency; free, 1 req/5 s), YouTube Data API (optional key), Ticketmaster Discovery (optional key).
A place gets a Pulse badge only when evidence exists; every number carries its source and fetch time.
"""

from __future__ import annotations

import asyncio
import logging
import math
import statistics
import urllib.parse
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Protocol

from app.core.geo import haversine_km
from app.core.resilience import ResilientClient
from app.domain.models import Evidence, Place, Provenance
from app.recommendations.scoring import trend_score

log = logging.getLogger(__name__)


@dataclass
class Signal:
    source: str  # wikipedia | gdelt | youtube | ticketmaster
    place_id: str
    fetched_at: datetime
    # raw normalised metrics (only what the source actually measured)
    series: list[int] = field(default_factory=list)  # daily attention, oldest → newest
    items: list[dict] = field(default_factory=list)  # articles / videos / events: {title, url, domain, published}
    url: str | None = None


class TrendProvider(Protocol):
    name: str

    async def fetch(self, place: Place, city_name: str) -> Signal | None: ...


class WikipediaPageviews:
    name = "wikipedia"

    def __init__(self, client: ResilientClient | None = None, today: date | None = None):
        self.http = client or ResilientClient("wikimedia", "https://wikimedia.org", timeout_s=8, max_concurrency=4,
                                              headers={"Api-User-Agent": "Arivo/0.1 (Pulse; contact via repo)"})
        self.today = today

    async def fetch(self, place: Place, city_name: str) -> Signal | None:
        if not place.wikipedia_en:
            return None
        end = (self.today or date.today()) - timedelta(days=1)
        start = end - timedelta(days=62)
        art = urllib.parse.quote(place.wikipedia_en.replace(" ", "_"), safe="")
        path = f"/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/{art}/daily/{start:%Y%m%d}/{end:%Y%m%d}"
        data = await self.http.get_json(path, cache_ttl_s=6 * 3600)
        series = [int(i["views"]) for i in data.get("items", [])]
        if len(series) < 21:
            return None
        return Signal(source=self.name, place_id=place.id, fetched_at=datetime.now(timezone.utc), series=series,
                      url=f"https://pageviews.wmcloud.org/?pages={art}&project=en.wikipedia.org")


class GdeltNews:
    name = "gdelt"

    def __init__(self, client: ResilientClient | None = None, min_interval_s: float = 5.5):
        self.http = client or ResilientClient("gdelt", "https://api.gdeltproject.org", timeout_s=20, max_concurrency=1, get_retries=0)
        self.min_interval_s = min_interval_s
        self._last = 0.0
        self._lock = asyncio.Lock()

    async def fetch(self, place: Place, city_name: str) -> Signal | None:
        async with self._lock:  # GDELT asks for ≤ 1 request / 5 s
            wait = self.min_interval_s - (asyncio.get_running_loop().time() - self._last)
            if wait > 0:
                await asyncio.sleep(wait)
            self._last = asyncio.get_running_loop().time()
            q = f'"{place.name}" {city_name}'
            try:
                data = await self.http.get_json("/api/v2/doc/doc", {"query": q, "mode": "artlist", "maxrecords": 75, "format": "json",
                                                                    "timespan": "30d", "sort": "datedesc"}, cache_ttl_s=3 * 3600)
            except Exception as e:  # noqa: BLE001 — GDELT returns plain-text notices on overload
                log.info("gdelt skipped %s: %s", place.name, e)
                return None
        items = [{"title": a.get("title"), "url": a.get("url"), "domain": a.get("domain"), "published": a.get("seendate"),
                  "language": a.get("language")} for a in (data or {}).get("articles", [])]
        if not items:
            return None
        return Signal(source=self.name, place_id=place.id, fetched_at=datetime.now(timezone.utc), items=items)


class YouTubeSearch:
    """YouTube Data API v3 search (key required). Counts recent uploads mentioning the place — no scraping."""

    name = "youtube"

    def __init__(self, api_key: str, client: ResilientClient | None = None):
        self.key = api_key
        self.http = client or ResilientClient("youtube", "https://www.googleapis.com", timeout_s=8, max_concurrency=2)

    async def fetch(self, place: Place, city_name: str) -> Signal | None:
        after = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
        data = await self.http.get_json("/youtube/v3/search", {"part": "snippet", "q": f"{place.name} {city_name}", "type": "video",
                                                                "publishedAfter": after, "maxResults": 25, "key": self.key}, cache_ttl_s=6 * 3600)
        items = [{"title": i["snippet"]["title"], "url": f"https://www.youtube.com/watch?v={i['id']['videoId']}",
                  "domain": i["snippet"]["channelTitle"], "published": i["snippet"]["publishedAt"]} for i in data.get("items", [])]
        return Signal(source=self.name, place_id=place.id, fetched_at=datetime.now(timezone.utc), items=items) if items else None


class TicketmasterEvents:
    name = "ticketmaster"

    def __init__(self, api_key: str, client: ResilientClient | None = None):
        self.key = api_key
        self.http = client or ResilientClient("ticketmaster", "https://app.ticketmaster.com", timeout_s=8, max_concurrency=2)

    async def fetch(self, place: Place, city_name: str) -> Signal | None:
        data = await self.http.get_json("/discovery/v2/events.json", {"apikey": self.key, "latlong": f"{place.lat},{place.lon}", "radius": 1,
                                                                        "unit": "km", "size": 20, "sort": "date,asc"}, cache_ttl_s=6 * 3600)
        evs = (data.get("_embedded") or {}).get("events", [])
        items = [{"title": e.get("name"), "url": e.get("url"), "domain": "ticketmaster", "published": (e.get("dates") or {}).get("start", {}).get("localDate")}
                 for e in evs]
        return Signal(source=self.name, place_id=place.id, fetched_at=datetime.now(timezone.utc), items=items) if items else None


# ------------------------------------------------------------------------------------------------ analysis

@dataclass
class PulseSnapshot:
    place_id: str
    name: str
    city: str
    score: float
    components: dict[str, float]
    spam_penalty: float
    label: str | None
    evidence: list[Evidence]
    sources: int
    computed_at: datetime

    def to_json(self) -> dict:
        return {"place_id": self.place_id, "name": self.name, "city": self.city, "score": self.score, "components": self.components,
                "spam_penalty": self.spam_penalty, "label": self.label, "sources": self.sources, "computed_at": self.computed_at.isoformat(),
                "evidence": [e.model_dump(mode="json") for e in self.evidence]}


def _clamp(x: float) -> float:
    return max(0.0, min(1.0, x))


def analyse(place: Place, city_name: str, signals: list[Signal], now: datetime | None = None) -> PulseSnapshot | None:
    """Turn raw signals into the seven TrendScore components + evidence. Missing measurements stay 0 (never guessed)."""
    now = now or datetime.now(timezone.utc)
    comps = {k: 0.0 for k in ("burst", "velocity", "recency", "source_diversity", "local_event", "local_relevance", "engagement_quality")}
    ev: list[Evidence] = []
    wiki = next((s for s in signals if s.source == "wikipedia"), None)
    if wiki and len(wiki.series) >= 21:
        recent = statistics.mean(wiki.series[-7:])
        baseline = statistics.mean(wiki.series[:-14]) or 1.0
        lift = recent / baseline - 1
        comps["burst"] = _clamp(lift / 1.0)  # +100% vs baseline saturates
        last14 = wiki.series[-14:]
        slope = (statistics.mean(last14[7:]) - statistics.mean(last14[:7])) / (statistics.mean(last14[:7]) or 1)
        comps["velocity"] = _clamp(slope / 0.5)
        comps["recency"] = max(comps["recency"], 1.0)  # daily data, yesterday included
        if abs(lift) >= 0.1:
            ev.append(Evidence(text=f"{lift:+.0%} Wikipedia attention this week vs its 6-week baseline", provenance=Provenance.LIVE,
                               source="Wikimedia pageviews", url=wiki.url, updated_at=wiki.fetched_at, weight=0.28 * comps["burst"]))
    articles = [i for s in signals if s.source in {"gdelt", "youtube"} for i in s.items]
    # de-duplicate syndicated copies (same headline) before counting anything
    seen, uniq = set(), []
    for a in articles:
        key = (a.get("title") or "").strip().lower()[:80]
        if key and key not in seen:
            seen.add(key)
            uniq.append(a)
    dup_ratio = 1 - (len(uniq) / len(articles)) if articles else 0.0
    domains = {a.get("domain") for a in uniq if a.get("domain")}
    if uniq:
        comps["source_diversity"] = _clamp(math.log1p(len(domains)) / math.log1p(12))
        newest = max((_parse_ts(a.get("published")) for a in uniq), default=None)
        if newest:
            age_days = max(0.0, (now - newest).total_seconds() / 86400)
            comps["recency"] = max(comps["recency"], _clamp(1 - age_days / 14))
        mentions_city = sum(1 for a in uniq if city_name.lower() in (a.get("title") or "").lower())
        comps["local_relevance"] = _clamp(0.5 + 0.5 * mentions_city / max(1, len(uniq)))
        ev.append(Evidence(text=f"{len(uniq)} recent articles/videos from {len(domains)} independent sources", provenance=Provenance.LIVE,
                           source="GDELT news" + (" + YouTube" if any(s.source == "youtube" for s in signals) else ""),
                           url=uniq[0].get("url"), updated_at=max(s.fetched_at for s in signals), weight=0.12 * comps["source_diversity"]))
    events = [i for s in signals if s.source == "ticketmaster" for i in s.items]
    upcoming = [e for e in events if (d := _parse_ts(e.get("published"))) and 0 <= (d - now).days <= 14]
    if upcoming:
        comps["local_event"] = 1.0
        ev.append(Evidence(text=f"Event nearby: {upcoming[0]['title']} ({upcoming[0]['published']})", provenance=Provenance.LIVE,
                           source="Ticketmaster", url=upcoming[0].get("url"), updated_at=now, weight=0.10))
    single_source_dominance = 0.0
    if uniq:
        counts = {}
        for a in uniq:
            counts[a.get("domain")] = counts.get(a.get("domain"), 0) + 1
        single_source_dominance = max(counts.values()) / len(uniq)
    spam_penalty = round(max(0.3, 1.0 - 0.5 * dup_ratio - 0.3 * max(0.0, single_source_dominance - 0.5)), 3)
    score = trend_score(comps, spam_penalty)
    sources = len({s.source for s in signals}) + max(0, len(domains) - 1)
    if not ev:
        return None  # no evidence → no Pulse
    label = None
    if score >= 55 and comps["burst"] >= 0.3 and sources >= 2:
        label = "Rising this week"
    elif comps["local_event"]:
        label = "Local event nearby"
    elif comps["source_diversity"] >= 0.4:
        label = "Recently discussed"
    ev.append(Evidence(text=f"Updated {now:%d %b %H:%M} UTC", provenance=Provenance.LIVE, updated_at=now))
    return PulseSnapshot(place_id=place.id, name=place.name, city=place.city, score=score, components={k: round(v, 3) for k, v in comps.items()},
                         spam_penalty=spam_penalty, label=label, evidence=ev, sources=sources, computed_at=now)


def _parse_ts(v: str | None) -> datetime | None:
    if not v:
        return None
    for fmt in ("%Y%m%dT%H%M%SZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d"):
        try:
            return datetime.strptime(v, fmt).replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


class PulseEngine:
    def __init__(self, store, places, providers: list[TrendProvider], trends: dict[str, float]):
        self.store, self.places, self.providers, self.trends = store, places, providers, trends

    async def refresh(self, city: str, limit: int = 24) -> list[PulseSnapshot]:
        info = self.places.city(city)
        pool = [p for p in self.places.search(city, limit=10000) if p.wikipedia_en and not p.is_stay and p.category != "station"]
        candidates = sorted(pool, key=lambda p: -p.notability)[:limit]
        out: list[PulseSnapshot] = []
        for p in candidates:
            signals = []
            for prov in self.providers:
                try:
                    s = await prov.fetch(p, info["name"])
                    if s:
                        signals.append(s)
                except Exception as e:  # noqa: BLE001 — one source failing degrades evidence, never the feed
                    log.info("pulse %s/%s failed: %s", prov.name, p.name, e)
            snap = analyse(p, info["name"], signals)
            if snap:
                out.append(snap)
                await self.store.kv_put("pulse", f"{city}:{p.id}", snap.to_json())
                if snap.label:
                    self.trends[p.id] = snap.score  # feeds RecommendationScore (weight 0.15) — never dominates
        return sorted(out, key=lambda s: -s.score)

    async def feed(self, city: str) -> list[dict]:
        return sorted(await self.store.kv_list("pulse", f"{city}:"), key=lambda s: -s["score"])


def nearby_events_boost(place: Place, events: list[dict], km: float = 1.0) -> bool:
    return any(haversine_km(place.lat, place.lon, e["lat"], e["lon"]) <= km for e in events if "lat" in e)
