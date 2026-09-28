# Arivo Design System — "Night Cartography"

> Your trip isn't generated once. It travels with you.

`design/tokens.json` is the single source of truth. `node tools/tokens/build.mjs` validates every contrast pair and generates `apps/mobile/lib/core/theme/tokens.g.dart` and `design/tokens.css`. Never hard-code a hex, size or duration in a widget.

---

## 1. Principles

1. **The trip is the interface.** The map and the Trip Spine carry the product. Chat with Ari is one tool among many, not the home screen.
2. **Surfaces carry meaning.** *Ink* (dark) means you are *in* the trip: Live, Rescue, Story, the globe. *Paper* (light) means you are *planning*: Trip, Book, You. A screen never switches surface just for variety.
3. **One volt per screen.** The volt accent marks the single primary action. Everything else is tone.
4. **Every number shows its source.** Prices, times, distances and scores carry a `DataProvenanceTag`: **Live** (provider data), **Est.** (Arivo computed) or **You** (user input). A number with no source never appears.
5. **AI explains, you decide.** Any AI change shows *why* (`WhyThisSheet`, `ChangeDiff`) and waits for confirmation when it is material.
6. **Calm under disruption.** Rain, delays and closures use Ari's `warning` state and ember accents, never red full-screen panic.
7. **Thumb-first.** Primary actions sit in the bottom 40% of the screen. Touch targets are ≥ 48 dp. Sheets beat new pages.

## 2. Signature motif: the Route Thread

A single continuous line that follows the traveller through the product:

| Where | Form |
|---|---|
| Map | the day's route, drawn in with `motion.route` (700 ms) and coloured with the day's `route[n]` |
| Trip Spine | the same line runs vertically through the timeline, with nodes at stops and dashes for travel legs |
| Rescue / Plan B | the line **morphs** from the old path to the new one; removed legs fade to 30% and dash out |
| Booking cards | the thread becomes the **perforation** of a boarding-pass stub |
| Ari | the dashed volt stitch on the hat band |

Ink surfaces carry a faint topographic contour texture (4% opacity) so dark screens feel like night maps rather than flat black.

## 3. Colour

| Role | Token | Hex | Use |
|---|---|---|---|
| Ink surfaces | `ink.950 / 900 / 800 / 700` | #070B16 · #0E1426 · #18203A · #232C4A | immersive screens, sheets on ink, cards on ink |
| Paper surfaces | `paper.50 / 100 / 200` | #FAF7F0 · #F2EDE2 · #E6DFD0 | planning screens, cards, dividers |
| Text | `text.onPaper`, `onPaperMuted`, `onInk`, `onInkMuted` | | all ≥ 4.5:1 (primary text ≥ 7:1) |
| **Volt** | `accent.volt` #C8F53C | | the one primary action; "You" provenance; Guide |
| **Signal** | `accent.signal` #3ED3F5 | | routes, Live mode, "Live" provenance |
| **Lantern** | `accent.lantern` #FFB547 | | Arivo Pulse, "Est." provenance, budget warnings |
| **Ember** | `accent.ember` #FF5D5D | | disruption, errors, destructive confirm |
| Accents on paper | `accentOnPaper.*` | | text and icons in accent hues on light surfaces (bright accents fail AA on paper) |
| Day routes | `route[0..7]` | | one colour per itinerary day |
| Crew | `crew[0..5]` | | one colour per crew member (Crew Constellation, avatars, votes) |

Colour never works alone: status pairs a hue with an icon and a word (for example "● Live", "⚠ Delayed").

### Sub-brand marks
- **Arivo Pulse**: lantern heartbeat waveform glyph. Pulse cards get a lantern hairline top border and a `PulseBadge` with score.
- **Arivo Live**: signal-cyan dot with a 2 s radar ring (static when reduced motion is on).
- **Arivo Crew**: constellation glyph. Each member is a star in their `crew[n]` colour, and lines connect shared interests.
- **Arivo Guide**: Ari (see `assets/mascot/README.md`).

## 4. Typography

