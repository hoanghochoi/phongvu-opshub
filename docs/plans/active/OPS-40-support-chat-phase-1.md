# Execution Plan: OPS-40 Support Chat Phase 1

Date: 2026-08-01

## Status

Active

## Outcome

Deliver the disabled-by-default Phase 1 Support Chat contract across Nest,
PostgreSQL, Go realtime and Flutter current UI, with private media, durable
invalidation, notifications, retention, rollback and affected-consumer proof.

## Context

- Product: `docs/product/support-chat.md`; Linear `OPS-40`.
- Story/proof: `docs/stories/SUPPORT-CHAT-001-phase-1.md` and
  `docs/TEST_MATRIX.md`.
- Architecture: `docs/decisions/0010-client-cache-and-realtime-invalidation.md`,
  `docs/decisions/0011-composite-principal-rate-limit-without-global-ip-bucket.md`.
- UI: current runtime/shared design system under owner steer. OPS-34 R2.9 is
  approved foundation context, not an exact Support Chat frame.
- Checkpoint: lifecycle `START PASS`; branch
  `codex/ops-40-support-chat-phase-1` at
  `4850c4ba6b9ee8022d47c7fb6b8c7a5e8bea35da`, initially clean and equal to
  live `origin/staging`.

## Scope

In scope:

- Wave 1 data, REST, authorization, idempotency, private image media and rate
  limits.
- Wave 2 durable outbox, Redis and strict v2-only realtime invalidation,
  bootstrap capability and additive notification feed.
- Wave 3 requester/admin current-UI Flutter flows, AppShell/assignment-pending
  launcher, shared floating stack, Seatalk fallback and memory-only state/media.
- Wave 4 retention worker, feature-off rollout, backup/restore purge and
  rollback documentation.
- Focused and full affected-consumer proof.

Out of scope:

- Figma changes or redesign approval.
- User/group chat, bot/AI, documents, voice/video, reactions, presence,
  edit/delete, push/email/Seatalk bot, offline queue, Markdown/link preview.
- Commit, push, PR, staging enablement, QA, release or `Done` transition without
  their later explicit gates.

## Architecture Envelope

This task implements accepted repository architecture rather than selecting a
new one:

1. Capacity evidence: staging smoke target 20 text messages/second; exact
   one-year p99 forecast is not asserted. Bounded pages/batches and indexed
   PostgreSQL paths avoid a premature scale architecture.
2. Tenancy: one internal OpsHub organization; authorization is per requester
   and Super Admin, not a new tenant model.
3. Flow: synchronous REST/PostgreSQL default; durable asynchronous invalidation
   is the explicit exception.
4. Sensitivity: private internal staff text/images with identity references;
   treat as sensitive/PII-adjacent, minimize and retain for 180 days.
5. Topology: existing Nest modular monolith + existing Go gateway; no new
   service or socket.
6. Recovery: retain platform RPO 24h / RTO 4h evidence requirements; restore
   purges expired chat data before enablement.
7. Reliability: no user SLA. Release gates are queue/history p95 <500 ms,
   outbox p95 <2 seconds, no dead letters and no unpublished row >60 seconds.

## Approach

1. Freeze authority and path contracts in product/story/plan/Test Matrix.
2. Add expand-only schema/migration/rollback, domain module and transaction
   tests. Verify migration on fresh and upgraded disposable PostgreSQL.
3. Extend private media with explicit `SUPPORT_CHAT` authorization and failure
   compensation; rerun warranty/feedback/avatar proof.
4. Add durable outbox publisher/retention worker, bootstrap capability and
   notification section; verify Redis-down send success and existing consumers.
5. Add strict Go channel mapping as v2-only and fail-closed tests without
   modifying legacy v1 behavior.
6. Add Flutter data/provider/current-UI surfaces and shared launch/floating
   stack integrations. Verify auth generation, logout/account-switch cleanup,
   reconnect resync, memory-only images and responsive/accessibility behavior.
