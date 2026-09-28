# Button

Pill button; `primary` (volt) marks the single main action on a screen.

- **Consumer provides:** `children` (the label), optional `icon`, `onClick`, `disabled`.
- **Variants:** `primary` (volt fill, text-on-volt), `tonal` (surface-raised with a line inset), `quiet` (underlined text), `danger` (ember fill for destructive confirms).
- One `primary` per screen. On the last checkout step the label **states the amount**: "Confirm & pay RM 1,243", never "Continue".
- Min height 48px; label in `label` style; focus ring `focus-ring`.
