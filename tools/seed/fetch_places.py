"""Fetch real places for demo cities from OpenStreetMap (Overpass) and enrich them with Wikidata.

Writes supabase/seed/places/<city>.json — the same normalized shape the API's PlaceProvider serves.

    python tools/seed/fetch_places.py            # all cities
    python tools/seed/fetch_places.py tokyo      # one city

Data: © OpenStreetMap contributors (ODbL); Wikidata (CC0); Wikimedia Commons images keep their own licences
and are referenced by URL with attribution, never re-hosted.
"""

from __future__ import annotations

import json
import math
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "supabase" / "seed" / "places"
UA = "Arivo/0.1 (open-source travel planner; dev seed script)"
OVERPASS = "https://overpass-api.de/api/interpreter"
WIKIDATA = "https://www.wikidata.org/w/api.php"

CITIES = {
    "tokyo": {"name": "Tokyo", "country": "JP", "tz": "Asia/Tokyo", "currency": "JPY", "bbox": (35.60, 139.64, 35.78, 139.86)},
    "kyoto": {"name": "Kyoto", "country": "JP", "tz": "Asia/Tokyo", "currency": "JPY", "bbox": (34.93, 135.68, 35.07, 135.82)},
    "kuala-lumpur": {"name": "Kuala Lumpur", "country": "MY", "tz": "Asia/Kuala_Lumpur", "currency": "MYR", "bbox": (3.05, 101.62, 3.20, 101.75)},
}

# Overpass selectors per group. Food/nightlife require an English name to keep volume bounded and useful.
GROUPS = {
    "sights": [
        'nwr["tourism"~"^(attraction|museum|gallery|viewpoint|theme_park|zoo|aquarium)$"]["name"]',
        'nwr["historic"~"^(castle|monument|memorial|ruins|temple)$"]["wikidata"]',
        'nwr["amenity"="place_of_worship"]["wikidata"]',
        'nwr["leisure"~"^(park|garden)$"]["wikidata"]',
        'nwr["amenity"="marketplace"]["name"]',
        'nwr["shop"="mall"]["name"]["wikidata"]',
    ],
    "food": [
        'nwr["amenity"~"^(restaurant|cafe|fast_food|food_court)$"]["name:en"]',
        'nwr["amenity"~"^(restaurant|cafe)$"]["wikidata"]',
    ],
    "night": ['nwr["amenity"~"^(bar|pub|nightclub)$"]["name:en"]'],
    "stay": ['nwr["tourism"~"^(hotel|hostel|guest_house)$"]["name"]'],
    "transit": ['node["railway"="station"]["name"]'],
}

MAX_PER_GROUP = {"sights": 1600, "food": 1400, "night": 300, "stay": 500, "transit": 400}


CACHE = Path(__file__).resolve().parent / ".cache"


def http_json(url: str, data: bytes | None = None) -> dict:
    """GET/POST JSON with a disk cache (re-runs don't re-hit public APIs) and polite backoff on 429."""
    import hashlib

    CACHE.mkdir(exist_ok=True)
    key = CACHE / (hashlib.sha1(url.encode() + (data or b"")).hexdigest() + ".json")
    if key.exists():
        return json.loads(key.read_text(encoding="utf-8"))
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Accept": "application/json"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                body = json.loads(r.read().decode())
                key.write_text(json.dumps(body), encoding="utf-8")
                return body
        except urllib.error.HTTPError as e:
            retry_after = int(e.headers.get("Retry-After", "0") or 0)
            wait = max(retry_after, 20 * (attempt + 1)) if e.code == 429 else 5 * (attempt + 1)
            print(f"  retry in {wait}s (HTTP {e.code})")
            time.sleep(wait)
        except Exception as e:  # noqa: BLE001 — seed script: retry then give up loudly
            wait = 5 * (attempt + 1)
            print(f"  retry in {wait}s ({e})")
            time.sleep(wait)
    raise RuntimeError(f"failed: {url}")


