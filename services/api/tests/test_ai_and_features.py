"""Guide agent (commands + fake-LLM tool loop), plan graph with a fake model, Pulse analysis, Crew, Lens, social URLs."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.ai.router import IntentAI
from app.domain.models import Place
from app.pulse.engine import Signal, analyse
from app.pulse.social import UnsupportedUrl, match_places, validate
from app.vision.receipt import parse_receipt, split_items
from tests.conftest import DEMO, TODAY, auth, make_settings


def trip_for(client, user="alice"):
    return client.post("/v1/trips", json={"text": DEMO, "quick": {"start_date": "2026-11-16"}}, headers=auth(user)).json()["trip"]


# ------------------------------------------------------------------------------------------------ guide (no AI)
def test_guide_commands_work_offline(client):
    trip = trip_for(client)
    now = f"{trip['days'][0]['date']}T09:00:00"
    nxt = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "What's next?", "now": now}, headers=auth("alice")).json()
    assert nxt["mode"] == "commands" and nxt["reply"].startswith("Next is") and nxt["cards"][0]["type"] == "stop"
    spent = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "How much have we spent?", "now": now}, headers=auth("alice")).json()
    assert "spent" in spent["reply"] and spent["cards"][0]["type"] == "budget"
    move = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "Move dinner later", "now": now}, headers=auth("alice")).json()
    assert move["proposals"] and move["proposals"][0]["kind"] == "move_item" and "Confirm" in move["reply"]
    rescue = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "It started raining", "now": f"{trip['days'][0]['date']}T12:30:00"}, headers=auth("alice")).json()
    assert rescue["proposals"][0]["kind"] == "trip_change"
    # proposals never apply themselves
    t = client.get(f"/v1/trips/{trip['id']}", headers=auth("alice")).json()
    assert t["version"] == trip["version"]


def test_guide_viewer_cannot_propose_or_book(client, container):
    import asyncio

    trip = trip_for(client)
    from app.domain.models import CrewMember, CrewRole

    stored = asyncio.run(container.store.get_trip(trip["id"]))
    stored.crew.append(CrewMember(user_id="vic", display_name="Vic", role=CrewRole.VIEWER))
    asyncio.run(container.store.put_trip(stored))
    r = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "Move dinner later"}, headers=auth("vic")).json()
    assert not r["proposals"] and "Not permitted" in r["reply"]


# ------------------------------------------------------------------------------------------------ guide (fake LLM)
class FakeMessages:
    """Scripted Claude: first asks for a tool, then answers. Also serves messages.parse for the plan graph."""

    def __init__(self):
        self.calls = []

    async def create(self, **kw):
        self.calls.append(kw)
        tool_names = {t["name"] for t in kw["tools"]}
        assert not tool_names & {"charge_card", "confirm_booking", "pay"}, "no payment tool is ever exposed"
        if len(self.calls) == 1:
            return SimpleNamespace(stop_reason="tool_use", usage=SimpleNamespace(input_tokens=10, output_tokens=5),
                                   content=[_Block(type="tool_use", id="tu_1", name="whats_next", input={})])
        last = kw["messages"][-1]["content"][0]
        assert last["type"] == "tool_result" and "next" in last["content"]
        return SimpleNamespace(stop_reason="end_turn", usage=SimpleNamespace(input_tokens=10, output_tokens=5),
                               content=[_Block(type="text", text="Next up is your first stop — about a 10 minute walk.")])

    async def parse(self, **kw):
        return SimpleNamespace(stop_reason="end_turn", usage=SimpleNamespace(input_tokens=1, output_tokens=1, cache_read_input_tokens=0),
                               parsed_output=kw["output_format"](**{
                                   "destinations": ["Tokyo"], "origin": "Kuala Lumpur", "start_date": None, "days": 5, "budget_amount": 4000,
                                   "budget_currency": "MYR", "budget_per_person": True, "crew_type": "friends", "crew_size": 4,
                                   "interests": ["anime", "food", "photography"], "avoid": [], "pace": "slow", "dietary": [],
                                   "must_do": ["Shibuya Sky"]}) if kw["output_format"] is IntentAI else None)


class _Block(SimpleNamespace):
    def model_dump(self, exclude_none=False):
        return {k: v for k, v in self.__dict__.items() if not (exclude_none and v is None)}


def test_guide_tool_loop_with_fake_claude(settings):
    from fastapi.testclient import TestClient

    from app.container import build_container
    from app.main import create_app

    fake = SimpleNamespace(messages=FakeMessages())
    s = make_settings()
    c = build_container(s, anthropic_client=fake, weather=None, fx=None, today=lambda: TODAY)
    cl = TestClient(create_app(s, c))
    trip = cl.post("/v1/trips", json={"text": DEMO + " Must do Shibuya Sky.", "quick": {"start_date": "2026-11-16"}}, headers=auth("alice")).json()["trip"]
    assert trip["intent"]["parser"] == "ai" and "Shibuya Sky" in trip["intent"]["must_do"]
    assert any("Shibuya Sky" in i["name"] for d in trip["days"] for i in d["items"]), "must-do honoured"
    r = cl.post(f"/v1/trips/{trip['id']}/guide", json={"text": "what should we do next", "now": f"{trip['days'][0]['date']}T09:00:00"}, headers=auth("alice")).json()
    assert r["mode"] == "ai" and "walk" in r["reply"]
    assert all(rec.ok for rec in c.router.calls if rec.task == "guide")


def test_card_numbers_are_refused_before_any_model_call(client):
    trip = trip_for(client)
    r = client.post(f"/v1/trips/{trip['id']}/guide", json={"text": "book it with 4242 4242 4242 4242"}, headers=auth("alice"))
    assert r.status_code in (200, 422)
    if r.status_code == 422:
        assert r.json()["detail"]["code"] == "pii_policy"


# ------------------------------------------------------------------------------------------------ pulse
def P(**kw):
    base = dict(id="osm:1", name="Tokyo Tower", category="attraction", lat=35.6586, lon=139.7454, city="tokyo", wikipedia_en="Tokyo Tower")
    base.update(kw)
    return Place(**base)


def test_pulse_needs_evidence_and_uses_exact_formula():
    assert analyse(P(), "Tokyo", []) is None  # no signals → no badge, no invented trend
    now = datetime(2026, 9, 24, tzinfo=timezone.utc)
    series = [100] * 49 + [110, 120, 130, 150, 170, 190, 210, 230, 250, 260, 270, 280, 290]
    wiki = Signal("wikipedia", "osm:1", now, series=series, url="https://pageviews.example")
    arts = [{"title": f"Story {i} about Tokyo Tower", "url": f"https://n{i}.example/a", "domain": f"n{i}.example",
             "published": (now - timedelta(days=1)).strftime("%Y%m%dT%H%M%SZ")} for i in range(6)]
    arts += [dict(arts[0])] * 4  # syndicated duplicates
    news = Signal("gdelt", "osm:1", now, items=arts)
    snap = analyse(P(), "Tokyo", [wiki, news], now=now)
    assert snap and snap.label == "Rising this week"
    from app.recommendations.scoring import trend_score

    assert snap.score == trend_score(snap.components, snap.spam_penalty)
    assert snap.spam_penalty < 1.0, "duplicates are penalised"
    assert any("independent sources" in e.text for e in snap.evidence) and all(e.provenance == "live" for e in snap.evidence)


# ------------------------------------------------------------------------------------------------ crew
def test_crew_join_votes_balance_and_nightlife_proposal(client):
    trip = trip_for(client)
    inv = client.post(f"/v1/trips/{trip['id']}/invites", headers=auth("alice")).json()
    for u in ("mia", "sam", "jo"):
        assert client.post(f"/v1/invites/{inv['token']}/join", headers=auth(u)).status_code == 200
    client.post(f"/v1/trips/{trip['id']}/crew/prefs", json={"votes": {"nightlife": "love", "culture": "skip"}}, headers=auth("jo"))
    client.post(f"/v1/trips/{trip['id']}/crew/prefs", json={"votes": {"nightlife": "skip", "culture": "love"}, "private": True}, headers=auth("mia"))
    crew = client.get(f"/v1/trips/{trip['id']}/crew", headers=auth("sam")).json()
    assert len(crew["members"]) == 4 and {m["color_index"] for m in crew["members"]} == {0, 1, 2, 3}
    mia = next(m for m in crew["members"] if m["user_id"] == "mia")
    assert mia["top"] == [], "private preferences stay private"
    assert any(c["dimension"] == "nightlife" for c in crew["conflicts"])
    assert all(sum(m["share"] for m in d["members"]) in range(98, 103) for d in crew["balance"])
    sug = client.post(f"/v1/trips/{trip['id']}/crew/suggestions", json={"text": "Izakaya night!", "kind": "nightlife", "day_index": 1}, headers=auth("jo")).json()
    client.post(f"/v1/trips/{trip['id']}/crew/suggestions/{sug['id']}/vote", json={"value": 1}, headers=auth("sam"))
    out = client.post(f"/v1/trips/{trip['id']}/crew/suggestions/{sug['id']}/vote", json={"value": 1}, headers=auth("alice")).json()
    assert out["majority"] and out["proposal"]["trigger"] == "nightlife" and out["proposal"]["status"] == "proposed"
    assert client.post(f"/v1/invites/{inv['token']}/join", headers=auth("eve")).status_code == 410  # max uses reached


def test_crew_prefs_is_a_partial_update(client):
    trip = trip_for(client)
    url = f"/v1/trips/{trip['id']}/crew/prefs"
    client.post(url, json={"private": True, "dietary": ["halal"]}, headers=auth("alice"))
    client.post(url, json={"votes": {"food": "love"}}, headers=auth("alice"))  # taste only: privacy and diet must survive
    me = next(m for m in client.get(f"/v1/trips/{trip['id']}", headers=auth("alice")).json()["crew"] if m["user_id"] == "alice")
    assert me["private_prefs"] is True and me["dietary"] == ["halal"] and me["dna"]["food"] == pytest.approx(0.95)


def test_place_names_are_traveller_readable():
    from app.places.providers import area_label, is_generic_name
    assert area_label("Atago 1-chome") == "Atago" and area_label("Roppongi 6") == "Roppongi" and area_label("Nishi-Shinjuku") == "Nishi-Shinjuku"
    assert is_generic_name("Main Shrine") and is_generic_name("Honden") and not is_generic_name("Meiji Jingu Main Shrine")


# ------------------------------------------------------------------------------------------------ lens
RECEIPT = """Izakaya Kura
2026/11/17 19:42
Yakitori (2)   ¥1,200
Edamame   ¥480
Sashimi Platter   ¥2,300
Green Tea   ¥300
Total   ¥4,280
VISA 4242 4242 4242 4242"""


def test_receipt_lens_parses_and_never_keeps_card_digits():
    d = parse_receipt(RECEIPT)
    assert d.merchant == "Izakaya Kura" and d.date == "2026-11-17" and d.currency == "JPY"
    assert [line.amount for line in d.lines] == [1200, 480, 2300, 300] and d.lines[0].qty == 2
    assert d.total == 4280 and d.total_matches_lines and d.confidence >= 0.8
    assert "4242" not in str(d.to_json())
    owed = split_items(d, {0: ["a"], 2: ["b", "c"]}, ["a", "b", "c"])
    assert round(sum(owed.values())) == 4280 and owed["a"] > owed["c"]


def test_receipt_endpoint_is_draft_only(client):
    trip = trip_for(client)
    r = client.post("/v1/lens/receipt", json={"text": RECEIPT}, headers=auth("alice")).json()
    assert r["requires_confirmation"]
    assert client.get(f"/v1/trips/{trip['id']}/budget", headers=auth("alice")).json()["spent"] == 0


def test_landmark_lens_from_gps(client):
    r = client.post("/v1/lens/landmark", json={"lat": 35.71476, "lon": 139.79665, "labels": ["temple"]}, headers=auth("alice")).json()
    assert r["status"] in {"ok", "uncertain"} and r["place"]["name"]


# ------------------------------------------------------------------------------------------------ social URL → trip
def test_social_url_validation_is_ssrf_safe():
    for bad in ["http://youtube.com/watch?v=x", "https://169.254.169.254/latest", "https://evil.example/oembed",
                "https://user:pw@youtube.com/x", "https://youtube.com:8443/x", "file:///etc/passwd"]:
        with pytest.raises(UnsupportedUrl):
            validate(bad)
    assert validate("https://www.youtube.com/watch?v=abc")[0] == "www.youtube.com"


def test_social_title_resolution_is_honest():
    places = [P(), P(id="osm:2", name="Shibuya Sky", iconic=0.6), P(id="osm:3", name="Main Shrine")]
    hits = match_places("Sunset at SHIBUYA SKY 🌆 Tokyo vlog", places)
    assert hits[0][0].name == "Shibuya Sky"
    assert not match_places("my favourite main shrine", places), "generic names never match"
