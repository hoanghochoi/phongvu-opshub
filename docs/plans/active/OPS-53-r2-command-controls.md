# OPS-53 R2 — Shared command controls

## Status

Locally implemented and verified — publication, Linear mutation, staging
deployment, and authenticated Chrome comparison remain outside this
implementation task, so the plan stays active for downstream release proof.

## Checkpoint and ownership

- Worktree: `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-53-r2-command-controls`.
- Branch: `codex/ops-53-r2-command-controls`.
- Base/HEAD before edits: `32f62d33149eacb057cf36b2a523f7c8520b64f0`.
- Worktree was clean before this plan was created.
- Production-code writer: `/root/ops53_r2_ui_fidelity_fixes` only for the
  current fidelity remediation. Prior implementation/review writers completed
  before this ownership transfer; no overlapping production writer is assigned.
- Owned runtime scope: the five target screens below plus one shared command
  composition under `lib/app/widgets/` if required. Existing callbacks,
  Provider state, API/query contracts, permissions, routing, realtime, scanner,
  and AppLogger behavior are protected.

## Authority and intake

- Input/lane: approved UI redesign implementation; normal runtime risk because
  one shared composition affects FIFO Check, FIFO Sort, and Warranty, with
  Sales and Follow-up filter geometry in the same delivery.
- Figma file: `mFzSmQzlapSe3RSmUhvzll`.
- Implementation node map: `2222:82`.
- Exact design context and screenshots were retrieved before production edits
  for `2222:82`, `2219:2`, `2219:76`, `2221:2`, `2221:206`, and `2221:346`.
- Shared responsive tokens classify compact `<600`, medium `600–899`, expanded
  `900–1199`, and wide `>=1200`. The review surfaces use content widths
  `343`, `720`, `872`, and `1126` in both Light and Dark semantic modes.

## Approved node map

The mapping below applies at every declared content width and both themes.
Light keeps the approved current semantic surfaces. Dark resolves the same
component tokens to dark surfaces/borders and high-contrast icon foregrounds.

| Family / node | Visible element and geometry | Flutter mapping | Protected behavior |
| --- | --- | --- | --- |
| Follow-up `2219:2` | Raised surface, 16px padding, 12px control gap; compact stacks three full-width 48px controls; medium/expanded/wide place three equal 48px controls in one row | `AppCommandTextInput`, canonical `AppDateRangeDropdown`, `AppCombobox` | Debounced search, status tabs, date query, showroom query/retry, realtime, import/export and pagination |
| Follow-up `2219:2` | Search copy `Tìm theo tên, điện thoại hoặc Zalo`; date copy `Khoảng ngày: Tất cả ngày`; showroom copy `Tất cả showroom`; no empty-range 30-day helper | Existing controllers/callbacks with shared fields; remove only the visual helper | API keeps its accepted default-date semantics |
| Sales `2219:76` | Raised command surface with 16px padding and 12px gaps; compact stacks full-width 48px `Ngày`, `Showroom`, `Nhân viên` controls, while medium/expanded/wide place the same three 48px controls inline with no external label lane | Canonical `AppDateRangeDropdown`, `AppCombobox`, existing readonly field for un-managed scope; retire the compact `Lọc`/advanced-sheet branch | Date/store/user provider query semantics remain directly available without permission expansion |
| Sales `2219:76` | Actions are ordered `Mua thủ công` → `Chưa mua` → `Tải lại`; compact stacks three full-width 48px actions with 12px gaps, while larger widths keep them inline | `AppPrimaryButton`, `AppSecondaryButton`; no local button primitive | Permissions, purchased/not-purchased navigation, loading and reload callbacks |
| FIFO Check `2221:2` | Canonical bordered Command Bar, 16px padding, 12px gaps; label `SKU hoặc serial`, 48px input, 48px QR and search actions on the same row; loading disables input/scan and replaces search with Phosphor `SpinnerGap` | Reusable `AppCommandBar` composition using `AppCommandTextInput`, `AppIconAction`, and command-scoped semantic colors | Submit/scan/provider/error callbacks and barcode scanner module |
| FIFO Check `2221:2` | `Hiển thị đã xuất kho` toggle begins exactly 16px below the command bar; recent chips remain between approved blocks when present | Existing `_FifoSwitchRow` and `_RecentSearchChips`; remove local frame/icon duplicates only | Toggle and recent-search selection behavior |
| FIFO Sort `2221:206` | Same canonical Command Bar instance; label/hint `SKU hoặc BIN`; 48px QR and search actions | Same shared `AppCommandBar`; no feature-local scan/search composition | Sort dispatch, scanner result and loading state |
| Warranty `2221:346` | `Tải lại` and `Quay lại` are equal 48px secondary actions; compact stacks as approved, other widths keep aligned row | `AppSecondaryButton` medium size | Refresh/loading and GoRouter back-to-hub callbacks |
| Warranty `2221:346` | Same canonical Command Bar instance; label/hint `Biên nhận`, 48px QR and search actions | Same shared `AppCommandBar`; preserve optional clear suffix | Clear/search/scan/loading and receipt navigation |

