"""Budget Brain: total · spent · reserved · forecast · remaining, in the traveller's home currency.

Forecast = planned itinerary costs (EST) + reserved bookings (LIVE) + spent expenses (YOU) + unbooked planned lines.
When the forecast exceeds the total, it proposes concrete substitutions with their savings.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from app.domain.models import Money, Provenance, Trip
from app.fx.providers import FrankfurterFX, Rate


@dataclass
class Expense:
    id: str
    trip_id: str
    amount: Money
    category: str  # food | transport | activities | shopping | accommodation | flights | other
    merchant: str | None
    note: str | None
    source: str  # manual | receipt_lens | booking
    created_by: str
    created_at: datetime
    confirmed: bool = True  # receipt lens rows are created only after the traveller confirms


@dataclass
class BudgetView:
    currency: str
    total: float
    spent: float
    reserved: float
    forecast: float
    remaining: float
    state: str  # ok | tight | over | no_budget
    lines: list[dict]
    fx: dict | None
    suggestions: list[dict] = field(default_factory=list)
    provenance: dict = field(default_factory=lambda: {"total": Provenance.YOU, "forecast": Provenance.EST, "spent": Provenance.YOU})


async def budget_view(trip: Trip, expenses: list[Expense], reservations: list[tuple[str, Money]], fx: FrankfurterFX | None) -> BudgetView:
    home = trip.home_currency
    rate: Rate | None = None
    if trip.currency != home and fx:
        rate = await fx.rate(trip.currency, home)
    conv = (lambda m: m.amount * rate.rate) if rate else (lambda m: m.amount)
    crew = trip.intent.crew_size
    planned_local = {"food": 0.0, "activities": 0.0, "transport": 0.0}
    for it in trip.all_items():
        if it.locked:  # booked items are counted via reservations
            continue
        if it.cost:
            planned_local["food" if it.kind in {"meal", "night"} else "activities"] += conv(it.cost) * crew
        if it.leg_cost:
            planned_local["transport"] += conv(it.leg_cost) * crew
    spent_by: dict[str, float] = {}
    for e in expenses:
        if not e.confirmed:
            continue
        amt = e.amount.amount if e.amount.currency == home else (conv(e.amount) if e.amount.currency == trip.currency else e.amount.amount)
        spent_by[e.category] = spent_by.get(e.category, 0.0) + amt
    reserved_by: dict[str, float] = {}
    for cat, m in reservations:
        amt = m.amount if m.currency == home else conv(m)
        reserved_by[cat] = reserved_by.get(cat, 0.0) + amt
    lines, forecast = [], 0.0
    budget_lines = {b.category: b for b in trip.budget.lines} if trip.budget else {}
    for cat in ["flights", "accommodation", "food", "transport", "activities", "shopping", "buffer"]:
        planned_line = budget_lines[cat].planned.amount if cat in budget_lines else 0.0
        itinerary = planned_local.get(cat, 0.0)
        reserved = reserved_by.get(cat, 0.0)
        spent = spent_by.get(cat, 0.0)
        # unbooked flights/stays: use the plan line until a real offer is reserved
        line_forecast = max(itinerary, 0.0) + reserved + spent if cat in planned_local else max(planned_line if not reserved else 0.0, 0.0) + reserved + spent
        if cat == "buffer":
            line_forecast = 0.0
        forecast += line_forecast
        lines.append({"category": cat, "planned": round(planned_line, 2), "itinerary": round(itinerary, 2), "reserved": round(reserved, 2),
                      "spent": round(spent, 2), "forecast": round(line_forecast, 2),
                      "provenance": Provenance.LIVE if reserved else Provenance.EST})
    total = trip.budget.total.amount if trip.budget else 0.0
    spent_total = sum(spent_by.values())
    reserved_total = sum(reserved_by.values())
    state = "no_budget" if not total else "over" if forecast > total else "tight" if forecast > total * 0.92 else "ok"
    view = BudgetView(currency=home, total=round(total, 2), spent=round(spent_total, 2), reserved=round(reserved_total, 2),
                      forecast=round(forecast, 2), remaining=round(total - spent_total - reserved_total, 2), state=state, lines=lines,
                      fx={"base": rate.base, "quote": rate.quote, "rate": rate.rate, "as_of": rate.as_of, "source": rate.source} if rate else None)
    if state in {"over", "tight"}:
        view.suggestions = savings(trip, conv)
    return view


def savings(trip: Trip, conv) -> list[dict]:
    """Largest planned paid items first; the Replanner's BUDGET trigger turns an accepted suggestion into a real change."""
    crew = trip.intent.crew_size
    paid = sorted((i for i in trip.all_items() if i.cost and i.cost.amount_minor > 0 and not i.locked and i.kind == "sight"),
                  key=lambda i: -i.cost.amount_minor)
    out = []
    for it in paid[:3]:
        day = next(d.index for d in trip.days if it in d.items)
        out.append({"day_index": day, "item_id": it.id, "name": it.name, "saves": round(conv(it.cost) * crew, 2),
                    "action": "replan", "trigger": "budget", "text": f"Swap {it.name} for a free stop nearby (saves ≈{round(conv(it.cost) * crew)} {trip.home_currency})"})
    return out