def overpass(bbox: tuple[float, float, float, float], selectors: list[str]) -> list[dict]:
    s, w, n, e = bbox
    body = "".join(f"{sel}({s},{w},{n},{e});" for sel in selectors)
    q = f"[out:json][timeout:170];({body});out center tags;"
    res = http_json(OVERPASS, urllib.parse.urlencode({"data": q}).encode())
    return res.get("elements", [])


def category(tags: dict) -> str | None:
    t = tags.get("tourism")
    a = tags.get("amenity")
    if t in {"museum", "gallery", "viewpoint", "theme_park", "zoo", "aquarium"}:
        return t
    if t in {"hotel", "hostel", "guest_house"}:
        return t
    if a in {"restaurant", "cafe", "fast_food", "food_court", "bar", "pub", "nightclub", "marketplace"}:
        return "market" if a == "marketplace" else a
    if a == "place_of_worship":
        religion = tags.get("religion")
        return "shrine" if religion == "shinto" else "mosque" if religion == "muslim" else "temple"
    if tags.get("historic"):
        return "landmark"
    if tags.get("leisure") in {"park", "garden"}:
        return "park"
    if tags.get("shop") == "mall":
        return "shopping"
    if tags.get("railway") == "station":
        return "station"
    if t == "attraction":
        return "attraction"
    return None


INDOOR = {"museum", "gallery", "aquarium", "shopping", "restaurant", "cafe", "fast_food", "food_court", "bar", "pub",
          "nightclub", "hotel", "hostel", "guest_house", "station"}

# Category → TravelerDNA dimensions it serves (weights 0..1). Tags refine this (cuisine, anime, etc.).
DNA = {
    "museum": {"culture": 0.9, "history": 0.7, "architecture": 0.3},
    "gallery": {"culture": 0.9, "photography": 0.4},
    "viewpoint": {"photography": 0.9, "nature": 0.4},
    "theme_park": {"adventure": 0.8, "nightlife": 0.2},
    "zoo": {"nature": 0.7, "relaxation": 0.3},
    "aquarium": {"nature": 0.6, "relaxation": 0.4},
    "temple": {"culture": 0.8, "history": 0.8, "architecture": 0.7, "photography": 0.5},
    "shrine": {"culture": 0.8, "history": 0.7, "architecture": 0.6, "photography": 0.6},
    "mosque": {"culture": 0.8, "architecture": 0.8, "history": 0.5},
    "landmark": {"history": 0.8, "architecture": 0.6, "photography": 0.5},
    "park": {"nature": 0.9, "relaxation": 0.8, "photography": 0.4},
    "market": {"food": 0.8, "shopping": 0.6, "localDiscovery": 0.6},
    "shopping": {"shopping": 0.9},
    "attraction": {"culture": 0.3, "photography": 0.35},
    "restaurant": {"food": 0.9},
    "cafe": {"food": 0.5, "relaxation": 0.6},
    "fast_food": {"food": 0.6},
    "food_court": {"food": 0.8, "localDiscovery": 0.4},
    "bar": {"nightlife": 0.8},
    "pub": {"nightlife": 0.8},
    "nightclub": {"nightlife": 1.0},
}

KEEP_TAGS = ["cuisine", "opening_hours", "website", "wikidata", "wikipedia", "stars", "fee", "charge", "wheelchair",
             "diet:vegetarian", "diet:vegan", "diet:halal", "diet:gluten_free", "phone", "addr:full", "addr:city",
             "brand", "operator", "internet_access", "outdoor_seating", "smoking", "rooms", "description:en",
             "tourism", "historic", "man_made", "religion", "heritage", "shop", "building"]

