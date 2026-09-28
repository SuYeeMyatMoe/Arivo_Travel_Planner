"""FX via Frankfurter (ECB reference rates). Rates carry their publication date; conversions are shown as estimates."""

from __future__ import annotations

from dataclasses import dataclass

from app.core.resilience import ResilientClient
from app.domain.models import Money


@dataclass
class Rate:
    base: str
    quote: str
    rate: float
    as_of: str
    source: str = "ECB via Frankfurter"


# Last-resort static rates (clearly labelled) so budgets still render offline. Updated manually; never used for payment.
FALLBACK = {("MYR", "JPY"): 34.0, ("MYR", "USD"): 0.22, ("USD", "MYR"): 4.5, ("JPY", "MYR"): 0.029}


class FrankfurterFX:
    def __init__(self, client: ResilientClient | None = None):
        self.client = client or ResilientClient("frankfurter", "https://api.frankfurter.app", timeout_s=6)

    async def rate(self, base: str, quote: str) -> Rate:
        base, quote = base.upper(), quote.upper()
        if base == quote:
            return Rate(base, quote, 1.0, "identity", "identity")
        try:
            data = await self.client.get_json("/latest", {"from": base, "to": quote}, cache_ttl_s=6 * 3600)
            return Rate(base, quote, float(data["rates"][quote]), data["date"])
        except Exception:  # noqa: BLE001 — degrade to labelled fallback rate
            if (base, quote) in FALLBACK:
                return Rate(base, quote, FALLBACK[(base, quote)], "offline-fallback", "Arivo fallback table")
            raise

    async def convert(self, money: Money, quote: str) -> tuple[Money, Rate]:
        r = await self.rate(money.currency, quote)
        return Money.of(money.amount * r.rate, quote), r
