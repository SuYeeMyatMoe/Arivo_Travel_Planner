Arivo is a living travel OS: the trip is the interface, and it changes as the trip does. The system is called **Night Cartography**. It has two surfaces that tell travellers which mode they are in, one continuous Route Thread, and numbers that always show their source.

## Content fundamentals

- **Talk like a local friend who plans well.** Use second person, active voice and short sentences. Write "Rain from 14:00. Plan B keeps your dinner." not "Due to adverse weather conditions, your itinerary has been modified."
- **Use sentence case** everywhere except status chips and provenance tags (`SANDBOX`, `LIVE`, `EST.`, `YOU`).
- **Say what a button does.** "Rescue my day", "Apply changes", "Keep original". On the last checkout step the button states the amount: "Confirm & pay RM 1,243", never "Continue".
- **Evidence over hype.** Never write "Trending", "#1" or "1M+ travellers" without a source. Pulse copy states the evidence: "+64% activity this week · 4 independent sources · updated 18 min ago".
- **State uncertainty in words.** "Likely Shibuya Sky, 64% sure." When confidence is low, ask instead of acting.
- **No emoji and no sparkles.** Show AI by what it did (a diff, evidence, a provenance tag), not by decoration.
- **Currency and time:** code-style symbol with a space (`RM 1,243`, `¥ 3,800` shows as `¥3,800`), 24-hour times (`09:30`), durations as `75 min` / `1 h 20`. Set every comparable number in `mono-m` or `mono-l`.

## Surfaces carry meaning

- Use the **`paper`** theme for planning: Trip, Book, You, Explore lists.
- Use the **`ink`** theme when the traveller is *in* the trip: Live, Rescue My Day, Story Mode, the globe.
- Never switch surface for variety. A screen is paper or ink, and sheets inherit it.
- Put screen backgrounds on `surface`, cards and sheets on `surface-raised`, and wells and meter tracks on `surface-sunken`.
- `line` is a decorative hairline and ticket perforation. It is never the only thing separating controls.

## Colour

- **`volt` marks the single primary action on a screen.** Put `text-on-volt` on it. One volt fill per screen. Secondary actions are `tonal`.
- **`signal`** is routes, Arivo Live and live data. **`lantern`** is Arivo Pulse, estimates and "tight" budget. **`ember`** is disruption, errors, removed stops and destructive confirms.
- For accent-coloured text or icons on a surface, use the `-text` tokens (`volt-text`, `signal-text`, `lantern-text`, `ember-text`). The bright fills fail AA as text on paper.
- Pair every status colour with an icon and a word (`StatusChip`). Colour never works alone.
- Itinerary days take `route-1` … `route-8` in order. Crew members take `crew-1` … `crew-6` in join order and keep them for the whole trip.
- **Provenance:** tag every price, time, distance, score and forecast with `ProvenanceTag`. `provenance-live` = provider data with timestamp, `provenance-est` = Arivo computed, `provenance-you` = traveller input.

## Type

- Set destination names, day titles and the onboarding prompt in the **display** family (Instrument Serif): `display-xl` / `display-l` / `display-m`, **at most one per screen**.
- Set interface text in **ui** (Geist): `title-l` for screen and sheet titles, `title-m` for place names, `body-m` (15px) as the paragraph minimum, `label` for buttons and chips, `caption` (12px) for metadata. Nothing is smaller than 12px.
- Set times, prices, routes, scores and references in **mono** (Geist Mono) with tabular figures: `mono-l` for totals and routes (`KUL → NRT`), `mono-m` in cards, `mono-s` for refs and tags. This is the "ticket" voice.

## Space, shape, elevation

- Build on the 4-pt grid: `space-4` (16) is the screen gutter and card padding, `space-3` the card inner gap, `space-6` / `space-8` between sections. Touch targets are ≥ `space-12` (48).
- Corners: `radius-xs` chips and tags, `radius-s` stop cards, `radius-m` large cards, inputs and boarding passes, `radius-l` bottom sheets, `radius-pill` buttons and the Guide FAB.
- Use `shadow-raised` only for floating things: the Guide FAB, a sheet over the map, a card being dragged. Everything else separates by tone.

## The Route Thread

One continuous line runs through the product:
- On the map it is the day's route, drawn in with `dur-route` and `ease-emphasized`.
- In `TripSpine` it is the dashed timeline, with nodes at stops and legs between.
- In Rescue and Plan B it morphs from the old path to the new; removed legs fade out.
- On `BoardingPassCard` it is the perforation.
- On Ari it is the volt stitch around the hat band.

Do not invent other decorative lines.

## Motion

- Use `dur-fast` for press and toggle, `dur-base` for sheets and cards, `dur-slow` for screen and camera, `dur-route` for route draw and morph.
- Motion must mean something: a camera move means a new day, a route morph means a replan, a number roll means the budget changed.
- Under reduced motion: routes appear without drawing, the camera jumps, Ari holds a still pose, and the Live radar ring is static.

## Components in use

- **Trip:** `TripSpine` of `StopCard`s. A booked stop (`status: booked`) is a hard constraint; Rescue never moves it.
- **Living Trip:** `ChangeDiff` after every AI change, with *Apply changes* (volt) and *Keep original* (tonal). Nothing applies silently.
- **Arivo Pulse:** `PulseBadge` only when evidence exists; it expands into the TrendScore breakdown.
- **Budget Brain:** `BudgetGauge` shows spent, reserved, forecast (EST.) and remaining. "Over" pairs with "Suggest savings".
- **Stays:** `LocationFitMeter` leads every hotel card with a real-travel-time sentence.
- **Bookings:** `BoardingPassCard` for every booking. `PriceBreakdown` before payment, with the price-changed banner when revalidation moves the total. `StatusChip tone="sandbox"` on anything not live.
- **Arivo Crew:** `CrewConstellation` shows shared interests, conflicts and balance, with no ranking.

## Iconography

- Use 20px-grid line icons with a 1.8 stroke, round caps and joins, drawn in `currentColor` (the `Icon` set inside the bundle: check, lock, arrow, plus, minus, warn, walk, train, bus, plane, bed, pulse, clock).
- Icons sit beside words; an icon-only button needs an accessible label.
- No emoji in UI copy.

## Imagery

- Place photos come only from licensed sources: Wikimedia Commons via Wikidata, or provider photos where terms allow. Each carries its attribution in place detail.
- A place with no photo gets a generated map-tile card in its day colour, never stock photography.

## Ari, the explorer (Mascot assets)

- Ari is Arivo Guide's face: a graphite vinyl explorer with a sand bucket hat (route-stitched band, boarding pass, compass-star pin), a signal beacon, a volt scarf and a compass-core chest emblem.
- **Use Ari sparingly:** onboarding, Story Mode, Rescue, celebrations, and the 64px Guide FAB. Speech bubbles appear at most once per screen visit and are never modal.
- **States:** `idle_float`, `listening`, `thinking`, `talking`, `pointing`, `warning`, `excited`, `offline`. `warning` is calm concern, never alarm.
- Ari is derived from "Miibot 3D Model" by itsmejhade (CC BY 4.0). Keep the credit in the app's About screen.

## Accessibility

- Every text pair in both themes is ≥ 4.5:1; primary text is ≥ 14:1.
- Focus shows a 2px `focus-ring` outline, offset 2px, on every interactive element.
- Critical information is never only on the map or only in colour: stops, legs and changes exist as text and are announced as one sentence.
