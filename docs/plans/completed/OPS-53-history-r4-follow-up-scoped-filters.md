# OPS-53 R4 — Follow-up scoped filters

## Status

Local implementation and proof complete. Publication,
Linear/Figma mutation, staging deploy, authenticated Chrome comparison, and
release remain outside this task.

## Checkpoint, authority, and ownership

- Worktree: `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-53-follow-up-scoped-filters`.
- Branch: `codex/ops-53-follow-up-scoped-filters`.
- Clean base/HEAD before edits: `1081c63d43e18f536820473ecce044c392c8d635`.
- Sole production writer: `/root/ops53_r4_implement`; no overlapping writer is
  assigned. Preserve unrelated edits and stop if HEAD or owned paths change.
- Approved Figma R4: file `mFzSmQzlapSe3RSmUhvzll`, section `2231:63150`,
  state board `2250:2`. Đại Ca approved this revision.
- Input/lane: approved Follow-up redesign plus role-scoped list/export filters;
  high runtime risk because permission, list/export parity, pagination, and a
  user-facing responsive command surface change together.

## Approved node map (recorded before production UI edits)

Exact root matrix (this list supersedes any shorthand in the mapping table):

- 375 base Light: `2232:63150`, `2232:63189`, `2232:63231`; Dark:
  `2232:63277`, `2232:63316`, `2232:63358`; Managed + import:
  `2250:154036`, `2250:154066`.
- 375 advanced-open Light/Dark: Staff `2253:86` / `2253:181`, Managed
  `2253:115` / `2253:210`, Super `2253:147` / `2253:242`, Managed + import
  `2253:276` / `2253:310`.
- 834 base Light: `2234:63150`, `2234:63201`, `2234:63255`; Dark:
  `2234:63312`, `2234:63363`, `2234:63417`; Managed + import:
  `2250:154096`, `2250:154134`.
- 1024 base Light: `2235:63150`, `2235:63195`, `2235:63243`; Dark:
  `2235:63295`, `2235:63340`, `2235:63388`; Managed + import:
  `2250:154172`, `2250:154209`.
- 1440 base Light: `2236:2`, `2236:47`, `2236:95`; Dark: `2236:147`,
  `2236:192`, `2236:240`; Managed + import: `2250:154246`, `2250:154283`.

The shell owns the only `Chăm sóc lại` page title. The route removes its
duplicate heading/subtitle and maps every remaining visible command element to
shared Flutter controls and semantic tokens.

| Viewport/state | Exact approved node | Geometry and visible element | Flutter mapping | Protected behavior |
| --- | --- | --- | --- | --- |
| Outer 375, command 343, collapsed | `2232:63150`, `2250:154036` | Separate OPEN/HISTORY/HIDDEN status strip; command surface shows 48px search then 48px `Tìm kiếm nâng cao` with Phosphor caret only | Existing status strip, `AppCommandTextInput`, shared secondary action/button tokens | Search debounce, status reload, compact default collapsed |
| Outer 375, command 343, open | `2253:86`, `2253:276` | Advanced section reveals 48px controls in date → showroom → category order; permission actions remain a separate 48px row/stack | Canonical `AppDateRangeDropdown`, `AppCombobox`, shared buttons | Date default/max, scope option state, import/export permissions |
| Outer 834, route 746, command 698 | `2232:63277`, `2253:181` | Row 1 search + canonical date + showroom + category; row 2 permitted actions; all controls/actions 48px and centered | Shared responsive tokens/components; no compact disclosure | List/export filter parity and no overflow |
| Outer 1024, route 936, command 888 | `2232:63189`, `2253:115` | Same two-row command composition at expanded width | Same shared mappings | Same contracts |
| Outer 1440, route 1190, command 1132 | `2232:63316`, `2253:210` | Same two-row command composition inside the bounded route lane | `AppResponsiveScrollView(maxWidth: 1190)` plus shared controls | Shell/route lane fidelity |
| Staff collapsed/open | `2232:63231`, `2253:147`, `2250:154066` | Showroom stays visible even for one option; no import/export actions | Profile `assignedStores`, scoped category options, shared controls | Assigned-case scope and assignee behavior only |
| Managed collapsed/open | `2232:63358`, `2253:242` | Showroom + category filters; export action; import only with effective `ADMIN_SALES_REPORTS` capability | Effective feature access + managed profile stores | Managed/assigned store scope, no role-name UI leakage |
| Super open states | `2253:310` | Authorized showroom catalog, category selector, export and effective-permission import | Authenticated store loader only for Super; shared combobox states | Super effective permissions without client-side scope authority |

