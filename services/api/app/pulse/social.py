"""Send It To My Trip: a public social/video URL → the place it shows (with honest confidence).

We never scrape platforms. We call the platform's public oEmbed endpoint (fixed, allowlisted hosts) to get the
title/author, then resolve that text against verified places. SSRF-safe by construction: the user's URL is only ever
a query parameter to a fixed oEmbed host; we never fetch arbitrary user-supplied hosts.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from urllib.parse import urlparse

from app.core.resilience import ResilientClient
from app.domain.models import Place

OEMBED = {
    "youtube.com": ("https://www.youtube.com", "/oembed"),
    "www.youtube.com": ("https://www.youtube.com", "/oembed"),
    "m.youtube.com": ("https://www.youtube.com", "/oembed"),
    "youtu.be": ("https://www.youtube.com", "/oembed"),
    "tiktok.com": ("https://www.tiktok.com", "/oembed"),
    "www.tiktok.com": ("https://www.tiktok.com", "/oembed"),
    "vimeo.com": ("https://vimeo.com", "/api/oembed.json"),
}


class UnsupportedUrl(Exception):
    pass


@dataclass
class Resolution:
    place: Place | None
    confidence: float
    source_title: str | None
    author: str | None
    candidates: list[tuple[Place, float]]
    note: str


def validate(url: str) -> tuple[str, str]:
    u = urlparse(url.strip())
    if u.scheme != "https" or not u.hostname or u.username or u.password or u.port not in (None, 443):
        raise UnsupportedUrl("Only public https links are supported.")
    host = u.hostname.lower()
    if host not in OEMBED:
        raise UnsupportedUrl("Paste a YouTube, TikTok or Vimeo link. Instagram needs its official API access, which we don't use yet.")
    return host, url.strip()


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9 ]+", " ", s)


def match_places(text: str, places: list[Place]) -> list[tuple[Place, float]]:
    """Name matching against verified places. Longer, more specific names win; generic names are ignored."""
    t = f" {_norm(text)} "
    out = []
    for p in places:
        n = _norm(p.name).strip()
        if len(n) < 5 or n in {"main shrine", "main hall", "station", "park"}:
            continue
        if f" {n} " in t:
            conf = min(0.95, 0.55 + 0.03 * len(n.split()) * 3 + 0.2 * p.iconic)
            out.append((p, round(conf, 2)))
    return sorted(out, key=lambda x: -x[1])[:5]


async def resolve(url: str, places_by_city: dict[str, list[Place]], client: ResilientClient | None = None) -> Resolution:
    host, clean = validate(url)
    base, path = OEMBED[host]
    http = client or ResilientClient(f"oembed:{host}", base, timeout_s=6, get_retries=0)
    meta = await http.get_json(path, {"url": clean, "format": "json"}, cache_ttl_s=3600)
    title = (meta.get("title") or "")[:300]
    author = meta.get("author_name")
    candidates: list[tuple[Place, float]] = []
    for city, plist in places_by_city.items():
        candidates += match_places(title, plist)
    candidates.sort(key=lambda x: -x[1])
    if not candidates:
        return Resolution(None, 0.0, title, author, [], "I couldn't identify a verified place from this post's title. Try searching the place name.")
    best, conf = candidates[0]
    note = f"Looks like {best.name}." if conf >= 0.7 else f"Maybe {best.name} — I'm not sure ({round(conf * 100)}%). Check before adding."
    return Resolution(best, conf, title, author, candidates, note)