7. Run focused proof after each batch, then full affected proof on the frozen
   final diff. Record exact results and residual staging gates in Linear.

## Audit-Gated Correction Wave

Read-only contract and repository audits on 2026-08-01 found that the initial
cross-service implementation is structurally broad but is not contract-ready.
Keep `SUPPORT_CHAT_ENABLED=false` while one serialized production writer fixes
the following coherent batch:

1. Establish one canonical Nest-to-Flutter response schema and shared JSON
   fixtures for requester/admin history, message sends and state mutations.
   Align multipart MIME handling so accepted Flutter images reach server-side
   normalization.
2. Change requester deletion semantics to the accepted nullable relation and
   retention-owned cleanup; update expand/rollback migration proof without
   deploying or down-migrating any shared environment.
3. Make Support Chat notification failure isolated from the existing feed,
   compute the Super Admin unread set as unassigned plus assigned-to-me, and
   consume the additive schema-v1 section as the single global Support Chat
   unread source in Flutter.
4. Strictly allowlist Support Chat realtime payload fields, remove former-
   assignee thread routing, and retain v2-only fail-closed behavior.
5. Repair admin selected-thread resync, older-history pagination and required
   queue ordering; gate admin tile/route from the explicit bootstrap capability
   while preserving Seatalk and public fallback behavior.
6. Add deploy flag defaults, restore-time purge/rollback guidance, worker and
   recovery proof, plus `scripts/validate-ops40-affected-consumers.mjs` mapping
   every protected old consumer without calling removed Harness commands.

Decision 0011 remains authority for endpoint-specific composite-principal
rate-limit keys: the four send routes keep their documented 30/minute text and
6/minute image quotas inside the existing 120/minute endpoint bucket model.

## Risks And Recovery

- Authorization/IDOR: server derives every identity and re-checks active roles;
  rollback disables the feature flag.
- Database race/data loss: unique constraints + conditional writes + serial
  sequence transaction; migration is expand-only and includes rollback rehearsal.
- Filesystem/DB partial media failure: reuse normalized private-media atomic
  write and explicit compensation/orphan cleanup.
- Redis outage/duplicate: HTTP remains authoritative; outbox retries and clients
  resync once on reconnect.
- Shared shell/feed/bootstrap regression: additive schema only plus named
  affected-consumer suites before moving to the next wave.
- Sensitive logging/cache: sanitized structured context and sentinel scans;
  Flutter chat state/images remain memory-only.
- Rollback: set `SUPPORT_CHAT_ENABLED=false`; keep additive data/migration,
  restore Seatalk launcher behavior, and do not down-migrate in production.

## Progress

- [x] Read AGENTS/project authority, OPS-40/25/34 relations and comments.
- [x] Restore canonical staging and pass lifecycle dry-run + `start --execute`.
- [x] Record/read back Linear checkpoint and move OPS-40 to `In Progress`.
- [x] Map Nest/Prisma, Go realtime and Flutter affected consumers.
- [x] Complete batch 0 authority docs and docs-only verification.
- [x] Recover the focused Flutter bundle on the current fingerprint: 53 tests
  passed with exit 0; no-op generated/l10n status entries were proven blob-
  identical to `HEAD` and removed by index refresh without staging content.
- [x] Complete read-only spec and backend/realtime audits; record the
  correction wave above before further production edits.
- [x] Complete Wave 1 implementation and focused proof.
- [x] Complete Wave 2 implementation and focused proof.
- [x] Complete Wave 3 implementation and focused proof.
- [x] Complete Wave 4 operational implementation and local proof.
- [x] Run final full affected-consumer validation on exact diff.
- [x] Close the publish-proof gap with fail-closed `--base <ref>` committed-diff
  discovery and focused wrapper self-tests; keep default pre-commit discovery.
