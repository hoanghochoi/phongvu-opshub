# OPS-53 — FIFO result runtime layout fix

## Checkpoint

- Branch: `codex/ops-53-fifo-metadata-alignment-full-sku-card`
- Base: `0eaebfeaec2a90e9d37295dc35316dc709a543ec` (exact `origin/staging`)
- Trigger: authenticated staging screenshots show metadata pills stacking,
  clipping and overlapping the export control.

## Approved node map

| Viewport/state | Figma node | Flutter target | Geometry contract |
| --- | --- | --- | --- |
| Desktop FIFO results | `2285:64848`, card `2285:65033` | serial body and SKU item cards | Card anatomy: accent 8; body padding 24; title/status row; metadata wrap; pills 40 high; gaps 12; export row 48 when applicable. SKU repeats the same anatomy per item. |
| Compact FIFO results | `2288:23647`, card `2288:23705` | compact serial body and SKU item cards | Card anatomy: accent 7; title then status pill on the same left axis with a 4px gap; pill visual 30; every pill shrink-wraps icon + gaps + copy + horizontal padding; the metadata container wraps complete pills by their intrinsic width. SKU repeats the same anatomy per item. |
| Compact serial scrolled | `2289:23723`, card `2289:23734` | same compact body | Same pill and non-overlap geometry after command area scrolls away |
| Shared compact pill | `2305:56165` | `AppMetadataPill`, `AppActionPill`, `_FifoBadge` | visual 30; label 12; icon 14; horizontal padding 10; gap 6; action hit target at least 48 |
| Shared inventory card runtime reference | same approved FIFO nodes; proven consumer `SortSKUGroupWidget._SortItemCard` | `AppInventoryResultCard` consumed by Sort and FIFO Check | One anatomy for accent, title/status, aligned `AppInfoChip` metadata wrap and contextual checkbox action. SKU check renders every item with the full six-field card. |

Visible elements covered: product title, status pill, serial/SKU/date/age/location/
BIN-type pills, copy icons, status accent and export checkbox/label. FIFO/API,
permission, recent-search and export behavior remain unchanged.

## Root cause and bounded fix

- Desktop interactive metadata pills expose a 48px layout box although Figma
  requires a 40px wrap item; two runs overflow the fixed 92px wrap.
- The desktop body column is not stretched to full width, so its wrap receives
  intrinsic constraints and collapses horizontally.
- Make desktop action pills retain a 48dp hit target without increasing their
  40px layout footprint, stretch the desktop column, and assert exact rect
  relationships/no overlap.
- SKU-result reuses the approved desktop/mobile card anatomy above. Remove the
  fixed 62px spacer, 130px product-title constraint and absolute stack; do not
  create a separate Figma contract for the repeated list form.
- Follow-up staging proof showed fixed metadata row columns stretching the date
  and location pills and leaving uneven gaps. Remove fixed row/column widths,
  text caps and font shrinking. Both compact and desktop metadata use one
  content-sized `Wrap`; a pill stays on one line and moves as a whole when the
  remaining run width is insufficient. Replace the fixed 84px title/status
  stack with natural column flow so the status pill follows the rendered title
  and shares its left edge.
- Latest staging proof showed interactive metadata pills using a 48px outer
  footprint beside 30px static pills, shifting their centerlines. Consolidate
  both Sort and Check on one shared inventory result card and `AppInfoChip`
  footprint. The SKU lookup path must no longer use its reduced three-field
  card; every item renders the same full card as serial lookup, with the FIFO
  Check export action preserved.

## Verification

- Focused FIFO widget suite, including desktop/mobile rect and overlap checks.
- Targeted analyzer, format and `git diff --check`.
- Web release build before publication.
- After staging deploy: authenticated Chrome at 1440×900 and 375×812 against
  the exact nodes above.
