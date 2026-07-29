# Execution Plan: OPS-25 Figma Foundation And Screen Rollout

Date: 2026-07-27

## Status

Completed — historical design closeout handed off to OPS-34 on 2026-07-29

## Outcome

Build the approved redesign foundation in Figma, then produce responsive and
state-aware draft designs for every route row in the approved 44-route screen
inventory without changing product, API, permission, or platform contracts.

## Scope

- Figma file `mFzSmQzlapSe3RSmUhvzll` as it existed during the OPS-25 rollout.
- Three-layer variables, text/effect styles and shared components from the
  approved Foundation Pack.
- Forty-two canonical route owners plus the documented inventory-import alias
  and reports redirect.
- Desktop/mobile loaded states and applicable loading, empty, error, form,
  dialog, result, unsupported, validation, saving, or submitting states.
- Local Figma state ledger at
  `C:\Users\ASUS1\AppData\Local\Temp\dsb-state-opshub-ops25.json`.

## Protected behavior

- Product contracts and current Flutter routes remained the source of truth.
- Figma did not add routes, permissions, API fields, business rules, fake
  time-series, or unsupported actions.
- Related long editors use one modal/fixed-context presentation family.
- Command inputs keep the input and scan/search actions in the same row.
- `/fifo/inventory-import` reuses `/admin/inventory-import`; `/reports` remains
  redirect-only.

## Skills used

- `ui-ux-pro-max` for the shared visual direction and component consistency.
- `design-system` for token/component architecture.
- `ux-designer` for responsive, form, state, accessibility and Vietnamese copy
  review.
- `figma-use`, `figma-generate-library`, and `figma-generate-design` for all
  Figma mutations and verification.

## Historical verification snapshot

- Inventory/ledger reconciliation: **44/44**, no missing or extra route keys.
- Canonical Figma owners: **42/42**, no missing owner.
- Top-level screen/state roots: **222**, no duplicate names.
- Ledger node references: **222/222 exist**, all expected Figma node types.
- All ledger page/component/utility/screen references: **339/339 exist**;
  shared component and utility roots: **90**.
- Typography audit: no font outside Be Vietnam Pro and Material Icons Round.
- Foundation component audit: no remaining Inter text and no invalid geometry
  across all 90 shared component/utility roots after normalizing the 69 legacy
  Inter nodes in Checkbox, Radio, Bottom Sheet and specimens.
- Geometry audit: no invalid text geometry and no remaining one-pixel generated
  text boxes after normalizing 1,033 nodes.
- Representative screenshots rechecked after normalization for Foundation
  Switch, Organization editor/states, Admin Policies, FIFO, Warranty, Finance,
  Sales cockpit/editors, Feedback and Settings.

## Closeout and ownership handoff

- Đại Ca approved closing the OPS-25 design scope on 2026-07-29.
- The local ledger is frozen as a historical snapshot with SHA-256
  `5171D9AAFD7EF44738D988C2A80E8F5DD65F6B97EF913494CDF4F078B782A0A6`.
- After this snapshot, OPS-34 reorganized the same live file into five canonical
  pages: Cover, Foundation, Desktop, Mobile and Tablet. Its plan explicitly
  owns the current page taxonomy, node inventory and shared redesign docs.
- The OPS-25 ledger still describes the earlier 28-page taxonomy and therefore
  must not be regenerated against, or used to overwrite, the OPS-34 structure.
- Narrative QA recorded 222 top-level roots, while the frozen ledger contains
  220 route-root references and 349 unique entity IDs. The discrepancy is
  preserved as historical evidence rather than normalized without the old
  live structure.
- Shared redesign-document edits were excluded from this closeout to avoid
  publishing stale content over OPS-34.

## Runtime implementation boundary

The historical screen set is not blanket Flutter implementation authority.
Implementation still needs a current exact frame/revision owned by its active
issue, Linear tracking, runtime regression proof, font asset/platform proof and
normal repository lifecycle gates.
