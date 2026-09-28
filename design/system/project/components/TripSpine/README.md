# TripSpine

The Route Thread as a timeline: a dashed line in the day's `route-n` colour, nodes at stops, travel legs between them.

- **Consumer provides:** `day`, `title` (serif day title, e.g. the district), `routeColor`, `stops[]` (StopCard props plus `legAfter`).
- Days are planned around geographic zones, so the title names the zone ("Shibuya / Harajuku").
- On the map the same colour draws the route; during Rescue the thread morphs (dur-route, ease-emphasized).