# Visit duration in minutes (quick, normal, deep) — Time-to-Stay baseline; the planner scales by pace.
DURATION = {
    "museum": (60, 120, 180), "gallery": (40, 75, 120), "viewpoint": (30, 60, 90), "theme_park": (180, 300, 480),
    "zoo": (90, 150, 240), "aquarium": (60, 100, 150), "temple": (30, 60, 90), "shrine": (30, 50, 80),
    "mosque": (20, 40, 60), "landmark": (20, 40, 60), "park": (40, 75, 120), "market": (40, 75, 120),
    "shopping": (45, 90, 150), "attraction": (40, 70, 110), "restaurant": (45, 75, 105), "cafe": (25, 45, 70),
    "fast_food": (20, 30, 45), "food_court": (30, 50, 70), "bar": (45, 75, 120), "pub": (45, 75, 120),
    "nightclub": (90, 150, 240),
}


def normalize(el: dict, city: str) -> dict | None:
    tags = el.get("tags", {})
    cat = category(tags)
    if not cat:
        return None
    lat = el.get("lat") or el.get("center", {}).get("lat")
    lon = el.get("lon") or el.get("center", {}).get("lon")
    if lat is None or lon is None:
        return None
    name = tags.get("name:en") or tags.get("name")
    if not name:
        return None
    if tags.get("office") == "diplomatic" or tags.get("amenity") == "embassy" or re.search(r"embass|embahada|大使館|consulate", name.lower()):
        return None  # not a visitor destination
    dna = dict(DNA.get(cat, {}))
    blob = " ".join(str(v).lower() for v in tags.values())
    if re.search(r"\b(anime|manga|otaku|gundam|pok[eé]mon|ghibli|figure|cosplay|maid caf[eé]|hobby|arcade)\b", blob):
        dna["anime"] = 1.0
    if tags.get("man_made") in {"tower", "observation_tower"} or re.search(r"\b(tower|observatory|observation deck|sky deck|展望)\b", blob):
        dna.update({"photography": 0.95, "architecture": max(dna.get("architecture", 0), 0.6)})
    if re.search(r"\b(crossing|street|yokocho|alley|arcade)\b", name.lower()):
        dna.update({"photography": max(dna.get("photography", 0), 0.7), "localDiscovery": max(dna.get("localDiscovery", 0), 0.5),
                    "food": max(dna.get("food", 0), 0.3)})
    if cat in {"restaurant", "fast_food", "food_court"} and tags.get("cuisine"):
        dna["localDiscovery"] = max(dna.get("localDiscovery", 0), 0.3)
    return {
        "id": f"osm:{el['type']}:{el['id']}",
        "name": name,
        "name_local": tags.get("name") if tags.get("name") != name else None,
        "category": cat,
        "lat": round(lat, 7),
        "lon": round(lon, 7),
        "city": city,
        "indoor": cat in INDOOR,
        "dna": dna,
        "duration_min": DURATION.get(cat),
        "tags": {k: tags[k] for k in KEEP_TAGS if k in tags},
        # evidence richness: how much verifiable information exists about this place (0..5)
        "quality": sum(1 for k in ("wikidata", "website", "opening_hours", "name:en", "description:en") if k in tags),
        "sources": [{"name": "OpenStreetMap", "url": f"https://www.openstreetmap.org/{el['type']}/{el['id']}", "license": "ODbL"}],
    }


def cap_by_grid(places: list[dict], limit: int) -> list[dict]:
    """Keep geographic coverage when capping: round-robin across ~1 km grid cells, notable places first."""
    if len(places) <= limit:
        return places
    cells: dict[tuple[int, int], list[dict]] = defaultdict(list)
    for p in sorted(places, key=lambda p: (-("wikidata" in p["tags"]), p["name"])):
        cells[(int(p["lat"] / 0.01), int(p["lon"] / 0.01))].append(p)
    out: list[dict] = []
    buckets = list(cells.values())
    i = 0
    while len(out) < limit and any(buckets):
        b = buckets[i % len(buckets)]
        if b:
            out.append(b.pop(0))
        i += 1
    return out


