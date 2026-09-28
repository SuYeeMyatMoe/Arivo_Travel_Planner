export type Money = { amount_minor: number; currency: string };
export type Stop = {
  id: string;
  place_id: string;
  name: string;
  category: string;
  lat: number;
  lon: number;
  start: string;
  duration_min: number;
  reason: string;
  status: string;
  indoor: boolean;
  locked?: boolean;
  cost?: Money;
  leg?: { minutes: number; distance_m: number; mode: string };
  image?: string;
};
export type Day = {
  index: number;
  date: string;
  title: string;
  zone: string;
  items: Stop[];
};
export type Trip = {
  id: string;
  title: string;
  cities: string[];
  start_date: string;
  currency: string;
  timezone: string;
  days: Day[];
  intent: { crew_size: number; crew_type: string; interests?: string[] };
  crew: { user_id: string; display_name: string; role: string }[];
  budget?: { total: Money };
  demo?: boolean;
};
export type Change = {
  id: string;
  explanation: string;
  day_index: number;
  new_items: Stop[];
  kept: { name: string }[];
  moved: { name: string }[];
  removed: { name: string }[];
  added: { name: string }[];
};
export type Expense = {
  id: string;
  merchant: string;
  amount: number;
  currency: string;
  category: string;
};
export type GuideProposal = {
  kind: "trip_change" | "move_item" | "checkout";
  summary: string;
  confirm: {
    method: string;
    path?: string;
    body?: { action?: string; new_start?: string };
  };
  data?: { change?: Change };
};
export type ReceiptDraft = {
  merchant: string | null;
  total: number | null;
  currency: string;
  category: string;
  lines: { name: string; qty: number; amount: number }[];
  warnings: string[];
};
export type Destination = {
  id: string;
  name: string;
  country: string;
  line: string;
  image: string;
  tag: string;
  category: string;
  color: string;
  text: string;
  supported: boolean;
};

export const photos = {
  fuji: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?auto=format&fit=crop&w=1800&q=85",
  tokyo:
    "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?auto=format&fit=crop&w=900&q=80",
  kyoto:
    "https://images.unsplash.com/photo-1478436127897-769e1b3f0f36?auto=format&fit=crop&w=900&q=80",
  bali: "https://images.unsplash.com/photo-1537996194471-e657df975ab4?auto=format&fit=crop&w=900&q=80",
  italy:
    "https://images.unsplash.com/photo-1533105079780-92b9be482077?auto=format&fit=crop&w=900&q=80",
  kl: "https://images.unsplash.com/photo-1596422846543-75c6fc197f07?auto=format&fit=crop&w=900&q=80",
  food: "https://images.unsplash.com/photo-1519984388953-d2406bc725e1?auto=format&fit=crop&w=600&q=80",
};

export const destinations: Destination[] = [
  {
    id: "tokyo",
    name: "Tokyo",
    country: "Japan",
    line: "A beautiful kind of electric.",
    image: photos.tokyo,
    tag: "CITY & CULTURE",
    category: "Cities",
    color: "#ffd0a5",
    supported: true,
    text: "Find a slower rhythm between neon streets and quiet shrines. Wander Asakusa, follow your curiosity through the markets, and end the day above the city.",
  },
  {
    id: "bali",
    name: "Bali",
    country: "Indonesia",
    line: "Let the world slow down.",
    image: photos.bali,
    tag: "NATURE & SLOW LIVING",
    category: "Nature",
    color: "#bde7c0",
    supported: false,
    text: "Terraced rice fields, sea air and time to breathe. Save this island escape to your inspiration collection while we expand verified planning coverage.",
  },
  {
    id: "kyoto",
    name: "Kyoto",
    country: "Japan",
    line: "A little closer to timeless.",
    image: photos.kyoto,
    tag: "CULTURE & DISCOVERY",
    category: "Culture",
    color: "#ffc5be",
    supported: true,
    text: "Step through torii gates and lantern-lit lanes. Build a day around gardens, local kitchens and the small discoveries between the landmarks.",
  },
  {
    id: "kuala-lumpur",
    name: "Kuala Lumpur",
    country: "Malaysia",
    line: "A world of flavours, together.",
    image: photos.kl,
    tag: "FOOD & CITY LIFE",
    category: "Food",
    color: "#d9ed9f",
    supported: true,
    text: "Explore neighbourhood markets, contemporary architecture and a food culture that brings the city together. A great place for a one-day discovery or a longer stay.",
  },
  {
    id: "amalfi",
    name: "Amalfi Coast",
    country: "Italy",
    line: "Take the scenic way.",
    image: photos.italy,
    tag: "COAST & DAYDREAMS",
    category: "Beaches",
    color: "#b2dcf1",
    supported: false,
    text: "Sea-facing villages and winding coastal paths. Keep this idea for later; verified route planning for the Amalfi Coast is not available yet.",
  },
];

