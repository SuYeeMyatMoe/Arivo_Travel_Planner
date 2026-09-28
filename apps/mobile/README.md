# Arivo mobile (Flutter)

See the repository README for setup and the demo script.

- `lib/core/`: theme (generated tokens), network (`ArivoApi`), models, formatting, shared UI (`primitives`, `trip_widgets`, `commerce_widgets`), Ari (sprite + 3D).
- `lib/features/`: onboarding, explore, trip, book, live, you, crew, lens, guide.
- `lib/state/providers.dart`: current trip, budget, bookings, selected day, demo clock.

API base: `--dart-define=ARIVO_API=...` (default `http://localhost:8787`).
Dev identity: `--dart-define=ARIVO_DEV_USER=...` (dev auth only; production uses Supabase sessions).
