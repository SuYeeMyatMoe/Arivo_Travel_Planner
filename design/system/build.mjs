// Generates the component READMEs, live previews and index.d.ts for the Arivo design-system artifact.
// Source of truth for behaviour is design/DESIGN.md; tokens come from design/system/project/tokens.json.
// Usage: node design/system/build.mjs
import { writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const OUT = resolve(import.meta.dirname, 'project/components');

const components = [
  {
    name: 'Button', group: 'Actions', height: 150,
    readme: `Pill button; \`primary\` (volt) marks the single main action on a screen.

- **Consumer provides:** \`children\` (the label), optional \`icon\`, \`onClick\`, \`disabled\`.
- **Variants:** \`primary\` (volt fill, text-on-volt), \`tonal\` (surface-raised with a line inset), \`quiet\` (underlined text), \`danger\` (ember fill for destructive confirms).
- One \`primary\` per screen. On the last checkout step the label **states the amount**: "Confirm & pay RM 1,243", never "Continue".
- Min height 48px; label in \`label\` style; focus ring \`focus-ring\`.`,
    props: `variant?: 'primary' | 'tonal' | 'quiet' | 'danger'; icon?: string; children: string; onClick?: () => void; disabled?: boolean`,
    preview: `h('div', { className: 'row' },
      h(A.Button, null, 'Confirm & pay RM 1,243'),
      h(A.Button, { variant: 'tonal' }, 'Keep original plan'),
      h(A.Button, { variant: 'quiet' }, 'Why this?'),
      h(A.Button, { variant: 'danger' }, 'Cancel booking'),
      h(A.Button, { disabled: true }, 'Booking needs internet'))`,
  },
  {
    name: 'ProvenanceTag', group: 'Trust', height: 110,
    readme: `Tiny tag after a number that says where it came from: **LIVE** (provider data), **EST.** (Arivo computed) or **YOU** (traveller input).

- **Consumer provides:** \`kind\`, and \`source\` + \`updated\` for the spoken label and tooltip.
- Every price, time, distance, score and forecast carries one. A number with no source never ships.
- Colours: \`provenance-live\` / \`provenance-est\` / \`provenance-you\` (aliases of the *-text accents, AA on both themes).`,
    props: `kind: 'live' | 'est' | 'you'; source?: string; updated?: string`,
    preview: `h('div', { className: 'stack' },
      h('p', { className: 'mono-m' }, '18°C Light rain', h(A.ProvenanceTag, { kind: 'live', source: 'Open-Meteo', updated: '12 min ago' })),
      h('p', { className: 'mono-m' }, '14 min by train', h(A.ProvenanceTag, { kind: 'est', source: 'Arivo route estimate' })),
      h('p', { className: 'mono-m' }, 'Budget RM 4,000', h(A.ProvenanceTag, { kind: 'you' })))`,
  },
  {
    name: 'StatusChip', group: 'Trust', height: 100,
    readme: `Status pill with an icon and a word, never colour alone.

- **Tones:** \`confirmed\`, \`pending\`, \`failed\`, \`cancelled\`, \`sandbox\`, \`offline\`, \`closed\`, \`booked\`.
- \`sandbox\` appears on every sandbox offer, checkout and confirmation and is never dismissible.
- **Consumer provides:** \`tone\`, optional \`children\` to override the default word.`,
    props: `tone: 'confirmed' | 'pending' | 'failed' | 'cancelled' | 'sandbox' | 'offline' | 'closed' | 'booked'; children?: string`,
    preview: `h('div', { className: 'row' }, ['confirmed', 'pending', 'booked', 'sandbox', 'offline', 'closed', 'failed'].map(function (t) { return h(A.StatusChip, { key: t, tone: t }); }))`,
  },
  {
    name: 'StopCard', group: 'Trip', height: 330,
    readme: `One itinerary stop: time · place · duration · leg · price with provenance · one-line reason · status.

- **Statuses:** \`planned\`, \`booked\` (hard constraint, volt edge + lock), \`next\` (signal ring, Live), \`done\`, \`closed\` (strikethrough + "Closed today", offer an alternative).
- **Consumer provides:** the strings (already formatted) and \`provenance\` for the price.
- Swipe left for Swap/Remove, long-press to drag (app). Screen readers get one sentence built from all fields.`,
    props: `time: string; place: string; duration?: string; leg?: string; price?: string; provenance?: 'live' | 'est' | 'you'; source?: string; reason?: string; status?: 'planned' | 'booked' | 'next' | 'done' | 'closed'; dayColor?: string`,
    preview: `h('div', { className: 'stack' },
      h(A.StopCard, { time: '09:30', place: 'Senso-ji', duration: '75 min', leg: '12 min from hotel', price: 'Free', provenance: 'live', source: 'Official site', reason: 'Best early to avoid heavier crowds.', status: 'next' }),
      h(A.StopCard, { time: '19:30', place: 'Dinner at Uogashi Nihon-Ichi', duration: '90 min', leg: '8 min walk', price: 'RM 180', provenance: 'you', reason: 'Your reservation — Rescue keeps this fixed.', status: 'booked' }),
      h(A.StopCard, { time: '14:00', place: 'Ueno Park walk', duration: '60 min', price: 'Free', provenance: 'est', status: 'closed', reason: 'Heavy rain from 13:40 — 2 indoor alternatives nearby.' }))`,
  },
  {
    name: 'TripSpine', group: 'Trip', height: 520,
    readme: `The Route Thread as a timeline: a dashed line in the day's \`route-n\` colour, nodes at stops, travel legs between them.

- **Consumer provides:** \`day\`, \`title\` (serif day title, e.g. the district), \`routeColor\`, \`stops[]\` (StopCard props plus \`legAfter\`).
- Days are planned around geographic zones, so the title names the zone ("Shibuya / Harajuku").
- On the map the same colour draws the route; during Rescue the thread morphs (dur-route, ease-emphasized).`,
    props: `day: string; title: string; routeColor?: string; stops: Array<StopCardProps & { legAfter?: { mode: 'walk' | 'train' | 'bus' | 'flight'; label: string } }>`,
    preview: `h(A.TripSpine, { day: 'Day 2 · Tue 17 Nov', title: 'Shibuya / Harajuku', routeColor: 'route-2', stops: [
      { time: '09:30', place: 'Meiji Jingu', duration: '60 min', price: 'Free', provenance: 'live', reason: 'Quiet before 10:00.', status: 'done', legAfter: { mode: 'walk', label: 'Walk · 11 min' } },
      { time: '10:45', place: 'Takeshita Street', duration: '75 min', price: '≈ RM 40', provenance: 'est', reason: 'Street food + your anime picks.', status: 'next', legAfter: { mode: 'train', label: 'JR Yamanote · 4 min' } },
      { time: '12:30', place: 'Shibuya Sky', duration: '70 min', price: 'RM 74', provenance: 'live', reason: 'Booked slot · photography at golden hour moved to 16:40.', status: 'booked' }
    ] })`,
  },
  {
    name: 'PulseBadge', group: 'Arivo Pulse', height: 330,
    readme: `Arivo Pulse trend mark: lantern waveform + TrendScore + label; expands into the evidence behind it.

- Rendered **only** when evidence exists. Never show "Trending" without sources, counts and an update time.
- **Consumer provides:** \`score\` (0–100), \`label\`, \`evidence[]\` (the weighted TrendScore components), \`facts[]\`, \`sources\`, \`updated\`, \`expanded\`.
- TrendScore = .28 Burst + .20 Velocity + .16 Recency + .12 Source diversity + .10 Local event + .08 Local relevance + .06 Engagement quality, × spam penalty.`,
    props: `score: number; label: string; expanded?: boolean; evidence?: Array<{ name: string; weight: number; value: string }>; facts?: string[]; sources?: number; updated?: string`,
    preview: `h(A.PulseBadge, { score: 86, label: 'Rising this week', expanded: true, sources: 4, updated: '18 min ago',
      evidence: [ { name: 'Burst vs baseline', weight: 0.28 * 0.9, value: '+64%' }, { name: 'Velocity', weight: 0.2 * 0.8, value: '0.80' }, { name: 'Recency', weight: 0.16 * 0.95, value: '2 d' }, { name: 'Source diversity', weight: 0.12 * 0.7, value: '4' }, { name: 'Local event', weight: 0.1, value: 'Sat' } ],
      facts: ['Night market opens this weekend (city event calendar)', '3 travel publications this week'] })`,
  },
  {
    name: 'ChangeDiff', group: 'Living Trip', height: 460,
    readme: `What Rescue My Day or Plan B changed: **Kept · Moved · Removed · Added**, with the time and budget change.

- **Consumer provides:** \`timeDelta\` (string), \`budgetDelta\` (number, negative = saving), \`currency\`, \`groups\`.
- Booked items are always in Kept. Nothing applies until the traveller taps *Apply changes*; *Keep original* sits beside it.
- Announces counts to screen readers ("1 moved, 1 removed, 2 added").`,
    props: `timeDelta: string; budgetDelta: number; currency: string; groups: { kept?: Item[]; moved?: Item[]; removed?: Item[]; added?: Item[] }  // Item = { name; from?; to?; reason?; detail? }`,
    preview: `h(A.ChangeDiff, { timeDelta: '−1 h 20', budgetDelta: -42, currency: 'MYR', groups: {
      kept: [{ name: 'Dinner at Uogashi (booked)' }, { name: 'Shibuya Sky 12:30 (booked)' }],
      moved: [{ name: 'Tokyo National Museum', from: '16:00', to: '13:50' }],
      removed: [{ name: 'Ueno Park walk', reason: 'Heavy rain 13:40–17:00' }],
      added: [{ name: 'teamLab Planets', detail: '18 min by train · RM 74' }, { name: 'Ameyoko covered market', detail: 'Street food, indoors' }] } })`,
  },
  {
    name: 'BudgetGauge', group: 'Budget Brain', height: 200,
    readme: `Budget Brain ring: spent (solid), reserved (hatched), forecast (lantern dashed arc), remaining in the centre.

- **States** derive from forecast/total: on track · tight (> 92%) · over (> 100%, ember). *Over* pairs with a "Suggest savings" action.
- **Consumer provides:** \`total\`, \`spent\`, \`reserved\`, \`forecast\`, \`currency\`. The forecast is an estimate and carries EST.`,
    props: `total: number; spent: number; reserved?: number; forecast: number; currency: string`,
    preview: `h(A.BudgetGauge, { total: 4000, spent: 1620, reserved: 1300, forecast: 3720, currency: 'MYR' })`,
  },
  {
    name: 'LocationFitMeter', group: 'Stays', height: 150,
    readme: `How well a hotel serves *this* itinerary (HotelTripFit), shown as a meter and a plain sentence.

- **Consumer provides:** \`score\` (0–100) and \`sentence\` computed from real travel times ("8 of 10 planned stops under 25 min").
- Never rank stays by stars alone; this meter leads the hotel card.`,
    props: `score: number; sentence?: string`,
    preview: `h(A.LocationFitMeter, { score: 94, sentence: '8 of your 10 planned stops are under 25 minutes away · 12 min average.' })`,
  },
  {
    name: 'BoardingPassCard', group: 'Bookings', height: 380,
    readme: `Booking as a ticket: route stub, perforation (the Route Thread), status and reference.

- **Kinds:** \`flight\`, \`stay\`, \`bus\`, \`rail\`. **Statuses:** \`confirmed\`, \`pending\` ("Confirming with airline"), \`failed\` (with the compensation note), \`cancelled\`, \`offline\` (served from the Booking Vault).
- \`sandbox: true\` adds the non-dismissible SANDBOX chip.
- **Consumer provides:** all display strings; references in mono.`,
    props: `kind: 'flight' | 'stay' | 'bus' | 'rail'; carrier: string; from: string; to: string; depart: string; arrive: string; date: string; reference: string; status?: 'confirmed' | 'pending' | 'failed' | 'cancelled' | 'offline'; sandbox?: boolean; note?: string`,
    preview: `h('div', { className: 'stack' },
      h(A.BoardingPassCard, { kind: 'flight', carrier: 'Duffel Airways · ZZ 812', from: 'KUL', to: 'NRT', depart: '07:30', arrive: '15:20', date: 'Mon 16 Nov · 1 stop · 7h50', reference: 'H92F3K', status: 'confirmed', sandbox: true }),
      h(A.BoardingPassCard, { kind: 'rail', carrier: 'Tokaido Shinkansen', from: 'Tokyo', to: 'Kyoto', depart: '09:33', arrive: '11:48', date: 'Thu 19 Nov', reference: 'Pending', status: 'pending', note: 'Confirming with supplier — never re-booked automatically.' }))`,
  },
  {
    name: 'PriceBreakdown', group: 'Bookings', height: 400,
    readme: `Every fee before payment, plus the price-changed banner that forces reconfirmation.

- **Consumer provides:** \`lines[]\` (base, taxes, fees, baggage, booking fee), \`total\`, \`currency\`, \`terms[]\` (cancellation/change in plain words), \`changedFrom\` when revalidation moved the price, \`action\` label.
- A changed price is never charged silently; the CTA restates the new total.`,
    props: `currency: string; lines: Array<{ label: string; amount: number }>; total: number; changedFrom?: number; terms?: string[]; action?: string`,
    preview: `h(A.PriceBreakdown, { currency: 'MYR', changedFrom: 1280, total: 1347, action: 'Confirm & pay RM 1,347',
      lines: [ { label: 'Base fare', amount: 1102 }, { label: 'Taxes', amount: 187 }, { label: 'Checked bag (23 kg)', amount: 58 }, { label: 'Booking fee', amount: 0 } ],
      terms: ['Changes allowed · RM 150 fee + fare difference', 'Refund on cancellation: taxes only (RM 187)'] })`,
  },
  {
    name: 'CrewConstellation', group: 'Arivo Crew', height: 330,
    readme: `Arivo Crew overview: members as stars in their \`crew-n\` colours, shared interests as lines, conflicts as dashed ember lines, then a balance row per person.

- No ranking, no winner. The balance row shows whose interests today serves and notes compromise.
- **Consumer provides:** \`members[]\`, \`links[]\` ({a, b, label, conflict}), \`balance[]\` ({name, share, note}).`,
    props: `members: Array<{ name: string }>; links?: Array<{ a: number; b: number; label?: string; conflict?: boolean }>; balance?: Array<{ name: string; share: number; note?: string }>; label?: string`,
    preview: `h(A.CrewConstellation, { label: 'Crew of four: shared food, a nightlife conflict',
      members: [{ name: 'Alex' }, { name: 'Mia' }, { name: 'Sam' }, { name: 'Jo' }],
      links: [ { a: 0, b: 1, label: 'nightlife', conflict: true }, { a: 1, b: 2, label: 'photography' }, { a: 2, b: 3, label: 'street food' }, { a: 3, b: 0, label: 'food' } ],
      balance: [ { name: 'Alex', share: 25, note: 'Evening: Golden Gai' }, { name: 'Mia', share: 30, note: 'Morning: museum' }, { name: 'Sam', share: 22, note: 'Lunch: Ameyoko' }, { name: 'Jo', share: 23, note: 'Sunset: Shibuya Sky' } ] })`,
  },
];

const previewDoc = (c) => `<!-- @dsCard group="${c.group}" height=${c.height} -->
<!doctype html>
<html>
<head><meta charset="utf-8"><title>${c.name} — preview</title>
<style>
  body { padding: 16px; }
  .row { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
  .stack { display: grid; gap: 12px; max-width: 460px; }
  .stack p { margin: 0; }
</style></head>
<body>
<div id="root"></div>
<script>
  var A = window.Arivo, h = React.createElement;
  ReactDOM.createRoot(document.getElementById('root')).render(${c.preview});
</script>
</body>
</html>
`;

for (const c of components) {
  const dir = resolve(OUT, c.name);
  await mkdir(dir, { recursive: true });
  await writeFile(resolve(dir, 'README.md'), `# ${c.name}\n\n${c.readme}\n`);
  await writeFile(resolve(dir, 'preview.html'), previewDoc(c));
}

const dts = `// Arivo design-system components (window.Arivo). React 18. Types are documentation.
${components.map((c) => `export interface ${c.name}Props { ${c.props} }\nexport declare function ${c.name}(props: ${c.name}Props): JSX.Element;`).join('\n\n')}
`;
await writeFile(resolve(OUT, 'index.d.ts'), dts);
console.log(`wrote ${components.length} components`);