def wikidata_enrich(places: list[dict]) -> None:
    """Sitelink count = global notability (drives Iconic ↔ Local); P18 = Commons image; enwiki title for Story Mode."""
    ids = sorted({p["tags"]["wikidata"] for p in places if p["tags"].get("wikidata", "").startswith("Q")})
    info: dict[str, dict] = {}
    for i in range(0, len(ids), 50):
        chunk = ids[i : i + 50]
        url = WIKIDATA + "?" + urllib.parse.urlencode({
            "action": "wbgetentities", "ids": "|".join(chunk), "props": "sitelinks|claims|descriptions",
            "languages": "en", "format": "json",
        })
        data = http_json(url)
        for qid, ent in data.get("entities", {}).items():
            claims = ent.get("claims", {})
            img = None
            if "P18" in claims:
                try:
                    img = claims["P18"][0]["mainsnak"]["datavalue"]["value"]
                except (KeyError, IndexError):
                    img = None
            links = ent.get("sitelinks", {})
            info[qid] = {
                "image_file": img,
                "enwiki": links.get("enwiki", {}).get("title"),
                "description": ent.get("descriptions", {}).get("en", {}).get("value"),
                "sitelinks": len(links),
            }
        time.sleep(1.5)
        print(f"  wikidata {min(i + 50, len(ids))}/{len(ids)}")
    for p in places:
        q = p["tags"].get("wikidata")
        if q and q in info:
            w = info[q]
            p["notability"] = w.get("sitelinks", 0)
            if w.get("description"):
                p["summary"] = w["description"]
            if w.get("enwiki"):
                p["wikipedia_en"] = w["enwiki"]
            if w.get("image_file"):
                fname = w["image_file"].replace(" ", "_")
                p["photo"] = {
                    "url": "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(fname) + "?width=800",
                    "page": "https://commons.wikimedia.org/wiki/File:" + urllib.parse.quote(fname),
                    "credit": "Wikimedia Commons (see file page for author and licence)",
                }
            p["sources"].append({"name": "Wikidata", "url": f"https://www.wikidata.org/wiki/{q}", "license": "CC0"})
        else:
            p["notability"] = 0


def iconic_score(p: dict) -> float:
    """0 = local discovery, 1 = world-famous. Log-scaled Wikidata sitelinks (evidence, not vibes)."""
    n = p.get("notability", 0)
    return round(min(1.0, math.log1p(n) / math.log1p(60)), 3)


def fetch_city(key: str) -> None:
    city = CITIES[key]
    print(f"== {city['name']}")
    all_places: dict[str, dict] = {}
    for group, selectors in GROUPS.items():
        els = overpass(city["bbox"], selectors)
        norm = [p for p in (normalize(e, key) for e in els) if p]
        uniq = list({p["id"]: p for p in norm}.values())
        if group == "sights":
            # know notability BEFORE capping so famous places (Senso-ji, Meiji Jingu…) can never be cut
            wikidata_enrich(uniq)
            limit = MAX_PER_GROUP[group]
            by_fame = sorted(uniq, key=lambda p: -p.get("notability", 0))
            famous = by_fame[: int(limit * 0.45)]
            rest = cap_by_grid(by_fame[len(famous):], limit - len(famous))
            capped = famous + rest
        else:
            capped = cap_by_grid(uniq, MAX_PER_GROUP[group])
        print(f"  {group}: {len(els)} raw → {len(capped)} kept")
        for p in capped:
            all_places[p["id"]] = p
        time.sleep(2)
    places = list(all_places.values())
    wikidata_enrich([p for p in places if "notability" not in p])
    for p in places:
        p["iconic"] = iconic_score(p)
    OUT.mkdir(parents=True, exist_ok=True)
    doc = {"city": {"key": key, **city, "bbox": list(city["bbox"])}, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "attribution": "© OpenStreetMap contributors (ODbL) · Wikidata (CC0) · images: Wikimedia Commons (per-file licences)",
           "places": sorted(places, key=lambda p: p["id"])}
    (OUT / f"{key}.json").write_text(json.dumps(doc, ensure_ascii=False, indent=0), encoding="utf-8")
    print(f"  wrote {len(places)} places")


if __name__ == "__main__":
    for key in sys.argv[1:] or list(CITIES):
        fetch_city(key)
