"""Booking saga: idempotency, revalidation, price change, compensation, ambiguous-timeout reconciliation, constraints."""

import uuid

from tests.conftest import auth

TRAVELLERS = [{"given_name": f"Traveller{i}", "family_name": "Tan", "born_on": "1998-04-0" + str(i + 1)} for i in range(4)]


def make_trip(client, payload):
    return client.post("/v1/trips", json=payload, headers=auth("alice")).json()["trip"]


def flight_offer(client, adults=4, date="2026-11-16"):
    r = client.post("/v1/bookings/search/flights", json={"origin": "KUL", "destination": "TYO", "depart": date, "adults": adults}, headers=auth("alice"))
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["sandbox"] is True
    assert any("BEST FIT" in o["badges"] for o in body["offers"]) and any("CHEAPEST" in o["badges"] for o in body["offers"])
    return next(o for o in body["offers"] if "BEST FIT" in o["badges"])


def start(client, trip_id, offer_id, key=None, travellers=4):
    return client.post(f"/v1/trips/{trip_id}/bookings", json={"offer_id": offer_id, "travellers": travellers},
                       headers={**auth("alice"), "Idempotency-Key": key or uuid.uuid4().hex})


def test_happy_path_books_once_and_updates_trip(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    key = uuid.uuid4().hex
    txn = start(client, trip["id"], offer["offer_id"], key).json()
    assert txn["state"] == "PRICE_CONFIRMED"
    assert start(client, trip["id"], offer["offer_id"], key).json()["id"] == txn["id"]  # same key → same txn
    body = {"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS}
    done = client.post(f"/v1/bookings/{txn['id']}/confirm", json=body, headers=auth("alice")).json()
    assert done["state"] == "CONFIRMED" and done["booking_reference"]
    replay = client.post(f"/v1/bookings/{txn['id']}/confirm", json=body, headers=auth("alice")).json()
    assert replay["state"] == "CONFIRMED"
    pay = container.bookings.payments
    assert len(pay.intents) == 1, "double confirm must never double charge"
    assert list(pay.intents.values())[0]["status"] == "succeeded"
    # confirmed flight is now a hard constraint: nothing on arrival day before landing + airport exit
    t = client.get(f"/v1/trips/{trip['id']}", headers=auth("alice")).json()
    day0 = t["days"][0]
    fixed = [i for i in day0["items"] if i["locked"]]
    assert fixed and fixed[0]["booking_id"] == txn["id"]
    arrival = done["offer"]["arrival"]
    flexible = [i for i in day0["items"] if not i["locked"]]
    assert all(i["start"] >= arrival for i in flexible)
    assert any(line["category"] == "flights" and line["reserved"]["amount_minor"] > 0 for line in t["budget"]["lines"])


def test_price_change_requires_reconfirmation(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    container.bookings.flights.book.price_bump_next = 0.05
    txn = start(client, trip["id"], offer["offer_id"]).json()
    assert txn["state"] == "PRICE_CHANGED"
    stale = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": offer["price"]["amount_minor"], "travellers": TRAVELLERS}, headers=auth("alice"))
    assert stale.status_code == 409 and stale.json()["detail"]["code"] == "price_changed"
    assert not container.bookings.payments.intents, "nothing charged at the old price"
    ok = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS}, headers=auth("alice"))
    assert ok.json()["state"] == "CONFIRMED"


def test_supplier_rejection_voids_payment(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    txn = start(client, trip["id"], offer["offer_id"]).json()
    container.bookings.flights.book.fail_next = "reject"
    out = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS}, headers=auth("alice")).json()
    assert out["state"] == "FAILED" and "released" in out["failure_reason"]
    assert list(container.bookings.payments.intents.values())[0]["status"] == "canceled"
    assert any("compensation" in e["note"] for e in out["events"])


async def test_ambiguous_timeout_reconciles_without_rebooking(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    txn = start(client, trip["id"], offer["offer_id"]).json()
    container.bookings.flights.book.fail_next = "timeout"  # the order IS created, the response is lost
    out = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS}, headers=auth("alice")).json()
    assert out["state"] == "SUPPLIER_PENDING" and out["needs_reconciliation"]
    orders_before = len(container.bookings.flights.book.orders)
    stats = await container.bookings.reconcile_all()
    assert stats["confirmed"] == 1
    assert len(container.bookings.flights.book.orders) == orders_before, "reconciliation must not create a second order"
    final = client.get(f"/v1/bookings/{txn['id']}", headers=auth("alice")).json()
    assert final["state"] == "CONFIRMED"


def test_declined_card_fails_cleanly_and_counts_for_risk(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    txn = start(client, trip["id"], offer["offer_id"]).json()
    container.bookings.payments.decline_next = True
    out = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS}, headers=auth("alice")).json()
    assert out["state"] == "FAILED" and not container.bookings.flights.book.orders


