# Arivo — The Living AI Travel OS

> Your trip isn't generated once. It travels with you.

Arivo is an AI-powered travel planning platform that covers the full journey lifecycle:
**Discover → Plan → Book → Experience → Adapt.**

Most travel apps generate a static itinerary and stop there. Arivo treats the trip itself as a living document — one that updates in real time as conditions change, budgets shift, and group preferences evolve. Ari, the AI guide, can search, compare, and prepare a checkout, but it can **never spend your money**.

---

## The Problems Arivo Solves

### 1. Static Plans Break in the Real World
Traditional travel planners give you a fixed itinerary. When it rains, a venue closes, or a flight is delayed, you're on your own. Arivo's **replanning engine** detects disruptions and proposes a revised plan — keeping your locked bookings in place and showing you exactly what changed before you accept anything.

> *Example: "It started raining." → Outdoor stops move indoors. Bookings stay put. You review a diff before applying.*

### 2. Planning Is Still Manual and Fragmented
Finding flights, accommodation, restaurants, and local events across five different apps, then assembling them into a coherent day-by-day plan, is exhausting. Arivo's **dynamic planner** takes a single natural-language brief and produces a complete, neighbourhood-grouped itinerary — with scoring evidence, source tags, and budget tracking built in.

> *Example: "Tokyo, five days, three friends, RM 4,000 each, anime, food, photography, no rushing." → Full itinerary in seconds.*

### 3. Group Travel Is Coordination Hell
Deciding where to go and what to do across a group of friends means endless chat threads and no one person in charge. Arivo's **Crew** feature gives every traveller a voice: members vote on proposed changes, a majority yes turns a suggestion into a plan update, and everyone sees the same live itinerary.

> *Example: Vote on a night out → majority yes → proposed evening change applied to the shared trip.*

---

## Key Features

| Feature | What It Does |
|---|---|
| **Dynamic Planning** | Natural-language brief → complete itinerary with neighbourhood grouping and route threading on a map |
| **Live Replanning** | Disruption detected (weather, closure, delay) → AI proposes a diff → you confirm before anything changes |
| **Crew Travel** | Shared trips, invite links, group voting, majority-based plan updates |
| **Ari (AI Guide)** | Floating conversational assistant — proposes changes, never executes payments |
| **Pulse** | Trending local events and experiences, each card backed by timestamped evidence |
| **Book** | Sandbox flight search and checkout with price revalidation and idempotent booking |
| **Receipt Lens** | Scan a receipt (phone camera or image upload) and add it to the group budget |
| **Live Mode** | Real-time next-stop view, walking/transit directions, and Story mode |
| **Why This?** | Every recommended stop shows its evidence, tagged LIVE / EST. / YOU |

---

## Google Maps & Google Tools Integration

Arivo is designed to plug into Google's ecosystem at multiple layers:

### Navigation & Routing
- **Google Maps Platform** will replace the current OpenFreeMap/MapLibre layer for production, enabling full turn-by-turn directions, Street View previews inside stop cards, and live traffic-aware leg durations.
- The `Go` button in Live Mode will deep-link into Google Maps for native navigation on Android and iOS.
- Estimated walking and transit times currently fall back to labelled estimates; Google Maps Directions API will provide live, traffic-aware durations.

### Places & Search
- **Google Places API** will power the place search, autocomplete, and opening-hours verification that currently uses OpenStreetMap/Wikidata. This unlocks richer photos, user reviews, and real-time open/closed status.
- **Google Geocoding API** will resolve free-text location inputs from Ari's conversation interface into precise coordinates.

### Calendar & Productivity
- **Google Calendar API** will allow confirmed itinerary days to be pushed directly to each traveller's calendar, including per-stop time blocks, venue addresses, and booking references.

### Wallet & Passes
- **Google Wallet API** will allow boarding passes and booking confirmations generated through Arivo's booking saga to be saved as wallet passes on Android.

---

## Real-World Relevance

Travel is one of the most emotionally significant and logistically complex things people do — and it is still largely managed through a patchwork of disconnected apps. Arivo addresses concrete, real pain points:

- **Budget travellers** in Southeast Asia (the primary design audience) often plan multi-city trips across tight budgets with groups of friends. The group voting and budget tracker features directly serve this use case.
- **Solo travellers** benefit from Ari's replanning loop: a missed bus, a closed attraction, or an unexpected event becomes a solvable problem rather than a ruined afternoon.
- **Families** with mixed preferences can use the Crew feature to surface compromises — majority-based voting ensures no single person dominates the plan.
- **Business travellers** benefit from idempotent bookings, receipt scanning, and the privacy gateway that masks personal details before any model call.

