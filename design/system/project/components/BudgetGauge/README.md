# BudgetGauge

Budget Brain ring: spent (solid), reserved (hatched), forecast (lantern dashed arc), remaining in the centre.

- **States** derive from forecast/total: on track · tight (> 92%) · over (> 100%, ember). *Over* pairs with a "Suggest savings" action.
- **Consumer provides:** `total`, `spent`, `reserved`, `forecast`, `currency`. The forecast is an estimate and carries EST.
