from datetime import date

from app.domain.models import CrewType, Pace
from app.planning.intent import parse_heuristic
from app.planning.rescue_intent import classify
from app.planning.replan import Trigger

TODAY = date(2026, 9, 24)  # a Thursday


def test_tokyo_friends_demo_sentence():
    i = parse_heuristic("5 days in Tokyo with three friends, about RM4,000 each. We love anime, street food and photography but don't want a rushed schedule.", TODAY)
    assert i.destinations == ["Tokyo"]
    assert i.days == 5 and i.crew_type == CrewType.FRIENDS and i.crew_size == 4
    assert i.budget_amount == 4000 and i.budget_currency == "MYR" and i.budget_per_person
    assert {"anime", "food", "photography"} <= set(i.interests)
    assert i.pace == Pace.SLOW and not i.missing


def test_kl_saturday_day_trip():
    i = parse_heuristic("I live in Kuala Lumpur and have one free Saturday. Give me somewhere interesting under RM150.", TODAY)
    assert i.destinations == ["Kuala Lumpur"] and i.days == 1
    assert i.start_date == date(2026, 9, 26) and i.budget_amount == 150


def test_couple_multi_country_and_total_budget():
    i = parse_heuristic("Europe for two weeks. Italy and Switzerland. Couple trip. Scenic places, good food, 12k EUR total.", TODAY)
    assert i.days == 14 and i.crew_type == CrewType.COUPLE and not i.budget_per_person
    assert "Italy" in i.destinations and "Switzerland" in i.destinations


def test_missing_destination_is_the_only_blocking_question():
    i = parse_heuristic("Somewhere relaxing for a week", TODAY)
    assert "destination" in i.missing and i.days == 7


def test_rescue_text_classification():
    assert classify("It started raining")["trigger"] == Trigger.RAIN
    r = classify("We woke up two hours late")
    assert r["trigger"] == Trigger.LATE and r["minutes_late"] == 120
    assert classify("we're exhausted")["trigger"] == Trigger.FATIGUE
    assert classify("we spent too much")["trigger"] == Trigger.BUDGET
    assert classify("skip museums please") == {"confidence": 0.8, "trigger": Trigger.SKIP, "category": "museum"}
    assert classify("hmm")["trigger"] is None
