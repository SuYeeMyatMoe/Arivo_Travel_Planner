# ProvenanceTag

Tiny tag after a number that says where it came from: **LIVE** (provider data), **EST.** (Arivo computed) or **YOU** (traveller input).

- **Consumer provides:** `kind`, and `source` + `updated` for the spoken label and tooltip.
- Every price, time, distance, score and forecast carries one. A number with no source never ships.
- Colours: `provenance-live` / `provenance-est` / `provenance-you` (aliases of the *-text accents, AA on both themes).
