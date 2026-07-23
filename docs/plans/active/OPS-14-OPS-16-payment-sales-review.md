# Execution Plan: OPS-14 + OPS-16 Review Bundle

Date: 2026-07-24

## Status

Active

## Outcome

Deliver one reviewable branch and PR that:

- keeps the eligible Windows payment speaker receiving and playing payments
  while the process is alive but inactive, hidden, or minimized;
- preserves the single authenticated realtime connection, FIFO, claim/ACK,
  reconnect, dedupe, and stale-operation guards;
- converts an existing purchased `SYNC_LIST` report to `COMEBACK` atomically
  when its follow-up case records a purchase, without creating a second report;
- blocks later manual, ERP, or follow-up duplicates with Vietnamese-first,
  actionable messages.

## Context

- Linear: OPS-14 and OPS-16 acceptance criteria and current comments.
- Product: `docs/product/ui-ux.md`, `docs/product/vietqr.md`,
  `docs/product/sales-report.md`, and
  `docs/product/not-purchased-customer-follow-up.md`.
- Decisions: `docs/decisions/0010-client-cache-and-realtime-invalidation.md`,
  `docs/decisions/0013-vieneu-offline-payment-audio-assets.md`, and
  `docs/decisions/0014-piper-offline-payment-audio-assets.md`.
- Existing proof: `docs/TEST_MATRIX.md`, payment/realtime Flutter tests, and
  Sales Report/Follow-up Nest tests.
- Checkpoint: clean task worktree
  `codex/ops-14-ops-16-payment-sales-review` at
  `cd2e181d6982256d5050ea60a7ffc27de1a24c3d`, created from live
  `origin/staging` by `scripts/task-lifecycle.mjs start --execute`.

## Scope

In scope:

- A scoped Windows-speaker background lease on the existing shared `/ws/v2`
  connection; no second socket or native background service.
- Background speaker event handling and `/ready` recovery while list/UI
  refreshes remain paused outside `resumed`.
- Safe lease release on speaker disable, lost eligibility, logout, and dispose;
  `detached` remains terminal for the background runtime.
- Context-aware order checks for follow-up purchases, atomic conditional
  `SYNC_LIST` to `COMEBACK` conversion, case/entry linking, duplicate blocking,
  sanitized logs, Flutter copy, focused tests, product docs, and test matrix.

Out of scope:

- Playback after kill/force-stop, sleep/hibernate, loss of network/audio device,
  a Windows service/tray redesign, or a second realtime consumer.
- Customer matching by phone/name, unrelated Sales Report behavior, schema
  changes unless implementation evidence proves they are unavoidable, staging
  deployment, production promotion, or Linear `Done`.

## Approach

1. Add an explicit background-connection requirement to the shared realtime
   manager. Keep its default foreground-only behavior for every existing
   consumer and reconnect in background only while the scoped lease is active.
2. Make Payment Monitor separate speaker eligibility from list foreground
   eligibility. Background events may drain/play speaker notifications, but
   may not fetch or mutate the visible transaction list.
3. Extend Sales Report order inspection to distinguish an existing
   `SYNC_LIST` report from other duplicates only inside an authorized follow-up
   case.
4. In the existing follow-up transaction, claim the open case, conditionally
   update exactly one `SYNC_LIST` report to `COMEBACK`, link that same report to
   the entry/case, and fail concurrent or already-converted attempts cleanly.
5. Keep normal manual/ERP creation on the existing unique `orderCode` path and
   return the specific COMEBACK duplicate message when applicable.
6. Update user-visible copy, AppLogger/backend logs, product truth, tests, and
   affected-consumer evidence. Integrate the two workstreams only after their
   focused proofs pass.

## Risks And Recovery

- Shared realtime regression: the lease defaults off and tests protect Home,
  notifications, delivery metrics, warranty, quick actions, auth refresh, and
  payment-list foreground behavior.
- Duplicate playback or reconnect: retain the manager event-id cache and the
  provider terminal/queued/in-flight sets; add hidden/reconnect/resume cases.