const stops: Omit<Stop, "start">[] = [
  {
    id: "sample-senso",
    place_id: "sample-senso",
    name: "Sensō-ji Temple",
    category: "Culture",
    lat: 35.7148,
    lon: 139.7967,
    duration_min: 90,
    reason: "Start with a little stillness at Asakusa’s celebrated temple.",
    status: "planned",
    indoor: false,
    image: photos.kyoto,
    cost: { amount_minor: 0, currency: "JPY" },
  },
  {
    id: "sample-nakamise",
    place_id: "sample-nakamise",
    name: "Nakamise Shopping Street",
    category: "Local discovery",
    lat: 35.7118,
    lon: 139.7964,
    duration_min: 60,
    reason: "Browse small shops and leave room for a street-side snack.",
    status: "planned",
    indoor: false,
    image: photos.tokyo,
    cost: { amount_minor: 1500, currency: "JPY" },
    leg: { minutes: 4, distance_m: 300, mode: "walk" },
  },
  {
    id: "sample-lunch",
    place_id: "sample-lunch",
    name: "A taste of Asakusa",
    category: "Food",
    lat: 35.7104,
    lon: 139.7945,
    duration_min: 60,
    reason: "An unhurried lunch break. Pick a restaurant when you arrive.",
    status: "planned",
    indoor: true,
    image: photos.food,
    cost: { amount_minor: 2200, currency: "JPY" },
    leg: { minutes: 5, distance_m: 350, mode: "walk" },
  },
  {
    id: "sample-skytree",
    place_id: "sample-skytree",
    name: "Tokyo Skytree",
    category: "Views",
    lat: 35.7101,
    lon: 139.8107,
    duration_min: 90,
    reason: "A new perspective on the city, from above.",
    status: "planned",
    indoor: true,
    image: photos.tokyo,
    cost: { amount_minor: 2500, currency: "JPY" },
    leg: { minutes: 22, distance_m: 1600, mode: "walk" },
  },
  {
    id: "sample-sumida",
    place_id: "sample-sumida",
    name: "Sumida riverside walk",
    category: "Nature",
    lat: 35.7108,
    lon: 139.8038,
    duration_min: 60,
    reason: "Wind down by the water with no reservations to rush to.",
    status: "planned",
    indoor: false,
    image: photos.fuji,
    cost: { amount_minor: 0, currency: "JPY" },
    leg: { minutes: 12, distance_m: 900, mode: "walk" },
  },
];
const baseDate = "2026-10-12";
export const sampleTrip: Trip = {
  id: "sample-tokyo",
  title: "A little love letter to Tokyo",
  cities: ["tokyo"],
  start_date: baseDate,
  currency: "JPY",
  timezone: "Asia/Tokyo",
  intent: {
    crew_size: 2,
    crew_type: "couple",
    interests: ["Culture", "Food", "Nature"],
  },
  crew: [{ user_id: "you", display_name: "You", role: "owner" }],
  budget: { total: { amount_minor: 180000, currency: "JPY" } },
  demo: true,
  days: [
    {
      index: 0,
      date: baseDate,
      title: "Old soul, new discoveries",
      zone: "Asakusa & Sumida",
      items: stops.map((s, i) => ({
        ...s,
        start: `${baseDate}T${["09:00", "10:45", "12:00", "14:00", "16:00"][i]}:00`,
      })),
    },
    {
      index: 1,
      date: "2026-10-13",
      title: "Green spaces & city lights",
      zone: "Shibuya & Harajuku",
      items: [
        {
          ...stops[0],
          id: "sample-meiji",
          name: "Meiji Shrine",
          lat: 35.6764,
          lon: 139.6993,
          start: "2026-10-13T09:00:00",
          reason: "A quiet forest walk in the middle of the city.",
        },
        {
          ...stops[1],
          id: "sample-harajuku",
          name: "Harajuku backstreets",
          lat: 35.6702,
          lon: 139.7044,
          start: "2026-10-13T11:00:00",
        },
        {
          ...stops[3],
          id: "sample-shibuya",
          name: "Shibuya Crossing",
          lat: 35.6595,
          lon: 139.7004,
          start: "2026-10-13T15:00:00",
          cost: { amount_minor: 0, currency: "JPY" },
          reason: "Watch the city move at its own remarkable pace.",
        },
      ],
    },
    {
      index: 2,
      date: "2026-10-14",
      title: "Art, gardens & a little wandering",
      zone: "Ueno",
      items: [
        {
          ...stops[4],
          id: "sample-ueno",
          name: "Ueno Park",
          lat: 35.7146,
          lon: 139.774,
          start: "2026-10-14T09:30:00",
          reason: "Make room for an easy morning outdoors.",
        },
        {
          ...stops[2],
          id: "sample-museum",
          name: "Tokyo National Museum",
          lat: 35.7188,
          lon: 139.7765,
          start: "2026-10-14T12:00:00",
          reason: "An afternoon for Japanese art and history.",
          category: "Culture",
        },
      ],
    },
  ],
};

