# PulseBadge

Arivo Pulse trend mark: lantern waveform + TrendScore + label; expands into the evidence behind it.

- Rendered **only** when evidence exists. Never show "Trending" without sources, counts and an update time.
- **Consumer provides:** `score` (0–100), `label`, `evidence[]` (the weighted TrendScore components), `facts[]`, `sources`, `updated`, `expanded`.
- TrendScore = .28 Burst + .20 Velocity + .16 Recency + .12 Source diversity + .10 Local event + .08 Local relevance + .06 Engagement quality, × spam penalty.
