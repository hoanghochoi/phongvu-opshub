# OPS-53 — Sales Report clickable cards

## Checkpoint

- Worktree: `opshub-ops-53-sales-report-clickable-cards`
- Branch: `codex/ops-53-sales-report-clickable-cards`
- Base/HEAD: `76edccc580578bed53e1f20a48269a3c1198da20`
- Dirty state at intake: clean.

## Goal and scope

Implement the approved Figma Sales Reports card revision (proposal section
`2357:65013`) while preserving report/order data, permissions and callbacks.
Only unreported cards remain clickable and open the existing report form;
reported cards remain read-only while retaining the visual caret. The visible
per-card `Báo cáo` link is removed.

## Approved node map

| Viewport/state | Figma authority | Flutter mapping |
| --- | --- | --- |
| Wide reported/unreported | `2357:65029`, `2357:65035` | `_OrderCockpitTile` / `AppSurfaceCard` |
| Reported variants | `2357:65044`, `2357:65048` | same shared tile, reported badge, no callback |
| Tall, expanded, medium, compact | OPS-53 Linear comment counterparts | same tile with canonical breakpoint constraints |

Visible geometry: 102px card height; order title and value/status badge share
the first row; second row is `SR • employee full name`; third row is employee
email; Phosphor `caretRight` is 20×20 on the right edge. Customer name is not
used in the employee row.

Chrome audit matrix: compact `<600`, medium `600–899`, expanded `900–1199`,
wide `>=1200`, for both reported and unreported states.

Interaction authority confirmed by Đại Ca on 2026-08-12: only `Chưa báo cáo`
cards are actionable; `Đã báo cáo` cards keep the caret as a visual cue but do
not receive a tap callback or open a new route/modal.

## Data authority

The backend DTO exposes employee identity as an atomic `employeeName` +
`employeeEmail` pair. Reported rows prefer report creator, then consultant,
then seller; unreported rows prefer consultant, then seller, then source user.
This prevents a name from one employee being paired with another employee's
email. Empty names fall back to the selected candidate's email only.

## Progress

- [x] Inspect checkpoint, docs, existing card/model/mapper paths.
- [x] Implement DTO/model/tile and focused tests.
- [x] `dart format`, targeted `flutter analyze`, and `git diff --check` passed.
- [x] Focused Flutter suite `flutter test --no-pub test/sales_report_hub_test.dart`
  passed (44 tests).
- [x] Focused Nest Sales Reports suite passed (102 tests) after generating the
  Prisma client from the tracked schema; `npm run build` passed.
- [x] Record final evidence and residual risks.

## Final local evidence

- `flutter test --no-pub test/sales_report_hub_test.dart`: 44/44 passed.
- Focused interaction/geometry proof confirms both cards are 102px, the
  reported card opens no dialog, and the existing unreported callback remains
  covered.
- Targeted Flutter analyzer: no issues.
- `npm test -- --runInBand --testPathPatterns=sales-reports.service`: 102/102
  passed; `npm run build` passed.
- `git diff --check`: passed.
- Protected consumers exercised: Sales Report cockpit DTO mapping, Dart domain
  parsing/name fallback, reported/unreported card rendering, pagination, and
  the existing unreported report-form callback.
- Independent review findings were fixed before PR creation: the visible
  employee row now uses literal `SR`, and deliberately different
  seller/consultant fixtures verify atomic identity precedence for both states.
- Residual risk: exact authenticated Chrome comparison at the full approved
  viewport matrix remains pending until this branch is merged and deployed to
  staging. Next step: review PR, run CI, deploy its merge SHA, then complete
  staging visual QA against the approved Figma nodes.

## Risks and recovery

- API response fixtures may omit the new optional fields; Dart parsing remains
  nullable and falls back safely.
- If focused proof exposes an affected consumer regression, revert only this
  plan's patch and recompute the node map before continuing.
