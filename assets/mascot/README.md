# Ari — the Arivo explorer mascot

Ari is Arivo Guide's face: a compact explorer who appears when the trip needs a companion (onboarding, Story Mode, Rescue, a finished day), never as constant decoration.

| File | Use |
|---|---|
| `ari_explorer.glb` (≈0.66 MB, meshopt) | Hero 3D moments in Flutter (`Ari3DView`, via `flutter_3d_controller`) and on the web |
| `ari_explorer.meta.json` | Machine-readable contract: clip names, durations, morph targets, node names |
| `sprites/ari_<state>.webp` + `sprites/manifest.json` | 4×4 sprite sheets (256 px cells, transparent) for the floating Guide button and chat bubbles (`AriSpriteView`) |
| `posters/*.webp` | Transparent 1024 px renders: hero poses and a turnaround for the design system |
| `source/miibot_source.glb` | Untouched base model (see attribution) |

Rebuild everything from source with `npm run build` in `tools/mascot-forge`. Refresh the sprites with `npm run preview`, then capture frames (see `tools/mascot-forge/README.md`) and run `node src/sprites.mjs`.

## Design

What makes Ari Arivo's own, rather than a copy of the reference boards' aviator/cape/scroll look:

- **Explorer bucket hat** in sand canvas. The band carries a dashed volt **route stitch**, which is the Route Thread motif, plus a **compass-star pin** and a **boarding pass** tucked in like an old press card.
- **Signal beacon** antenna. It glows signal-cyan and pulses faster while Ari listens or thinks.
- **Volt scarf** with wind-swept tails that flutter in every state.
- **Compass-core emblem.** It replaces the base model's "AI" chest logo. The needle is a node (`Needle`), so it can spin while Ari thinks, swing toward a target when pointing, and in custom renderers point at the next stop.
- **Glass visor face.** Emissive eyes and mouth sit on a fitted visor plate. Every expression comes from a morph target, not a texture swap.
- **Moulded vinyl shell.** The patchy generated texture is removed, and the scan is welded and Taubin-smoothed (280 passes) into a clean graphite body.

## States (glTF animation clips)

| Clip | Loop | Expression | Used for |
|---|---|---|---|
| `idle_float` | ✓ 4 s | gentle float + blinks | default, empty states |
| `listening` | ✓ 3 s | wide eyes, head tilt, fast beacon | mic open |
| `thinking` | ✓ 3 s | looks up, compass needle spins | planning / replanning in progress |
| `talking` | ✓ 1.6 s | mouth flaps (`talk` morph) | TTS playback, Story Mode |
| `pointing` | once 2 s → hold | lean + needle swings | "look here" on map / cards |
| `warning` | ✓ 2 s | concerned eyes, frown, beacon blink | disruption, budget exceeded (calm, not alarm) |
| `excited` | once 1.6 s | hop-spin, happy `^^` eyes, grin | booking confirmed, day completed |
| `offline` | ✓ 4 s | sleepy eyes, drooped, dim beacon | no connection |

Morph targets: `EyeL`/`EyeR` = `blink, happy, lookUp, concerned, sleepy, wide`; `Mouth` = `talk, frown, flat, ooh, grin`.

## Rive contract

The product spec calls for Rive. A `.riv` file can only be authored in the Rive editor, so it cannot be generated from code. The app is built against this contract so a designer-made `ari.riv` drops in without code changes:

- Artboard `Ari`, state machine `Ari`
- Number input `state`: 0 idle · 1 listening · 2 thinking · 3 talking · 4 pointing · 5 warning · 6 excited · 7 offline (same order as `AriState` in Flutter)
- Number inputs `lookX`, `lookY` (−1…1) for gaze, and `heading` (degrees) for the compass needle
- Trigger `blink`

Until `ari.riv` exists, `AriController` renders the sprite sheets (small) and the GLB (hero).

## Attribution (CC BY 4.0)

Ari is derived from **"Miibot 3D Model"** by **itsmejhade** (https://sketchfab.com/3d-models/miibot-3d-model-7606b66321934033a5dcfecf0f7925e5), licensed under CC BY 4.0 (http://creativecommons.org/licenses/by/4.0/).

Changes: the texture was removed and the shell remeshed and smoothed. Arivo added the hat, boarding pass, beacon, scarf, compass emblem, visor face, morph targets and animation clips. The credit also appears in the app's About screen.

For long-term brand ownership, commission an original base sculpt in the same silhouette. The forge pipeline can then re-apply the gear and animation.
