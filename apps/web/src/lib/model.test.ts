import test from "node:test";
import assert from "node:assert/strict";
import {
  expenseTotal,
  fromMinor,
  guideAction,
  isTrip,
  routeCoordinates,
  sampleTrip,
  type GuideProposal,
} from "./model.ts";

test("map coordinates use longitude, latitude and discard invalid points", () => {
  const valid = sampleTrip.days[0].items[0];
  assert.deepEqual(
    routeCoordinates([valid, { ...valid, lat: NaN }, { ...valid, lon: 181 }]),
    [[valid.lon, valid.lat]],
  );
});
test("currency conversion preserves yen and cent-based amounts", () => {
  assert.equal(fromMinor({ amount_minor: 1500, currency: "JPY" }), 1500);
  assert.equal(fromMinor({ amount_minor: 1500, currency: "USD" }), 15);
});
test("local budget totals never mix unconverted currencies", () => {
  assert.equal(
    expenseTotal(
      [
        {
          id: "a",
          merchant: "Cafe",
          amount: 10,
          currency: "USD",
          category: "food",
        },
        {
          id: "b",
          merchant: "Cafe",
          amount: 1500,
          currency: "JPY",
          category: "food",
        },
      ],
      "USD",
    ),
    10,
  );
});
test("guide proposals accept reviewed trip edits only", () => {
  const proposal: GuideProposal = {
    kind: "move_item",
    summary: "Move lunch",
    confirm: {
      method: "POST",
      path: "/v1/trips/abc/items/item_123",
      body: { action: "move", new_start: "14:30" },
    },
  };
  assert.deepEqual(guideAction("abc", proposal), {
    path: "/v1/trips/abc/items/item_123",
    body: { action: "move", new_start: "14:30" },
  });
  assert.equal(guideAction("another-trip", proposal), null);
  assert.equal(
    guideAction("abc", {
      ...proposal,
      confirm: { ...proposal.confirm, path: "https://example.com/steal" },
    }),
    null,
  );
  assert.equal(
    guideAction("abc", {
      ...proposal,
      confirm: {
        ...proposal.confirm,
        body: { action: "move", new_start: "29:99" },
      },
    }),
    null,
  );
  assert.equal(
    guideAction("abc", {
      kind: "checkout",
      summary: "Pay",
      confirm: { method: "POST", path: "/v1/bookings/123/confirm" },
    }),
    null,
  );
});
test("invalid persisted trips fall back safely", () => {
  assert.equal(isTrip(sampleTrip), true);
  for (const value of [
    null,
    {},
    [],
    { ...sampleTrip, days: [] },
    { ...sampleTrip, intent: null },
  ])
    assert.equal(isTrip(value), false);
});
