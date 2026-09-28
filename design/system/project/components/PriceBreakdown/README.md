# PriceBreakdown

Every fee before payment, plus the price-changed banner that forces reconfirmation.

- **Consumer provides:** `lines[]` (base, taxes, fees, baggage, booking fee), `total`, `currency`, `terms[]` (cancellation/change in plain words), `changedFrom` when revalidation moved the price, `action` label.
- A changed price is never charged silently; the CTA restates the new total.
