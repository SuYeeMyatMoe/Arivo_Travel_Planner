import asyncio, time, sys, logging
logging.disable(logging.WARNING)
from datetime import date
from app.places.providers import SeedPlaceProvider
from app.config import REPO_ROOT
from app.planning.intent import parse_heuristic
from app.planning.engine import TripPlanner, PlannerDeps
places = SeedPlaceProvider(REPO_ROOT/"supabase/seed/places")
text = sys.argv[1] if len(sys.argv) > 1 else "I'm visiting Tokyo for five days with three friends. Around RM4,000 each. We love anime, food and photography but hate rushing."
intent = parse_heuristic(text, date(2026,9,24))
planner = TripPlanner(PlannerDeps(places=places, today=lambda: date(2026,9,24)))
t0 = time.time()
trip = asyncio.run(planner.build(intent.model_copy(update={"start_date": date(2026,11,16)}), "u1"))
print("build", round(time.time()-t0,2), "s |", trip.title)
for d in trip.days:
    print(f"\nDay {d.index+1} {d.date:%a} — {d.title}")
    for i in d.items:
        leg = f"{i.leg.mode[:4]} {i.leg.minutes:>2}m" if i.leg else "      -"
        print(f"  {i.start:%H:%M} {i.duration_min:>3}m {i.kind:5} {(i.lane or ''):7} {i.name[:34]:34} [{i.category[:10]}] {leg} {i.cost.display() if i.cost else '-':>7} | {i.reason[:52]}")
print("\n".join(" ! " + w for w in trip.warnings))
