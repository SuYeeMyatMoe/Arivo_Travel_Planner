"""End-to-end API: create → read → rescue (propose) → apply; plus BOLA/IDOR and auth checks on every {id} route."""

from tests.conftest import auth


def create(client, payload, user="alice"):
    r = client.post("/v1/trips", json=payload, headers=auth(user))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "ok", body
    return body["trip"]


def test_demo_trip_is_route_aware_and_grounded(client, container, demo_trip_payload):
    trip = create(client, demo_trip_payload)
    assert len(trip["days"]) == 5 and trip["intent"]["crew_size"] == 4
    for day in trip["days"]:
        kinds = [i["kind"] for i in day["items"]]
        assert kinds.count("meal") >= 2, f"day {day['index']} lacks meals: {kinds}"
        assert kinds.count("sight") >= 2
        starts = [i["start"] for i in day["items"]]
        assert starts == sorted(starts)
        for it in day["items"]:
            assert container.places.get(it["place_id"]) is not None  # never an invented POI
            assert it["evidence"], "every stop explains itself"
            if it["leg"]:
                assert it["leg"]["provenance"] == "est"
    assert trip["budget"]["total"]["amount_minor"] == 4000 * 4 * 100


def test_needs_destination_asks_one_question(client):
    r = client.post("/v1/trips", json={"text": "somewhere relaxing for a week"}, headers=auth("alice")).json()
    assert r["status"] == "needs_input" and r["question"]["field"] == "destination"


def test_unsupported_city_is_honest(client):
    r = client.post("/v1/trips", json={"text": "3 days in Lisbon"}, headers=auth("alice")).json()
    assert r["status"] == "error" and r["error"]["code"] == "coverage"
    assert "Tokyo" in r["error"]["supported"]


def test_rescue_rain_keeps_booked_and_needs_confirmation(client, demo_trip_payload):
    trip = create(client, demo_trip_payload)
    day = trip["days"][1]
    r = client.post(f"/v1/trips/{trip['id']}/rescue", json={"text": "It started raining", "day_index": 1,
                                                             "now": f"{day['date']}T12:30:00"}, headers=auth("alice"))
    assert r.status_code == 200, r.text
    change = r.json()["change"]
    assert change["trigger"] == "rain" and change["status"] == "proposed"
    before = client.get(f"/v1/trips/{trip['id']}", headers=auth("alice")).json()
    assert before["version"] == trip["version"], "a proposal must not modify the trip"
    applied = client.post(f"/v1/trips/{trip['id']}/changes/{change['id']}/apply", headers=auth("alice"))
    assert applied.status_code == 200 and applied.json()["trip"]["version"] == trip["version"] + 1
    again = client.post(f"/v1/trips/{trip['id']}/changes/{change['id']}/apply", headers=auth("alice"))
    assert again.status_code == 409  # can't double-apply


def test_stale_proposal_is_rejected(client, demo_trip_payload):
    trip = create(client, demo_trip_payload)
    d = trip["days"][0]
    c1 = client.post(f"/v1/trips/{trip['id']}/rescue", json={"trigger": "fatigue", "day_index": 0, "now": f"{d['date']}T11:00:00"}, headers=auth("alice")).json()["change"]
    c2 = client.post(f"/v1/trips/{trip['id']}/rescue", json={"trigger": "budget", "day_index": 0, "now": f"{d['date']}T11:00:00"}, headers=auth("alice")).json()["change"]
    assert client.post(f"/v1/trips/{trip['id']}/changes/{c1['id']}/apply", headers=auth("alice")).status_code == 200
    assert client.post(f"/v1/trips/{trip['id']}/changes/{c2['id']}/apply", headers=auth("alice")).status_code == 409


def test_bola_other_users_cannot_touch_a_trip(client, demo_trip_payload):
    trip = create(client, demo_trip_payload, user="alice")
    tid = trip["id"]
    for method, path, body in [
        ("get", f"/v1/trips/{tid}", None),
        ("get", f"/v1/trips/{tid}/budget", None),
        ("get", f"/v1/trips/{tid}/changes", None),
        ("post", f"/v1/trips/{tid}/rescue", {"trigger": "rain", "day_index": 0}),
        ("post", f"/v1/trips/{tid}/items/{trip['days'][0]['items'][0]['id']}", {"action": "remove"}),
        ("post", f"/v1/trips/{tid}/expenses", {"amount": 10, "currency": "JPY", "category": "food"}),
        ("get", f"/v1/trips/{tid}/bookings", None),
    ]:
        r = getattr(client, method)(path, json=body, headers=auth("mallory")) if body else getattr(client, method)(path, headers=auth("mallory"))
        assert r.status_code == 404, f"{method} {path} leaked: {r.status_code}"  # same as "doesn't exist"


def test_auth_required_and_dev_auth_off_in_production(client, demo_trip_payload):
    assert client.get("/v1/trips").status_code == 401
    assert client.get("/v1/trips", headers={"Authorization": "Bearer not-a-jwt"}).status_code == 401
    from app.config import Settings

    import pytest

    with pytest.raises(RuntimeError):
        Settings(_env_file=None, env="production", allow_dev_auth=True).assert_safe()


def test_budget_brain_and_expense_after_confirmation(client, demo_trip_payload):
    trip = create(client, demo_trip_payload)
    b = client.get(f"/v1/trips/{trip['id']}/budget", headers=auth("alice")).json()
    assert b["currency"] == "MYR" and b["total"] == 16000 and b["forecast"] > 0
    r = client.post(f"/v1/trips/{trip['id']}/expenses", json={"amount": 4280, "currency": "JPY", "category": "food",
                                                                "merchant": "Izakaya Kura", "source": "receipt_lens"}, headers=auth("alice"))
    assert r.status_code == 200 and r.json()["budget"]["spent"] > 0


def test_add_place_from_explore_is_a_proposal_that_fits_the_route(client, container, demo_trip_payload):
    trip = create(client, demo_trip_payload)
    in_trip = {i["place_id"] for d in trip["days"] for i in d["items"]}
    tower = next(p for p in container.places.search("tokyo", text="Tokyo Skytree", limit=5) if p.id not in in_trip)
    r = client.post(f"/v1/trips/{trip['id']}/add-place", json={"place_id": tower.id}, headers=auth("alice")).json()
    ch = r["change"]
    assert ch["trigger"] == "add_place" and ch["status"] == "proposed"
    assert any("Skytree" in a["name"] for a in ch["added"])
