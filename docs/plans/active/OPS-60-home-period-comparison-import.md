# Execution Plan: OPS-60 Home period comparison and historical CSV import

Date: 2026-08-10

## Status

Active

## Outcome

Ship a staging-ready, backward-compatible Home comparison contract and a
Windows/Web historical CSV import flow. Exactly 28 Sales cards show compact
T−1 and N−1 rows matching approved Figma revision
`OPS-59-v2-runtime-parity-2026-08-10`; Finance and Overview remain unchanged.

## Context

- Product authority: Linear OPS-58.
- Approved design authority: Linear OPS-59, Figma file
  `mFzSmQzlapSe3RSmUhvzll`, revision anchor `2259:154134`.
- Implementation tracking: Linear OPS-60.
- Source checkpoint reconciled to `origin/staging` at
  `66407b86c157dab050536188e1ae673f4de4c2d9` before final proof.
- Existing behavior: `docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md`,
  Home projection/service/controller/Flutter provider and the existing Sales
  Report Excel import.

## Scope

In scope:

- Add opt-in `includeComparisons=true` to Home summary and cache identity.
- Compute shifted calendar-month and calendar-year ranges in Vietnam time with
  independent endpoint clamping.
- Persist immutable historical import jobs/versions, date+showroom coverage,
  quarantined grains, atomic activation pointers and rollback history.
- Stream CSV/TSV imports asynchronously in bounded chunks, accepting UTF-8/BOM
  and Windows-1258, up to 200 MiB or 1,000,000 rows.
- Support the approved historical metrics and derive totals without partial
  display; preserve server-authoritative scope and `ADMIN_SALES_REPORTS`.
- Add the approved comparison presentation to 28 Sales cards only and a
  Windows/Web related-flow import modal with sanitized `AppLogger` coverage.
- Reuse `HOME_SUMMARY_UPDATED`; keep the Go protocol unchanged unless executable
  evidence proves a contract change is required.

Out of scope:

- Changes to Finance or four Overview/progress cards.
- Replacement or regression of the existing synchronous Excel import.
- Raw CSV or PII retention, fuzzy Salesman matching, mobile-native import UI.
- Production deployment or promotion to `main`.

## Approach

1. Add tests/contracts for period shifting, comparison response compatibility,
   CSV parsing/normalization, permissions, activation/rollback and old consumers.
2. Add Prisma persistence and the bounded async import worker/API while keeping
   the Excel path untouched.
3. Integrate complete-source precedence with Home projections, cache identity
   and existing realtime invalidation.
4. Add Flutter domain/repository/provider support, the shared card variant and
   Windows/Web import modal using approved shared controls.
5. Run focused, affected-consumer and full validation; remediate independent
   code/security/UI reviews; package exact-SHA ready-for-deploy evidence.

## Risks And Recovery

- Partial or mixed history could produce false totals: activate only complete
  date+showroom grains and render unavailable comparisons when coverage is
  incomplete.
- Large uploads could exhaust memory: stream to bounded temporary/chunk storage,
  enforce byte/row limits and remove raw chunks after parse/cancel/TTL.
- Migration or pointer races could mix versions: use additive schema, immutable
  versions and transactional active pointers; rollback changes pointers only.
- Cache/realtime staleness: enqueue affected dates through the existing
  projection/outbox path and include comparison ranges in overlap checks.
- Recovery: revert the task branch or deactivate/rollback the imported version;
  canonical SalesReport/Home projection facts are never rewritten.

## Progress

- [x] Product decisions recorded in OPS-58.
- [x] Exact Figma revision approved and recorded in OPS-59.
- [x] Guarded branch/worktree created from live `origin/staging`.
- [x] Implement backend schema, worker, APIs and comparison contract.
- [x] Implement Flutter card and import flow.
- [x] Add focused and affected-consumer tests.
- [x] Run full validation and Windows/Web platform builds.
- [x] Complete independent code, security and UI review waves with no remaining
  Blocker/High finding after remediation.
