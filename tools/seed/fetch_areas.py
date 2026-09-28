"""Fetch neighbourhood names (OSM place=suburb|quarter|neighbourhood) so day zones read "Shibuya / Harajuku", not
"Cluster 3". Writes supabase/seed/areas/<city>.json.  Usage: python tools/seed/fetch_areas.py [city...]"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from fetch_places import CITIES, overpass  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "supabase" / "seed" / "areas"


def fetch(key: str) -> None:
    city = CITIES[key]
    els = overpass(city["bbox"], ['node["place"~"^(suburb|quarter|neighbourhood)$"]["name"]'])
    areas = []
    for e in els:
        tags = e.get("tags", {})
        name = tags.get("name:en") or tags.get("name")
        if not name or "lat" not in e:
            continue
        areas.append({"name": name, "name_local": tags.get("name"), "kind": tags.get("place"), "lat": e["lat"], "lon": e["lon"],
                      "wikidata": tags.get("wikidata")})
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{key}.json").write_text(json.dumps({"city": key, "areas": areas}, ensure_ascii=False), encoding="utf-8")
    print(f"{key}: {len(areas)} areas")


if __name__ == "__main__":
    for k in sys.argv[1:] or list(CITIES):
        fetch(k)
        time.sleep(2)
