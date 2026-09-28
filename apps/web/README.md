# Arivo web

The responsive React + Three.js redesign uses the existing FastAPI service. It includes Discover, destination saving, trip creation, daily itineraries, 3D maps, reviewed replanning, Ari chat, budget tracking, receipt-text extraction, crew preferences, and stay/flight search with explicit checkout review. The native Flutter application remains in `../mobile`.

## Start

From the repository root, start the API:

```powershell
services/api/.venv/Scripts/python.exe -m uvicorn app.main:app --app-dir services/api --host 127.0.0.1 --port 8787
```

In another terminal:

```powershell
cd apps/web
npm ci
npm run dev
```

Open http://127.0.0.1:5181. The development server proxies API requests. With no API, the labelled sample journey, local saved destinations, and 3D map remain available. The default API store is in memory: restarting it removes generated server trips. Create a new trip after a restart, or configure the existing persistent backend.

## Maps

No account or key is needed by default. MapLibre uses OpenFreeMap tiles with extruded buildings, selectable itinerary markers, and a 2D/3D toggle. Attribution stays visible. Connecting lines show itinerary order; use the Directions button for actual navigation.

For Mapbox, copy `.env.example` to `.env.local` and set:

```dotenv
VITE_MAPBOX_TOKEN=pk.your_public_token
```

Restart Vite. Only public `pk.` tokens are accepted. Restrict the token to your deployment URLs in Mapbox. Mapbox Standard supplies 3D buildings and a dusk basemap; map failures offer the free provider. Mapbox currently includes 50,000 web map loads per month, then charges for additional usage; it is not unlimited free. See [Mapbox pricing](https://www.mapbox.com/pricing) and [OpenFreeMap quick start](https://openfreemap.org/quick_start/). No Mapbox token was available during local verification, so that provider still needs an account-backed smoke test.

## Motion and performance

- Three.js mascot and map engines are separate lazy-loaded chunks. Mapbox is fetched only when its provider is used.
- Mascot rendering is capped at 30 fps and 1.5 device pixel ratio; it pauses off screen and when the tab is hidden. Resources are disposed on unmount.
- Reduced-motion preferences and the in-app animation switch disable decorative motion. WebGL failure keeps a static mascot and a readable itinerary.
- Self-hosted fonts, responsive image sizes, lazy destination images, keyboard-visible focus, native modal focus handling, and mobile navigation.
- The Mapbox SDK is large and produces a build size warning, but is excluded from the initial page bundle. External tile/image speed depends on the network; no Lighthouse score is claimed.

## Production integration

`npm run build` creates `dist/`. Serve it over HTTPS and proxy `/v1` to the existing API, or set `VITE_API_URL` at build time and configure backend CORS for that origin.

Development uses the API's local-only `Dev traveler-web` identity. Production builds never send that header. Connect your authenticated session to `setSessionToken()` in `src/lib/api.ts` before enabling account actions; a production login flow is not included in this visual rewrite. Keep provider secrets on the API. Frontend `VITE_*` values are public.

The backend supplies planning coverage, sources, pricing, and sandbox/live states. Verified planning currently covers Tokyo, Kyoto, and Kuala Lumpur; Bali and Amalfi are inspiration cards. Receipt text parsing works on web; camera OCR remains in the native app. Guide edits require review and can only target the current trip. Booking payment is available only through an explicit human confirmation; automated validation does not execute it. Native offline packs, camera lenses, and hardware integrations have not been ported to web.

## Checks

```powershell
npm test
npm run build
npm audit
```

Tests cover longitude/latitude order, currency units, expense-currency isolation, persisted trip recovery, and guide-action restrictions. Visual assets use the repository's Ari GLB/poster and Unsplash destination photos. Typography is DM Sans and DM Serif Display under their bundled OFL licenses.