- [x] Record Linear proof and move OPS-60 to `Ready for QA`.

## Implementation Checkpoint And Ownership

- Branch: `codex/ops-60-home-period-comparison-import`.
- HEAD and `origin/staging`: `7b98149102132fbc6753761cc5dc66bc54d2bc56`.
- Initial worktree state was stable across two snapshots; the only dirty path
  was this root-owned active plan.
- The OPS-60 implementer is the sole production-code writer for the bounded
  NestJS/Prisma/Flutter/test/doc scope. No overlapping writer was present.
- Planned backend ownership: additive Prisma schema/migration; a separate
  historical CSV parser/job service and upload options; Sales Reports
  controller/module; Home comparison DTO/service/cache integration and focused
  tests. The synchronous Excel preview/commit service, parser and routes remain
  behaviorally unchanged.
- Planned Flutter ownership: Home model/repository/provider/card presentation;
  Sales Report history-import domain/repository/provider/modal/admin action;
  platform capability/API constants and focused widget/provider tests.

## Figma Node Map

Approved revision: `OPS-59-v2-runtime-parity-2026-08-10`, file
`mFzSmQzlapSe3RSmUhvzll`.

| Viewport/state | Exact node | Runtime mapping |
| --- | --- | --- |
| All Home Sales card sizes/states | `2259:154137` | Existing `SummaryCard` keeps its icon tile, title, current value, card border/radius/padding and existing grid heights. For the 28 Sales cards only, the current trend pill and helper are replaced by a 36 px comparison block containing two 16 px rows separated by 4 px. Each row uses a 12 px shared Phosphor icon, 4 px label gap, neutral text, left label and right value/delta. `T−1` uses `ClockCounterClockwise`; `N−1` uses `ArrowsLeftRight`. Unavailable copy is `Chưa có dữ liệu`; zero/zero is `0%`; positive current over zero prior is `Mới`. Finance and Overview card constructors do not receive comparisons. |
| Windows/Web import lifecycle: choose, upload, parsing, preview, quarantine, activating, complete, failure, history/rollback | `2259:154549` | Related-flow `Dialog` from Sales Report Admin, 680 px bounded desktop width, shared raised/sunken surfaces, 16 px card radius, Vietnamese title `Nhập dữ liệu bán hàng lịch sử`, compact status panel and shared primary/secondary buttons. File chooser accepts CSV/TSV, shows 200 MiB/1,000,000-row limit and the date+showroom/no-raw-PII note. Unsupported platforms hide the entry action and cannot start the flow. |

The shared responsive matrix remains compact `<600`, medium `600–899`,
expanded `900–1199`, wide `>=1200`. Geometry proof must cover all four widths;
the Windows/Web import modal applies only where the platform contract permits.

## Protected Consumers And Proof Map

- Legacy `/home/summary` clients without `includeComparisons`,
  `includeDailySeries`, response-cache identity/refresh-ahead and summary detail
  routes.
- Home projection completeness/freshness, Sales and Finance aggregate reads,
  scope selection, selected-assignee scope, outbox invalidation and
  `HOME_SUMMARY_UPDATED` payload/Go routing.
- Existing Sales Report synchronous Excel `import/preview` + `import/commit`,
  admin list/export and feature guard.
- Flutter Home JSON compatibility/cache/provider/realtime behavior, exactly 28
  Sales card geometry, untouched Finance/Overview cards, GoRouter admin route,
  and the existing Excel follow-up modal.
- Focused proof commands: Prisma format/validate/generate; Home DTO/service/cache
  Jest; historical parser/job/authorization/activation/rollback Jest; existing
  Excel import Jest; Home and Sales Report Flutter tests; Nest build; Flutter
  analyze; Go tests; `git diff --check`.

## Decisions