---

## Sustainability & Long-Term Potential

### Responsible AI Travel
- Every "trending" recommendation is backed by real, timestamped evidence (Wikipedia pageviews, GDELT, YouTube, Ticketmaster). Arivo never surfaces invented popularity.
- Opening hours and place data are only shown when verified, reducing wasted journeys.
- The replanning engine encourages travellers to adapt their existing trip rather than cancel and rebook, reducing unnecessary transactions.

### Scalable Architecture
- The API is a FastAPI modular monolith designed to be split into microservices without rewrites. Each domain (`planning`, `bookings`, `crew`, `pulse`, `vision`) is already a self-contained module.
- The Postgres + PostGIS + pgvector stack supports geospatial queries, semantic place search, and row-level security — all of which scale horizontally on managed cloud databases.
- The Flutter mobile app targets Android, iOS, and web from a single codebase, covering the majority of the global smartphone market.

### Commercial Path
- Supplier integrations (Duffel for flights, Stripe for payments) are already wired in sandbox mode. Going live is a configuration change, not a rebuild.
- The Pulse feature is a natural foundation for destination marketing partnerships — verified, evidence-backed content, not paid placements.

---

## How IBM Bob Supported This Project

IBM Bob (the AI software engineering assistant) was used throughout the development of Arivo as a hands-on coding collaborator, not just a documentation tool. Here is how it contributed:

### Codebase Development
- Scaffolded and refined the FastAPI modular monolith structure, including the LangGraph-based agent loop for Ari and the OR-Tools planning solver.
- Generated and iterated on Flutter widget implementations — the 3D Ari mascot controller, the route thread map overlay, and the Crew voting UI.
- Wrote and debugged the Supabase RLS policies and migration files, then verified them with the `rls_check.sql` test script.
- Set up the React/Vite/Three.js web app, including the glass-surface design system and the interactive 3D map component.

### Problem Solving & Debugging
- Diagnosed and fixed environment issues during local setup (including Windows-specific `EPERM` errors with `npm ci` and `esbuild.exe`).
- Traced API integration bugs across the Flutter ↔ FastAPI boundary and resolved CORS and port configuration issues.
- Helped interpret test failures in the pytest suite covering booking sagas, BOLA checks, and the privacy gateway.

### Architecture & Design Decisions
- Advised on the trade-off between a full microservices split and the current modular monolith approach, recommending the monolith for the current stage with clear module boundaries for future extraction.
- Designed the PrivacyGateway pattern that masks PII before any model call — a non-obvious requirement surfaced through Bob's security review pass.
- Shaped the idempotent booking saga pattern so that ambiguous supplier responses are reconciled rather than retried blindly.

### Documentation & Onboarding
- Wrote and maintained this README, the `apps/web/README.md`, and inline code documentation throughout the project.
- Generated the demo script used in presentations and reviews.

---

## Project Structure

```
Arivo_Travel_Planner/
├── apps/
│   ├── web/          # React · TypeScript · Vite · Three.js · Mapbox/MapLibre
│   └── mobile/       # Flutter · Riverpod · go_router · Dio · MapLibre
├── services/
│   └── api/          # FastAPI · LangGraph/LangChain · OR-Tools · Anthropic SDK
├── supabase/         # Postgres 17 · PostGIS · pgvector · RLS migrations
├── design/           # Night Cartography design tokens
├── assets/           # Mascot and static assets
└── tools/
    └── mascot-forge/ # glTF-Transform + Three.js mascot build pipeline
```

---

## Running Locally

**Prerequisites:** Python 3.11 · Node 22 · Flutter 3.47+ · Docker (optional, for Postgres only)

### Step 1 — Start the API

```bash
cd services/api

# Windows
python -m venv .venv && .venv/Scripts/pip install -e ".[dev]"
.venv/Scripts/python -m uvicorn app.main:app --port 8787

# macOS / Linux
python -m venv .venv && .venv/bin/pip install -e ".[dev]"
.venv/bin/python -m uvicorn app.main:app --port 8787
```

Runs at **http://localhost:8787**. No API keys needed — uses in-memory storage and sandbox suppliers by default.

### Step 2 — Start the Web App

