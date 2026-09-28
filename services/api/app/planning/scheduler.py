"""Day scheduling as an orienteering problem with time windows (OR-Tools), plus a deterministic timeline pass.

Inputs per stop: coordinates, visit duration, opening window for that date, priority, and whether it is fixed
(a booking). Objective: minimise travel while dropping as little value as possible; must-dos and bookings carry
penalties large enough that the solver only drops them when the day is physically impossible.
Hard constraints (fixed times, closing times, day end) always override preference.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from ortools.constraint_solver import pywrapcp, routing_enums_pb2

from app.core.geo import estimate_leg
from app.domain.models import Leg, Money

log = logging.getLogger(__name__)

MUST_PENALTY = 10_000_000
FIXED_PENALTY = 50_000_000


@dataclass
class Stop:
    key: str
    lat: float | None  # None for a virtual stop (a meal slot resolved after routing)
    lon: float | None
    duration: int  # minutes
    window: tuple[int, int]  # minutes after day start, [earliest start, latest end]
    priority: float = 0.5  # 0..1
    must: bool = False
    fixed_at: int | None = None  # minutes after day start for bookings
    payload: object = None


@dataclass
class Scheduled:
    stop: Stop
    start: datetime
    leg: Leg | None
    leg_cost: Money | None


@dataclass
class DayPlan:
    scheduled: list[Scheduled]
    dropped: list[tuple[Stop, str]] = field(default_factory=list)
    travel_minutes: int = 0
    solver: str = "ortools"


def _travel(a: Stop, b: Stop, country: str, walking: float) -> int:
    if a.lat is None or b.lat is None:
        return 0
    leg, _ = estimate_leg(a.lat, a.lon, b.lat, b.lon, country, walking)
    return leg.minutes


def solve_order(origin: Stop, stops: list[Stop], day_len: int, country: str, walking: float, buffer_min: int,
                time_limit_s: float = 1.0) -> tuple[list[Stop], list[Stop], str]:
    """Return (ordered visited stops, dropped stops, solver name)."""
    if not stops:
        return [], [], "empty"
    nodes = [origin, *stops]
    n = len(nodes)
    end = n  # dummy end node: routes may finish anywhere
    manager = pywrapcp.RoutingIndexManager(n + 1, 1, [0], [end])
    routing = pywrapcp.RoutingModel(manager)
    travel = [[0] * (n + 1) for _ in range(n + 1)]
    for i in range(n):
        for j in range(n):
            if i != j:
                travel[i][j] = _travel(nodes[i], nodes[j], country, walking)

    def time_cb(fi: int, ti: int) -> int:
        i, j = manager.IndexToNode(fi), manager.IndexToNode(ti)
        service = nodes[i].duration + (buffer_min if i != 0 else 0) if i < n else 0
        return service + (travel[i][j] if i < n and j < n else 0)

    def cost_cb(fi: int, ti: int) -> int:
        i, j = manager.IndexToNode(fi), manager.IndexToNode(ti)
        return travel[i][j] if i < n and j < n else 0

    t_idx = routing.RegisterTransitCallback(time_cb)
    c_idx = routing.RegisterTransitCallback(cost_cb)
    routing.SetArcCostEvaluatorOfAllVehicles(c_idx)
    routing.AddDimension(t_idx, 240, day_len, True, "Time")  # waiting allowed (slack) up to 4 h
    dim = routing.GetDimensionOrDie("Time")
    dim.SetSlackCostCoefficientForAllVehicles(1)  # idle waiting costs something: fill the morning instead of starting at lunch
    for node in range(1, n):
        s = nodes[node]
        idx = manager.NodeToIndex(node)
        if s.fixed_at is not None:
            dim.CumulVar(idx).SetRange(s.fixed_at, s.fixed_at)
        else:
            lo, hi = s.window
            hi = min(hi - s.duration, day_len - s.duration)
            if hi < lo:  # cannot fit at all today → solver must drop it
                hi = lo
            dim.CumulVar(idx).SetRange(max(0, lo), max(0, hi))
        penalty = FIXED_PENALTY if s.fixed_at is not None else MUST_PENALTY if s.must else int(400 + 1600 * s.priority)
        routing.AddDisjunction([idx], penalty)
    params = pywrapcp.DefaultRoutingSearchParameters()
    params.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
    if len(stops) <= 12:
        # a day has a handful of stops: greedy descent reaches a local optimum in milliseconds
        params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GREEDY_DESCENT
    else:
        params.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
    params.time_limit.FromMilliseconds(int(time_limit_s * 1000))
    solution = routing.SolveWithParameters(params)
    if not solution:
        log.warning("OR-Tools found no solution; using greedy order")
        return _greedy(origin, stops, country, walking), [], "greedy"
    ordered, index = [], routing.Start(0)
    while not routing.IsEnd(index):
        node = manager.IndexToNode(index)
        if 0 < node < n:
            ordered.append(nodes[node])
        index = solution.Value(routing.NextVar(index))
    visited = {id(s) for s in ordered}
    return ordered, [s for s in stops if id(s) not in visited], "ortools"


def _greedy(origin: Stop, stops: list[Stop], country: str, walking: float) -> list[Stop]:
    fixed = sorted([s for s in stops if s.fixed_at is not None], key=lambda s: s.fixed_at)
    rest = [s for s in stops if s.fixed_at is None]
    order, cur = [], origin
    while rest:
        nxt = min(rest, key=lambda s: _travel(cur, s, country, walking) if s.lat is not None else 0)
        order.append(nxt)
        rest.remove(nxt)
        if nxt.lat is not None:
            cur = nxt
    for f in fixed:  # insert fixed stops by time; timeline pass enforces the rest
        order.append(f)
    return order


def timeline(origin: Stop, ordered: list[Stop], day_start: datetime, day_len: int, country: str, walking: float,
             buffer_min: int) -> DayPlan:
    """Assign real clock times in order, honouring windows and fixed bookings; drop what no longer fits."""
    # fixed stops anchor the day: sort all by (fixed time if any, else current order position)
    plan = DayPlan(scheduled=[])
    cursor = 0
    prev = origin
    fixed_times = sorted([s.fixed_at for s in ordered if s.fixed_at is not None])
    for s in ordered:
        leg_min, leg, cost = 0, None, None
        if prev.lat is not None and s.lat is not None:
            leg, cost = estimate_leg(prev.lat, prev.lon, s.lat, s.lon, country, walking)
            leg_min = leg.minutes
        arrive = cursor + leg_min + (buffer_min if plan.scheduled else 0)
        if s.fixed_at is not None:
            if arrive > s.fixed_at + 10:
                plan.dropped.append((s, "booked time can't be reached after earlier stops"))  # surfaced, never hidden
                continue
            start = s.fixed_at
        else:
            start = max(arrive, s.window[0])
            next_fixed = next((f for f in fixed_times if f > cursor), None)
            if next_fixed is not None and start + s.duration > next_fixed - 10:
                plan.dropped.append((s, "would collide with a booking"))
                continue
            soft = 45 if s.key.startswith("meal") else 0  # meals flex a little; people still eat when a morning runs long
            if start + s.duration > min(s.window[1] + soft, day_len):
                plan.dropped.append((s, "closes before a full visit" if s.window[1] < day_len else "day is full"))
                continue
        plan.scheduled.append(Scheduled(stop=s, start=day_start + timedelta(minutes=start), leg=leg, leg_cost=cost))
        plan.travel_minutes += leg_min
        cursor = start + s.duration
        if s.lat is not None:
            prev = s
    return plan


def schedule_day(origin: Stop, stops: list[Stop], day_start: datetime, day_len: int, country: str, walking: float,
                 buffer_min: int) -> DayPlan:
    ordered, dropped, solver = solve_order(origin, stops, day_len, country, walking, buffer_min)
    plan = timeline(origin, ordered, day_start, day_len, country, walking, buffer_min)
    plan.dropped = [(s, "not enough time today") for s in dropped] + plan.dropped
    plan.solver = solver
    return plan
