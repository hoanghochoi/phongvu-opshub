# OPS-53 — Employee filter and desktop Sales command bar

## Checkpoint

- Branch: `codex/ops-53-employee-filter-command-bar`.
- Base: `c8d03e7d8cd53b52c924ab231320d739cf276c81` (exact live
  `origin/staging` when lifecycle start passed).
- Canonical staging worktree was clean; lifecycle dry-run and execute passed.
- Staging reproduction: authenticated Chrome showed no employee options for
  `/sales-reports` on the exact base build.

## Approved Figma node map

- Desktop Light: `380:7977`; Desktop Dark: `1874:130010`.
- Compact regression authority: `2213:152961`.
- Wide desktop card: 1126x132, 16px inset, 12px inter-control gaps. One
  left-anchored row contains Date 220, Showroom 180, Employee 220, Reload 120,
  Manual purchase 160 and Not purchased 154. Inputs/actions are 48px high;
  labels sit 8px above the input row. Light/Dark geometry is identical.
- Shared mappings: canonical DateRangePicker, searchable AppCombobox, shared
  secondary/primary buttons and Phosphor icons.

## Implementation

1. Build employee options from historical report/order-cache rows constrained
   by the caller's authorized scope and selected showroom, independent of the
   selected date and employee.
2. Preserve server-side intersection for selected showroom/employee so
   out-of-scope values remain fail-closed.
3. Add an external-label fixed-height mode to the shared AppCombobox and use it
   for the wide Sales command bar, matching the date field and Figma geometry.
4. Select wide layout from the available content width, not the whole window,
   so a desktop sidebar cannot force an overflowing command row.
5. Add backend scope/option tests and Flutter shared-control/desktop geometry,
   selection-query, compact and no-overflow regressions.

## Verification

- Focused Nest SalesReportsService tests, then full Nest build/tests.
- Focused AppCombobox and Sales Report widget tests, then format, analyze, full
  Flutter tests and Web release build.
- Review exact diff and unchanged fingerprint before publication.
- One accumulated commit/PR only after all local gates pass. Merge/deploy and
  authenticated Chrome audit require the existing OPS-53 staging workflow;
  do not call the UI complete before exact-SHA proof.

## Recovery

Keep all work on the task branch. If a Figma node or product target changes,
stop UI mutation, update this node map, and rerun every downstream geometry and
runtime proof.