**Option A: React web app** (recommended) → opens at **http://127.0.0.1:5181**

```bash
cd apps/web
npm install
npm run dev
```

**Option B: Flutter web build** → opens at **http://localhost:5180**

```bash
cd apps/mobile
flutter build web --release
python -m http.server 5180 --directory build/web
```

### Step 3 — Mobile App (Android emulator)

```bash
flutter run --dart-define=ARIVO_API=http://10.0.2.2:8787
```

> `10.0.2.2` is the Android emulator's alias for your machine's localhost.

---

## Optional API Keys

Copy [`.env.example`](.env.example) to `.env` at the repo root. Every key is optional — missing features show a clear **"not configured"** or **SANDBOX** label, never fake data.

| Key | What It Unlocks |
|---|---|
| `ANTHROPIC_API_KEY` | Claude-powered Ari: intent parsing, "Why this?" explanations, full agent tool loop |
| `DUFFEL_TOKEN` | Test-mode flight search and booking (label: SANDBOX) |
| `STRIPE_SECRET_KEY` | Test-mode checkout and payment revalidation |
| `YOUTUBE_API_KEY` | YouTube as a Pulse trending source |
| `TICKETMASTER_KEY` | Live events as a Pulse trending source |
| `ORS_API_KEY` | Real walking/transit durations (falls back to estimates without it) |

---

## Optional: Postgres + Row-Level Security

```bash
npx supabase start          # spins up local Postgres and applies migrations
psql "$DATABASE_URL" -f supabase/tests/rls_check.sql   # verifies trip data is member-only
```

Switch from in-memory to Postgres by setting `STORAGE=postgres` in your `.env`.

---

## Running Tests

```bash
# API tests (booking saga, BOLA, privacy gateway, scoring, Guide, Crew)
cd services/api
.venv/Scripts/python -m pytest -q          # Windows
.venv/bin/python -m pytest -q              # macOS / Linux

# Flutter tests
cd apps/mobile
flutter analyze
flutter test
```

---

## Security & Safety Guardrails

These are enforced in code, not just documented:

- **The AI never spends money.** Ari's agent tool scopes explicitly exclude charging or finalising a booking. Payment requires a human tap.
- **No secrets in the app.** The Flutter build only holds the API URL and the Stripe publishable key — never secret keys.
- **Idempotent bookings.** Every booking carries an idempotency key. Ambiguous supplier responses are reconciled, not retried blindly.
- **Server-side ownership checks.** Every trip, booking, and expense route verifies ownership on the server (BOLA), mirrored by Postgres RLS.
- **Privacy gateway.** Names, passport numbers, booking references, and phone numbers are masked before any model call. Card numbers are never stored or logged.
- **No invented facts.** Trending cards require timestamped evidence. Opening hours are only shown when verified. Stories cite their source or say they cannot.

---

## Quick Demo (≈ 4 minutes)

1. **Onboarding** — Enter: *"Tokyo, five days, three friends, RM 4,000 each, anime, food, photography, no rushing."* → tap **Build my trip**.
2. **Trip view** — Days grouped by neighbourhood, route thread on the map. Tap a stop → **Why this?** → see evidence tagged LIVE / EST. / YOU.
3. **Pulse** — Browse trending cards with source links. **Add to trip** shows a KEPT / MOVED / ADDED diff before anything changes.
4. **Book → Flights** — Sandbox inventory labelled **SANDBOX**. Price is revalidated at checkout. If it changed, you must re-confirm before **Confirm & pay** runs.
5. **Rescue my day** — Type *"It started raining."* → outdoor stops move indoors, bookings stay, review the diff before applying.
6. **Live mode** — Simulate the clock. See next stop, leg info, **Go** directions, and Story mode.
7. **Receipt Lens** — Scan a receipt on phone or upload the sample image on web → review and add to group budget.
8. **Crew** — Create an invite link, vote on a night out, majority yes → proposed evening change.
9. **Ari** — Tap the floating button → *"Move dinner later."* → Ari proposes, you confirm. Ari cannot pay.

---

## Credits

Ari is based on **"Miibot" by itsmejhade** (CC BY 4.0), modified with travel gear.
Places © OpenStreetMap contributors (ODbL) · Facts from Wikidata (CC0) · Photos from Wikimedia Commons (per-photo licence) · Map tiles by OpenFreeMap / OpenMapTiles · Weather by Open-Meteo · FX rates by Frankfurter (ECB).