export function money(value: number, currency = "JPY") {
  return new Intl.NumberFormat("en", {
    style: "currency",
    currency,
    maximumFractionDigits: currency === "JPY" ? 0 : 2,
  }).format(value);
}
export function fromMinor(value: Money) {
  return (
    value.amount_minor /
    (["JPY", "KRW", "VND", "IDR"].includes(value.currency) ? 1 : 100)
  );
}
export function dayLabel(
  date: string,
  options: Intl.DateTimeFormatOptions = { month: "short", day: "numeric" },
) {
  return new Date(date + "T12:00:00").toLocaleDateString("en", options);
}
export function routeCoordinates(items: Stop[]): [number, number][] {
  return items
    .filter(
      (i) =>
        Number.isFinite(i.lon) &&
        Number.isFinite(i.lat) &&
        Math.abs(i.lon) <= 180 &&
        Math.abs(i.lat) <= 90,
    )
    .map((i) => [i.lon, i.lat]);
}
export function expenseTotal(expenses: Expense[], currency: string) {
  return expenses
    .filter((e) => e.currency === currency)
    .reduce((sum, e) => sum + e.amount, 0);
}
// Only these two reviewed itinerary operations can be applied from a guide reply.
// Never execute arbitrary model-provided URLs or checkout/payment instructions.
export function guideAction(
  tripId: string,
  proposal: GuideProposal,
): { path: string; body: unknown } | null {
  const prefix = `/v1/trips/${tripId}/`,
    path = proposal.confirm.path;
  if (proposal.confirm.method !== "POST" || !path?.startsWith(prefix))
    return null;
  const suffix = path.slice(prefix.length);
  if (
    proposal.kind === "trip_change" &&
    /^changes\/[a-zA-Z0-9_-]+\/apply$/.test(suffix)
  )
    return { path, body: {} };
  const body = proposal.confirm.body;
  if (
    proposal.kind === "move_item" &&
    /^items\/[a-zA-Z0-9_-]+$/.test(suffix) &&
    body?.action === "move" &&
    /^([01]\d|2[0-3]):[0-5]\d$/.test(body.new_start ?? "")
  )
    return { path, body: { action: "move", new_start: body.new_start } };
  return null;
}
export function isTrip(value: unknown): value is Trip {
  if (!value || typeof value !== "object") return false;
  const t = value as Trip;
  return (
    typeof t.id === "string" &&
    typeof t.title === "string" &&
    Array.isArray(t.cities) &&
    t.cities.length > 0 &&
    Array.isArray(t.days) &&
    t.days.length > 0 &&
    t.days.every((d) => typeof d.date === "string" && Array.isArray(d.items)) &&
    !!t.intent &&
    Array.isArray(t.crew)
  );
}
export function storedTrip(): Trip {
  const value = readLocal<unknown>("arivo.trip", null);
  return isTrip(value) ? value : sampleTrip;
}
export function readLocal<T>(key: string, fallback: T): T {
  try {
    const data = localStorage.getItem(key);
    return data ? JSON.parse(data) : fallback;
  } catch {
    return fallback;
  }
}
export function writeLocal(key: string, value: unknown): boolean {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}