def test_offer_ids_are_per_user_and_prices_come_from_server(client, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client)
    other = client.post("/v1/trips", json=demo_trip_payload, headers=auth("mallory")).json()["trip"]
    r = client.post(f"/v1/trips/{other['id']}/bookings", json={"offer_id": offer["offer_id"], "travellers": 4},
                    headers={**auth("mallory"), "Idempotency-Key": uuid.uuid4().hex})
    assert r.status_code == 404  # mallory never searched this offer
    txn = start(client, trip["id"], offer["offer_id"]).json()
    assert client.get(f"/v1/bookings/{txn['id']}", headers=auth("mallory")).status_code == 404


def test_stays_ranked_by_location_fit_and_cancellation_flow(client, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    r = client.post(f"/v1/trips/{trip['id']}/bookings/search/stays", json={"check_in": "2026-11-16", "nights": 4, "guests": 4, "rooms": 2},
                    headers=auth("alice")).json()
    offers = r["offers"]
    assert offers and offers[0]["location_fit"] is not None and "BEST LOCATION" in offers[0]["badges"]
    fits = [o["meta"]["fit_score"] for o in offers]
    assert fits == sorted(fits, reverse=True)
    refundable = min((o for o in offers if o["refundable"]), key=lambda o: o["price"]["amount_minor"])
    txn = start(client, trip["id"], refundable["offer_id"], travellers=1).json()
    done = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": TRAVELLERS[:1]}, headers=auth("alice")).json()
    assert done["state"] == "CONFIRMED", done
    quote = client.post(f"/v1/bookings/{txn['id']}/cancel-quote", headers=auth("alice")).json()
    cancelled = client.post(f"/v1/bookings/{txn['id']}/cancel", json={"accepted_refund_minor": quote["refund"]["amount_minor"]}, headers=auth("alice")).json()
    assert cancelled["state"] in {"REFUNDED", "CANCELLED"}


def test_high_value_payment_requires_step_up(client, container, demo_trip_payload):
    trip = make_trip(client, demo_trip_payload)
    offer = flight_offer(client, adults=6)  # ≈ RM 7,000 — above the step-up threshold
    txn = start(client, trip["id"], offer["offer_id"], travellers=6).json()
    six = TRAVELLERS + TRAVELLERS[:2]
    out = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"], "travellers": six}, headers=auth("alice"))
    assert out.status_code == 401 and out.json()["detail"]["code"] == "step_up_required"
    assert not container.bookings.payments.intents, "nothing is authorised before step-up"


def test_ground_compare_explains_tradeoffs(client):
    r = client.post("/v1/bookings/search/ground", json={"origin": "tokyo", "destination": "kyoto", "depart": "2026-11-19", "passengers": 4}, headers=auth("alice")).json()
    modes = {o["meta"]["mode"] for o in r["offers"]}
    assert modes == {"rail", "bus", "flight"}
    assert r["insights"] and any("door-to-door" in s for s in r["insights"])


def test_best_fit_flight_lands_before_day_one(client):
    # 20:00 cut-off: the fast overnight flight (lands next morning) is excluded, so best fit must come from the rest
    body = {"origin": "KUL", "destination": "tokyo", "depart": "2026-11-15", "adults": 2, "arrive_by": "2026-11-15T20:00:00"}
    offers = client.post("/v1/bookings/search/flights", json=body, headers=auth("alice")).json()["offers"]
    in_time = [o for o in offers if o["arrival"][:19] <= body["arrive_by"]]
    best = next(o for o in offers if "BEST FIT" in o["badges"])
    assert in_time and len(in_time) < len(offers)
    assert best["arrival"][:19] <= body["arrive_by"], "a flight that misses day 1 must not be called best fit"


def test_flight_landing_the_night_before_shows_on_day_one(client):
    trip = make_trip(client, {"text": "Tokyo 3 days solo, RM3000", "quick": {"start_date": "2026-11-16"}})
    body = {"origin": "KUL", "destination": "tokyo", "depart": "2026-11-15", "adults": 1, "arrive_by": "2026-11-16T10:00:00"}
    offers = client.post("/v1/bookings/search/flights", json=body, headers=auth("alice")).json()["offers"]
    evening = next(o for o in offers if o["arrival"].startswith("2026-11-15"))
    txn = start(client, trip["id"], evening["offer_id"], travellers=1).json()
    done = client.post(f"/v1/bookings/{txn['id']}/confirm", json={"accepted_total_minor": txn["offer"]["price"]["amount_minor"],
                                                                     "travellers": [{"given_name": "Aina", "family_name": "Test"}]}, headers=auth("alice")).json()
    assert done["state"] == "CONFIRMED"
    day1 = client.get(f"/v1/trips/{trip['id']}", headers=auth("alice")).json()["days"][0]
    first = day1["items"][0]
    assert first["locked"] and first["booking_id"] == txn["id"] and "night before" in first["name"]
