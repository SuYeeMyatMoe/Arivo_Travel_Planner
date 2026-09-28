"""Natural-language trip intent → TripIntent.

`parse_heuristic` is deterministic and always available (offline, AI outage, tests). The AI parser in
app.ai.router refines it; results are merged so a model can add detail but never silently drop what the rules saw.
"""

from __future__ import annotations

import re
from datetime import date, timedelta

from app.domain.models import CrewType, Pace, TripIntent

NUM_WORDS = {
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "couple of": 2, "few": 3,
}
CURRENCY = {"rm": "MYR", "myr": "MYR", "ringgit": "MYR", "usd": "USD", "$": "USD", "us$": "USD", "¥": "JPY", "jpy": "JPY",
            "yen": "JPY", "€": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR", "£": "GBP", "gbp": "GBP", "sgd": "SGD", "s$": "SGD"}
KNOWN_PLACES = [
    "kuala lumpur", "tokyo", "kyoto", "osaka", "nara", "hokkaido", "sapporo", "fukuoka", "hiroshima", "japan", "seoul", "busan",
    "bangkok", "chiang mai", "bali", "singapore", "penang", "langkawi", "melaka", "malacca", "ipoh", "cameron highlands",
    "taipei", "hong kong", "paris", "rome", "florence", "venice", "milan", "zurich", "lucerne", "interlaken", "london",
    "barcelona", "italy", "switzerland", "france", "spain", "europe", "kl",
]
INTERESTS = {
    "anime": ["anime", "manga", "otaku", "akihabara", "ghibli", "pokemon"],
    "food": ["food", "eat", "street food", "ramen", "sushi", "foodie", "cuisine", "restaurants", "hawker", "dining"],
    "photography": ["photo", "photograph", "instagram", "camera", "sunset", "views"],
    "culture": ["culture", "museum", "art", "gallery", "traditional", "temple", "shrine"],
    "history": ["history", "historic", "heritage", "castle"],
    "nature": ["nature", "hike", "hiking", "scenic", "mountain", "park", "garden", "beach", "lake"],
    "shopping": ["shopping", "shop", "markets", "fashion", "souvenir"],
    "nightlife": ["nightlife", "bars", "bar", "clubbing", "club", "izakaya", "drinks", "party"],
    "architecture": ["architecture", "buildings", "temple", "shrine", "skyline"],
    "relaxation": ["relax", "chill", "onsen", "spa", "cafe", "coffee", "slow"],
    "adventure": ["adventure", "thrill", "theme park", "rollercoaster", "diving"],
    "luxury": ["luxury", "fancy", "fine dining", "five star", "5-star"],
    "localDiscovery": ["local", "hidden gem", "off the beaten", "authentic", "locals"],
}
DIETARY = {"vegetarian": "vegetarian", "vegan": "vegan", "halal": "halal", "gluten": "gluten_free", "no pork": "halal"}
WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]


def _num(tok: str) -> int | None:
    tok = tok.strip().lower()
    if tok.isdigit():
        return int(tok)
    return NUM_WORDS.get(tok)


def _days(t: str) -> int | None:
    m = re.search(r"\b(\d{1,2}|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen)"
                  r"[\s-]*(day|days|night|nights|week|weeks)\b", t)
    if m:
        n = _num(m.group(1)) or 1
        unit = m.group(2)
        return n * 7 if unit.startswith("week") else (n + 1 if unit.startswith("night") else n)
    if "fortnight" in t:
        return 14
    if "weekend" in t:
        return 2
    if re.search(r"\b(saturday|sunday|day trip|one day|a day)\b", t):
        return 1
    return None


def _budget(text: str) -> tuple[float | None, str | None, bool]:
    t = text.lower().replace(",", "")
    pat = r"(rm|myr|usd|us\$|s\$|\$|¥|jpy|€|eur|£|gbp|sgd)\s?(\d+(?:\.\d+)?)\s?(k)?\b|(\d+(?:\.\d+)?)\s?(k)?\s?(rm|myr|ringgit|usd|yen|jpy|eur|euros?|gbp|sgd)\b"
    m = re.search(pat, t)
    if not m:
        return None, None, True
    if m.group(1):
        cur, amt, k = m.group(1), float(m.group(2)), m.group(3)
    else:
        amt, k, cur = float(m.group(4)), m.group(5), m.group(6)
    if k:
        amt *= 1000
    per_person = not re.search(r"\b(total|altogether|in total|combined|for (all|everyone|the group))\b", t)
    return amt, CURRENCY.get(cur, cur.upper()), per_person


