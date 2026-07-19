# PAYMENT-STATEMENT-KEYBOARD-001

## Goal

Keep the focused mobile `Sao kê` filter visible when the iOS or Android
software keyboard opens, without changing the existing desktop statement
workspace or bank-statement data behavior.

## Accepted Behavior

- On compact widths, the filter panel, state banners, and statement results use
  one vertical scrollable viewport.
- Opening the software keyboard does not cause a `RenderFlex` overflow.
- The focused filter is scrolled into the visible body above the keyboard.
- Dragging the mobile statement viewport dismisses the keyboard.
- Wide layouts keep the existing fixed filter header and independently
  scrollable result list.
- `AppLogger` records keyboard-avoidance start, success, and failure with only
  the filter name, keyboard inset, and duration; entered values are never logged.
- The app keeps Flutter's active light/dark keyboard appearance. Visual colors
  and transparency inside a third-party iOS keyboard such as Laban Key remain
  owned by that keyboard extension.

## Protected Existing Behavior

- Mobile filters still expand/collapse and collapse after a successful search.
- Statement loading, empty, error, pagination, selection, and result-card flows
  remain available in the same mobile scroll viewport.
- Desktop/tablet statement list geometry and independent list scrolling remain
  unchanged.
- Existing income-type work already present in the dirty checkpoint is not part
  of this story or its commit.
