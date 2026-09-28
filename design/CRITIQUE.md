# Design critique: EscapeSync reference boards → Arivo

Eight reference boards (48 screens) covering hero, trip creation, itinerary, rescue, Trend Pulse, crew, budget/hotels/food, live mode, computer vision and offline/privacy.

## What to keep
| Strength | Why it works | Arivo carries it as |
|---|---|---|
| Navy + warm off-white + lime accent family | Premium, travel-editorial, distinct from typical blue SaaS | Ink / Paper / Volt tokens |
| Serif destination names ("Tokyo", "Japan") | Editorial, emotional, instantly scannable | Instrument Serif, one display line per screen |
| Map-first planner with a timeline sheet | The trip is spatial; the map shows the real shape of a day | Explore and Trip are map-first; Trip Spine sits in a bottom sheet |
| KEPT / MOVED / REMOVED / ADDED | Makes AI replanning auditable | `ChangeDiff` component |
| Location Fit % on hotels | Ranks hotels by *your* trip, not by stars | `LocationFitMeter` + HotelTripFit score |
| A warm mascot | Humanises AI moments | Ari, used sparingly |

## What to fix
| # | Problem (where) | Impact | Arivo fix |
|---|---|---|---|
| 1 | Every screen is the same stack of rounded photo cards | No signature; the product feels like a template | The **Route Thread** runs through map, spine, rescue morph and ticket perforations |
| 2 | Lime CTA on almost every screen, often two per screen | The accent stops meaning "primary" | One volt per screen; secondary actions are tonal |
| 3 | Mascot on ~70% of screens (splash, hub, budget, food, crew, CV) | Noise; competes with content; contradicts "should not interrupt" | Ari appears in onboarding, Story, Rescue, celebrations and the FAB only; bubbles at most once per visit |
| 4 | Unverifiable numbers: "32.6K mentions", "+320% increase", "1M+ Happy Travelers", "12.4K likes" | Violates the evidence rule; erodes trust once users notice | No number without a source; Pulse shows its evidence breakdown |
| 5 | 9–10 px captions; grey-on-navy text (live, rescue, crew) | Fails WCAG AA; unreadable outdoors | 12 px minimum; every text pair validated ≥ 4.5:1 in CI (`tools/tokens/build.mjs`) |
| 6 | Tab bars differ between boards (Explore/Trips/Assistant/Saved/Profile vs Home/Explore/Trips/Profile) | Inconsistent mental model | Four tabs everywhere: Explore · Trip · Live · You + GuideFab |
| 7 | Sparkle emoji stands for "AI" | Generic AI look | AI is shown by what it did (diff, evidence, provenance), not by decoration |
| 8 | Light and dark screens alternate with no rule | Users can't tell which mode they are in | Ink = in the trip, Paper = planning |
| 9 | Stock-photo dependence | Licensing risk and fake-looking; breaks when no photo exists | Licensed Commons photos with attribution; generated map-tile fallback |
| 10 | NFC postcard / BLE Hardware Lab inside the core app | Scope creep; spec removes NFC | Removed |
| 11 | "Budget Brain" donut shows spent only | No forecast, no reserved amounts, no provenance | BudgetGauge shows spent, reserved, forecast and remaining |
| 12 | Gesture navigation as a hero feature | Low utility on phones; accessibility risk | Deferred; Receipt Lens is the one CV feature in the MVP |
| 13 | Crew "Venn diagram" | Breaks down beyond three people; implies overlap equals fairness | Crew Constellation + Balance bars with no ranking |
| 14 | Trend cards identical to normal cards except for a pill | Pulse is hard to tell apart and has no "why" | Lantern hairline + PulseBadge + EvidenceSheet |

## Priority for the build
1. The Route Thread across Trip Spine, map and ChangeDiff, since it is the identity carrier.
2. Provenance tags on every number, since trust underpins the whole product.
3. The one-volt rule and the contrast gate, both cheap to enforce from day one.
4. Mascot restraint, enforced through `AriController` rules rather than designer discipline.
