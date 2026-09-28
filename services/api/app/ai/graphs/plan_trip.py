"""plan_trip LangGraph: sentence → Living Trip.

  parse_intent ─▶ need_more? ─yes─▶ ask (END with a question)
                     │no
                     ▼
                plan (deterministic engine) ─▶ plan_b (rain/fatigue variants) ─▶ narrate (LLM, optional) ─▶ validate ─▶ END

The LLM extracts and narrates; routing, scheduling, prices and hours come from code and providers.
"""

from __future__ import annotations

import logging
from datetime import date
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.ai.router import INTENT_SYSTEM, ChangeNarration, DayNarration, IntentAI, ModelRouter
from app.domain.models import CrewType, Pace, Trip, TripIntent
from app.planning.engine import PlanningError, TripPlanner
from app.planning.intent import parse_heuristic
from app.planning.replan import Replanner

log = logging.getLogger(__name__)


class PlanState(TypedDict, total=False):
    text: str
    today: date
    overrides: dict[str, Any]  # quick controls from the UI (dates, budget, crew) — the traveller's own input wins
    owner_id: str
    iconic_local: float
    intent: TripIntent
    question: dict | None
    trip: Trip | None
    error: dict | None
    trace: list[str]


def merge_intent(rule: TripIntent, ai: IntentAI | None, overrides: dict[str, Any]) -> TripIntent:
    data = rule.model_dump()
    if ai:
        a = ai.model_dump()
        for k in ("destinations", "interests", "dietary", "must_do", "avoid"):
            merged = list(dict.fromkeys([*(data.get(k) or []), *(a.get(k) or [])]))
            data[k] = merged
        for k in ("origin", "start_date", "days", "budget_amount", "budget_currency"):
            if data.get(k) in (None, "") and a.get(k) not in (None, ""):
                data[k] = a[k]
        if rule.crew_type == CrewType.SOLO and a["crew_type"] != "solo":
            data["crew_type"], data["crew_size"] = a["crew_type"], max(a["crew_size"], 2)
        if rule.pace == Pace.BALANCED:
            data["pace"] = a["pace"]
        data["parser"] = "ai"
        data["confidence"] = 0.85
    for k, v in (overrides or {}).items():
        if v is not None and k in data:
            data[k] = v
    data["missing"] = [m for m in ("destination", "days") if (m == "destination" and not data["destinations"]) or (m == "days" and not data["days"])]
    return TripIntent(**data)


def build_plan_graph(planner: TripPlanner, router: ModelRouter, replanner: Replanner):
    async def parse_intent(state: PlanState) -> PlanState:
        rule = parse_heuristic(state["text"], state.get("today"))
        ai, _ = await router.structured("extract", INTENT_SYSTEM, state["text"], IntentAI)
        intent = merge_intent(rule, ai, state.get("overrides") or {})
        return {"intent": intent, "trace": [*state.get("trace", []), f"intent:{intent.parser}"]}

    def need_more(state: PlanState) -> str:
        return "ask" if "destination" in state["intent"].missing else "plan"

    async def ask(state: PlanState) -> PlanState:
        # Only ask when the answer materially changes the plan. Everything else gets a sensible default + a note.
        return {"question": {"field": "destination", "text": "Where should we go? A city, a country, or 'somewhere near KL'."}}

    async def plan(state: PlanState) -> PlanState:
        try:
            trip = await planner.build(state["intent"], state["owner_id"], iconic_local=state.get("iconic_local", 0.0))
            return {"trip": trip, "trace": [*state.get("trace", []), "plan:ok"]}
        except PlanningError as e:
            return {"error": {"code": e.code, "message": str(e), **e.detail}, "trace": [*state.get("trace", []), f"plan:{e.code}"]}

    async def plan_b(state: PlanState) -> PlanState:
        trip = state["trip"]
        for i, _ in enumerate(trip.days):
            try:
                trip.days[i].plan_b = replanner.plan_b(trip, i)
            except Exception as e:  # noqa: BLE001 — Plan B is best-effort; Rescue can still run live
                log.warning("plan b day %s failed: %s", i, e)
        return {"trip": trip}

    async def narrate(state: PlanState) -> PlanState:
        trip = state["trip"]
        if not router.available:
            return {"trace": [*state.get("trace", []), "narrate:skipped"]}
        for day in trip.days[:6]:
            stops = ", ".join(f"{i.start:%H:%M} {i.name} ({i.category})" for i in day.items)
            prompt = (f"Day {day.index + 1} in {day.zone} ({day.title}). Stops: {stops}. Traveller interests: "
                      f"{', '.join(trip.intent.interests) or 'general'}; pace {trip.intent.pace}.")
            out, _ = await router.structured("plan", NARRATE_SYSTEM, prompt, DayNarration, max_tokens=400)
            if out and 3 <= len(out.title) <= 48:
                day.title = out.title
        return {"trip": trip, "trace": [*state.get("trace", []), "narrate:ok"]}

    async def validate(state: PlanState) -> PlanState:
        trip = state["trip"]
        ids = set()
        for d in trip.days:
            for it in d.items:
                assert -90 <= it.lat <= 90 and -180 <= it.lon <= 180, "invalid coordinate"
                assert it.duration_min > 0, "invalid duration"
                assert it.id not in ids, "duplicate item id"
                ids.add(it.id)
                if it.kind != "transfer":
                    assert planner.deps.places.get(it.place_id) is not None, f"unknown place {it.place_id}"  # no invented POIs
        return {"trace": [*state.get("trace", []), "validate:ok"]}

    def after_plan(state: PlanState) -> str:
        return "end" if state.get("error") else "plan_b"

    g = StateGraph(PlanState)
    g.add_node("parse_intent", parse_intent)
    g.add_node("ask", ask)
    g.add_node("plan", plan)
    g.add_node("plan_b", plan_b)
    g.add_node("narrate", narrate)
    g.add_node("validate", validate)
    g.add_edge(START, "parse_intent")
    g.add_conditional_edges("parse_intent", need_more, {"ask": "ask", "plan": "plan"})
    g.add_edge("ask", END)
    g.add_conditional_edges("plan", after_plan, {"end": END, "plan_b": "plan_b"})
    g.add_edge("plan_b", "narrate")
    g.add_edge("narrate", "validate")
    g.add_edge("validate", END)
    return g.compile()


NARRATE_SYSTEM = """You title one day of a trip for Arivo. Return a short title (max 40 chars) naming the area or the day's
theme, e.g. "Asakusa & Ueno" or "Shibuya / Harajuku", and a one-sentence summary. Use only the stops given; do not add
places, prices or opening hours."""

__all__ = ["build_plan_graph", "merge_intent", "PlanState", "ChangeNarration"]