## Planned files

Runtime ownership:

- `lib/app/widgets/app_command_bar.dart` (new shared composition, if the existing
  primitives cannot express the exact reusable frame without duplication).
- `lib/features/sales_report/presentation/screens/not_purchased_customers_screen.dart`.
- `lib/features/sales_report/presentation/screens/sales_report_screen.dart`.
- `lib/features/fifo/presentation/screens/fifo_check_screen.dart`.
- `lib/features/sort/presentation/screens/sort_screen.dart`.
- `lib/features/warranty/presentation/screens/check_warranty_screen.dart`.
- `lib/features/fifo_check/presentation/widgets/fifo_check_input.dart` only for
  deletion after a repository-wide reachability check confirms no import,
  route, test, or dynamic reference.

Verification ownership:

- `test/not_purchased_customers_test.dart`.
- `test/sales_report_hub_test.dart`.
- `test/fifo_check_redesign_test.dart`.
- `test/sort_screen_redesign_test.dart`.
- `test/warranty_redesign_test.dart`.
- `test/design_system_migration_guard_test.dart`.

## Affected consumers and proof

- Follow-up: status/date/showroom/search filtering, showroom retry,
  realtime-coalesced reload, import/export, cards and pagination.
- Sales cockpit: managed and personal direct filters at every breakpoint,
  manual-report permissions/navigation, reload/loading, both order columns.
- FIFO Check: typed submit, recent searches, exported toggle, QR scanner,
  loading/error/results and copy/export actions.
- FIFO Sort: typed submit, scanner, request dispatch and grouped result states.
- Warranty: refresh/back, clear/search/scan, loading/error/empty/list/detail.
- Shared consumers: canonical DateRangePicker desktop/mobile presentation,
  shared `AppCommandTextInput`, `AppIconAction`, `AppCombobox`, and button theme
  behavior in Light/Dark.

Focused proof will assert all four declared widths in Light/Dark for each
changed family, 48px control/action geometry, compact same-row command actions,
Sales action order/padding/gaps, FIFO toggle gap, Warranty action equality, and
callback reachability. The migration guard will reject retired FIFO local frame
and scan/search duplication plus imports of an unreachable legacy input.

## Implementation sequence

1. Add the smallest shared command-bar composition using existing semantic
   cards/input/button/icon primitives; add its direct geometry tests through
   each target screen.
2. Migrate FIFO Check, FIFO Sort, and Warranty without changing callbacks; then
   remove sole-use local frame/icon classes and verify legacy input reachability.
3. Migrate Follow-up filters and Sales command area to the exact approved
   shared controls while preserving accepted query and compact behavior.
4. Add/update the focused breakpoint/theme regression matrix and migration
   guard, format each batch, and run focused tests.
5. Run analyzer, full Flutter tests, local Web release build, exact diff review,
   and stale-proof fingerprint check. Report any proof unavailable locally.

## Verification commands

```powershell
dart format --output=none --set-exit-if-changed <changed-dart-files>
flutter test --no-pub test/not_purchased_customers_test.dart test/sales_report_hub_test.dart test/fifo_check_redesign_test.dart test/sort_screen_redesign_test.dart test/warranty_redesign_test.dart test/design_system_migration_guard_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
git diff --check
git status --short --branch
git diff --stat
git diff -- <owned paths>
```

## Recovery and stop conditions

- Keep every mutation on this task branch; never reset, clean, rebase, or touch
  canonical `staging`.
- If HEAD changes, another writer edits an owned runtime path, a Figma node is
  revised, or the compact Sales advanced-filter contract cannot coexist with
  the approved visible node, stop production mutation and recompute the plan.
- Revert only this task's bounded patch via an explicit reviewed inverse patch;
  never overwrite unrelated work.
- After any visual correction, rerun all downstream geometry, analyzer, full
  test, and build proof. Staging deploy and authenticated Chrome screenshots
  remain mandatory later and cannot be claimed from local widget tests.

## Progress

- [x] Confirmed repository instructions, approved plan authority, worktree,
  branch, clean checkpoint, exact ownership, and sole production writer.
- [x] Read required redesign/product/verification contracts and exact Figma
  contexts/screenshots.
- [x] Recorded the reviewable node map and affected-consumer proof before the
  first production UI edit.
- [x] Implement shared composition and migrate runtime consumers.
- [x] Retire confirmed unreachable/local legacy command UI.
- [x] Complete focused and broad local proof.
- [x] Resolve review blockers for editable semantics, Follow-up showroom error
  recovery, direct command-bar behavior, and Warranty provider reachability.
- [x] Apply the approved fidelity correction: direct compact Sales controls,
  canonical loading/disabled/focus command states, exact command-scoped colors,
  and production-theme matrix proof.

## Local verification — 2026-08-09

- `flutter pub get`: passed; no dependency or lockfile change. Generated
  line-ending-only noise was content-identical to HEAD and restored from the
  index before final diff review.
