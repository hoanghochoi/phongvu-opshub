# Execution Plan: OPS-41 Offset ERP And Bulk Actions

Date: 2026-07-30

## Status

Active; local implementation, review remediation, affected-consumer proof, and
full repository validation are green. Publication, staging deployment, and
staging QA remain in progress.

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
  `origin/staging` through the lifecycle guard. The branch was subsequently
  synchronized without path overlap to live `origin/staging`
  `07f5b43603f9ae1fe14ddfc7324006e628959abd` before final verification.

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
  batch re-follow, ERP recheck at reviewer completion, and production
  promotion.

## Approach

1. Reuse `SalesReportErpService.lookupOrderStatus()` after local/duplicate
   validation; commit Offset row and history together and publish after commit.
2. Implement both batch APIs with preflight checks, transactional snapshot
   guards, existing audit/history metadata, and all-or-nothing errors.
3. Extend the current Flutter providers/repositories/screens without changing
   routes or redesign targets; preserve old single-row and export behavior.
4. Add focused tests, run protected-consumer and full gates, then independently
   review security/UI/correctness before recording Linear proof.
5. Publish through a reviewed PR to `staging`, wait for the exact merged SHA to
   deploy, complete real ERP/concurrency/platform smoke, and stop at Ready for
   Release without promoting `main`.

## Risks And Recovery

- ERP latency/failure could create invalid financial records. Fail closed, keep
  lookups outside DB transactions, and log only phase/lifecycle/value presence.
- Concurrent changes could cause partial batch state. Recheck server snapshots
  after locking rows in canonical ID order; one conflict rolls back every row
  and audit/history write.
- ERP orders are intentionally not required to match the Offset request
  showroom. The request showroom remains the authorization/reporting scope;
  the normalized ERP selling-store code and fixed `Cấn trừ trên OpsHub`
  creation channel are carried in history and exposed in list/detail/CSV.
- Selection changes could regress existing export/editor behavior. Keep old
  selection contract, constrain only batch eligibility, and run affected tests.
- Recovery before publication: remove or revert only OPS-41 work in the isolated
  task worktree. No database migration or external runtime mutation is involved.
- Recovery after a staging merge: revert only the OPS-41 squash commit if ERP
  validation accepts an invalid lifecycle/value, a batch produces partial state,
  or a stale single action overwrites a batch. Redeploy that revert to staging,
  verify Offset create/resubmit/single review and statement single tracking, then
  repeat affected-consumer proof before reopening release readiness.

## Progress

- [x] Create/verify OPS-41, record acceptance criteria, and move to In Progress.
- [x] Create isolated lifecycle-guarded task branch/worktree.
- [x] Implement backend ERP validation and both atomic batch endpoints.
- [x] Implement existing-UI Flutter batch selection/actions.
- [x] Restore legacy Sao kê toolbar geometry regression with focused proof.
- [x] Complete focused Flutter coverage and contract/test documentation.
- [x] Keep ERP selling-store metadata distinct from the request showroom and
  add `data.order.consultant.email` as the Sales Report owner-mapping fallback
  for CHAT-style orders.
- [x] Synchronize the branch to live `origin/staging@07f5b436` with no OPS-41
  path overlap.
- [x] Complete independent correctness/security review and remediate row-lock,
  scope-query, response-contract, provider-disposal, in-flight selection,
  single-review concurrency, and ERP source-metadata findings.
- [x] Restore the existing web visual-smoke inventory by excluding the legacy
  `/fifo-menu` redirect and aligning the guard/docs to the 38 current shell
  routes; no runtime route or UI behavior changed.
- [x] Replace the provisional selling-channel presentation with `Cửa hàng bán`
  backed only by the normalized leading code from
  `data.order.createdFromSiteDisplayName`; keep the request showroom separate.
- [x] Run focused store-contract proof: Offset/Sales Report Nest `62/62`,
  Flutter repository `6/6`, and Offset workspace `4/4`.
- [x] Deploy the real Prisma migrations into a disposable PostgreSQL database
  and exercise independent clients: two stale Offset single/batch races, one
  statement no-op-batch/stale-re-follow race, two atomic rollback scenarios,
  and exact history/audit/revision/outbox counts.
- [x] Freeze the final-candidate SHA and rerun Prisma validation, Nest build/full
  Jest, Flutter analyze/full tests, Go tests, PostgreSQL verifier, and diff check.
- [x] Complete independent remediation review with no remaining severity finding.
- [ ] Complete the staging smoke/live ERP proof for cross-showroom orders and
  selling-store labels.
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
- Store/source metadata proof: ERP normalization, Offset history/list/CSV
  metadata, and consultant-email owner fallback tests.
- Protected consumers: Offset create/resubmit/single complete/reject,
  notification/realtime/CSV; statement single tracking/editor/export/filter,
  Payment Monitor, Home projection/fallback, XLSX, BigQuery; Go isolation.
- Repository gates: Prisma validate, Nest build/full Jest, Flutter analyze/full
  tests, `go test ./...`, `git diff --check`, and exact diff review.
- Release-only proof: staged Android/Windows/web smoke with real ERP orders,
  two-client concurrency, and latency/error-log observation.

## Result

The branch is synchronized to `origin/staging@07f5b436`. Review blockers, the
stale web-smoke inventory, the final `Cửa hàng bán` store-code steer, and the
statement no-op/stale-re-follow race have green proof. A disposable PostgreSQL
run against the real migrated table/trigger schema proved the required
independent-client lock/rollback scenarios without audit or downstream revision
on the logical no-op. Prisma validate, Nest build and `91/91` suites (`1,029`
tests), Flutter analyze and full Flutter `671` passed / `3` skipped, Go `64`
tests, and `git diff --check` are green. Independent review found no remaining
severity finding. Publication, staging Android/Windows/web, live ERP, and
operational proof remain release gates; their immutable results will be recorded
on OPS-41 before transition.
