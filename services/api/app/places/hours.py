"""Minimal OSM `opening_hours` parser for the common forms.

Supported: "24/7", "Mo-Su 09:00-17:00", "10:00-20:00", "Mo-Fr 10:00-20:00; Sa,Su 09:00-21:00",
"Tu-Su 09:30-17:00; Mo off", overnight ranges ("18:00-02:00"), multiple ranges ("11:00-14:00,17:00-22:00").
Anything else returns UNKNOWN — the UI then says "Hours not verified" rather than guessing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, time
from enum import StrEnum

DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
_RANGE = re.compile(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})")


class OpenState(StrEnum):
    OPEN = "open"
    CLOSED = "closed"
    UNKNOWN = "unknown"


@dataclass
class Hours:
    raw: str
    by_day: dict[int, list[tuple[int, int]]] | None  # weekday → [(start_min, end_min)] ; end may exceed 1440

    def state_at(self, when: datetime) -> OpenState:
        if self.by_day is None:
            return OpenState.UNKNOWN
        minute = when.hour * 60 + when.minute
        wd = when.weekday()
        for s, e in self.by_day.get(wd, []):
            if s <= minute < e:
                return OpenState.OPEN
        for s, e in self.by_day.get((wd - 1) % 7, []):  # yesterday's overnight range
            if e > 1440 and minute < e - 1440:
                return OpenState.OPEN
        return OpenState.CLOSED

    def open_between(self, start: datetime, end: datetime) -> OpenState:
        """OPEN only if open for the whole visit window (checked at start and just before end)."""
        a, b = self.state_at(start), self.state_at(end.replace(second=0) if end.minute == 0 else end)
        if OpenState.UNKNOWN in (a, b):
            return OpenState.UNKNOWN
        return OpenState.OPEN if a == b == OpenState.OPEN else OpenState.CLOSED

    def closes_at(self, when: datetime) -> time | None:
        if self.by_day is None:
            return None
        minute = when.hour * 60 + when.minute
        for s, e in self.by_day.get(when.weekday(), []):
            if s <= minute < e:
                e = e % 1440
                return time(e // 60, e % 60)
        return None


def _days(spec: str) -> list[int]:
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-")
            if a not in DAYS or b not in DAYS:
                raise ValueError(part)
            i, j = DAYS.index(a), DAYS.index(b)
            out.extend(range(i, j + 1) if i <= j else list(range(i, 7)) + list(range(0, j + 1)))
        else:
            if part not in DAYS:
                raise ValueError(part)
            out.append(DAYS.index(part))
    return out


def parse(raw: str | None) -> Hours:
    if not raw:
        return Hours(raw or "", None)
    text = raw.strip()
    if text == "24/7":
        return Hours(raw, {d: [(0, 1440)] for d in range(7)})
    try:
        by_day: dict[int, list[tuple[int, int]]] = {}
        for rule in [r.strip() for r in text.split(";") if r.strip()]:
            if "PH" in rule or "SH" in rule or '"' in rule:
                continue  # public holiday / school holiday rules: ignore, not a reason to fail the whole string
            m = re.match(r"^([A-Za-z,\-\s]+?)\s+(.*)$", rule)
            if m and m.group(1).strip()[:2] in DAYS:
                days, times = _days(m.group(1).replace(" ", "")), m.group(2).strip()
            else:
                days, times = list(range(7)), rule
            if times == "off" or times == "closed":
                for d in days:
                    by_day[d] = []
                continue
            ranges = []
            for s_h, s_m, e_h, e_m in _RANGE.findall(times):
                s, e = int(s_h) * 60 + int(s_m), int(e_h) * 60 + int(e_m)
                if e <= s:
                    e += 1440
                ranges.append((s, e))
            if not ranges:
                raise ValueError(times)
            for d in days:
                by_day[d] = ranges
        return Hours(raw, by_day if by_day else None)
    except ValueError:
        return Hours(raw, None)
