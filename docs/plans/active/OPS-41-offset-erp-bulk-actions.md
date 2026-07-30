# Execution Plan: OPS-41 Offset ERP And Bulk Actions

Date: 2026-07-30

## Status

Active; local implementation is verified, with release and product-authority
gaps recorded below.

## Outcome

Keep the existing Cấn trừ and Sao kê UI while adding fail-closed ERP validation
to Offset create/resubmit, atomic reviewer completion for selected eligible
Offset requests, and atomic `Bỏ theo dõi đã chọn` for selected statements.

## Context

- Linear: OPS-41, related to OPS-36; High priority, `In Progress`.
- Product authority: Đại Ca's approved plan and explicit direction to use the
  existing UI without redesign/Figma.
- Contracts: `docs/product/offset-adjustments.md` and
  `docs/stories/PAYMENT-STATEMENT-001-bank-statement/`.
- Runtime: Offset Nest/Flutter feature, MAP statement Nest/Flutter feature,
  shared Sales Report ERP lookup, notification/realtime, Home/XLSX/BigQuery.
- Checkpoint: branch `codex/ops-41-offset-erp-bulk-actions`, worktree
  `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-41`, clean base
  `0a0cc10e3f46bac7fe48f6d0cd676a1f621fa98a` created from live
  `origin/staging` through the lifecycle guard.

## Scope

In scope:

- ERP validation on Offset create/resubmit only, with Vietnamese fail-closed
  errors and no write/realtime side effects on failure.
- Additive atomic batch APIs for non-VNPAY Offset completion and statement
  unfollow, maximum 100 unique IDs, existing permission/showroom boundaries.
- Existing UI selection, confirmation, loading, success/failure, refresh, and
  AppLogger/Nest logging with sanitized counts and lifecycle summaries.
- Focused, affected-consumer, full validation and contract documentation.

Out of scope:

- Visual redesign, Figma, new routes, schema migration, backfill, batch reject,
  batch re-follow, ERP recheck at reviewer completion, commit/push/PR/deploy.

## Approach

1. Reuse `SalesReportErpService.lookupOrderStatus()` after local/duplicate
   validation; commit Offset row and history together and publish after commit.
2. Implement both batch APIs with preflight checks, transactional snapshot
   guards, existing audit/history metadata, and all-or-nothing errors.
3. Extend the current Flutter providers/repositories/screens without changing
   routes or redesign targets; preserve old single-row and export behavior.
4. Add focused tests, run protected-consumer and full gates, then independently
   review security/UI/correctness before recording Linear proof.

## Risks And Recovery

- ERP latency/failure could create invalid financial records. Fail closed, keep
  lookups outside DB transactions, and log only phase/lifecycle/value presence.
- Concurrent changes could cause partial batch state. Recheck server snapshots
  after locking rows in canonical ID order; one conflict rolls back every row
  and audit/history write.
- ERP orders are intentionally not required to match the Offset request
  showroom. The request showroom remains the authorization/reporting scope;
  sanitized ERP selling-channel metadata and the fixed `Cấn trừ trên OpsHub`
  creation channel are carried in history and exposed in list/detail/CSV.
- Selection changes could regress existing export/editor behavior. Keep old
  selection contract, constrain only batch eligibility, and run affected tests.
- Recovery before publication: remove or revert only OPS-41 work in the isolated
  task worktree. No database migration or external runtime mutation is involved.

## Progress

- [x] Create/verify OPS-41, record acceptance criteria, and move to In Progress.
- [x] Create isolated lifecycle-guarded task branch/worktree.
- [x] Implement backend ERP validation and both atomic batch endpoints.
- [x] Implement existing-UI Flutter batch selection/actions.
- [x] Restore legacy Sao kê toolbar geometry regression with focused proof.
- [x] Complete focused Flutter coverage and contract/test documentation.
- [x] Keep ERP selling-channel metadata distinct from the request showroom and
  add `data.order.consultant.email` as the Sales Report owner-mapping fallback
  for CHAT-style orders.
- [x] Run local affected-consumer and full gates; record the two full-Flutter
  failures and environment gaps without weakening tests.
- [x] Complete independent correctness/security review and remediate row-lock,
  scope-query, response-contract, and provider-disposal findings.
- [ ] Verify real PostgreSQL two-client lock behavior and complete the staging
  smoke/live ERP proof for cross-showroom orders and channel labels.
- [ ] Complete staging Android/Windows/web, live ERP, latency/log proof, and
  Linear proof readback before the next lifecycle transition.

## Decisions

- 2026-07-30: Existing UI is authoritative for this task; no redesign/Figma.
- 2026-07-30: ERP validation occurs only at create/resubmit.
- 2026-07-30: Both batches are atomic and accept at most 100 unique IDs.
- 2026-07-30: VNPAY remains individual because completion requires `Mã CT`.
- 2026-07-30: No schema, migration, backfill, or event-shape change.

## Validation

- Focused proof: Offset ERP/batch service and controller Jest; MAP batch service
  and controller Jest; Flutter repository/provider/widget coverage.
- Channel fallback proof: ERP normalization, Offset history/list/CSV metadata,
  and COMEBACK owner resolution tests.
- Protected consumers: Offset create/resubmit/single complete/reject,
  notification/realtime/CSV; statement single tracking/editor/export/filter,
  Payment Monitor, Home projection/fallback, XLSX, BigQuery; Go isolation.
- Repository gates: Prisma validate, Nest build/full Jest, Flutter analyze/full
  tests, `go test ./...`, `git diff --check`, and exact diff review.
- Release-only proof: staged Android/Windows/web smoke with real ERP orders,
  two-client concurrency, and latency/error-log observation.

## Result

Local implementation is complete on the task worktree. Prisma validation, Nest
build, focused Nest (`4 suites / 187 tests` before the channel amendment), full
Nest (`91 suites / 1,026 tests`), channel-focused Flutter (`27 tests`), Flutter
analyze, and Go isolation (`64 tests`) pass. Full Flutter previously reported
`664` passes, `3`
skips, and two failures: the
pre-existing `/fifo-menu` visual-smoke inventory mismatch plus the Offset
realtime max-wait timing test under full-suite load; the latter passes focused.
Real PostgreSQL two-client, staging/device/web, live ERP, and operational proof
remain pending. No publication or external runtime mutation is authorized.
Local `origin/staging` advanced to `4ba6e5915c5d04063700a1083c573a4f54f0f618`
through an OPS-31 deploy/load-proof-only commit after this task started; its
changed paths do not overlap OPS-41. The branch still requires the repository's
approved latest-staging synchronization and fresh affected proof before any PR.