Shared state board `2250:2` controls loading, empty, error/retry, stale option,
focus/keyboard, long Vietnamese text, collapsed/open, disabled/loading actions,
and Light/Dark semantic rendering. `AppCombobox` remains the only selector
primitive. Client options are UX only; the Nest scope intersection is the
authorization boundary.

## Implementation plan and owned files

1. Add DTO/repository forwarding for `categoryGroupId`; validate requested
   store/category filters against the server-derived caller scope, then apply
   identical primary-or-selection category predicates to list and XLSX.
2. Replace Follow-up global-store loading for non-Super users with assigned
   profile options, load category options, and preserve actionable
   loading/empty/error/retry/stale behavior and sanitized AppLogger branches.
3. Implement the approved status/command/action composition and compact
   disclosure without changing cards, modal, pagination, realtime, or date
   contracts.
4. Add focused Nest DTO/controller/service and Flutter permission/scope/query/
   geometry/realtime tests; update product/test-matrix truth.
5. Format, run focused proof, then analyzer/full suites/build as feasible; inspect
   final diff/status and rerun any stale downstream proof after corrections.

Owned runtime/test/document paths are limited to Follow-up Flutter screen,
domain/repository constants as needed, Follow-up Nest DTO/controller/service,
their focused tests, this plan, the Follow-up product contract, and test matrix.
No generated files, dependencies, unrelated Sales cockpit, routes, import
internals, Prisma schema, Go, deploy, or release state are owned.

## Protected consumers and proof

- Follow-up OPEN/HISTORY/HIDDEN status semantics, 30-day default, 90-day max,
  pagination/total, contact-grace visibility, cards, detail/modal and reopen.
- Staff assignee-only read/write; Managed node/store semantics; Super scope;
  effective feature guard; import/export action visibility.
- Search/date/store/category list and XLSX parity, including primary
  `categoryGroupId` and `categorySelections` matches.
- Scoped showroom option loading/retry/stale selection and category
  loading/empty/error/retry; AppCombobox focus/keyboard/long text.
- Realtime coalescing keeps the selected status/search/date/store/category.
- Geometry at outer widths 375/834/1024/1440 with command widths
  343/698/888/1132, 48px controls/actions, compact collapsed/open order, and
  duplicate title removal.

Focused commands target
`backend-nest/src/sales-reports/sales-report-follow-ups.{controller,service}.spec.ts`
and `test/not_purchased_customers_test.dart`; broad proof is Nest build/full
tests, Flutter analyze/full tests/Web release build, and `git diff --check`.

## Recovery and stop conditions

- Recovery is a reviewed inverse `apply_patch` against this bounded diff on the
  recorded HEAD; never reset, checkout, clean, rebase, or overwrite unrelated
  files.
- Stop if HEAD changes, an owned path gains another writer's edits, any approved
  node/revision changes, a requested filter cannot be fail-closed without a new
  product/API decision, or proof would require weakening an old consumer.
- Staging deploy and authenticated Chrome/Figma comparison for every declared
  viewport/state remain downstream gates and are not claimable locally.

## Progress

- [x] Confirmed instructions, approved plan authority, branch/HEAD/clean state,
  exact ownership, and no overlapping production writer.
- [x] Read relevant workflow, redesign, product, current code, and proof.
- [x] Recorded the complete R4 node map and protected consumers before the first
  production UI edit.
- [x] Implement backend/query and Flutter responsive/permission behavior.
- [x] Add focused regression proof and update product/test matrix.
- [x] Complete local focused/broad verification and final diff review.

## Local verification — 2026-08-09

- Nest focused DTO/controller/service: 3 suites, 24/24 tests passed.
- Flutter focused Follow-up/shared controls: passed, including compact/open,
  route-width matrix, role/capability actions, error/retry, contact grace,
  realtime, and latest-filter queuing.
- `flutter analyze --no-pub`: no issues.
- Full Flutter suite: exit 0; existing configured skips remain unchanged.
- Full Nest suite: 103 suites, 1126/1126 tests passed.
- `npm run build`: passed.
- `flutter build web --release --no-pub`: passed; Wasm dry run succeeded.
- Independent code review findings were corrected: Staff retained assignee-only
  base scope while explicit showroom filters fail closed; in-flight filter
  changes now queue one latest page-0 request and stale responses do not render.
- Independent security review found no reportable authorization/data-exposure
  regression. UI review findings for outer-width breakpoints, scaled compact
  actions, semantic labels/states, and shared radius were corrected.

Remaining downstream proof: commit/PR, exact-SHA staging deployment, and
authenticated Chrome plus Android/Windows comparison are intentionally not
authorized in this local implementation task.
