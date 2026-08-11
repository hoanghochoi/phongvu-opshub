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

## Third staging regression — artifact provisioning

Staging build `2026.08.10.387+200387` at merge SHA
`0cd987911279003772d0a7196f653f4ecd572596` reads the same 58,179,129-byte
Windows CSV successfully, but every first-chunk attempt fails with
`Không mở được tệp tạm`. Admission currently persists a random artifact path
without creating the file, while the chunk writer opens that path with `r+`.
The second hotfix correctly cancels the zero-byte job after three failures.

The bounded third hotfix provisions the unique empty artifact before admission
is reported successful, compensates filesystem state if the database operation
fails, and preserves strict offset/idempotency semantics. Staging QA is limited
to exactly one healthy API replica with no restart during upload because the
current `/tmp` tmpfs remains container-local. Shared restart- and replica-safe
storage requires a separate approved architecture decision and is not implied
by this hotfix. That durable full-fix is tracked in Linear as `OPS-63`.

## Fourth staging regression — historical export schema

The production Sales export is an exact 34-column item-grain file rather than
either legacy history-import shape. The bounded adapter reads only that exact
header/order, uses `Revenue with VAT`, `HRM ID`, and the first 14 leading order
digits, then maps exact lowest `Subcat ID` with exact `Subcat 2 ID` fallback
from one cached taxonomy snapshot. Known non-target taxonomy rows remain valid
zero-KPI facts; unknown taxonomy rows quarantine their date/showroom grain.

PC assembly stages six net component quantities per canonical order. Final
assembled-PC quantity remains the existing direct quantity plus the
non-negative minimum of CPU, mainboard, memory, storage, case, and PSU. The
legacy parser shapes, import API, and final aggregate contract remain unchanged.

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
- Third-hotfix base: clean `origin/staging` SHA
  `0cd987911279003772d0a7196f653f4ecd572596`.
- Third-hotfix branch/worktree: `codex/ops-62-history-artifact-path-hotfix` at
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-62-artifact`.
- Export-adapter base: `a5a8b4f07a5bf56cbb00b60ef08672f05068159d`.
- Export-adapter branch/worktree: `codex/ops-62-history-export-schema` at
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-62-export`.

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
10. Reproduce admission followed by a missing first-chunk artifact, then create
    the artifact before successful admission with cleanup on database failure.
11. Preserve strict `r+` offset handling, cancellation, worker and TTL cleanup;
    prove missing-parent and first-chunk behavior on a real filesystem.
12. Before staging QA, verify one healthy API replica, zero stale nonterminal
    import jobs and no API restart during the same-file upload.
13. Reconcile an ambiguous transaction result by generated job ID before
    filesystem compensation; return the durable job as recovered admission when
    it owns the artifact, retain on unavailable reconciliation, and let TTL
    cleanup reclaim true orphans. Create raw upload artifacts with mode `0600`.
14. Reproduce the exact 34-column Sales export separately from both legacy
    parser shapes and build one immutable exact-ID taxonomy snapshot per file.
15. Stage the six assembly components per canonical order and aggregate direct
    PC ráp plus the non-negative six-component minimum without changing the
    output aggregate contract.
16. Add a forward-only migration for the six staging facts and focused parser,
    taxonomy, quarantine, chunk-boundary, and service aggregation proof.
17. Run Prisma format/validate/generate, focused Nest tests, Nest build,
    Prettier, and exact diff checks without commit, push, deploy, or Linear
    mutation.
18. Address independent review by bounding scientific coefficients before
    `BigInt`, accumulating revenue as checked bigint, enforcing int32 quantity
    bounds, and quarantining a date/showroom grain when one canonical order
    crosses employees or storage bounds.
19. Re-run immutable-diff code/security review, full affected proof, release
    builds, PR/CI, exact-SHA staging deploy, same-file QA, and guarded cleanup.

## Fourth regression progress

- Exact export parser and taxonomy snapshot implemented; exact file SHA-256
  `86557af23860da305ea61392f62f236a27f8714dc0e7408805f87dacc2cb8364`
  parses 98,473 rows with 211 taxonomy-only quarantines and no numeric/order
  errors.
- Independent review findings are addressed with bounded numeric parsing,
  checked order/aggregate-grain bounds, fail-closed canonical-order identity
  handling, and an indexed cross-chunk order lookup.
- Local executable gates pass: focused `58/58`, PostgreSQL `8/8`, full Nest
  `108/108` suites (`1,201` passed, `5` PostgreSQL-gated skipped), Flutter
  `850` passed with
  `3` skipped, analyze, Go, Windows release, Web release/Wasm dry-run and
  Android staging debug.
- Remaining: immutable final review, Linear proof, PR/CI, squash merge, exact
  merge-SHA deploy, same-file staging reconciliation and lifecycle cleanup.

## Recovery

The export adapter adds six nullable-free, zero-default staging columns through
a forward migration; it does not backfill or alter final aggregates. Before
merge, discard only the OPS-62 worktree/branch through the lifecycle workflow.
After merge, rollback application behavior by reverting the OPS-62 squash
commit on a new branch from live `origin/staging`; database rollback follows a
separately reviewed forward migration because the columns may already contain
staged facts.

## Protected consumers

- History import admission, chunk append, cancel, worker claim, activation and
  rollback; authorization, quota, fencing and artifact cleanup.
- Existing synchronous Sales Report Excel import.
- Legacy wide/category history parser inputs and the existing history import
  API/final aggregate consumers.
- Home historical Sales KPI totals, especially PC ráp calculated per canonical
  order before user/store aggregation.
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
- Admission/first-chunk artifact creation, database-failure compensation,
  strict offset/idempotency, cancel/worker/TTL removal, and exact-SHA single-
  replica staging proof with the same file reaching its parser terminal state.
