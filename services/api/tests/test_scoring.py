from datetime import datetime

from app.domain.models import Money, Place, TravelerDNA
from app.places.hours import OpenState, parse
from app.recommendations.scoring import (
    TREND_WEIGHTS, WEIGHTS, ScoreContext, budget_fit, hotel_trip_fit, preference_match, rerank_diverse, score, trend_score,
)


def P(**kw) -> Place:
    base = dict(id="p1", name="Test", category="museum", lat=35.68, lon=139.76, city="tokyo", dna={"culture": 0.9})
    base.update(kw)
    return Place(**base)


def test_recommendation_weights_are_the_spec_baseline():
    assert WEIGHTS == {"preference": 0.30, "schedule": 0.17, "geographic": 0.13, "budget": 0.10, "weather": 0.08, "crew": 0.07, "trend": 0.15}


def test_trend_score_formula_exact():
    assert TREND_WEIGHTS == {"burst": 0.28, "velocity": 0.20, "recency": 0.16, "source_diversity": 0.12, "local_event": 0.10,
                             "local_relevance": 0.08, "engagement_quality": 0.06}
    comps = {"burst": 1, "velocity": 0.5, "recency": 1, "source_diversity": 0.5, "local_event": 1, "local_relevance": 1, "engagement_quality": 0}
    expected = 100 * (0.28 + 0.10 + 0.16 + 0.06 + 0.10 + 0.08 + 0) * 0.9
    assert trend_score(comps, spam_penalty=0.9) == round(expected, 1)
    assert trend_score({k: 5 for k in TREND_WEIGHTS}, 2) == 100.0  # clamped


def test_total_is_weighted_sum_and_closed_sinks():
    dna = TravelerDNA(culture=0.9)
    p = P(tags={"opening_hours": "Mo-Su 10:00-17:00"})
    open_ = score(p, ScoreContext(dna=dna, slot_start=datetime(2026, 11, 16, 11, 0), duration_min=60), "JPY")
    closed = score(p, ScoreContext(dna=dna, slot_start=datetime(2026, 11, 16, 18, 0), duration_min=60), "JPY")
    assert abs(open_.total - sum(WEIGHTS[k] * v for k, v in open_.components.items())) < 1e-3
    assert closed.total < open_.total * 0.3


def test_preference_uses_strong_single_interest():
    anime_fan = TravelerDNA(anime=1.0)
    assert preference_match(anime_fan, P(dna={"anime": 1.0, "shopping": 0.9})) > preference_match(anime_fan, P(dna={"shopping": 0.9}))


def test_budget_fit_penalises_over_budget():
    assert budget_fit(Money.of(100, "MYR"), Money.of(200, "MYR"), 0.5) > budget_fit(Money.of(300, "MYR"), Money.of(200, "MYR"), 0.5)


def test_diversity_rerank_avoids_five_identical_cafes():
    dna = TravelerDNA(food=1)
    items = [score(P(id=f"c{i}", category="cafe", dna={"food": 0.9}), ScoreContext(dna=dna), "JPY") for i in range(5)]
    items.append(score(P(id="m", category="museum", dna={"culture": 0.6}), ScoreContext(dna=dna), "JPY"))
    picked = rerank_diverse(items, 3)
    assert {s.place.category for s in picked} == {"cafe", "museum"}


def test_hours_parser_common_forms():
    h = parse("Mo-Fr 10:00-20:00; Sa,Su 09:00-21:00")
    assert h.state_at(datetime(2026, 11, 16, 9, 30)) == OpenState.CLOSED  # Monday
    assert h.state_at(datetime(2026, 11, 21, 9, 30)) == OpenState.OPEN  # Saturday
    assert parse("18:00-02:00").state_at(datetime(2026, 11, 17, 1, 0)) == OpenState.OPEN  # overnight
    assert parse("sunrise-sunset").by_day is None  # unknown stays unknown


def test_hotel_trip_fit_sentence_counts_real_stops():
    hotel = P(id="h", category="hotel", lat=35.681, lon=139.767)
    near = [P(id=f"s{i}", lat=35.681 + i * 0.002, lon=139.767) for i in range(4)]
    far = [P(id="far", lat=35.9, lon=139.9)]
    fit = hotel_trip_fit(hotel, near + far, [], TravelerDNA(), "JP")
    assert fit.within_25 == 4 and fit.total_stops == 5
    assert fit.sentence.startswith("4 of your 5 planned stops")
