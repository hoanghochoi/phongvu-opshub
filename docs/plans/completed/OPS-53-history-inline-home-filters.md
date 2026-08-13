# OPS-53 — Inline Home filters, intrinsic overview, scrolling header

## Corrective Home node-map delta — 2026-08-09

- Remove the standalone `Bán hàng` heading and its helper copy from Home; both
  are absent from approved nodes `2203:2/99`, `2204:2/85`, `2205:2/91`, and
  `2204:151839/152140`.
- All four Overview cards size from visible content. Expanded/wide rows share
  the taller intrinsic height; compact/medium stack. No fixed trailing filler.
- `Tổng quan Cửa hàng` keeps three period columns at expanded/wide and stacked
  periods at compact. Label, amount, progress, target, and missing-target copy
  flow without overlap for long Vietnamese data.
- Flutter mapping stays `_ApprovedReportProgressPanel` plus existing semantic
  surface/progress/text tokens. Preserve provider/API/permission behavior.
- Chrome matrix: `375×812`, `834×1112`, `1024×768`, `1440×900`, Light/Dark.
  Geometry proof covers copy absence, intrinsic heights, store no-overlap,
  long missing-target copy, and horizontal overflow.

## Checkpoint

- Branch: `codex/ops-53-inline-home-filters`
- Base: `57079b7bf678c834e0b6c8c4c56112f9cc3e3378`
- Worktree was clean when created by `scripts/task-lifecycle.mjs start --execute`.
- Đại Ca authorized commit/push, one feature PR and squash merge into `staging`
  after the complete local gates pass. Staging deployment and authenticated
  Chrome audit remain required before visual completion; stop only for a
  blocker that cannot be resolved safely in code or a failed mandatory gate.

## Product intent

1. Home scope and date filters remain visible in the header. Scope opens only
   its anchored option list; date opens the canonical shared DateRangePicker.
   The combined scope/date popover is removed.
2. The greeting/filter header scrolls with Home content and is not pinned above
   the dashboard body. Medium/expanded header geometry hugs its 146 px content.
3. The four `Tổng quan` cards use content-driven row heights and the outer
   surface has no trailing filler below the final card row.
4. Desktop sidebar brand copy uses a 4 px title-to-slogan gap and 17 px slogan
   line height without changing logo asset, copy, font, or colors.

## Approved Figma node map

Section: `2201:61216` — `APPROVED — Home Inline Filters + Intrinsic Overview + Brand Spacing · OPS-53`.

| Viewport/theme | Approved node | Header/filter target | Overview target |
| --- | --- | --- | --- |
| 375x812 Light | `2203:2` | full-width stacked inline controls; header scrolls | stacked cards; outer height 996 |
| 375x812 Dark | `2203:99` | same geometry, dark tokens | same geometry, dark tokens |
| 834x1112 Light | `2204:2` | 146 px intrinsic header; 220/220/180 controls | stacked cards; outer height 916 |
| 834x1112 Dark | `2204:85` | same geometry, dark tokens | same geometry, dark tokens |
| 1024x768 Light | `2205:2` | 146 px intrinsic header; direct controls | 2x2 rows; 166 px + 280 px cards; outer height 534 |
| 1024x768 Dark | `2205:91` | same geometry, dark tokens | same geometry, dark tokens |
| 1440x900 Light | `2204:151839` | direct 324/296/280 controls; scrolling header | 2x2 intrinsic rows; outer height 574; brand gap 4/17 |
| 1440x900 Dark | `2204:152140` | same geometry, dark tokens | same geometry, dark tokens |

Shared mappings:

- Scope trigger: existing Home surface tokens and Phosphor CaretDown; anchored
  scope option list only.
- Date trigger: canonical `AppDateRangeDropdown` / shared DateRangePicker,
  extended with the approved 40 px inline surface.
- Overview: existing Home semantic surface/border/progress tokens and existing
  Phosphor icons; no feature-local colors or icons.
- Brand: existing Be Vietnam Pro styles and sidebar semantic colors.

## Implementation plan

1. Move `HomeSummaryHeader` inside the Home scroll body and remove medium fixed
   204 px geometry.
2. Replace `_HomeScopeDateControl` combined menu with a direct anchored scope
   dropdown and a direct canonical date trigger.
3. Extend `AppDateRangeDropdown` with the approved compact inline trigger.
4. Make `_ApprovedReportProgressPanel` use the approved stacked/2x2 thresholds,
   intrinsic row heights, and exact wide horizontal insets.
5. Adjust desktop sidebar title/slogan spacing.
6. Update focused Home/AppShell/shared date-range tests and run final gates.

## Affected consumers and proof

- Home header loading/loaded/warning states, scope selection, date selection,
  refresh, action slot, scroll behavior, compact/medium/expanded/wide geometry.
