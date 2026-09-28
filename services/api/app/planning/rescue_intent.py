"""'Rescue my day' free text → a replan trigger. Deterministic first; only unclear messages need a model."""

from __future__ import annotations

import re

from app.domain.models import ItineraryDay
from app.planning.intent import NUM_WORDS
from app.planning.replan import Trigger

CATEGORY_WORDS = {"museum": "museum", "museums": "museum", "temple": "temple", "temples": "temple", "shrine": "shrine",
                  "shrines": "shrine", "shopping": "shopping", "gallery": "gallery", "galleries": "gallery", "park": "park", "parks": "park"}


def classify(text: str, day: ItineraryDay | None = None) -> dict:
    t = text.lower()
    out: dict = {"confidence": 0.8}
    m = re.search(r"(\d+|an?|one|two|three|four|half an?)\s*(hour|hr|minute|min)", t)
    minutes = None
    if m:
        n = 0.5 if m.group(1).startswith("half") else float(NUM_WORDS.get(m.group(1), m.group(1)) if not m.group(1).isdigit() else m.group(1))
        minutes = int(n * (60 if m.group(2).startswith(("hour", "hr")) else 1))
    if re.search(r"\b(rain|raining|rainy|storm|wet|typhoon|downpour)\b", t):
        out["trigger"] = Trigger.RAIN
    elif re.search(r"\b(delay|delayed|flight late|train late|missed (the|our) (train|bus|flight))\b", t):
        out.update(trigger=Trigger.DELAY, minutes_late=minutes or 60)
    elif re.search(r"\b(late|overslept|woke up|slept in|running behind)\b", t):
        out.update(trigger=Trigger.LATE, minutes_late=minutes or 90)
    elif re.search(r"\b(tired|exhausted|sore feet|worn out|slow down|need a break|fatigue)\b", t):
        out["trigger"] = Trigger.FATIGUE
    elif re.search(r"\b(closed|shut|not open|renovation)\b", t):
        out["trigger"] = Trigger.CLOSED
        if day:
            hit = next((i for i in day.items if i.name.lower() in t or any(w in t for w in i.name.lower().split() if len(w) > 4)), None)
            out["place_id"] = hit.place_id if hit else None
            if not hit:
                out["confidence"] = 0.4
    elif re.search(r"\b(spent too much|over budget|too expensive|cheaper|save money|broke)\b", t):
        out["trigger"] = Trigger.BUDGET
    elif re.search(r"\b(skip|no more|don'?t want)\b", t) and (cat := next((v for k, v in CATEGORY_WORDS.items() if re.search(rf"\b{k}\b", t)), None)):
        out.update(trigger=Trigger.SKIP, category=cat)
    elif re.search(r"\b(hungry|more food|eat more|food tour|snack)\b", t):
        out["trigger"] = Trigger.MORE_FOOD
    elif re.search(r"\b(nightlife|bar|bars|drinks|party|club|izakaya)\b", t):
        out["trigger"] = Trigger.NIGHTLIFE
    else:
        out.update(trigger=None, confidence=0.0)
    return out