- 2026-08-10: `T−1` uses the shared Phosphor ClockCounterClockwise icon and
  means the immediately previous calendar month; `N−1` uses ArrowsLeftRight and
  means the same period in the previous year. Labels are left-aligned and
  values/deltas right-aligned.
- 2026-08-10: Active CSV wins at covered date+showroom grains for supported
  metrics; uncovered grains may use only complete OpsHub projection data.
- 2026-08-10: Existing Excel import remains a separate unchanged contract.
- 2026-08-10 final remediation checkpoint: branch remains
  `codex/ops-60-home-period-comparison-import` at HEAD
  `66407b86c157dab050536188e1ae673f4de4c2d9`; the worktree contains the
  preserved uncommitted OPS-60 implementation. The root orchestrator confirmed
  this implementer as the sole production-code writer; no overlapping writer
  was active.
- 2026-08-10: Historical uploads use an admitted `UPLOADING` job, sequential
  4 MiB chunks and server-authoritative offsets. The client resumes from the
  last acknowledged offset after a transient response failure and may cancel
  before upload completion. Admission reserves no more than 220 MiB of raw
  artifacts and the parser runs one claimed job at a time, leaving headroom on
  the 256 MiB temporary filesystem.
- 2026-08-10: Every parser-worker write is fenced by a monotonically increasing
  job claim token. Staging, progress, finalization, failure cleanup and raw
  artifact release stop when a newer worker reclaims the job.
- 2026-08-10: Home response-cache identity now includes token, session and
  access versions so a role/showroom reassignment cannot reuse a response from
  the previous authorization snapshot.

## Final Implementation And Staging Evidence

- PR #155 merged into `staging` at
  `00a5c5b631719688fbf0474337ab5b2fb137dce3`; exact-SHA staging deploy run
  `31403136393` passed its prepare, Android, Windows and deploy jobs.
- Linear is `Ready for QA`; neither the merge nor staging deployment proves
  production completion.
- Nest build, full focused Home and Sales proof, Flutter proof, Go tests and
  Windows/Web release builds passed before publication as recorded below.
- Authenticated four-viewport Figma comparison and the actual maximum-size
  200 MiB/1,000,000-row environment smoke remain staging QA gates.

## Validation

- Focused proof: Prisma format/validate/generate; Home comparison unit/integration
  tests; CSV parser/job/worker/authorization/version tests; Flutter Home/import
  widget/provider/repository tests.
- Integration or end-to-end proof: fresh and upgraded migration, activation and
  rollback concurrency, cache/realtime refresh, generated 200 MiB/1M-row bounded
  load, Windows/Web import smoke and authenticated four-viewport screenshots.
- Repository-required checks: full Nest tests/build, Go tests, Flutter tests and
  analyze, Windows/Web builds, `git diff --check`, exact affected-consumer proof.

## Result

Implementation and local validation are complete on the task branch. The final
proof includes Prisma validation, Nest build and 107/107 Jest suites (1,170
passed, 1 skipped), Go tests, Flutter analyze, the full Flutter suite, focused
Home/import/upload regressions, `git diff --check`, and release Windows/Web
builds. Protected existing consumers include legacy Home requests without
comparisons, projection/cache/realtime behavior, Finance/Overview cards, the
existing synchronous Excel import, and Sales Report admin/realtime flows.

Residual proof moves to staging QA: authenticated four-viewport runtime/Figma
screenshots and an actual maximum-size 200 MiB/1,000,000-row environment smoke.
Security review also records a Medium availability risk where a privileged user
can reserve the global upload budget until cancellation/TTL; authorization,
PII boundaries, bounded 4 MiB streaming, claim fencing and cleanup otherwise
passed review. PR #155 is merged and exact-SHA staging deployment passed. Next
action: complete the authenticated four-viewport Figma comparison and
maximum-size import smoke, record the result in Linear, then continue the
guarded production release handoff. OPS-60 remains open until those gates and
production deployment pass.