| Style | Family | Size/Line | Use |
|---|---|---|---|
| `displayXL/L/M` | Instrument Serif | 56/58 · 44/46 · 34/38 | destination names, day titles, hero statements. At most one per screen |
| `titleL/M` | Geist 600 | 22/28 · 18/24 | section and card titles |
| `bodyL/M` | Geist 400 | 16/24 · 15/22 | reading text (15 is the minimum for paragraphs) |
| `label` | Geist 600 +2% | 13/16 | chips, buttons, tabs |
| `caption` | Geist 500 | 12/16 | metadata; **never smaller than 12** |
| `monoL/M/S` | Geist Mono | 20 · 15 · 12 | times, prices, PNRs, scores, flight numbers: the "ticket" voice |

Rules: numbers that users compare (price, time, duration, score) always use mono with tabular figures. Destination names use the serif. Nothing else does.

## 5. Space, shape, elevation, motion

- **Space:** 4-pt grid (`space.1` = 4 … `space.16` = 64). The screen gutter is 16, and 20 on large phones.
- **Radius:** `xs 8` (chips, tags), `s 14` (cards), `m 22` (large cards, inputs), `l 32` (bottom sheets), `pill` (FAB, segmented).
- **Elevation:** one shadow (`raised`) for floating elements (FAB, sheets on map, dragged card). Cards separate by tone, not shadow.
- **Motion:** `fast 140` (press, toggle), `base 220` (sheet, card), `slow 420` (screen, camera), `route 700` (route draw/morph). The easing is `standard` (0.2,0,0,1) for entering and `exit` (0.4,0,1,1) for leaving. Motion always means something: a camera move signals a new day, a route morph signals a replan, a number roll signals a budget change.
- **Reduced motion:** when `MediaQuery.disableAnimations` is set, routes appear without drawing, the camera jumps, Ari holds a static pose, and the radar ring is static.

## 6. Components

Each entry lists purpose, variants, states and accessibility. Implementations live in `apps/mobile/lib/core/ui/`.

### StopCard
Purpose: one itinerary stop in the Trip Spine.
Anatomy: time (monoM) · place (titleM) · duration · travel leg from previous stop · price + provenance · one-line reason · status chip.
- **Variants:** `planned`, `booked` (lock glyph plus boarding-pass edge: a hard constraint), `live-next` (ink, signal ring), `done` (60% opacity with check), `moved` / `added` / `removed` (diff states).
- **States:** default, pressed, dragging (raised shadow, the map highlights the district), disabled (closed place, with an ember "Closed today" note).
- **Actions:** swipe-left reveals *Swap / Remove*. Long-press drags. Tap opens Details.
- **A11y:** one semantic node: "09:30, Senso-ji, 75 minutes, 12 minutes from hotel, free. Best early to avoid crowds." Custom actions: Move, Swap, Remove, Details.

### TripSpine
The vertical Route Thread with StopCards as nodes. Travel legs appear as dashed segments labelled with mode and minutes. Each day starts with a serif day title ("Day 2 · Shibuya / Harajuku") and a day-colour dot.

### DataProvenanceTag
A tiny tag after a value: `LIVE` (signal), `EST.` (lantern), `YOU` (volt). The long-press tooltip names the source and time ("Open-Meteo · 12 min ago").
A11y: read as "live from Open-Meteo, updated 12 minutes ago".

### WhyThisSheet
A bottom sheet that opens from any recommendation's "Why this?". It shows the match % (monoL) plus 2–5 evidence rows, each with an icon, a plain sentence and a provenance tag. Its footer offers *Not for me* (feeds TravelerDNA) and *Show similar*.

### PulseBadge + EvidenceSheet (Arivo Pulse)
- **Badge:** lantern waveform glyph + `TrendScore` (mono) + label ("Rising this week"). It is only rendered when evidence exists.
- **EvidenceSheet:** the score breakdown, as 7 bars showing weighted components; source count; "+64% activity vs 4-week baseline"; event mention; "Updated 18 min ago"; and links to sources.

### ChangeDiff (Rescue / Plan B)
Grouped list: **Kept** (check, muted), **Moved** (signal arrow, old→new time), **Removed** (ember, strikethrough, reason), **Added** (volt plus). The header summarizes the time change and budget change (mono, signed). Footer: *Apply changes* (volt) · *Keep original*.
A11y: announces "3 changes: 1 moved, 1 removed, 1 added. Budget saves RM 42."

### PlanABCompare
Two columns: Plan A (current) and Plan B (with its trigger: rain, fatigue, closure). Each column shows stops, walking km, total time and cost. The recommended plan has a volt outline. It stacks vertically on narrow screens.