- Transaction race: rely on the existing unique `orderCode`, open-case compare
  and conditional `entrySource='SYNC_LIST'` update inside one transaction.
- Cross-domain review cost: keep implementation/tests/logs in separate commits
  where practical and summarize each domain separately in the PR.
- Recovery: revert the task branch commits or close the unmerged PR. Canonical
  `staging` and user stashes are not modified by implementation. The stale,
  clean OPS-14 worktree/local branch was separately removed after explicit
  user authorization and verification that it had no unique work.

## Progress

- [x] Read Linear, comments, repository authority, lifecycle playbook, and
  relevant code/tests.
- [x] Record and verify the clean live-base worktree checkpoint.
- [x] Move OPS-16 to In Progress after posting a setup/proof note and read it
  back; OPS-14 was already In Progress.
- [x] Remove the stale clean OPS-14 worktree/local branch after verifying no
  diff, ignored artifact, unique commit, remote branch, or PR; preserve all
  stashes and the guarded combined worktree.
- [x] Implement and focused-test OPS-14.
- [x] Implement and focused-test OPS-16.
- [x] Update docs/test matrix and run affected-consumer proof.
- [x] Run the repository validation ladder and inspect the exact final diff.
- [ ] Commit, push, open the staging PR, monitor CI, then record/read back proof
  and transition both issues to In Review.

## Decisions

- 2026-07-24: Use one shared realtime socket with a scoped payment-speaker
  background lease. A dedicated second consumer conflicts with the repository's
  one-authenticated-socket contract and increases duplicate risk.
- 2026-07-24: Keep UI/list reads foreground-only; background authority applies
  only to speaker realtime and metadata recovery.
- 2026-07-24: Reuse the existing `SalesReport.orderCode` uniqueness and avoid a
  schema migration. Conversion updates the existing row and its follow-up links
  in one transaction.
- 2026-07-24: After explicit user authorization, remove the stale clean OPS-14
  worktree/local branch. The combined task remains on the guarded worktree
  created from live `origin/staging`; user stashes remain intact.
- 2026-07-24: Source conversion is strictly one-way. Only a conditional
  `SYNC_LIST` to `COMEBACK` transition is valid; an existing `COMEBACK` report
  is never changed back and is treated as a duplicate for every retry/source.

## Validation

- OPS-14 focused proof: realtime manager, authenticated coordinator, runtime
  coordinator, payment monitor/provider, local speaker fallback/FIFO tests.
- OPS-14 affected consumers: notifications, delivery metrics, Home, warranty,
  quick actions, bank statement, offset adjustment, and Sales Report providers
  remain foreground/route gated.
- OPS-16 focused proof: Sales Reports, follow-up cases, BigQuery mapping,
  provider/form/widget tests, duplicate-source matrix, and concurrent claims.
- Integration proof: Nest build plus focused/full Jest; Flutter analyze plus
  focused/full tests; Windows debug build if local dependencies permit; `git
  diff --check` and exact diff review.
- Post-PR proof: required GitHub checks. Physical Windows speaker QA and safe
  staging synthetic latency/duplicate evidence remain staging gates, not local
  review-readiness claims.

## Result

Implementation and local validation are complete on the integrated changeset.
OPS-14 focused Flutter tests pass 49/49 and affected realtime/UI consumers pass
187/187 (185 serial plus 2 runtime-coordinator tests); Flutter analyze and the
full Flutter suite pass with 610 tests and 3 intentional platform skips. OPS-16
focused Nest proof passes 3
suites/89 tests; Nest build and all 88 suites (863 tests) pass. Prisma
validation, 64 Go tests, the Windows debug build, formatter check, and `git
diff --check` pass. Independent final reviews found no remaining blocking issue
and confirmed the strictly one-way `SYNC_LIST` to `COMEBACK` invariant.

The remaining work is publication and review tracking: commit the bounded
scope, push the task branch, open a ready PR to `staging`, monitor required CI,
then write and read back the implementation/proof notes before moving OPS-14
and OPS-16 to `In Review`. Physical Windows speaker QA, live PostgreSQL
concurrency, and live BigQuery refresh remain staging-only proof.