- Home progress, personal, store and finance-permission combinations.
- Shared DateRangePicker desktop anchored popover and compact/mobile surface.
- AppShell desktop brand, navigation layout and sidebar list start position.

Required proof after final edit:

- Dart format check and `git diff --check`.
- Focused Home, DateRangePicker and AppShell widget tests.
- `flutter analyze --no-pub`.
- Full `flutter test --no-pub`.
- Local Web release build when time/runtime permits; otherwise state it as
  unverified and do not claim publish readiness.

## Local verification — 2026-08-08

- Focused affected-consumer suites: 80 tests passed across
  `home_dashboard_test.dart`, `app_date_range_dropdown_test.dart`, and
  `app_shell_route_viewport_test.dart`.
- Full Flutter suite before the iOS PWA/Sales correction: 769 passed, 3
  skipped; no failures.
- `flutter analyze --no-pub`: no issues found.
- `flutter build web --release --no-pub`: passed, including the Wasm dry run.
- `git diff --check`: passed.
- Runtime icon audit: no `Icons.*` references remain under `lib/`; the changed
  scope/date/brand surfaces use Phosphor icons or existing shared assets.
- Publication remained pending at this checkpoint; the later correction gate
  below supersedes this status before publication.

## iOS PWA auth and Sales Report correction — approved revision

Section: `2213:152953` —
`APPROVED — iOS PWA Login + Sales Report Insets · OPS-53`.

| Surface/state | Approved node | Runtime mapping |
| --- | --- | --- |
| Login iOS PWA 390x844 | `2213:152954` (source root `1375:8146`) | Center the complete auth stack against the PWA viewport; ignore asymmetric portrait Safari horizontal safe-area values, while landscape uses the larger inset symmetrically. Keep 15px page inset, 24px top inset, 360px card cap and existing copy/assets. |
| Sales cockpit compact/iOS PWA | `2213:152961` | 358px surface; 16px inner horizontal inset; `Mua thủ công` and `Chưa mua`; two 159x48 primary actions; `Lọc` then `Tải lại` in one 159/159 row with 8px gap and equal height. |
| Purchased order command compact/iOS PWA | `2213:153053` | 358px card with 16px inner padding; one 326px command row; 222px input plus 44px scan and 44px search actions separated by 8px; search glyph is Phosphor white/inverse. |

Implementation remains restorative and preserves authentication, reporting,
filtering, scanning, order-check, permissions, modal and API behavior. Focused
proof must cover asymmetric iOS safe-area centering, compact cockpit insets and
button geometry/copy/order, plus Android/iOS command row padding and white
filled-action foreground.

The runtime treats this as Safari/mobile Web PWA, not native iOS. A phone-sized
Web viewport on iOS/Android (`shortestSide < 600`) keeps the mobile auth shell
when rotated; a wide short desktop window and an iPad-sized Web viewport retain
the existing width-based desktop shell.

## Final correction and review verification — 2026-08-08

- Direct Figma design-context read confirms node `2203:66` renders the text
  `Ngày`. Its metadata layer name remains `Khoảng chọn / Label`; runtime and
  regression proof follow the visible text, not the stale layer name.
- Independent UI review corrected wide Home control widths to 324/296/280 and
  confirmed Quick/Support geometry/icons, Safari PWA centering, Sales controls
  and command row. Independent code review found and verified the phone-PWA vs
  short-desktop breakpoint correction.
- Focused final Auth/Home/AppShell suite: 80 tests passed, no failures. The
  Android Home compact regression that previously exposed a 24px period-card
  overflow passes after limiting stacked dense periods to the Store card and
  keeping the staff personal card at 266px.
- Asymmetric Safari/PWA proof uses a 390x844 viewport with 28px right safe-area
  inset and verifies the logo/card remain centered at x=195.
- Sales compact proof verifies the 16px insets, equal 159x48 primary buttons,
  `Lọc` before `Tải lại`, a 16px-padded command card, 44px actions and the
  resolved white Phosphor search glyph.
- `dart format`: all 11 changed Dart files are formatted.
- `git diff --check`: passed.
- Full `flutter test --no-pub --reporter compact`: 773 passed, 3 existing
  configured skips, no failures (130.4 seconds).
- Final `flutter analyze --no-pub`: no issues found.
- `flutter build web --release --no-pub`: passed, including the Wasm dry run
  (138.7 seconds).
- Runtime icon audit: `rg` found no `Icons.*` references under `lib/`.
- Build-only l10n line-ending changes were content-empty and restored; no
  generated localization file remains in the task diff.
- Commit/push/PR/merge, staging deployment, authenticated Chrome comparison and
  Linear proof/status remain pending.