### BudgetGauge (Budget Brain)
A ring: spent (ink/paper tone), reserved (hatched), forecast (lantern dashed), remaining (volt). Tap to open categories.
- **States:** on-track, tight (lantern), over (ember + a "Suggest savings" action).
- **A11y:** "RM 1,620 of RM 2,500 spent, forecast RM 2,320, on track."

### LocationFitMeter
A horizontal meter (0–100) with a sentence such as "8 of 10 planned stops under 25 min". It is used on hotel cards and hotel detail.

### BoardingPassCard (bookings)
A ticket-shaped card with a perforated edge (the Route Thread). The left stub holds the route (KUL → NRT in monoL) and times. The right side holds the status chip (`CONFIRMED`, `PENDING`, `CANCELLED`, `SANDBOX`), the reference (mono) and actions.
- **Variants:** flight, stay, bus/rail, activity.
- **States:** confirmed, supplier-pending (spinner + "Confirming with airline"), failed (ember, with the compensation note "Payment voided"), cancelled, offline (cached from the Booking Vault, with a "Saved offline" tag).

### PriceBreakdown + PriceChangedBanner
- **PriceBreakdown:** base fare · taxes · fees · baggage · booking fee · total, with currency always shown and cancellation/change terms in plain language.
- **PriceChangedBanner:** an ember-bordered banner, "Price changed RM 1,280 → RM 1,347", that must be reconfirmed. It is never dismissed silently.

### CheckoutStepper
Four steps: Traveller · Details · Payment · Review. The Review step's primary button **always states the amount**: "Confirm & pay RM 1,243". "Continue" is never used on the final step.

### SandboxBadge
A lantern outline pill reading `SANDBOX`. It appears on every sandbox offer, checkout and confirmation. It is non-dismissible.

### CrewConstellation + CrewBalanceBars (Arivo Crew)
- **Constellation:** members are stars in their crew colours; shared interests are lines, and conflicts are dashed ember lines.
- **Balance bars:** per member, the share of the day's time aligned to their interests. There is no ranking and no winner framing.

### GuideFab + AriBubble
- **GuideFab:** 64 dp circle showing Ari's sprite. It is bottom-right, above the tab bar, and draggable to either edge. Long-press = voice.
- **AriBubble:** a short contextual line (≤ 90 characters) that appears at most once per screen visit and auto-dismisses after 6 s. It is never modal.

### ConfirmSheet
Used for every agent action proposal ("Move dinner to 20:00?"). It shows the proposed change, its impact (time, budget, bookings affected) and two buttons. Destructive actions use an ember primary.

## 7. Required states (all screens)

| State | Treatment |
|---|---|
| Loading | skeleton in the final layout shape. Ari `thinking` only for AI work > 1.5 s, with honest step labels ("Checking opening hours…") |
| Empty | one sentence + one action; Ari `idle_float` sprite |
| Offline | ink banner "Offline — showing saved trip" + Ari `offline`; booking and search actions disabled with the reason |
| Error | what happened, what still works, retry. Never a stack trace |
| No results | suggest the nearest relaxation ("No ramen open now — 3 open after 17:00") |
| Location / camera denied | explain the value, offer manual entry, link to settings. Never nag twice per session |
| Budget exceeded | BudgetGauge `over` + "Suggest savings" (substitutions with deltas) |
| Route unavailable | straight-line estimate labelled `EST.` + "Directions unavailable" |
| Place closed | StopCard disabled + one-tap "Find alternative nearby" |
| Weather disruption | Ari `warning` bubble + PlanABCompare |
| Crew conflict | CrewConstellation dashed ember line + "Suggest a fair split" |
| AI uncertainty | confidence shown in words ("Likely Shibuya Sky — 64% sure"); low confidence asks instead of acting |

## 8. Navigation

The bottom tab bar has four tabs: **Explore · Trip · Live · You**. The Live tab dims when no trip is active and becomes the default landing screen during a trip. The GuideFab floats above every tab. Booking lives inside Trip (Trip Cart, My Bookings) and Explore (Stay). It is never a separate app.

## 9. Imagery

- **Sources:** place photos come from licensed sources only: Wikimedia Commons via Wikidata, or provider photos where terms permit. Every photo shows its attribution in the place detail.
- **Missing photos:** the fallback is a generated "map tile" card (the place's surroundings in the day colour), never stock photography.
- **Captions:** no fake social metrics, testimonials or "1M+ travellers".
