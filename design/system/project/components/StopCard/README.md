# StopCard

One itinerary stop: time · place · duration · leg · price with provenance · one-line reason · status.

- **Statuses:** `planned`, `booked` (hard constraint, volt edge + lock), `next` (signal ring, Live), `done`, `closed` (strikethrough + "Closed today", offer an alternative).
- **Consumer provides:** the strings (already formatted) and `provenance` for the price.
- Swipe left for Swap/Remove, long-press to drag (app). Screen readers get one sentence built from all fields.