- [x] Add and read back Linear implementation/proof note
  `a1101772-9d66-45e3-977b-1635042050ac`; OPS-40 remains `In Progress`
  with no lifecycle transition.

## Decisions

- 2026-08-01: Use current/legacy runtime UI and shared tokens/components by
  direct owner steer. This neither creates nor approves a redesign.
- 2026-08-01: Keep one OPS-40 lifecycle branch for the coherent cross-service
  contract; no separate child issue is required before implementation.
- 2026-08-01: Keep HTTP/PostgreSQL authoritative and make Support Chat a
  strict `/ws/v2` invalidation-only consumer.

## Validation

- Focused proof: new domain/controller/provider/widget suites plus the precise
  existing consumer suites named in the story path contracts.
- Integration proof: disposable PostgreSQL fresh/upgrade/rollback and race
  tests; Redis outage/outbox retry; private-media normalization/access/cleanup;
  realtime audience/reconnect; current-UI responsive/accessibility tests.
- Repository checks: Prisma validate/generate, Nest build/full Jest, Go
  test/vet, Flutter analyze/full tests and Windows/Android/web debug builds,
  then `git diff --check`.

## Result

Local implementation and affected-consumer proof pass with the feature flag
still disabled. Final evidence on 2026-08-01:

- Post-OPS-33 reconciliation is pinned to feature commit `b8984ef1`, merged
  `origin/staging@47ec0956` and merge HEAD `97122acb`. The TEST_MATRIX order
  remains OPS-40, OPS-33, OPS-41; the focused route guard passes with all 40
  authenticated routes, 88 route/viewport checks and `Hộp thư hỗ trợ`.
- Prisma validate, generate and static migration contract: PASS. The single
  isolated PostgreSQL binary rehearsal was stopped and cleaned safely but did
  not complete fresh/upgrade/rollback; per coordinator authority it was not
  retried and remains unverified due local execution/runtime behavior.
- Nest build: PASS. Focused final correction batch: 4 suites/22 tests PASS.
  Affected wrapper Nest set: 14 suites/152 tests PASS. Full Jest: 102 suites/
  1106 tests PASS. Post-merge OPS-33 proof also passes 5 suites/206 tests;
  Contract Appendix passes 6 Nest suites/46 tests and 10 Flutter tests.
- Go realtime: `go test ./...` and `go vet ./...` PASS, including v2 payload
  allowlisting and all existing realtime consumers.
- Flutter: analyze PASS with no issues; final Support Chat/design focused batch
  38 tests PASS; affected wrapper mapped 102 tests PASS; full machine run
  passes 696 tests with 3 intentional skips under `--concurrency=1`. The
  post-merge Home/Sales Report bundle passes 53 tests. An initial concurrent
  full run missed one OPS-33 debounce assertion; that exact test then passed
  6/6 isolated runs before the serial full-suite PASS, with no code change.
- Final platform builds: Windows debug PASS
  (`build/windows/x64/runner/Debug/phongvu_opshub.exe`, 1,058,816 bytes),
  staging APK debug PASS (`build/app/outputs/flutter-apk/app-staging-debug.apk`,
  207,065,744 bytes), and web debug plus wasm dry-run PASS (`build/web`).
- `OPS40_SECURITY_SENTINELS_PASS`; affected path-contract wrapper default and
  `--base origin/staging` modes PASS (67 base-aware paths); committed/dirty/
  untracked/invalid-base/dedup self-tests pass 2/2; wrapper Prettier and
  `git diff --check` PASS. No generated/plugin status-only noise remains.

Still pending and not local completion claims: disposable PostgreSQL migration
rehearsal, staging two-requester/two-admin QA, 20 message/s load, live Redis
restart/outage and metrics evidence, backup/restore purge rehearsal, exact-SHA
staging deployment, release approval and production deployment. Future Figma/
redesign work remains a separate follow-up; the current UI authority is
temporary and is not redesign approval.
