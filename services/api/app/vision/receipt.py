"""Receipt Lens (server half). OCR runs on the phone (ML Kit); only the recognised TEXT comes here.

The parser extracts merchant, date, line items, total and currency and returns a DRAFT. Nothing is written to the
budget until the traveller confirms (then the app calls POST /trips/{id}/expenses). Card digits are masked out.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field
from datetime import datetime

MONEY = r"(?:¥|￥|RM|MYR|JPY|\$|USD|S\$)?\s?-?\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?"
TOTAL_WORDS = r"(?:total|grand total|合計|お会計|jumlah|amount due|total due|税込)"
SKIP_WORDS = re.compile(r"(subtotal|小計|tax|消費税|service|change|お釣り|cash|visa|master|card|tel|phone|receipt|領収|invoice|gst|sst)", re.I)
CATEGORY_HINTS = {"food": r"(izakaya|ramen|sushi|restaurant|cafe|coffee|bar|kitchen|食堂|屋|mamak|kopitiam|bakery)",
                  "transport": r"(taxi|jr|metro|station|grab|parking|fuel|petrol)", "shopping": r"(store|shop|mart|mall|market|donki|uniqlo)"}


@dataclass
class ReceiptLine:
    name: str
    qty: int
    amount: float


@dataclass
class ReceiptDraft:
    merchant: str | None
    date: str | None
    currency: str
    lines: list[ReceiptLine] = field(default_factory=list)
    total: float | None = None
    total_matches_lines: bool = False
    category: str = "food"
    confidence: float = 0.5
    warnings: list[str] = field(default_factory=list)

    def to_json(self) -> dict:
        return asdict(self)


def _amount(s: str) -> float:
    s = re.sub(r"[¥￥RM$A-Z\s]", "", s.replace(",", ""))
    return float(s) if s not in {"", "-", "."} else 0.0


def _currency(text: str, hint: str | None) -> str:
    if re.search(r"[¥￥]|円|JPY", text):
        return "JPY"
    if re.search(r"\bRM\b|MYR|SST", text):
        return "MYR"
    if re.search(r"S\$|SGD", text):
        return "SGD"
    if "$" in text:
        return "USD"
    return hint or "MYR"


def parse_receipt(text: str, currency_hint: str | None = None) -> ReceiptDraft:
    text = re.sub(r"\b(?:\d[ -]?){12,19}\b", "[card]", text)  # never keep card numbers
    lines = [ln.strip() for ln in text.splitlines() if ln.strip()]
    cur = _currency(text, currency_hint)
    merchant = next((ln for ln in lines[:4] if not re.search(r"\d{3,}", ln) and len(ln) >= 3), None)
    date = None
    m = re.search(r"(20\d\d)[/.\-年](\d{1,2})[/.\-月](\d{1,2})", text)
    if m:
        date = f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    else:
        m = re.search(r"(\d{1,2})[/.\-](\d{1,2})[/.\-](20\d\d)", text)
        if m:
            date = f"{m.group(3)}-{int(m.group(2)):02d}-{int(m.group(1)):02d}"
    draft = ReceiptDraft(merchant=merchant, date=date, currency=cur)
    for ln in lines:
        if re.search(TOTAL_WORDS, ln, re.I) and not re.search(r"sub", ln, re.I):
            amts = re.findall(MONEY, ln)
            if amts:
                draft.total = _amount(amts[-1])
            continue
        if SKIP_WORDS.search(ln):
            continue
        m = re.match(rf"^(.+?)\s+(?:[x×]\s?(\d+)\s+)?({MONEY})$", ln)
        if m and re.search(r"[A-Za-z぀-ヿ一-鿿]", m.group(1)):
            name = re.sub(r"\s*\(?(\d+)\)?\s*$", "", m.group(1)).strip()
            qty = int(m.group(2)) if m.group(2) else int(q.group(1)) if (q := re.search(r"\((\d+)\)", m.group(1))) else 1
            amt = _amount(m.group(3))
            if amt > 0:
                draft.lines.append(ReceiptLine(name=name[:60], qty=qty, amount=amt))
    s = round(sum(line.amount for line in draft.lines), 2)
    if draft.total is None and draft.lines:
        draft.total = s
        draft.warnings.append("No total line found — using the sum of items. Check it.")
    draft.total_matches_lines = draft.total is not None and abs(s - draft.total) <= max(1.0, 0.02 * draft.total)
    if draft.total is not None and not draft.total_matches_lines and draft.lines:
        draft.warnings.append("Items don't add up to the total (tax or service may be included).")
    blob = " ".join(lines[:5]).lower()
    draft.category = next((k for k, pat in CATEGORY_HINTS.items() if re.search(pat, blob)), "food")
    draft.confidence = round(min(0.95, 0.35 + 0.2 * bool(draft.merchant) + 0.15 * bool(draft.date) + 0.2 * draft.total_matches_lines
                                 + 0.05 * min(4, len(draft.lines))), 2)
    return draft


def split_items(draft: ReceiptDraft, assignment: dict[int, list[str]], members: list[str]) -> dict[str, float]:
    """Group Receipt Split: line index → member ids sharing it. Unassigned lines split evenly. Returns amount per member."""
    owed = {m: 0.0 for m in members}
    for i, line in enumerate(draft.lines):
        who = assignment.get(i) or members
        for m in who:
            owed[m] += line.amount / len(who)
    if draft.total and draft.lines:  # distribute tax/service difference proportionally
        s = sum(line.amount for line in draft.lines)
        factor = draft.total / s if s else 1
        owed = {m: round(v * factor, 2) for m, v in owed.items()}
    return owed


def _now() -> str:
    return datetime.utcnow().isoformat()
