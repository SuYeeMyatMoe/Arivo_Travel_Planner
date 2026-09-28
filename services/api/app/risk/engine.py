"""RiskEngine: combines weak signals into ALLOW / CHALLENGE / RATE_LIMIT / MANUAL_REVIEW / BLOCK.

No single weak signal blocks. Card testing (many failed authorisations), booking bursts and high-value payments
without step-up auth are the patterns that matter most for travel commerce.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import StrEnum

from app.domain.models import Money


class Decision(StrEnum):
    ALLOW = "ALLOW"
    CHALLENGE = "CHALLENGE"  # step-up auth (aal2 / passkey) then retry
    RATE_LIMIT = "RATE_LIMIT"
    MANUAL_REVIEW = "MANUAL_REVIEW"
    BLOCK = "BLOCK"


@dataclass
class RiskSignals:
    bookings_last_hour: int = 0
    failed_payments_last_hour: int = 0
    distinct_cards_last_day: int = 0
    accounts_on_device: int = 1
    account_age_days: float = 30.0
    amount_home: float = 0.0
    step_up_done: bool = False
    provider_flag: str | None = None  # e.g. Stripe Radar "elevated"


@dataclass
class RiskResult:
    decision: Decision
    score: int
    reasons: list[str] = field(default_factory=list)


HIGH_VALUE_MYR = 5000.0


def assess(s: RiskSignals) -> RiskResult:
    score, reasons = 0, []
    if s.failed_payments_last_hour >= 3:
        score += 45
        reasons.append("multiple failed payments in the last hour (card-testing pattern)")
    if s.distinct_cards_last_day >= 4:
        score += 30
        reasons.append("many different cards in a day")
    if s.bookings_last_hour >= 6:
        score += 25
        reasons.append("unusual booking velocity")
    if s.accounts_on_device >= 4:
        score += 15
        reasons.append("several accounts on one device")
    if s.account_age_days < 1 and s.amount_home > 2000:
        score += 15
        reasons.append("new account, high value")
    if s.provider_flag == "highest":
        score += 50
        reasons.append("payment provider flagged highest risk")
    elif s.provider_flag == "elevated":
        score += 20
        reasons.append("payment provider flagged elevated risk")
    if score >= 90:
        return RiskResult(Decision.BLOCK, score, reasons)
    if score >= 60:
        return RiskResult(Decision.MANUAL_REVIEW, score, reasons)
    if s.failed_payments_last_hour >= 3 or s.bookings_last_hour >= 6:
        return RiskResult(Decision.RATE_LIMIT, score, reasons)
    if s.amount_home >= HIGH_VALUE_MYR and not s.step_up_done:
        return RiskResult(Decision.CHALLENGE, score, [*reasons, "high-value payment needs step-up authentication"])
    return RiskResult(Decision.ALLOW, score, reasons)


def within(ts: list[datetime], window: timedelta, now: datetime | None = None) -> int:
    now = now or datetime.utcnow()
    return sum(1 for t in ts if now - t <= window)


def amount_in_myr(m: Money) -> float:
    rough = {"MYR": 1.0, "JPY": 0.03, "USD": 4.5, "EUR": 4.9, "SGD": 3.4}
    return m.amount * rough.get(m.currency, 1.0)
