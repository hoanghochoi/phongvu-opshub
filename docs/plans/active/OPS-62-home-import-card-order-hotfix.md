# OPS-62 Home import and card-order hotfix

## Outcome

Restore historical CSV import on staging without weakening transaction locks,
replace the misleading generic server error with Vietnamese actionable copy,
and make the 28 Home Sales cards use the root viewport for approved
expanded/wide grouping while keeping the shared content-width rule for narrow
and mobile Sales/Finance grids.

## Second staging regression — chunk boundary

The first hotfix was squash-merged as PR #156 at staging SHA
`28b55ecc41061dacb6ff1333301ff4b93c6ec9e7`. Windows staging then admitted a
58,179,129-byte CSV but rejected its first exact 4 MiB multipart chunk as
`File too large`; the admitted job remained `UPLOADING` at 0% and polling could
reattach indefinitely.

The bounded follow-up keeps the logical chunk contract at exactly 4 MiB while
giving the multipart parser envelope headroom. A permanent chunk-upload failure
must cancel and clean the admitted job before surfacing the actionable retry
error. Server-advertised/negotiated chunk limits and real proxy-level multipart
coverage remain the durable full-fix follow-up.

## Authority and checkpoint

- Linear: OPS-62, related to OPS-58/59/60.
- Product behavior: OPS-58 and `docs/product/sales-report.md`.
- Approved design: Figma revision `OPS-59-v2-runtime-parity-2026-08-10`,
  anchor `2259:154134`, component `2259:154137`, desktop frame
  `2264:64688` and desktop Sales/KPI nodes `2264:64789`/`2264:64799`.
- Base: clean `origin/staging` SHA
  `00a5c5b631719688fbf0474337ab5b2fb137dce3`.
- Branch/worktree: `codex/ops-62-home-import-card-order-hotfix` at
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-62`.
- Second-hotfix base: clean `origin/staging` SHA
  `28b55ecc41061dacb6ff1333301ff4b93c6ec9e7`.
- Second-hotfix branch/worktree:
  `codex/ops-62-history-chunk-boundary-hotfix` at
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-62-chunk`.

## Plan

1. Add failing PostgreSQL adapter and viewport/content-width reproductions.
2. Replace all six history-import advisory-lock queries with one
   adapter-compatible transaction-lock helper while preserving lock keys and
   ordering.
3. Scope Vietnamese 5xx fallback and admission guidance to the history-import
   UI.
4. Select grid breakpoints from the viewport, preserving approved sequences and
   Finance/Overview behavior.
5. Run focused, PostgreSQL-backed, affected-consumer and repository gates.
6. Independent code/UI review, Linear proof, PR to `staging`, CI, squash merge,
   staging smoke and guarded lifecycle cleanup.
7. Reproduce the exact 4 MiB multipart boundary and the stuck admitted-job
   failure from Windows staging.
8. Add parser envelope headroom without weakening the service-level 4 MiB
   logical guard; cancel/clean an admitted job after terminal upload failure.
9. Re-run affected Nest/Flutter consumers and builds, independent review, PR,
   exact-SHA staging deploy, then retry the same 58 MB CSV past 0%.

## Recovery

No schema or data migration is introduced. Before merge, discard only the
OPS-62 worktree/branch through the lifecycle workflow. After merge, rollback by
reverting the OPS-62 squash commit on a new branch from live `origin/staging`.

## Protected consumers

- History import admission, chunk append, cancel, worker claim, activation and
  rollback; authorization, quota, fencing and artifact cleanup.
- Existing synchronous Sales Report Excel import.
- Home Sales metric sequences/actions/comparisons at compact, medium, expanded
  and wide viewports.
- Finance and Overview remain visually and behaviorally unchanged.

## Authority reconciliation

`docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md` previously described KPI
rows as 6/8 while the exact approved OPS-59 desktop frame is 5/5/4. OPS-62
reconciles the story to the approved frame without changing metric sequence,
formula, permission, action or responsive breakpoint policy.

## Validation

- Focused Nest history-import unit tests and real Prisma adapter-pg/PostgreSQL
  smoke on a disposable loopback database.
- Existing Excel import regression and Nest build/full tests.
- Focused Home geometry/order and history-import provider/widget tests, Flutter
  analyze/full tests.
- Go tests for unchanged Home realtime consumers and `git diff --check`.
- CI, exact-SHA staging deploy, authenticated small-file import smoke and Home
  desktop viewport comparison.
- Exact 4 MiB multipart acceptance, over-limit service rejection, permanent
  chunk-failure cancellation, and authenticated Windows staging proof with the
  same 58 MB file progressing beyond 0% without `File too large`.