- Target family and migration guard command: 106 tests passed across Follow-up,
  Sales, FIFO Check, FIFO Sort, Warranty, and the Design System guard.
- Shared affected-consumer command: 30 tests passed with 3 existing configured
  skips across DateRangePicker, form controls, Web form controls, and buttons.
- `flutter analyze --no-pub`: no issues found (78.6 seconds).
- `flutter test --no-pub --reporter compact`: 770 passed, 3 existing configured
  skips, no failures (130.8 seconds).
- `flutter build web --release --no-pub`: passed, including the Wasm dry run
  (122.2 seconds).
- `git diff --check`: passed after the build and generated-file cleanup.
- Runtime scan: no Material `Icons.*`, `_FifoFrame`, `_FifoIconAction`, or
  feature-local `AppIconAction` command composition remains in the three shared
  command consumers.
- Reachability: repository-wide search found `fifo_check_input.dart` /
  `FifoCheckInput` only in its own source and historical/docs references; the
  source was deleted. The actively imported shared `barcode_scanner_screen.dart`
  remains intact and is asserted by the migration guard.

Residual proof: exact-SHA staging build/deploy and authenticated Chrome
comparison at every declared viewport/theme are still required before visual
completion. No commit, push, PR, Linear mutation, deploy, or release action was
performed here.

## Review-blocker remediation — 2026-08-09

- Added a backward-compatible `semanticLabel` path to
  `AppCommandTextInput`; `AppCommandBar` now merges its visible label onto the
  editable semantics node without changing the 48px field or 108px bar
  geometry. FIFO Check, FIFO Sort, and Warranty tests assert their exact label
  prefix and text-field semantics.
- Kept the Follow-up showroom combobox body at exactly 48px and moved its
  actionable Vietnamese load error plus `Thử lại` control into a separate row.
  The regression forces one loader failure, verifies no overflow/clipping,
  retries successfully, and confirms the restored showroom option.
- Added direct `AppCommandBar` regressions for scan, primary action, Enter
  submission, clear suffix, and disabled/loading action suppression. Added
  Warranty screen proof that normalized search and clear/reload reach
  `WarrantyProvider`.
- Focused target command: 54 tests passed across `app_command_bar_test.dart`,
  Follow-up, FIFO Check, FIFO Sort, and Warranty.
- Shared/structural command: 73 tests passed across shared form controls, the
  design-system migration guard, and Sales Report affected consumers.
- `flutter analyze --no-pub`: no issues found (23.4 seconds).
- `flutter test --no-pub --reporter compact`: 774 passed, 3 existing configured
  skips, no failures (140.5 seconds).
- `flutter build web --release --no-pub`: passed, including the Wasm dry run
  (141.5 seconds). Three generated localization files had content-identical
  line-ending noise and were restored from the pre-build index checkpoint.
- HEAD remained `32f62d33149eacb057cf36b2a523f7c8520b64f0`; no overlapping
  production writer, generated diff, dependency change, commit, push, PR,
  Linear mutation, deploy, or release action occurred.

## UI fidelity remediation — 2026-08-09

- Sales node `2219:76` now renders three direct 48px filters and the ordered
  `Mua thủ công` → `Chưa mua` → `Tải lại` actions. Compact stacks all visible
  controls full-width with 12px gaps and 16px surface padding; larger widths
  use one 48px filter row plus one 48px action row. The obsolete compact `Lọc`
  trigger, bottom sheet, and `_AdvancedFilterSheet` have no remaining runtime
  consumer and were retired while preserving direct provider mutations.
- `AppCommandBar.isLoading` is backward-compatible and maps FIFO, Sort, and
  Warranty provider loading independently from disabled state. Loading disables
  input/scan, presents Phosphor `SpinnerGap` with `Đang tìm kiếm`, and keeps a
  high-contrast primary progress surface; disabled retains `MagnifyingGlass`.
- Command-only semantic tokens resolve the dark command border to `#334155`,
  input borders to `#667085` Light / `#64748B` Dark, and QR surfaces to
  `#F0FDFA` Light / `#052E22` Dark without changing unrelated form controls.
- All new viewport/theme wrappers use `AppTheme.lightTheme` /
  `AppTheme.darkTheme`. Direct proof covers enabled/loading/disabled, exact
  colors, keyboard focus/tab, 2x text scaling, no overflow, and widths 343,
  720, 872, and 1126 in both themes.
- Focused command composition: 5 tests passed. FIFO/Sort/Warranty consumers:
  38 tests passed. Sales/Follow-up/shared controls/migration guard: 107 tests
  passed. `flutter analyze --no-pub`: no issues (23.5 seconds).
- Full `flutter test --no-pub --reporter compact`: exit 0, 779 tests passed and
  3 existing configured skips (148.4 seconds). `flutter build web --release
  --no-pub`: passed, including Wasm dry run (133.5 seconds compile; 136.9
  seconds command runtime).
- Build-created localization line-ending noise was content-identical to the
  index and removed. Publication, Linear mutation, staging deploy, and
  authenticated Chrome comparison were not performed.