def _crew(t: str) -> tuple[CrewType, int]:
    m = re.search(r"with (?:my )?(\d+|two|three|four|five|six|seven|eight|nine|ten) (?:friends|mates|buddies|colleagues|people)", t)
    if m:
        return CrewType.FRIENDS, (_num(m.group(1)) or 1) + 1
    m = re.search(r"\b(\d+|two|three|four|five|six|seven|eight) of us\b", t)
    if m:
        n = _num(m.group(1)) or 2
        if re.search(r"\b(family|kids|children|parents|mum|mom|dad)\b", t):
            return CrewType.FAMILY, n
        return (CrewType.COUPLE, 2) if n == 2 else (CrewType.FRIENDS, n)
    if re.search(r"\b(family|kids|children|my parents|toddler|grandma|grandpa)\b", t):
        return CrewType.FAMILY, 3
    if re.search(r"\b(couple|partner|wife|husband|girlfriend|boyfriend|honeymoon|anniversary|fianc)", t):
        return CrewType.COUPLE, 2
    if re.search(r"\bfriends\b", t):
        return CrewType.FRIENDS, 3
    return CrewType.SOLO, 1


def _start_date(t: str, today: date) -> date | None:
    m = re.search(r"\b(20\d\d)-(\d{2})-(\d{2})\b", t)
    if m:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    m = re.search(r"\b(\d{1,2})(?:st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b", t)
    if m:
        d = date(today.year, MONTHS.index(m.group(2)) + 1, int(m.group(1)))
        return d if d >= today else d.replace(year=today.year + 1)
    if "this weekend" in t or "weekend" in t:
        return today + timedelta(days=(5 - today.weekday()) % 7)
    for i, wd in enumerate(WEEKDAYS):
        if re.search(rf"\b(next |this |one free |free )?{wd}\b", t):
            delta = (i - today.weekday()) % 7 or 7
            return today + timedelta(days=delta)
    if "tomorrow" in t:
        return today + timedelta(days=1)
    m = re.search(r"\bin (january|february|march|april|may|june|july|august|september|october|november|december)\b", t)
    if m:
        month = MONTHS.index(m.group(1)[:3]) + 1
        year = today.year if month >= today.month else today.year + 1
        return date(year, month, 1)
    return None


def parse_heuristic(text: str, today: date | None = None) -> TripIntent:
    today = today or date.today()
    t = " " + text.lower() + " "
    dests: list[str] = []
    for place in sorted(KNOWN_PLACES, key=len, reverse=True):
        if re.search(rf"\b{re.escape(place)}\b", t) and not any(place in d.lower() for d in dests):
            dests.append(place)
    origin = None
    m = re.search(r"\b(?:i live in|from|based in|home is)\s+([a-z ]+?)(?:[,.]| and | to |$)", t)
    if m and m.group(1).strip() in KNOWN_PLACES:
        origin = m.group(1).strip()
    # "I live in KL ... give me somewhere" → a staycation in the home city
    order = {d: t.find(d) for d in dests}
    dests = sorted(dests, key=lambda d: order[d])
    if origin and len(dests) > 1:
        dests = [d for d in dests if d != origin] or dests
    norm = {"kl": "Kuala Lumpur", "malacca": "Melaka"}
    destinations = [norm.get(d, d.title()) for d in dests]
    if not destinations:  # unknown city: capture the proper noun after "in/to/visiting…" so coverage can be answered honestly
        stop = {w.title() for w in WEEKDAYS} | {"January", "February", "March", "April", "May", "June", "July", "August",
                                                  "September", "October", "November", "December", "I", "We", "My", "The"}
        for m in re.finditer(r"\b(?:in|to|visit|visiting|around|explore|exploring)\s+([A-Z][a-zà-ÿ]+(?:\s[A-Z][a-zà-ÿ]+)?)", text):
            if m.group(1) not in stop:
                destinations.append(m.group(1))
                break

    amount, currency, per_person = _budget(text)
    crew_type, crew_size = _crew(t)
    interests = [k for k, words in INTERESTS.items() if any(re.search(rf"\b{re.escape(w)}", t) for w in words)]
    avoid = []
    for k, words in INTERESTS.items():
        if any(re.search(rf"\b(no|skip|avoid|hate|not into|don'?t like)\s+{re.escape(w)}", t) for w in words):
            avoid.append(k)
            if k in interests:
                interests.remove(k)
    pace = Pace.BALANCED
    if re.search(r"(don'?t|do not|not) want (a |to )?rush|hate rushing|not rushed|no rush|slow|relaxed|laid[- ]back|chill|easy pace|not too packed", t):
        pace = Pace.SLOW
    elif re.search(r"packed|as much as possible|see everything|action[- ]packed|busy", t):
        pace = Pace.PACKED
    dietary = sorted({v for k, v in DIETARY.items() if k in t})
    days = _days(t)
    missing = []
    if not destinations:
        missing.append("destination")
    if days is None:
        missing.append("days")
    return TripIntent(
        raw_text=text, destinations=destinations, origin=norm.get(origin, origin.title()) if origin else None,
        start_date=_start_date(t, today), days=days, budget_amount=amount, budget_currency=currency,
        budget_per_person=per_person, crew_type=crew_type, crew_size=crew_size, interests=interests, avoid=avoid,
        pace=pace, dietary=dietary, missing=missing, confidence=0.6 if missing else 0.75, parser="heuristic",
    )
