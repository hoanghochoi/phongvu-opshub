# Execution Plan: OPS-64 Upstream Harness, Workflow And OpsHub Cleanup

Date: 2026-08-13

## Status

Active — the current workflow checkpoint is OPS-150 Phase 9C main-KPI
runtime extraction, created from exact live
`origin/staging@cef2b17071cbe11537e349a656d3baac72d008e9` after OPS-149.
OPS-149 Home Summary sales-progress runtime extraction is squash-merged through
PR #273 at `cef2b17071cbe11537e349a656d3baac72d008e9`, staging-deployed by
`31938424395`, and tracked `Ready for QA` after proof. Its local Flutter
affected-consumer proof remains an explicit environment residual because the
dependency root is unavailable; no profile was suppressed and no product
failure was retried to green.
OPS-148 Home Summary comparison runtime extraction is squash-merged through PR
#272 at `324c87d264df3b96ee6409d939aaa5dcf0a97091`, staging-deployed by
`31936440130`, and tracked `Ready for QA` after proof. Its local Flutter
affected-consumer proof remains an explicit environment residual because the
task worktree lacked `.dart_tool/package_config.json` and plugin metadata; no
profile was suppressed and no product failure was retried to green.
OPS-138 organization-tree/assignment extraction is squash-merged through PR
#264 at `db427f6d44d2dde5c219a982fc1d835e9378e536`, staging-deployed by
`31923613626`, and tracked `Ready for QA` after proof. OPS-70 protocol-v1
retirement is merged at `5685b5e6b5714924a716a5b4dd77f0a4b9925514` and
OPS-71 docs/plan authority normalization is merged at `02045ba7`; both have
passed guarded lifecycle cleanup and remain production-pending.
OPS-72 has five valid shadow observations but remains `revise` /
`do-not-promote` because the measured timing reduction is 8.77% and rerun
reduction is unmeasurable. The dependency-hardening work is deliberately
deferred as residual risk; no dependency gate is weakened or treated as a
pass. Product, API, permission and runtime behavior stay unchanged.

### OPS-114 checkpoint — dependency bootstrap enforcement

- Branch/worktree: `codex/ops-114-enforce-dependency-bootstrap` in
  `../opshub-ops-114`, created by the lifecycle gate from exact
  `origin/staging@b93ec7e4d15104a6afc428912324c72af4bbe9d0`.
- Before mutation the task had no tracked changes. Lifecycle hydration finished
  independently for Nest/Prisma and Flutter; its ignored readiness state names
  the task-local fingerprints and is not copied from another worktree.
- Affected authority: `run-with-toolchain`, verification profiles, current
  command/runbook templates, release workflow command blocks and toolchain
  coverage tests. Product/runtime APIs, Docker context ownership and data/UI
  behavior are explicitly out of scope.
- Required proof: focused toolchain/verification/lifecycle tests, direct
  wrapped Flutter analysis and Nest build, workflow syntax/static coverage, and
  exact `verify-task --base origin/staging` with `stale=false` after the final
  docs change. A squash revert of the OPS-114 merge is the rollback unit.

## Outcome

Move OpsHub from the legacy SQLite/protocol-v1 Harness surface to the
upstream repository protocol, then improve verification workflow, reconcile
plans/docs, remove proven dead Harness/artifact surfaces, and refactor large
runtime modules in independently verifiable slices. Product behavior, API,
permission, security, platform and approved UI contracts remain unchanged.

The legacy `harness.db` is migration input and a local, read-only archive. It
is never refreshed by upstream `import brownfield`, never written by this
branch, and is not converted row-for-row into Markdown.

## Authority and checkpoint

- Linear parent: `OPS-64`.
- Previous slice: `OPS-96` MAP Vietin HTTP/session/backoff extraction, merged
  into `staging` at `7a06f1272ae97f02d5fecc2c3a29e80a8db70f5a` after deploy
  `31770320592` and guarded lifecycle cleanup. `MapVietinProviderRuntime`
  owns bounded provider transport, MAP/eFAST session caching and provider
  backoff/retry-after state; the service facade and public contract are intact.
- Previous slice: `OPS-97` MAP Vietin sync scheduler/coordinator extraction,
  created from exact live `origin/staging@7a06f1272ae97f02d5fecc2c3a29e80a8db70f5a`.
  PR #208 merged into `staging` at
  `73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a`; deploy `31773642512`, post-merge
  CodeQL `31773642509`, and guarded lifecycle cleanup passed. Linear remains
  `Ready for QA` until production deployment. The coordinator owns timer
  lifecycle, MAP/eFAST windows and cadence, backoff-aware scheduling,
  deep-sweep state and single-flight leases; `MapVietinService` remains the
  stable facade and owns sync execution, persistence, statement policy and
  response mapping.
- Previous slice: `OPS-98` Nest/Prisma toolchain bootstrap, created from exact
  live `origin/staging@73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a`, merged in PR
  #209 at `b9fe4d6e0234ea3f89561978b8974e738b0f8dfb`, and staging-deployed by
  run `31777758147`. The guarded lifecycle finish passed and the task worktree
  and local/remote task branch were removed. Its preflight remains the tracked
  remedy for fresh worktrees missing `backend-nest/node_modules` and Prisma
  client output.
- Previous slice: `OPS-99` User/Auth characterization, created from exact live
  `origin/staging@b9fe4d6e0234ea3f89561978b8974e738b0f8dfb`, merged in PR #210 at
  `00a8021c5848abe8032dad1385cf65f139748aef`, and staging-deployed by run
  `31780994964`. Linear is `Ready for QA`; the focused suite passed `70/70`,
  affected Nest auth/session/access-change passed `177/177`, affected Flutter
  auth/profile/admin passed `48`, and the exact runner reported `stale=false`.
  This test-only slice preserved the public facade and left collaborator
  extraction to the current slice.
- Previous slice: `OPS-100` UserService profile collaborator extraction,
  created from exact live
  `origin/staging@00a8021c5848abe8032dad1385cf65f139748aef`. PR #211 merged into
  `staging` at `6817cdfd60fe8dbbbc6f64a497765669dba4e562`; exact-SHA staging
  deploy run `31783456149` passed and Linear is `Ready for QA`. The slice
  extracted only profile DTO/read, update
  validation/trim and avatar media compensation behind the stable facade.
  The task worktree/local branch are absent after merge; production completion
  is not inferred from that repository state.
  OPS-89 cache state, in-flight dedupe, refresh-ahead, daily-series extension,
  support caches, scope-option caching and projection invalidation remain in
  `home-summary-cache.runtime.ts`.
  OPS-72, OPS-73, OPS-74 header, OPS-81 KPI/summary, OPS-82 detail-renderer
  and OPS-83 analytics/progress slices are merged at the current checkpoint.
- OPS-80 replaces the single joined comparison cache interval with independent
  primary and previous-year coverage ranges. Strict 366-day validation remains
  unchanged; focused Home Summary proof passed `72/72`, all Home Summary Nest
  suites passed `119/119` with 6 skips, the Nest build passed, affected Flutter
  Home proof passed `60/60`, and exact-base full verification passed all eight
  profiles with `stale=false`. PR #201 merged into staging at
  `5c3867fae35bd022a6a599283fce9a62032476e6`; deploy run `31750262557`
  passed. Linear remains `In Progress`; authenticated four-day smoke and
  production deployment are still open.
- Previous slice: `OPS-70` (Phase 5 protocol-v1 retirement and Harness producer
  cleanup) on a fresh lifecycle worktree created from the live `origin/staging`
  checkpoint.
- Previous slice: `OPS-65` (Phase 0 baseline/master plan), Phase 0-1 archive
  tooling, and Phase 2 upstream adoption; PR #175 is merged into `staging`.
- Historical Phase 0-1 branch: `codex/ops-64-harness-cleanup-phase-0-1`;
  its exact base was `6525b6e3805eb666a86066cfe98469d5dba4af53`.
- Historical OPS-73 NestJS branch: `codex/ops-73-nestjs-artifact-dependency-audit`;
  its base was `b2a2df9cd47e7f1007ad92872c7b8547353656dc` and PR #185 merged
  into staging at `ccff928f703c3a5dc0969798e6d02905d7c164ce`.
- Historical OPS-73 Go/deployment branch: `codex/ops-73-go-deployment-artifact-audit`.
- Historical OPS-73 Go/deployment base/HEAD checkpoint:
  `ccff928f703c3a5dc0969798e6d02905d7c164ce`.
- `origin/staging` matched `ccff928f703c3a5dc0969798e6d02905d7c164ce` when
  that historical lifecycle start gate passed.
- Canonical staging worktree was clean. Existing worktrees were preserved and
  were not reset, removed, or rewritten.
- Historical implementation worktree: `../opshub-ops-92`.
- Historical OPS-92 branch: `codex/ops-92-sales-reports-scope-query`.
- OPS-89 implementation worktree/branch was cleaned after its squash merge;
  canonical staging and `origin/staging` are at
  `77ec6ff3482b3ff689e10af77b6981c1a96293d`.
- OPS-90 and OPS-91 compatibility wrappers are internal facade inspection
  points only; they preserve characterization spies without widening the
  product API.

- OPS-68 implementation worktree:
  `../opshub-ops-68-disposition-ledger-fresh`.
- OPS-68 branch: `codex/ops-68-disposition-ledger-fresh`; PR #176 merged into
  `staging` at `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`, and its post-merge
  lifecycle `finish --execute` gate passed.
- Historical OPS-69 implementation worktree:
  `../opshub-ops-69-current-authority-promotion`.
- Historical OPS-69 branch:
  `codex/ops-69-current-authority-promotion-and-linear-follow-ups`.
- Historical OPS-69 base SHA and live `origin/staging` checkpoint:
  `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`.
- OPS-69 was created from that exact lifecycle checkpoint; publication and
  current-authority promotion were merged through PRs #177 and #178.
- OPS-70 implementation worktree: `../opshub-ops-70-retire-protocol-v1`.
- OPS-70 branch: `codex/ops-70-retire-protocol-v1-and-harness-producers`.
- OPS-70 base SHA: `e83c24bb7ae6cd83af379ec003818ad74b6fcbe0`; canonical staging
  and `origin/staging` matched it at task start.
- OPS-70 squash merge: `ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1`; lifecycle
  `finish --execute` passed.
- OPS-71 base SHA: `ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1`; canonical staging,
  `origin/staging` and the OPS-71 task worktree matched before cleanup.
- Historical reconciliation slice: `OPS-143`, branch
  `codex/ops-143-reconcile-master-plan-after-ops-138-ops-71`, started from
  exact `origin/staging@02045ba7c5c772e734040b1b6593faff98526293`. It updates
  only this master plan and the active-plan index after OPS-138/70/71; no
  runtime, dependency manifest, archive or Harness DB files are in scope.
- Current reconciliation slice: `OPS-146`, branch
  `codex/ops-146-master-plan-checkpoint-after-ops-145`, started from exact
  `origin/staging@c46cf5d9c5e64e8e7e855e8c8fd5290941e9dafe`; it records the
  post-OPS-145 merge, staging deploy and lifecycle evidence without changing
  runtime, dependency, archive or Harness DB files.

Before every later slice, repeat the lifecycle start gate and replace this
checkpoint if the live `origin/staging` SHA changes. A proof run is stale when
HEAD, worktree/index state, guard source, path contracts, commands, or story
authority changes during the run.

## Scope

### In scope for the complete initiative

- Adopt upstream `repository-harness` `harness-v0.1.8` as the only Harness
  product surface.
- Preserve and disposition the legacy Harness knowledge without making the DB
  a new authority.
- Add one repository-owned `verify-task` runner with changed-path contracts,
  structured results, fingerprints and fail-closed stale-proof handling.
- Reduce repeated validation friction, including benign Flutter plugin noise,
  without retry-to-green behavior.
- Reconcile `docs/plans/active/`, product/docs authority, duplicate artifacts,
  and proven unused dependencies.
- Refactor oversized Home, payment, sales, MAP and user/auth modules behind
  stable public facades, one bounded context per slice.

### Explicitly out of scope for this slice

- Deleting the raw local archive or changing product/runtime behavior.
- Writing, migrating, refreshing, or compacting the authoritative DB.
- Runtime code or UI refactors.
- Linear status transitions to `Done`, production deployment, direct pushes,
  or public upstream posting.
- Removing the raw local archive; that requires a separate explicit decision.

## Phase map and dependency gates

| Phase | Deliverable | Required gate before next phase |
| --- | --- | --- |
| 0 | Checkpoint, inventory, baseline metrics, master plan | clean canonical worktree; two stable inventories; `git diff --check` |
| 1 | WAL-safe local archive, manifest, disposition schema/export | source hash unchanged; two archive copies pass integrity/counts; no secrets |
| 2 | Upstream `harness-v0.1.8` payload/adoption and ADR | status/doctor/update dry-run plus conflict/continue/abort proof |
| 3 | Sanitized legacy disposition and current-authority promotion | all 199 records have one disposition and valid targets |
| 4 | Generic `verify-task` runner and canary wrappers | changed paths fail closed; fingerprint invalidates stale proof; canary parity |
| 5 | Retire protocol-v1 producer/SQLite surfaces | fresh checkout works without DB/CLI; references only in archive/EOL docs |
| 6 | Plans/docs authority reconciliation | every active plan classified; no broken links/conflicting authority |
| 7 | Flutter test preflight and CI profile/shadow matrix | no known benign plugin noise; no missed affected consumer in shadow runs |
| 8 | Artifact/dependency/toolchain cleanup | allowlist/reference/build/package checks pass |
| 9 | Runtime refactor waves | characterization + focused + affected-consumer proof per slice |
| 10 | Final consolidation and release evidence | full ladder, staging smoke, archive/disposition/fingerprint checks |

Phases 0-8 are serialized by authority and verification changes. Runtime waves
are also serialized within a bounded context; no two production writers share
the same worktree or overlapping paths.

## Phase 0 — baseline and inventory

Record the following as sanitized, reproducible evidence (not raw DB payload):

- Git branch, exact HEAD/base, staged/unstaged/untracked paths, normalized file
  modes, deletions and all protected worktrees.
- Tracked/ignored Harness files, schemas, adapters, installers, binaries,
  release workflows, docs/contracts and current pins.
- DB schema version, table counts, source SHA and known local-only fields.
- All plans under `docs/plans/active/` with file size, status evidence,
  referenced issue/PR and proposed disposition.
- Verification commands, path-contract validators, repeated failure classes,
  plugin exceptions, rerun observations and runtime hotspots.
- Baseline metrics: active-plan count, median time to first actionable failure,
  same-fingerprint reruns, known benign plugin exception count, and hotspot
  line/byte counts. Metrics are comparison signals, not completion gates by
  themselves.

The two inventory passes must be identical. If the worktree changes while
inventory runs, discard the result and restart from a new checkpoint.

## Phase 1 — archive and migration artifacts

The archive is local-only by explicit choice. Create two copies when the
machine exposes two safe paths:

- `.harness-backup/retirement-<UTC>/` under the canonical repository; and
- `%USERPROFILE%\Documents\OpsHub-Harness-Archive\retirement-<UTC>\`.

If both paths are on one physical disk, record that residual loss risk. Do not
claim off-host backup. Keep the source DB untouched and read-only.

Archive procedure:

1. Confirm no process owns the source DB for writing and record source SHA.
2. Use SQLite online backup/WAL-safe snapshot; never use a raw file copy as the
   consistency proof while WAL may be active.
3. Run `PRAGMA integrity_check`, foreign-key check, schema-version inventory,
   table counts and deterministic row digests against each copy.
4. Use a separately downloaded and checksum-verified immutable
   `harness-cli-v0.1.22` only for read/export support. The local ignored
   `harness-cli 0.1.11` is not migration evidence.
5. Re-hash the source; any change fails the phase.
6. Commit only sanitized manifests and disposition metadata. Raw DB/WAL/SHM,
   exports and downloaded binaries remain local and ignored.

Expected source counts are 92 intakes, 37 stories, 7 decisions, 27 backlog
items and 36 traces; schema versions 1 through 12 must be present. The tracked
manifest schema is `formatVersion`, `source`, `legacyTool`, `copies` and
`dispositionSha256`. The disposition ledger has one entry for every legacy
record and accepts only `promoted`, `already-authoritative`,
`linear-follow-up`, `superseded`, `historical-only` or `rejected-with-reason`.

No DB row is imported into upstream schema 14. Current behavior, decisions,
open follow-ups and affected-consumer contracts are promoted only to their
proper Git/Linear owners.

## Phase 2 — upstream protocol adoption

Install/adopt the exact upstream payload from the tagged release using merge
and three-way update behavior. Preserve OpsHub-specific policy outside the
managed Harness block. Add the upstream `improve-harness` skill, application
runbook and improvement template where they are part of the declared payload.

The only supported local Harness interface after cutover is upstream
`status`, `doctor`, `update`, `update --dry-run`, `update --continue` and
`update --abort`. OpsHub does not publish a Harness binary or maintain a
SQLite/protocol-v1 compatibility product.

Create ADR `0029-adopt-upstream-repository-protocol-and-retire-protocol-v1.md`
to supersede Harness-only SQLite/protocol-v1 decisions while preserving
product/runtime ADRs. Prove fresh install, non-overlapping update, conflict,
continue, abort and interrupted-update recovery in disposable copies.

## Phase 3 — disposition and promotion

Disposition every 199 legacy records exactly once. Stories and decisions that
still describe current behavior map to existing product/ADR/story authority;
open backlog becomes deduplicated Linear follow-up; historical traces/intakes
become a sanitized grouped migration summary. Path contracts and affected
commands are promoted only when their consumer still exists. Invalid prose is
never turned into a path contract.

Every `promoted`, `already-authoritative` or `linear-follow-up` entry must have
an existing target. Record implementation/proof in Linear before any forward
status transition and read it back.

## Phase 4 — verification runner

Build `scripts/verify-task.mjs` from the existing changed-path behavior in the
OPS-39/OPS-40 validators. Profiles contain `id`, path patterns, affected
consumers, prerequisites and argv arrays with explicit `cwd`; they do not store
fragile shell strings.

Required behavior:

- working-tree plus staged/untracked discovery; optional base-aware committed
  diff; rename evaluated as delete plus add;
- unmatched runtime/verification paths fail closed;
- explicit profile selection adds profiles but never suppresses auto-selected
  profiles; `--full` adds the full ladder;
- JSON schema v1 includes exact base/HEAD, profiles, consumers, tool versions,
  duration, sanitized result and a fingerprint;
- fingerprint covers command/config/runner hashes and all relevant Git state;
- recompute after the final command and exit stale when it changed;
- exit codes 0 pass, 2 contract/preflight, 3 product/test, 4 stale, 5
  environment/infrastructure.

Keep existing story validators as compatibility wrappers until three canary
tasks prove equivalent results. Never accept a pass from a different
fingerprint.

## Phase 5 — legacy retirement

Only after archive, disposition, upstream canary and parity pass, remove the
SQLite schemas/adapters/materialization/rebuild surfaces, protocol-v1 contracts,
CLI build/release/promotion workflows and tests whose only owner was that
surface. Retain Git history, ADR, migration manifest/disposition and local
archive guidance. Keep `.gitignore` protection for consumer-owned legacy DB,
WAL/SHM and binaries; the old DB is not automatically deleted.

Fresh checkout, upstream `status`/`doctor`, update dry-run, runtime builds and
tests must work without the retired files. Remaining SQLite/protocol-v1
references are allowed only in explicit EOL/archive/migration material and
`.gitignore`.

## Phase 6 — docs and plans

Classify every active plan as `active`, `execution-complete`,
`release-pending`, `superseded`, `cancelled` or `duplicate/stale`. A merged PR
does not imply production `Done`; release-pending plans retain the gap and
Linear stays open. Consolidate OPS-44 and OPS-53 execution fragments into
canonical summaries, move durable product/design rules to their owning docs,
repair indexes/backlinks and remove ordinary historical journals only after
disposition mapping.

## Phase 7 — validation and CI

Add a shared Flutter test bootstrap that initializes the binding, uses owned
temporary path-provider storage, stubs file-picker cancellation by default,
initializes mock preferences and disables AppLogger network upload. Tests that
exercise import/export inject explicit picker behavior. Do not swallow unknown
plugin errors.

Run the changed-path matrix in shadow mode for at least five representative
PRs while existing blocking gates remain. Move profiles to blocking only after
no missed consumer is found. Infrastructure retries are bounded and classified;
product tests are never retried to green.

## Phase 8 — artifact/dependency cleanup

Use allowlists to distinguish generated platform assets from duplicate sources.
Remove only files with no references, build/package owner, migration owner or
rollback requirement. Explain every lockfile change and run affected builds,
Prisma validation, Go tests, asset scans and deployment-reference checks.

## Phase 9 — runtime waves

Refactor one bounded context per PR, retaining public facades and interfaces.
Characterization tests precede extraction. Planned order:

1. Flutter Home: header/filter, summary/comparison, details, analytics.
2. Payment monitor: list state, realtime lease, speaker queue/audio, actions.
3. Nest Home Summary: cache, scope, projection, comparisons, aggregation.
4. Sales Reports: scope/query, aggregation, import comparison, admin/export.
5. MAP Vietin: clients/backoff, scheduler, persistence/dedup, policy, mapping.
6. User/Auth: profile/admin, import, organization tree, store admin, access.

Each slice must preserve routes, DTOs, DI tokens, permission, logs, copy and
UI geometry, then run focused tests plus every old affected consumer. File size
is only a review signal; do not split code mechanically or create a new
god-helper.

## Rollback and residual risk

- Every phase is a separate PR-sized change and can be reverted independently.
- Source DB and local archive are never mutated by repository cleanup.
- A missing archive copy, count/digest mismatch, stale proof, unresolved
  upstream conflict or unmatched consumer blocks the phase.
- Local-only archive has disk-loss risk; manifest records whether both copies
  share a physical disk. Raw archive deletion requires explicit approval.
- Upstream legacy consumers may pin `harness-cli-v0.1.22` independently after
  EOL; OpsHub current tree provides no compatibility maintenance.

## Progress

- [x] Create Linear parent `OPS-64` and child `OPS-65`.
- [x] Pass lifecycle start gate from live `origin/staging` and create task
  worktree/branch.
- [x] Record exact base SHA and initial clean/worktree checkpoint.
- [x] Add Phase 0 baseline inventory and this durable plan. The two initial
  baseline passes were byte-identical with SHA-256
  `225eabaad96dfe1cbfd2356128c0b77cfaadfba27a2c74495ddb4c298147273` (the
  reproducible command and final sanitized output are retained in
  `docs/migrations/harness-cleanup-baseline.json`).
- [x] Add Phase 1 WAL-safe archive/export tooling and manifests.
- [x] Verify archive copies, counts, digests and source immutability. The
  validated archive timestamp is `20260813T013900Z`; source SHA and logical
  state remained unchanged.
- [x] Adopt the upstream `harness-v0.1.8` payload declaration, release pin,
  explicit-only improvement skill and generic runbook templates; add ADR 0029.
- [x] Verify tagged Windows binary identity (`harness 0.1.8`) and disposable fresh install, status/doctor/update dry-run behavior. Customized `AGENTS.md` preservation is proven.
- [x] Complete disposable updater lifecycle proof using the published
  `harness-v0.1.7` → `harness-v0.1.8` transition. The v0.1.7 and v0.1.8
  Windows artifacts were downloaded through the GitHub Releases API and
  matched their published sidecars (`9948fa714ee8e7731c1691f3d84649832571b882d009aaa0c511a0c82086754c`
  and `e15ad887d028d27844e326fa76bb43931660a7452a9ef474f8a8eeb7610ff9c`).
  Disposable workspaces proved non-overlapping update, overlapping conflict
  staging, human-edited `--continue`, `--abort` without file changes, and
  `--dry-run` immutability. The live direct-download retry remains an
  environment limitation; it is not represented as a successful live network
  proof.
- [x] Add generic `verify-task` runner, tracked profile registry, structured command plans, schema-v1 JSON, fingerprint/stale detection and unit tests.
- [x] Add structured command definitions and release profile ownership to the
  generic runner; preserve additive explicit profile selection.
- [x] Include structured command definitions in the runner fingerprint and fail
  closed on inconsistent or invalid command contracts.
- [x] Add optional archive validation of every non-null disposition target
  against the repository root.
- [x] Reconcile current authority wording across `AGENTS.md`, `docs/WORKFLOW.md`,
  `docs/GLOSSARY.md`, `docs/decisions/README.md` and `scripts/README.md` so
  legacy DB/CLI usage is explicitly archive-only.
- [x] Run three repository-protocol canary fixtures (Harness/docs,
  verification-tooling, and cross-stack consumers) without a database or
  `harness-cli`; selected profiles and fingerprints are recorded in the canary
  JSON output.
- [x] Add shared Flutter `test/flutter_test_config.dart` bootstrap with binding,
  mock preferences, owned temporary path-provider storage, cancelled picker
  default, and disabled AppLogger uploads. This is test-only and does not alter
  runtime plugin registration.
- [x] Add the test-only `path_provider_platform_interface` dev dependency and
  a bootstrap smoke test that exercises the fake path and cancelled-picker
  paths.
- [x] Make shared test teardown deterministic on Windows by exposing an
  AppLogger test-only flush hook and retrying deletion of the owned temporary
  directory with bounded backoff. No plugin exception is swallowed.
- [x] Add deterministic save-file picker fakes and explicit success/error
  coverage for Bank Statement, Offset Adjustment and Sales Report exports.
  Focused export proof passes 64 provider tests plus the Sales Report export
  case; the full Flutter suite was rerun afterward and passed 860 visible
  tests with 3 platform skips.
- [x] Record implementation/proof note in Linear before status transition.
- [x] Create later-phase child issues after the current slice's proof gate:
  `OPS-66` (upstream adoption), `OPS-67` (runner/canary), `OPS-68/69`
  (disposition/promotion), `OPS-70` (retirement), `OPS-71` (docs/plans),
  `OPS-72` (CI/noise), `OPS-73` (artifacts/toolchain), `OPS-74` (runtime
  waves), and `OPS-75` (final consolidation). All remain Backlog; no status
  transition or publication authority was inferred.
- [x] Complete Phase 3A disposition on the fresh lifecycle checkpoint
  `codex/ops-68-disposition-ledger-fresh` from base
  `1d57a9b13796182190b15f3014f728005278f98c`: exactly 199 records, source and
  archive parity, two protocol-v1 decisions superseded by ADR 0029, 41
  already-authoritative targets, 27 deduplicated Linear follow-ups and 129
  historical-only records. The proof was read back before any status change;
  publication remains pending explicit push/PR authority.
- [x] Harden verification fingerprinting to hash raw `git diff --binary` bytes
  instead of a UTF-8-decoded string; add invalid-UTF-8 binary-diff regression
  coverage for unstaged, staged and base-aware changes (verification suite now
  13/13).
- [x] Add Windows `.cmd`/`.bat` structured-command invocation coverage; the
  runner exercises the supported shell path and preserves exit classification
  (verification suite now 14/14 on Windows).
- [x] Preserve command stdout/stderr while classifying platform-level
  command-not-found errors as environment failures (exit `5`), with actual
  Windows `npm.cmd`/missing-command coverage. This prevents missing local
  toolchains from being mislabeled as product failures.
- [x] Publish `OPS-65` through the guarded feature-PR flow: PR #175 merged into
  `staging` at `1d57a9b13796182190b15f3014f728005278f98c`, and the post-merge
  lifecycle finish gate passed.
- [x] Publish `OPS-68` through the guarded feature-PR flow: PR #176 merged into
  `staging` at `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`, and the post-merge
  lifecycle `finish --execute` gate passed.
- [x] Publish `OPS-69` through the guarded feature-PR flow. Draft PR `#177`
  targets `staging` at head `97dcaac2767df6cd2b286c81a59d21174cb853d2`, based
  on live `origin/staging` `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`;
  Release Guard passed and the Linear publication proof was read back. Review,
  merge and post-merge lifecycle gates remain open.
- [x] Publish `OPS-70` through the guarded feature-PR flow. PR #179 merged
  into `staging` at `ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1`; retirement
  validation and the post-merge lifecycle gate passed.
- [x] Classify all 33 pre-slice active-tree files in the OPS-71 disposition
  ledger. Ten Linear-Done execution plans moved to `completed/`; OPS-44 and
  nine OPS-53 fragments were consolidated with history preserved.
- [x] Finish the remaining Phase 6 link/authority review and publish OPS-71.
- [x] Publish OPS-94 through the guarded feature-PR flow. PR #205 merged into
  `staging` at `8c9793545c98b97336b0753f1d7a60ff60e72ac3`; staging deploy
  `31764343895` and the post-merge lifecycle finish gate passed. Linear remains
  `Ready for QA` until production deployment.
- [x] Publish OPS-95 Sales Reports export orchestration through the guarded
  feature-PR flow. PR #206 merged into `staging` at
  `e6a0085d1d40bdded5c019e72451ec42a5e496e9`; staging deploy `31767383719`
  passed and the post-merge lifecycle cleanup removed its worktree and local
  branch. Linear is `Ready for QA`; production deployment remains outstanding.
- [x] Complete and publish OPS-96 MAP Vietin HTTP/session/backoff extraction
  from the exact `origin/staging@e6a0085d1d40bdded5c019e72451ec42a5e496e9`
  checkpoint. PR #207 merged at `7a06f1272ae97f02d5fecc2c3a29e80a8db70f5a`;
  deploy `31770320592` and guarded lifecycle cleanup passed. Linear remains
  `Ready for QA` until production deployment.
- [x] Complete OPS-97 MAP Vietin sync scheduler/coordinator extraction from the
  exact `origin/staging@7a06f1272ae97f02d5fecc2c3a29e80a8db70f5a` checkpoint.
  PR #208 merged at `73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a`; deploy and
  lifecycle finish passed; Linear remains `Ready for QA`.
- [x] Complete OPS-98 Nest/Prisma toolchain bootstrap from the exact
  `origin/staging@73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a` checkpoint. Flutter
  hydration remains a separate follow-up because generated tracked-file
  changes need their own contract and cleanup gate.
- [x] Complete OPS-99 User/Auth characterization. PR #210 merged at
  `00a8021c5848abe8032dad1385cf65f139748aef`, staging deploy `31780994964`
  passed and Linear is `Ready for QA` pending production deployment.
- [x] Complete OPS-100 post-merge staging evidence. PR #211 merged at
  `6817cdfd60fe8dbbbc6f64a497765669dba4e562`; deploy `31783456149` passed
  and Linear is `Ready for QA` pending authenticated QA and production.
- [x] Complete OPS-114 dependency bootstrap enforcement. PR #227 merged into
  `staging` at `73251095bd9d7628a9d6e4f8b528516719081667`; focused toolchain
  coverage and exact runner proof passed.
- [x] Complete OPS-115/OPS-116/OPS-117 MAP runtime extraction waves. PRs
  #228/#229/#230 merged into `staging`; exact staging deploys passed and the
  task branches/worktrees were cleaned. Linear remains `Ready for QA` pending
  authenticated QA and production deployment.
- [x] Complete OPS-118 affected-consumer dependency boundary closure. PR #231
  merged into `staging` at `c46dff3ae9379f663fcac3d8c960ce7c17361933`; staging
  deploy `31848065825` passed, exact cold-worktree proof and `stale=false`
  runner evidence passed, Linear is `Ready for QA`, and lifecycle cleanup
  removed the task worktree/local branch.
- [x] Complete OPS-119 operational local dependency-entrypoint closure. PR #232
  merged into `staging` at `b3913e8d973d2fd35fef03f986cdf79c88c819b6`;
  staging deploy `31850797873` passed, disposable PostgreSQL fresh/rollback/
  upgrade proof passed, exact runner returned `stale=false`, Linear is
  `Ready for QA`, and lifecycle cleanup removed the task worktree/local branch.
- [x] Complete OPS-120 Windows MSIX Flutter dependency-boundary closure. PR
  #233 merged into `staging` at `d5b81d45ac9bd6a706e03dffa6b30028e5ef2dfb`,
  staging deploy `31852572385` passed, Linear is `Ready for QA`, and the
  guarded lifecycle cleanup removed the task worktree/local branch.
- [x] Complete OPS-121 dependency bootstrap resume/entrypoint closure. PR #234
  merged into `staging` at `ceb883d6c919962e5ba2cedfab56ce3802387435`; staging
  deploy run `31855893031` passed, toolchain/doctor/entrypoint proof passed
  `30/30`, verification/lifecycle proof passed `50/50`, the full toolchain
  suite passed `52/52`, wrapped Nest build and Flutter analyze passed, exact
  `verify-task --base origin/staging` returned `stale=false`, and guarded
  lifecycle cleanup removed the task worktree/local/remote branch. Linear is
  `Ready for QA`; production deployment remains outstanding.
- [x] Complete OPS-122 master-plan reconciliation after OPS-121. PR #235
  merged at `d10241c0eafab66bd34390e7dda8d58a96e54147`; the current checkpoint
  is subsequently reconciled to the exact post-OPS-113 `origin/staging` SHA.
- [ ] Complete OPS-72 Phase 7B percentage-target evidence; the v2 live timing
  baseline is recorded, but the 25% timing target is unmet and rerun reduction
  is unmeasurable, so keep the affected matrix observational.
- [x] Complete OPS-123 master-plan reconciliation after OPS-72 PR #239. The
  source checkpoint is exact `origin/staging@4dda2592de5d0691082756d0d6fb32d0b93e8607`;
  the reconciliation is docs-only and preserves the explicit `revise`
  residual, deployment proof and cleanup evidence.
- [x] Complete OPS-124 command-time dependency readiness closure. PR #241
  squash-merged into `staging` at `5432a995fb1a68a70be96a95ba45592fb9e703c1`;
  PR checks, CodeQL, Release Guard and Affected Verification Shadow passed.
  Exact staging deploy `31875595813` passed Android, Windows, web, backend,
  direct-origin and public health/version checks; Linear is `Ready for QA` and
  guarded lifecycle cleanup removed the task worktree/local/remote branch.
- [x] Reconcile this master plan in OPS-125 from the exact
  `origin/staging@5432a995fb1a68a70be96a95ba45592fb9e703c1` checkpoint. PR #242
  merged at `f0f080d78871b8e3112eab18c3c6f9e834ab36ea`, staging deploy
  `31876813285` passed, and guarded cleanup removed the task worktree/local/
  remote branch.
- [x] Reconcile the plan after OPS-124/OPS-128 dependency slices in OPS-129.
  PR #246 merged at `5c457e6ec044894b4603fa2f4ecea6a928859c2c`; staging deploy
  `31885815185` passed and the guarded cleanup left only canonical staging.
- [x] Complete OPS-131 dependency bootstrap hardening. PR #248 squash-merged
  at `e338e51bc212c050c9f70b95f0aca91d286b705d`; PR checks and staging deploy
  `31894609071` passed on the exact SHA, and guarded lifecycle cleanup removed
  the task worktree/local/remote branch. Linear OPS-131 is `Ready for QA`;
  production deployment remains the Done gate.
- [x] Reconcile OPS-72 after OPS-73 in OPS-132. The sanitized progress ledger
  now records five same-cohort post-OPS-130 manifests (#247–#251), all passed
  with `stale=false`, zero unmatched paths and zero reruns. The current median
  reduction is `8.77%` against the `25%` target and rerun reduction remains
  unmeasurable, so the aggregate is `revise`/`do-not-promote`.
- [x] Close OPS-134 generated-root writeability and cold dependency bootstrap
  lifecycle. PR #251 merged at `46c8aa90`, exact staging deploy
  `31901021962` passed, Linear proof/status is `Ready for QA`, and the guarded
  worktree/local/remote branch cleanup passed. Production remains the only
  completion gate.
- [x] Complete OPS-135 cold-worktree dependency canary from exact
  `origin/staging@46c8aa90d932f8cfadb25eddae80305180ca9d95`. PR #252 merged at
  `98d7316648a60e415e154b114c6bb5ec87f52286`; Windows canary `31903049090`,
  exact staging deploy `31903246094` and guarded cleanup passed. The canary
  proves a clean checkout hydrates both Nest/Prisma and Flutter, including the
  allowlisted `lib/l10n` ReadOnly fault; Linear is `Ready for QA`.
- [x] Complete OPS-141 dependency-root readiness hardening. PR #260
  squash-merged at `31149394b5bcf62028be331e03f3d36b1d2d1dd4`; PR checks,
  Windows cold dependency canary `31917740541`, exact staging deploy
  `31917897049` and guarded lifecycle cleanup passed. The readiness contract
  now covers both `.dart_tool` and `backend-nest/node_modules`, repairs only
  allowlisted directory-level Windows `ReadOnly` blockers, and invalidates
  stale receipts. Linear is `Ready for QA`; production remains the Done gate.
- [x] Complete OPS-130 live-shadow evidence assembly. PR #247 merged at
  `837df86c2a781b256c72fbe0eb6bdb37cbae26e0`, staging deploy `31888018450`
  passed, and the shadow workflow/collector is implemented. The affected
  matrix remains observational because OPS-72's revised cohort still does not
  meet the 25% timing and 30% rerun-reduction targets.
- [x] Complete the Phase 8 artifact/dependency/toolchain review and deletion
  decision. The refreshed inventory, retained-owner review, Flutter/Nest
  dependency batches and Go/deploy review all pass; zero deletion batches are
  authorized. Dependency bootstrap hardening remains an explicit residual
  risk and is not treated as a pass by this closure.
- [ ] Run Phase 9 runtime waves and Phase 10 final consolidation.

Phase 8 inventory checkpoint (OPS-73):

- [x] Inventory-only slice: add `docs/migrations/ops-73-artifact-inventory.json`
  with exact branch/HEAD, tracked/ignored paths, dependency manifests, asset
  hashes, runtime hotspots, owner rules and generated-file policy.
- [x] Validate the inventory with `scripts/verify-artifact-inventory.mjs`;
  deletion batches must remain empty until an independent reference/build/
  package/migration/rollback review proves a candidate safe to remove.
- [x] Preserve `n8n/`, legacy runtime routes, platform assets and release
  allowlist entries after the sanitized OPS-73 retained-owner review proves an
  owner reference and rollback path for every candidate. No deletion batch is
  authorized by this evidence.
- [x] Refresh the Phase 8 inventory/owner evidence at the exact
  `origin/staging@6814d4ba29d7dbd854590daea3c890f15174d3c7` checkpoint. The
  clean checkout inventory now records 6,046 tracked and zero ignored paths,
  153 hashed assets and zero deletion batches; generated dependency/build
  output is intentionally excluded from the committed snapshot. The
  retained-owner review covers 19 paths and passes with
  `no-safe-deletion-candidate`. The validator rejects only a `..` path segment,
  so valid generated filenames containing consecutive dots are accepted. No
  n8n/platform/release asset is authorized for deletion.
- [x] Open OPS-139 after the clean-checkout gate exposed raw checkout-EOL drift
  in the OPS-137 retained-owner hashes. The repair uses Git-normalized bytes
  and retains `no-safe-deletion-candidate`; reviewed payloads remain untouched.

Flutter batch checkpoint:

- [x] Candidate review identifies `cupertino_icons` as unused: no production or
  test imports/symbols, no generated plugin owner, and existing audit notes
  already call for removal after a platform build.
- [x] Remove only the direct dependency and lock entry; keep all consumer-owned
  assets and build tooling. Record before/after inventory and revert guidance
  in `docs/migrations/ops-73-flutter-dependency-batch.json`. Offline pub
  resolution, analyzer, focused (94) and full Flutter tests (860 with 3
  platform skips), inventory checks, and Windows debug build pass. The first
  unconstrained full-suite run exposed one existing polling timing race;
  concurrency=1 rerun passed and the named test passed independently.

NestJS batch checkpoint:

- [x] Candidate review found `source-map-support` and `ts-loader` without a
  repository-owned import, config or script owner. `source-map-support` remains
  available transitively through Jest/Terser; `ts-loader` has no remaining lock
  entry.
- [x] Removed only those two direct dev dependencies. Preserved Nest CLI,
  Prisma, Sharp/native build, bcrypt, Jest, TypeScript and release owners. The
  before/after graph, hashes, reference scan and rollback guidance are recorded
  in `docs/migrations/ops-73-nestjs-dependency-batch.json`.
- [x] Sequential proof passed after `npm ci`: Prisma generate/validate, Nest
  build, 108 suites/1,205 tests with 6 skips, security dependency checks and
  Sharp Dockerfile x64/arm64 contract.
- [x] Hardened the artifact inventory Git collector with a bounded 16 MiB
  subprocess buffer after a post-build ignored-output scan hit Windows
  `spawnSync git ENOBUFS`; this keeps generated output ignored while making
  repeatable inventory checks independent of build artifact volume.

Go/deployment batch checkpoint:

- [x] Re-collected the machine inventory at `ccff928f`; 5,981 tracked paths,
  16 Go paths, 38 deployment paths and zero existing ignored paths were
  recorded. The reviewed artifact is
  `docs/migrations/ops-73-go-deployment-batch.json`.
- [x] Reviewed every Go direct module and all deployment/runtime paths against
  source imports, Docker/release allowlists, workflows, smoke checks and
  rollback helpers. All candidates retain an operational owner; no safe
  deletion candidate exists and no Go module graph change was made.
- [x] Corrected two validator-only authority drifts without changing runtime:
  OPS-39 now asserts the current `bankapis*.hoanghochoi.com` domains, and the
  platform security replica count scopes to the staff Caddy site before the
  dedicated BIDV site. Go tests/vet, Caddy/platform contracts, OPS-40 tests,
  static transaction rehearsal and inventory validation pass.
- [x] Retained `backend-go/`, `deploy/home-server/`, `deploy/staging/` and
  `deploy/windows/`; deletion status is explicitly `no-safe-deletion-candidate`.

Phase 7B implementation checkpoint (OPS-72):

- Added `scripts/verify-task-shadow.mjs`, which compares auto-selected profiles
  to the full ladder without replacing existing blocking checks and emits a
  schema-v1 sanitized report for CI artifacts/step summaries.
- Added `.github/workflows/verify-task-shadow.yml` for pull requests into
  `staging`; the shadow job is observational (`continue-on-error`) and does not
  weaken Release Guard or product checks.
- `verify-task` now permits at most one infrastructure retry only when the
  fingerprint remains unchanged; product failures are never retried and a
  changed worktree during retry returns stale exit code `4`.
- Expanded the Harness profile to own repository verification fixtures and
  metadata so retirement/verification paths remain fail-closed without false
  unmatched-path failures.
- Unit proof: `node --test tests/verification/*.test.mjs` — 22/22 pass,
  including shadow comparison, unknown-path contract, retry stability, stale
  retry and no-retry product failure cases.
- Historical shadow evidence: `docs/migrations/ops-72-shadow-metrics.json`
  replays PRs #176–#180 (OPS-68, OPS-69A/B, OPS-70, OPS-71): 5/5 pass,
  exact parent/head and stable fingerprints, zero unmatched paths. The report
  deliberately remains `pending-live-shadow-data`; historical replay does not
  satisfy the five live PR observations or the rerun/time-to-actionable-failure
  percentage targets.

Historical Phase 7B live observation checkpoint (OPS-72 v1):

- Five live PR observations are tracked in
  `docs/migrations/ops-72-live-shadow-evidence.json`: PRs #181, #183, #184,
  #185 and #186. Each has a schema-v1 report hash, exact PR/base/report-head
  SHAs, selected/full profiles, changed-path count, GitHub timing, unchanged
  blocking-check marker, stale=false, zero unmatched paths and zero reruns.
- PR #182's contract failure is retained separately with its original report
  hash and unmatched `scripts/collect-ops72-shadow-metrics.mjs` path. It is
  an accepted discovery of a missing profile, not an omitted failure.
- `scripts/verification-profiles.mjs` now owns the collector and the new
  `scripts/verify-ops72-live-shadow-evidence.mjs` validator. The artifact
  verifier and focused tests are required before publication.
- The v1 aggregate status was `pending-live-timing-baseline`; it is retained as
  historical evidence and is not the current promotion authority.

Phase 9A runtime checkpoint (OPS-74):

- Slice branch: `codex/ops-74-home-characterization-header`, started from
  `origin/staging@b0537d8030db6e4a737911f6869b45776f877780`.
- Extracted the pure `HomeSummaryHeaderLayout` desktop width contract from
  `HomeSummaryPage` while preserving `HomeSummaryHeader`, widget keys,
  Vietnamese copy, shared date-range picker, callbacks and responsive values.
- Added four geometry tests covering wide, regular/action, narrow and action
  threshold behavior. Existing Home dashboard and route viewport
  characterization tests remain unchanged and pass.
- Proof so far: `flutter pub get --offline`, geometry test 4/4, combined Home
  dashboard/viewport suite 82/82, `flutter analyze --no-pub` no issues. No
  runtime API, permission, data, platform or visual contract change is claimed.

Phase 9A runtime checkpoint (OPS-81):

- Slice branch/worktree: `codex/ops-81-home-kpi-summary-comparison` in
  `../opshub-ops-81`, started from `origin/staging@0f251063524792421b8b3f3e8fe0a2ac2132b75e`.
- Extracted `SummaryCardGrid` and `MainKpiSummaryCardGrid` into the same-library
  part file `home_summary_metric_sections.dart`; public constructors, widget
  keys, card ordering, callback wiring, comparisons, Vietnamese copy and
  responsive geometry remain unchanged.
- Baseline focused characterization passed: desktop KPI columns, metric icon
  map, finance comparison labels, sub-320 fallback and behavior-detail modal.
- Post-extraction proof passed: `home_summary_header_layout_test.dart` 4/4 and
  `home_dashboard_test.dart` 53/53 in one invocation; affected realtime,
  scope, cache/details and comparison consumers are included in that suite.
  `dart format`, `git diff --check` and Flutter targeted analyze passed.
  `scripts/verify-task.mjs --base origin/staging --profile flutter --json`
  passed with `stale=false`, matching fingerprint before/after; the runner's
  Flutter analyze command took 156,941 ms. Full standalone Home test invocation
  exceeded the local 120-second command timeout before this slice, so that
  timeout is retained as a harness limitation rather than a product failure.

Phase 9A runtime checkpoint (OPS-82):

- Slice branch/worktree: `codex/ops-82-home-details-dialogs-tables-paging` in
  `../opshub-ops-82`, started from `origin/staging@880167d6e1cb01395e2ad674079e6ccb737b87bc`.
- Extracted pure Home detail renderers into the same-library part file
  `home_summary_detail_sections.dart`: detail tab pills, sales-behavior table,
  installment table, typed data tables, load-more footer and display helpers.
  Dialog state, provider calls, cursor append and load-generation guards remain
  in `HomeSummaryPage` unchanged.
- Baseline representative detail flow passed 1/1 before extraction, covering
  both behavior tabs, cursor load-more and installment details. Post-extraction
  focused proof passed the same flow 1/1 and the combined Home/header/cache/
  details suite passed 60/60 visible Home tests plus repository/cache tests.
  `dart format`, `git diff --check` and targeted Flutter analyze passed.
- Generated localization/plugin files changed only in index metadata after
  offline dependency setup; their content hashes match HEAD and they are not
  part of the intended diff. No runtime plugin registration changed.

Phase 9B runtime checkpoint (OPS-84, query/list state slice):

- Slice branch/worktree: `codex/ops-84-payment-monitor-query-state` in
  `../opshub-ops-84-next`, started from live
  `origin/staging@0076944e5410dbfb62af06a0d1094d577ee8f923` after the OPS-83
  rerun-safe deployment hotfix and successful staging deploy.
- Moved PaymentMonitorProvider's public query/list state getters and mutations
  (store selection, date range, pagination, row state and latest transactions)
  into the same-library part file
  `payment_monitor_query_state.dart`. The provider facade, private state/helpers,
  speaker/realtime APIs, normalization, polling, logs and behavior are unchanged.
- Baseline before extraction was 119/119 across Payment Monitor, audio/realtime,
  Bank Statement and VietQR consumers. After applying the extraction, the
  affected suite passed 166/166 across 18 test files in one invocation; the
  focused provider suite passed 48/48. The first failed invocation was a
  command/dependency hydration timeout (no product assertion failure); after
  `flutter pub get`, compact reporter execution passed.
- `dart format` and `git diff --check` passed. Exact `verify-task` and
  `flutter analyze --no-pub` remain final gates before publication.

Phase 9B runtime checkpoint (OPS-85, realtime refresh/background-lease slice):

- Slice branch/worktree: `codex/ops-85-payment-monitor-realtime-lease` in
  `../opshub-ops-85`, created by the guarded lifecycle start gate from live
  `origin/staging@323dd098bbe99a9184ed70dede69f9fb971aaae6`. The canonical
  `staging` worktree remained clean and unchanged during implementation.
- Extracted realtime subscriptions, foreground/background runtime flags,
  refresh debounce/pending state, and background speaker lease ownership into
  the same-library part file `payment_monitor_realtime_runtime.dart`.
  `PaymentMonitorProvider` remains the public facade and retains event
  filtering, authorization, poll, audio, logging and affected-consumer
  behavior. The coordinator receives callbacks and lease eligibility through
  its constructor; it does not access provider globals.
- Characterization baseline passed `48/48` in
  `test/payment_monitor_provider_test.dart`. Post-extraction focused proof
  passed `48/48`; the affected Payment Monitor/repository/transaction/audio,
  Bank Statement provider and VietQR screen matrix passed `118/118`.
- `dart analyze` for the provider passed; full `flutter analyze --no-pub`
  passed with no issues. `dart format` passed. Generated plugin registrant
  files were only dependency-hydration noise with byte-identical content and
  are excluded from the intended diff.
- Remaining gates before publication: exact `verify-task` from this branch,
  final diff/fingerprint review, Linear proof note, PR/CI and staging deploy.
  After squash merge, run lifecycle `finish --allow-ignored --execute` and
  verify no OPS-85 worktree or local task branch remains before the next slice.

Phase 9B runtime checkpoint (OPS-86, speaker queue/delivery slice):

- Slice branch/worktree: `codex/ops-86-payment-monitor-speaker-audio` in
  `../opshub-ops-86`, created by the guarded lifecycle start gate from live
  `origin/staging@5c5500a77106f00fad3d0cb01ccc1ffa7909c9c9` after OPS-85 was
  squash-merged, staging-deployed and cleaned. The canonical staging worktree
  remained clean and unchanged during implementation.
- Narrowed the slice to stream queue/delivery orchestration: queue ordering,
  local terminal/active/in-flight locks, duplicate suppression, drain
  lifecycle and authorization cancellation now live in the constructor-
  injected same-library part `payment_monitor_speaker_queue.dart`.
  PaymentMonitorProvider remains the facade; stream parsing, eligibility,
  silence, low-level audio preparation/playback and acknowledgement helpers
  remain in the provider for the next bounded audio slice (OPS-87).
- Baseline speaker/provider/audio characterization passed `55/55` (48
  Payment Monitor provider tests plus audio composer/speaker suites). After
  queue extraction, focused Payment Monitor provider proof passed `48/48`.
- `dart format` and provider `dart analyze` pass. Generated plugin registrant
  files changed only as dependency-hydration metadata noise with content hashes
  equal to HEAD and are excluded from the intended diff.
- Remaining gates before publication: affected Bank Statement/VietQR matrix,
  full `flutter analyze --no-pub`, exact `verify-task` with `stale=false`,
  final staged diff review, Linear proof note, PR/CI, staging deploy and
  lifecycle `finish --allow-ignored --execute` cleanup after squash merge.

Phase 9B runtime checkpoint (OPS-87, audio preparation/playback/ack slice):

- Slice branch/worktree: `codex/ops-87-payment-monitor-audio-runtime` in
  `../opshub-ops-87`, created by the guarded lifecycle start gate from live
  `origin/staging@be86b0cbb1d37692bfc0fe81f4d53dc68b22bb36`. Canonical staging
  remained clean and unchanged during implementation.
- Characterization baseline passed `64/64` across the Payment Monitor
  provider/repository, amount-audio-composer and speaker I/O suites. The
  extracted coordinator is the same-library part
  `payment_monitor_audio_runtime.dart`; it receives repository, speaker,
  composer, retry delay, voice-preset, speaker-generation, acknowledgement
  and terminal-state callbacks through its constructor. The provider remains
  the public facade and retains queue/orchestration, speaker error state,
  authorization and all public contracts.
- Moved low-level server/local audio preparation, local preset composition and
  claim handling, playback retry, stream-start/playback-failed/played/failed
  acknowledgement, audio logging and error mapping into the coordinator.
  Windows local preset, Android/iOS server stream, claim-409 suppression,
  401/403 propagation, three-attempt retry semantics and Vietnamese error copy
  remain unchanged. Order update/transfer/row-message actions remain in the
  facade for a later slice.
- Post-extraction affected matrix passed `118/118` in one invocation across
  Payment Monitor provider/repository/transaction/audio, Bank Statement
  provider and VietQR screen consumers. Full `flutter analyze --no-pub`,
  `dart format` and `git diff --check` pass with no analyzer issues. Generated
  plugin registrant files are dependency-hydration noise with byte-identical
  content and are excluded from the intended diff.
- Remaining gates before publication: exact `verify-task` with `stale=false`,
  final staged diff/fingerprint review, Linear implementation/proof note, PR/
  CI, staging deploy and lifecycle `finish --allow-ignored --execute` cleanup
  after squash merge. No API, data, permission, UI or platform behavior
  change is intended.

Phase 9A runtime checkpoint (OPS-83):

- Slice branch/worktree: `codex/ops-83-home-analytics-progress` in
  `../opshub-ops-83`, started from `origin/staging@1eeda4a5f38ae39585c8a5a881c16bc9293d5579`.
- Extracted `ReportProgressPanel`, the approved overview/analytics renderers,
  responsive layout coordinator, progress bars, assignee selector and donut
  painter into the same-library part file
  `home_summary_progress_sections.dart`. The public `ReportProgressPanel`
  constructor, provider callback, widget keys, Vietnamese copy, geometry and
  retained characterization-only legacy path are unchanged.
- Focused characterization passed 53/53 in
  `home_dashboard_test.dart` plus `home_summary_header_layout_test.dart` in
  one invocation, covering Home dashboard summary/progress, readable sales
  cards, compact R3 geometry, empty-SA state, expanded layout, long-target
  warning, desktop sizing, viewport geometry and SA selection reload.
- `dart format --output=none --set-exit-if-changed` passed for both widget
  files; `git diff --check` passed; `flutter analyze --no-pub` passed with no
  issues (238.3s). Affected-consumer `verify-task` remains the final exact
  commit gate before publication.

Phase 9C runtime checkpoint (OPS-89, Home Summary cache runtime slice):

- Slice branch/worktree: `codex/ops-89-home-summary-service` in
  `../opshub-ops-89`, created from live
  `origin/staging@3cc4ce09cf24758165a993583aac3b4a97a52b96`. Canonical
  staging stayed clean and unchanged during implementation.
- Baseline focused characterization passed `110/110` across the Home Summary
  service/controller/DTO/projection/backfill/comparison suites. After
  extraction, the same six suites and `npm run build` pass `110/110`.
- Moved response cache, in-flight dedupe, refresh-ahead, daily-series
  extension, projection invalidation, support-cache loading and scope-option
  cache state into `home-summary-cache.runtime.ts`. `HomeSummaryService`
  remains the facade; routes, DTOs, DI tokens, permissions, data contracts and
  product computation callbacks are unchanged. Internal compatibility views
  keep existing characterization inspection points stable.
- PR #198 merged into `staging` at
  `77ec6ff3482b3ff689e10af77b6981c1a96293d`; staging deploy run
  `31735051035` passed and the guarded lifecycle cleanup completed. OPS-89 is
  release-pending/Ready for QA until production deployment.

Phase 9C runtime checkpoint (OPS-90, Home Summary scope/access slice):

- Historical slice branch/worktree: `codex/ops-90-home-summary-scope-access` in
  `../opshub-ops-90`, created from live `origin/staging@77ec6ff3482b3ff689e10af77b6981c1a96293d`.
  PR #199 merged into `staging` at
  `1891a7a961c738b36bbc307c00ff92ce2c651123`; staging deploy run
  `31739803253` passed and the guarded lifecycle cleanup completed. Linear
  `OPS-90` is `Ready for QA`; production deployment remains outstanding.
- Baseline focused characterization passed `83/83` across the Home Summary
  service/controller/DTO suites. After extraction, the same matrix and
  `npm run build` pass `83/83` plus a clean compile.
- Extracted section feature access, selected sales-metrics scope resolution,
  active SA assignee lookup and scope conversion into
  `home-summary-scope.runtime.ts`. `HomeSummaryService` retains the facade,
  private compatibility wrappers, existing logger/normalizer callbacks and
  all public routes, DTOs, DI tokens, permission and scope descriptor behavior.
- The slice preserved the facade/public contract and is complete through
  staging QA tracking; no task worktree remains.

Phase 9C runtime checkpoint (OPS-91, Home Summary projection runtime slice):

- Slice branch/worktree: `codex/ops-91-home-summary-projection-runtime` in
  `../opshub-ops-91`, created from live
  `origin/staging@1891a7a961c738b36bbc307c00ff92ce2c651123`. Canonical staging
  remained clean and unchanged; the implementation checkpoint was recorded in
  Linear before source edits.
- Baseline and post-extraction NestJS characterization both passed `110/110`
  across Home Summary service/controller/DTO/projection/backfill/comparison
  suites. `npm run build`, Prettier checks and `git diff --check` passed.
- Extracted projection feature gating, freshness/readiness calculation,
  projection version snapshots, aggregate metric loading and optional daily
  series into `home-summary-projection.runtime.ts`. `HomeSummaryService`
  retains the facade/orchestration, comparison/CSV overlay, sales aggregation,
  legacy sync fallback and private compatibility wrappers; public routes, DTOs,
  DI tokens, permissions and projection response contracts are unchanged.
- Affected Flutter Home/cache/details/realtime/scope proof passed `60/60` after
  `flutter pub get` preflight. Generated Flutter registrant/l10n changes were
  kept out of the slice in a named local stash and are not part of the product
  diff.
- Exact `verify-task` and all focused/affected proof are now passing. Remaining
  gates are final staged diff review, PR/CI, staging deploy and lifecycle
  `finish --allow-ignored --execute` cleanup after squash merge.

Phase 9D runtime checkpoint (OPS-92, Sales Reports scope/query slice):

- Slice branch/worktree: `codex/ops-92-sales-reports-scope-query` in
  `../opshub-ops-92`, started from exact live
  `origin/staging@f8c8ee27b6d4b95d950eb8ecd82d13cb454cfb44`; canonical
  staging stayed clean and unrelated OPS-68/OPS-72 metrics worktrees were
  preserved.
- Extracted feature/admin access, managed and user/store scope resolution,
  store authorization, report/order-cockpit filter normalization, date-range
  handling, pagination and Prisma where composition into the
  constructor-injected same-library collaborator
  `sales-reports-scope-query.runtime.ts`. `SalesReportsService` retains the
  public facade, routes, DTOs, DI tokens, permissions, Vietnamese copy and
  AppLogger context. Parser/import, ERP lookup/status, follow-up, BigQuery
  sync and export/admin mutation orchestration remain in their existing
  owners.
- Baseline and post-extraction NestJS characterization both passed `232/232`
  across the selected sales-report service/controller/DTO/import/follow-up/ERP/
  BigQuery suites. `npm run build` passed. Affected Flutter sales-report,
  not-purchased and Home cache consumers passed `72/72`; `flutter analyze
  --no-pub`, Prettier and `git diff --check` passed.
- Final gates: exact commit `verify-task` with `stale=false`, staged diff review,
  Linear implementation/proof note, PR/CI, staging deploy, and guarded
  lifecycle `finish --allow-ignored --execute` cleanup. No API, data,
  permission, UI or platform behavior change is intended.

Phase 9D runtime checkpoint (OPS-93, Sales Reports revenue/order aggregation
slice):

- Slice branch/worktree: `codex/ops-93-sales-reports-revenue-aggregation` in
  `../opshub-ops-93`, started from exact live
  `origin/staging@c146b9cfca091136af8b046d8aa582b3c1f0e07e`; canonical staging
  and the unrelated OPS-68/OPS-72 worktrees remain untouched.
- Extracted pure revenue/order aggregation into the constructor-injected
  `sales-reports-revenue-aggregation.runtime.ts`. `SalesReportsService` keeps
  `summarizeSalesRevenueRows` as the stable facade, canonical revenue lookup,
  order dedupe, customer split, installment and promotion metrics, category
  quantities and assembled-PC semantics unchanged. Routes, DTOs, DI tokens,
  permissions, API/data contracts, UI and Vietnamese copy are unchanged.
- Baseline and post-extraction NestJS characterization both passed `205/211`
  (six skipped); `npm run build`, affected Flutter sales-report,
  not-purchased and Home cache consumers passed `72/72`,
  `flutter analyze --no-pub`, Prettier and `git diff --check` passed. Flutter
  generated hydration noise was kept in the named local stash
  `ops93-local-flutter-generated` and is not part of the product diff.
- Final gates: exact commit `verify-task` with `stale=false`, staged diff review,
  Linear implementation/proof note, PR/CI, staging deploy, and guarded
  lifecycle cleanup. No API, data, permission, UI or platform behavior change
  is intended.

Phase 9D runtime checkpoint (OPS-94, import-history comparison and CSV overlay
slice):

- Slice branch/worktree: `codex/ops-94-import-history-comparison-csv-overlay` in
  `../opshub-ops-94`, started from exact live
  `origin/staging@8bdd24b4ddd653fa55479bb7b5c0e5bfd4bc59b9`; canonical staging
  and the unrelated OPS-68/OPS-72 worktrees remain untouched.
- Planned extraction: move `HomeSummaryService.overlayActiveCsvHistory` and
  its hybrid active-grain/coverage/CSV/projection aggregation into a
  constructor-injected `HomeSummaryCsvComparisonRuntime`. Preserve source,
  complete/unavailable semantics, personal coverage handling, store/user
  dimensions, date boundaries and metric values. No route, DTO, DI, permission,
  API/data, UI or Vietnamese-copy change is intended.
- Baseline and post-extraction Home Summary characterization pass `116/116`
  across six suites: service, controller, DTO, projection, backfill and
  comparison. Deterministic affected Flutter Home/sales-report proof passes
  `124/124` with `--concurrency=1`; individual files also pass. The first
  default-concurrency batch had one isolation flake and is not accepted as
  final proof. Dependency hydration (`npm ci`, `npx prisma generate`,
  `flutter pub get`) is ignored worktree state only and generated Flutter
  registrant/l10n changes are isolated in the local stash
  `ops94-local-flutter-generated`.
- Final gates passed: post-extraction characterization, affected Flutter Home/
  sales-report consumers, `npm run build`, Prettier, exact
  `verify-task --base origin/staging` with `stale=false`, PR #205 checks,
  staging deploy run `31764343895` and guarded lifecycle cleanup. The merge
  SHA is `8c9793545c98b97336b0753f1d7a60ff60e72ac3`; canonical staging,
  origin/staging and the post-finish checkpoint match. Linear OPS-94 is
  `Ready for QA`; production deployment remains outstanding.

Phase 9D runtime checkpoint (OPS-95, Sales Reports export orchestration slice):

- Slice branch/worktree: `codex/ops-95-sales-reports-export-orchestration` in
  `../opshub-ops-95`, started from exact live
  `origin/staging@8c9793545c98b97336b0753f1d7a60ff60e72ac3`; canonical staging
  remained clean and the OPS-68/OPS-72 worktrees were preserved.
- Planned extraction: move `SalesReportsService.exportWorkbook`, its canonical
  revenue quality-warning flow and HVTC/revenue/installment workbook rendering
  into constructor-injected `SalesReportsExportRuntime`. Scope/query loading,
  Prisma access, imports, ERP, follow-up, BigQuery and
  `SalesReportsRevenueAggregationRuntime` remain in their existing owners.
- Intake checkpoint: branch/head, status/untracked, tracked-index and binary
  diff hashes were captured twice with identical results before source edits.
- Current proof: `npx prisma generate`, `npm run build`, Sales Reports service
  characterization `102/102`, DTO tests `4/4`, and serial affected Flutter
  Home/sales-report/follow-up matrix `128/128` pass. The initial combined
  Flutter batch timed out with a closed reporter pipe; per-file serial runs
  are the accepted proof. Exact commit runner and publication gates remain.

Phase 9E runtime checkpoint (OPS-96, MAP Vietin provider slice):

- Slice branch/worktree: `codex/ops-96-map-vietin-http-session-backoff` in
  `../opshub-ops-96`, started from exact live
  `origin/staging@e6a0085d1d40bdded5c019e72451ec42a5e496e9`; canonical staging
  and the OPS-68/OPS-72 worktrees were preserved.
- Planned extraction: move bounded MAP/eFAST HTTP transport, MAP/global and
  eFAST session caching, provider backoff and Retry-After parsing into
  `MapVietinProviderRuntime`. `MapVietinService` keeps request construction,
  credential crypto, scheduler, persistence, statement policy and response
  mapping. No route, DTO, DI, permission, API/data, UI or Vietnamese-copy
  change is intended.
- Intake checkpoint: branch/head, status/untracked, tracked-index and binary
  diff hashes were captured twice with identical results before source edits;
  checkpoint hash is `985c34b4d3661f0669ced1b74738b3e38b80eb816a146d9d69aee51f8bc39a7e`.
- Pre-publication characterization passes: MAP provider runtime and
  MapVietinService `156/156`; affected Flutter Payment Monitor, Bank Statement,
  VietQR and API rate-limit matrix `164/164` across 18 files with
  `--concurrency=1`; `flutter analyze --no-pub`, Prisma validate, Nest build,
  Prettier and `git diff --check` pass. Exact runner with additive `flutter`
  profile passes `harness,docs,nestjs,flutter`, `stale=false`, exit `0` and five
  changed paths; final publication, staging deploy and lifecycle cleanup remain
  open.

Phase 9E runtime checkpoint (OPS-97, MAP Vietin scheduler/coordinator slice):

- Slice branch/worktree: `codex/ops-97-map-vietin-sync-coordinator` in
  `../opshub-ops-97`, started from exact live
  `origin/staging@7a06f1272ae97f02d5fecc2c3a29e80a8db70f5a`. The intake
  checkpoint was captured twice with identical branch, status, tracked-index
  and binary-diff hashes; the canonical `staging` worktree and the protected
  OPS-68/OPS-72 worktrees were not changed.
- Extracted timer ownership, MAP/eFAST fast/night window calculations,
  randomized cadence, backoff-aware scheduling, deep-sweep due state, module
  stop/dispose and single-flight MAP/eFAST leases into the constructor-configured
  `MapVietinSyncCoordinator`. `MapVietinService` remains the public facade;
  public sync methods delegate through coordinator leases while scheduler
  callbacks call the facade, preserving existing Jest spies and contracts.
- No route, DTO, DI token, permission, API/data contract, Vietnamese copy,
  persistence, statement policy or response mapping changed. The existing
  `mapHistoryDeepSweepDueAt` and scheduler inspection points remain delegated
  compatibility views.
- Focused characterization and coordinator proof passes `157/157`; all
  MAP/Vietin and BigQuery affected Nest suites pass `207/207`; `npm run build`
  and `npx prisma validate` pass. Exact runner after Flutter dependency
  hydration passes profiles `nestjs,flutter`, 4 changed paths,
  `stale=false`, and Flutter analyzer reports no issues. Hydration-generated
  l10n/plugin files are isolated in local stash `ops97-local-flutter-generated`
  and are not part of the product diff. Publication and lifecycle gates remain
  open.

## Historical workflow checkpoint (OPS-98 complete; OPS-99 User/Auth characterization)

- OPS-98 slice branch/worktree was `codex/ops-98-backend-nest-toolchain-bootstrap`
  in `../opshub-ops-98`, started from exact live
  `origin/staging@73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a`. PR #209 merged at
  `b9fe4d6e0234ea3f89561978b8974e738b0f8dfb`, staging deploy run
  `31777758147` passed, and guarded lifecycle cleanup removed the task
  worktree/local/remote branch. The canonical `staging` and protected
  OPS-68/OPS-72 worktrees remain untouched.
- Root cause: fresh task worktrees omit ignored `backend-nest/node_modules`
  and the generated Prisma client, so the first Nest build reports a late
  environment failure. The preflight now checks the package/lockfile and
  Prisma schema/config contract, fingerprints those inputs plus Node platform,
  runs `npm ci --ignore-scripts` and `npx --no-install prisma generate`, and
  records only repository-relative ignored state for idempotent cache hits.
- Lifecycle `start --prepare --execute` runs the preflight only after the new
  worktree is created; dry-run never executes it. A failed prepare rolls back
  the new worktree/local branch, including reviewed ignored output. The NestJS
  verification profile invokes the same preflight before `npm run build`.
- The slice deliberately excludes Flutter dependency hydration. `flutter pub
  get` can create tracked l10n/plugin files, so Flutter needs a separate
  explicit generated-file contract and cleanup gate rather than being silently
  run by task creation.
- Preflight unit proof is `7/7`; lifecycle regression proof is `15/15`.
- Actual worktree preflight with `--force` passed `npm ci --ignore-scripts` and
  Prisma generation; the immediate repeat returned `cached` with the same
  fingerprint `a245e03be67b0189c76f47f3b1b84bb4f9f2feeef1ec69d66acf45454e20e381`.
- Exact runner against the OPS-98 base checkpoint
  `73e1e2c77aa7e796e4cbd2ee614c4aa16ef5104a` selected
  `harness,docs,verification-runner,release,nestjs`, covered 8 paths, returned
  code `0` with `stale=false`; the authoritative base/head and before/after
  fingerprint are retained in the ignored `tmp/ops98-verify-final.json`
  artifact. Publication, staging deployment and lifecycle cleanup completed
  with the merged slice.

## Historical workflow checkpoint (OPS-99 complete; OPS-100 profile extraction)

- OPS-99 slice branch/worktree was `codex/ops-99-user-auth-characterization` in
  `../opshub-ops-99`, started from exact live
  `origin/staging@b9fe4d6e0234ea3f89561978b8974e738b0f8dfb`. PR #210 merged at
  `00a8021c5848abe8032dad1385cf65f139748aef`; staging deploy `31780994964`
  passed, Linear is `Ready for QA`, and guarded lifecycle cleanup removed the
  task worktree/local/remote branch. Focused UserService passed `70/70`,
  affected Nest passed `177/177`, affected Flutter passed `48`, and the exact
  runner passed with `stale=false`.

## Historical workflow checkpoint (OPS-100 complete; OPS-101)

- Slice branch/worktree: `codex/ops-100-user-profile-collaborator` in
  `../opshub-ops-100`, started from exact live
  `origin/staging@00a8021c5848abe8032dad1385cf65f139748aef`. The canonical
  `staging` worktree and protected OPS-68/OPS-72 worktrees remain untouched.
- Lifecycle `start --prepare --execute` created the worktree and completed the
  Nest/Prisma preflight with fingerprint
  `a245e03be67b0189c76f47f3b1b84bb4f9f2feeef1ec69d66acf45454e20e381`; the
  ignored `backend-nest/node_modules` and generated Prisma client are local
  task artifacts, not product changes.
- PR #211 merged into `staging` at
  `6817cdfd60fe8dbbbc6f64a497765669dba4e562`; all PR checks passed. The task
  worktree and local branch are absent. Exact-SHA staging deploy run
  `31783456149` passed its Android, Windows, web, backend, route and health
  gates. UserService regression passed `70/70`, affected Nest passed `177/177`,
  affected Flutter passed `48`, Nest build and Prisma validation passed, and
  the exact runner returned code `0` with `stale=false`. Linear is
  `Ready for QA`; authenticated QA and production deployment remain open, so
  no production completion is inferred.

## Historical workflow checkpoint (OPS-102/OPS-78 complete; OPS-104 current at that time)

- OPS-102 started from exact `origin/staging@ad8a6de51b5b9e9eac93417cd3a87488ef1606c0`.
  PR #213 squash-merged at `43708ec5d86968ec04882771563ca927fe3763f5`; the
  exact-SHA staging deploy passed all prepare, Android, Windows and deploy
  jobs. Linear is `Ready for QA`; authenticated QA and production deployment
  remain open. The task worktree/local/remote branch were removed by the
  guarded lifecycle finish.
- OPS-78 started from `origin/staging@43708ec5d86968ec04882771563ca927fe3763f5`.
  PR #214 squash-merged at `5b5d644644aa69b2b33fcfbd5442716ec41429c2`; its
  task worktree/local/remote branch were removed by `FINISH PASS`. The staging
  deploy run `31790637975` passed all prepare/build/deploy/health gates; no QA
  or production completion is inferred.
- OPS-78 adds the raw-byte migration evidence EOL preflight and CRLF
  regression coverage. The three tracked migration JSON files are now
  LF-materialized in the canonical checkout; preflight passes, archive
  validation passes against both immutable copies (199 records), promotion
  validation passes, the source DB SHA remains
  `7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`, and
  both archive copies remain `29951f9e16a6c69e4cbd6b8c697f23fa9ca88d513784c00b3dd35353a7ddd955`.
- OPS-68's old local branch/worktree `codex/ops-68-disposition-ledger` at
  `0f4e21c6b45c845e7fcaeafd692d38e19c594d7a` was reviewed, stashed and cleaned;
  it must not be merged, rebased or pushed; the authoritative execution is PR
  #176 plus OPS-69's correction. OPS-72's detached worktree at
  `6ff4899f631f55eb41c0a8b4f1b9a739138768fd` was reviewed, stashed and
  cleaned; merged OPS-72 history on staging is canonical. At this historical
  checkpoint OPS-103 had no implementation worktree and was `Backlog`; it was
  later started from a fresh live checkpoint and is now merged/staging-deployed
  as recorded in the current checkpoint below.
- OPS-104 branch/worktree is `codex/ops-104-master-plan-reconcile` /
  `../opshub-ops-104`, created from exact
  `origin/staging@628d79ef5c938f1c804c7c14e168737ba3755b7b`.
- OPS-104 PR #217 squash-merged into `staging` at
  `1d251d8ed5a94c2d3746cb2aa28a7c45d7ffb237`; exact-SHA staging deploy run
  `31807641556` passed. The task worktree/local branch and remote branch were
  removed after the guarded finish gate.
- OPS-106 branch/worktree is `codex/ops-106-harden-dependency-integrity` /
  `../opshub-ops-106`, initially created from exact
  `origin/staging@628d79ef5c938f1c804c7c14e168737ba3755b7b` and synchronized
  with live `origin/staging@1d251d8ed5a94c2d3746cb2aa28a7c45d7ffb237` by a
  normal merge after OPS-104. Its current implementation commit is
  `b8a0eff4c92fe7f120d926625f83ec04c69150df`; it hardens Flutter package-root
  and Nest install-lock readiness, preserves dirty generated bytes, sanitizes
  diagnostics, retries one transient dependency materialization failure, and
  versions the CI Pub cache key. Focused toolchain proof is `18/18`; exact-base
  runner, PR and staging deployment remain open.

## Validation

Phase 0-1 focused proof:

- deterministic inventory/checkpoint command twice with identical output;
- read-only SQLite integrity/schema/count/digest check for both archive copies;
- source hash before/after unchanged;
- archive/disposition schema validation and secret/path sanitization;
- focused exporter tests;
- `git diff --check`.

Observed Phase 0-1 evidence:

- Source DB SHA-256 before/after: `7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`.
- Source logical-state SHA-256: `2633654f87c15fee6c143a14fa3138a7448c4204f4e24902dadff149583a78fd`.
- Schema versions: `1..12`; logical counts: intake `92`, story `37`, decision `7`, backlog `27`, trace `36`.
- Final local archive timestamp: `20260813T013900Z`; both copies passed integrity, foreign-key, table-digest parity and restore-read checks. Windows ACL was reduced to the current user on each archive leaf; both paths remain on the same host/possible physical disk.
- The empty source sidecars observed during the earlier read-only attempt were
  moved (not deleted) to the ignored `tmp/source-sidecars-20260813T013233Z/`
  quarantine. The final immutable reader created no new `harness.db-wal` or
  `harness.db-shm` beside the canonical source.
- Verified legacy read/export artifact: `harness-cli-v0.1.22`, SHA-256 `1be4be2d47dd8f76c28fed9a238897eab6f542f610e119a69d4281fe64f848b6`. The ignored local `0.1.11` binary was not used.
- Disposition ledger contains exactly `199` records and its SHA-256 is linked from the manifest. Baseline inventory is tracked at `docs/migrations/harness-cleanup-baseline.json`; two consecutive runs matched at SHA-256 `225eabaad96dfe1cbfd2356128c0b77cfaadfba27a2c74495ddb4c298147273`.
- Executed successfully: `python -m unittest discover -s tests/migration -p 'test_*.py' -v` (14 tests), `python -m py_compile scripts/archive-harness-legacy.py`, `node --check scripts/collect-harness-cleanup-baseline.mjs`, `validate-disposition`, `validate-archive`, source before/after hash and sidecar checks, ACL checks, sanitized/mojibake scans, and `git diff --check`.

Repository/runtime proof is intentionally deferred until a later phase because
this slice must not change runtime or retire its current consumers.

Phase 4 evidence:

- `scripts/verify-task.mjs` discovers working-tree, staged, untracked and optional base-to-HEAD paths with rename-as-delete+add semantics.
- `scripts/verification-profiles.mjs` owns profile ids, path patterns, affected consumers, prerequisites and explicit `cwd`/`executable`/`argv` commands.
- Unknown changed paths fail closed with exit code `2`; explicit profiles add to auto-selected profiles; `--full`, `--dry-run`, and repeated `--profile` are supported.
- JSON schema version 1 records base/head, changed paths, profiles, consumers, tool versions, durations, command results and before/after fingerprints. Exit codes are 0 pass, 2 contract, 3 product/test, 4 stale, 5 environment.
- Verified: runner syntax, dry-run JSON and normal JSON execution; structured
  command definitions are fingerprinted and invalid command contracts fail
  closed.
- Extended proof: `node --test tests/verification/*.test.mjs` (14 pass),
  `node scripts/verify-task-canary.mjs` (3/3 fixture canaries pass), and
  product-failure/stale-after-command cases both return their required exit
  codes. Canary fixtures run in disposable Git repositories and explicitly
  report `database: none`.
- `node scripts/verify-task.mjs --base HEAD --dry-run --json
  tmp/final-verify.json` returned exit 0 with profiles
  `harness,docs,verification-runner,flutter`, 28 changed paths and identical
  before/after fingerprints. Archive validation passed against the actual
  primary and secondary `retirement-20260813T013900Z` copies with
  `--repository-root`, including disposition target existence checks.
- The harness profile registry now explicitly owns legacy `scripts/adapter`,
  `scripts/schema`, CLI release/build/promote/verify files and legacy test
  directories. A dedicated fixture proves these retirement paths select the
  `harness` profile instead of failing with an accidental unmatched-path
  contract. Full verification tests remain 14/14 after this registry change.

Phase 3A disposition evidence:

- Branch/worktree: `codex/ops-68-disposition-ledger-fresh`, based on
  `1d57a9b13796182190b15f3014f728005278f98c`; PR #176 merged into `staging`
  at `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`, followed by a passing
  lifecycle `finish --execute` gate.
- `python -m unittest discover -s tests/migration -p 'test_*.py' -q`: all
  migration tests pass (archive and disposition review suites).
- `review-harness-disposition.py --input ...`: PASS, 199 records; after
  correcting the overlapping backlog mapping (`17 → OPS-78`), the ledger SHA
  is `92f114684cb52823fe77d928674b7353e14edb931bf431f09e582435b5d35858`.
- `validate-archive` now requires a tracked `--linear-targets` ledger for
  `OPS-*` references and rejects missing/duplicate/fabricated target IDs; the
  live archive validation passed with all six declared Linear targets.
- `node --test tests/verification/*.test.mjs`: 16/16 pass after adding the
  disposition reviewer to the Harness profile. Exact-base dry-run
  `node scripts/verify-task.mjs --base
  1d57a9b13796182190b15f3014f728005278f98c --dry-run --json
  tmp/ops68-verify.json` passed with profiles `harness`, `docs` and
  `verification-runner`, 11 changed paths, and identical before/after
  fingerprints (`stale=false`).
- Source archive SHA remained
  `29951f9e16a6c69e4cbd6b8c697f23fa9ca88d513784c00b3dd35353a7ddd955` and
  was unchanged before/after the immutable read. The canonical repository DB
  was not opened or modified.
- Both local archive copies were independently re-hashed and matched that
  SHA; all six Linear targets (`OPS-67`, `OPS-72`, `OPS-76`, `OPS-77`,
  `OPS-78`, `OPS-79`) were read back and exist.
- The sanitized ledger contains valid UTF-8, zero duplicate entity/id pairs,
  zero missing required targets and no absolute local paths or raw payloads.
- Linear implementation/proof comment was recorded on `OPS-68` and read back;
  the issue remains Backlog because no status transition was authorized.

Phase 3B current-authority promotion evidence:

- Branch/worktree: `codex/ops-69-current-authority-promotion-and-linear-follow-ups`,
  based on `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`; draft PR `#177`
  (`https://github.com/hoanghochoi/phongvu-opshub/pull/177`) is open against
  `staging` at head `97dcaac2767df6cd2b286c81a59d21174cb853d2`.
- The final local commit SHA is recorded in the Linear proof note and the
  exact-base `verify-task` JSON output; the report's `repositoryRevision`
  remains the exact Phase 3B input checkpoint
  `ee74d0efb9b16cda0725d8940b0a1e544d0ba006` so the artifact does not create a
  self-referential commit-hash cycle.
- Corrected ledger/archive linkage was revalidated against both immutable local
  archive copies: `199` records, counts `92/37/7/27/36`, source DB SHA
  `7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`, and
  archive copy SHA `29951f9e16a6c69e4cbd6b8c697f23fa9ca88d513784c00b3dd35353a7ddd955`.
- `scripts/promote-harness-authority.py` generated and round-tripped the
  payload-free `docs/migrations/harness-v1-authority-promotion.json` report:
  `199` records, `70` target-bearing records, `34` Git destinations and six
  existing Linear follow-up targets. Policy asserts archive read-only,
  database-written false, raw-payload committed false and no row-for-row
  Markdown migration.
- The promotion report records `OPS-78` backlog coverage as `[14,17,26]` and
  `OPS-79` coverage as `[15,16,18,19,20,21,22,23,24,25]`; the verifier now
  rejects target manifests whose report IDs do not match the tracked ledger.
- Promotion validation now recomputes the complete report from the ledger and
  rejects semantic tampering or source/schema drift against the archive
  manifest; regression coverage includes both failure classes.
- Migration tests: `30/30` pass; archive validator and disposition reviewer
  both pass against the immutable copies; promotion generation and round-trip
  both pass. Exact-base `verify-task` and Linear proof read-back pass; only the
  guarded push/PR/merge lifecycle remains for this slice.

Phase 5 retirement evidence (OPS-70):

- The retirement manifest covers `96` legacy paths/groups and is checked by
  `node scripts/verify-harness-retirement.mjs`. The validator inspects both
  `HEAD` and the index, so staged deletions cannot evade disposition coverage;
  database/archive deletion remains explicitly forbidden.
- Removed OpsHub Harness producer surfaces include SQLite schema/adapters,
  materialization/rebuild tools, protocol-v1 contracts, CLI/core release
  workflows and their obsolete tests. The upstream installer now exposes one
  `harness-v0.1.8` core payload; no `--with-cli` or compatibility bundle path
  remains.
- Current authority docs and `AGENTS.md` now describe the upstream binary as
  the only Harness interface. The generic verification registry owns legacy
  deletion paths during this transition, while current validation invokes only
  `scripts/verify-task.mjs` and repository-native workflow tests.
- Validation on the OPS-70 worktree: retirement validator PASS; docs contract
  PASS; verification suite `16/16` PASS; migration suite `30/30` PASS; and
  `git diff --check` PASS. The first migration run exposed a CRLF-normalized
  fixture hash mismatch; restoring the tracked LF artifact removed the false
  failure without changing migration data.
- No `harness.db`, WAL/SHM file, archive copy, or runtime product file was
  written or deleted. Fresh upstream binary lifecycle smoke remains a final
  pre-merge gate and must be rerun on the exact published SHA.

Verification hardening evidence:

- Commit `ef8995ec` makes `verify-task` fingerprint staged, unstaged and
  base-aware binary diffs from raw Git bytes; a temporary invalid-UTF-8 binary
  fixture changes the fingerprint as required.
- `node --test tests/verification/*.test.mjs`: 14/14 pass;
  `node scripts/verify-task.mjs --base origin/staging --dry-run`: exit 0,
  stale=false; `git diff --check`: pass.
- Windows `.cmd`/`.bat` structured-command invocation was exercised through
  the supported shell path and returned a structured pass with exit code 0.

Environment classification evidence:

- The first full-profile attempt correctly returned exit `5` for a missing local
  Nest toolchain. After the task worktree installed dependencies with
  `npm ci --ignore-scripts` and generated the Prisma client with
  `npx prisma generate`, the exact final runner proof passed:
  `node scripts/verify-task.mjs --base origin/staging --full --json
  tmp/verify-ops65-final.json` after the final implementation commit. The
  artifact's `baseSha` and `headSha` are the authoritative exact-SHA record;
  they must be read back with the result rather than duplicated in this
  fingerprinted plan file.
  All eight profiles (`harness`, `docs`, `verification-runner`, `release`,
  `flutter`, `nestjs`, `go-realtime`, `deployment`) returned code `0`, with
  matching before/after fingerprints and `stale=false`. The exact final
  fingerprint is emitted in the JSON artifact from the command above; it is
  intentionally not copied into this fingerprinted plan file.
- `node --test tests/verification/*.test.mjs`: 16/16 pass, including mocked
  and actual Windows `npm.cmd` command-not-found cases.

Phase 7A groundwork evidence:
- `flutter pub get --offline` completed successfully on the task worktree.
- `dart analyze test/flutter_test_config.dart` passed, and
  `flutter test --no-pub test/app_log_file_test.dart test/app_logger_upload_test.dart test/flutter_test_config_smoke_test.dart --reporter expanded` passed 6/6 with the shared bootstrap; the smoke test directly verifies the fake path provider and cancelled file picker, with no benign plugin exception emitted.
- `flutter test --no-pub test/widget_test.dart --reporter compact` passed 2/2;
  existing app startup/session consumers remain green under the bootstrap.
- Full Flutter suite after teardown hardening passed with exit `0`, zero failed
  tests and zero `MissingPluginException` noise (`tmp/flutter-full-suite-after.json`;
  855 visible tests plus framework setup/teardown events). The initial run
  exposed one Windows directory-handle teardown error; it was fixed by the
  test-only flush/retry change. After adding save-file picker success/error
  fakes, the focused export proof passed and the exact final full suite passed
  again with 860 visible tests and 3 platform skips (`tmp/flutter-full-suite-final.log`).
  Expected error logs from failure-path tests remain observable; they are not
  test failures and are not swallowed by the bootstrap.

Phase 2 evidence:
- Upstream tag `harness-v0.1.8` resolves to release source commit
  `8f78cbbc2c0bd146f4174ab0f3fd9e9699cb4298`; the pinned release file now
  records that tag.
- The published Windows artifact `harness-windows-x64.exe` reports
  `harness 0.1.8`. Its SHA-256 was independently checked against the published
  sidecar during the disposable proof (the sidecar download was retried because
  GitHub intermittently returned an incomplete response).
- A fresh disposable install using the tagged binary passed JSON install,
  `status`, `doctor`, and `update --dry-run` with exit code `0`; dry-run emitted
  changes without writing the target. A pre-existing customized target was
  also inspected to confirm install adoption preserves consumer text outside
  the managed Harness boundary.
- The tracked core manifest now includes the exact v0.1.8 generic payload:
  `$improve-harness`, `application-runbook.md`, and `harness-improvement.md`.
  Legacy SQLite/protocol-v1 files remain untouched for the later retirement
  phase.
- The published v0.1.7 → v0.1.8 transition was exercised with the exact
  upstream release handoff in disposable workspaces. Non-overlap applied
  cleanly; overlap returned exit `2` and retained a resolution packet and
  candidate; editing the staged resolution then `--continue` applied exit `0`;
  `--abort` removed the packet while preserving the local file; dry-run kept
  hashes and state unchanged. The upstream source test suite also passed all
  10 unit,
  2 release-update, 8 update-lifecycle, 2 CLI-lifecycle and 2 architecture
  integration tests. Direct live download remains blocked by the environment's
  premature GitHub response and is intentionally recorded as residual risk.

Current live upstream retry evidence:
- A disposable v0.1.8 install and customized `AGENTS.md` preservation pass;
  `status --json` passes; `update --dry-run` reaches the release fetch but is
  blocked by the environment's premature GitHub response (`curl: (52) Empty
  reply from server`). The same failure was reproduced with PowerShell
  `Invoke-WebRequest`; this remains a live-network residual risk, not a reason
  to discard the independently verified local candidate-transition proof.

- The GitHub Releases API successfully downloaded the exact published
  `harness-windows-x64.exe` (1,385,472 bytes), reported `harness 0.1.8`, and
  matched SHA-256 `e15ad887d028d27844e326fa76bb43931660a7452a9ef474f8a8eeb7610ff9c0`.
  The published v0.1.7 artifact also matched SHA-256
  `9948fa714ee8e7731c1691f3d84649832571b882d009aaa0c511a0c82086754c`.
  Disposable v0.1.7 → v0.1.8 proof covered non-overlap, retained
  candidate/conflict, human resolution plus `--continue`, `--abort`, and
  dry-run immutability.

## Historical workflow checkpoint (OPS-104 complete; OPS-106 current at that time)

- OPS-105 branch/worktree was `codex/ops-105-mandatory-toolchain-preflight` /
  `../opshub-ops-105`, created from exact live
  `origin/staging@db0fb30c24ed3421a7519e5a4f9ee0a7b2f4fc48`. PR #216
  squash-merged into `staging` at
  `628d79ef5c938f1c804c7c14e168737ba3755b7b`; exact-SHA staging deploy run
  `31804029517` passed all build/deploy/health gates. The task worktree and
  local branch were removed by guarded lifecycle cleanup; the remote branch is
  retained only where GitHub's merged-PR deletion was blocked by the canonical
  worktree guard.
- Cold worktree preparation with `--prepare --prepare-profile all` passed for
  Nest/Prisma and Flutter package config before implementation. The lifecycle
  now defaults to `prepare=true` and profile `all`; `finish` remains a cleanup
  operation and no longer mistakes the default preparation state for a
  start-only flag.
- Toolchain schema is bumped to invalidate old readiness state. Readiness now
  requires a readable Flutter package config and the npm install lock marker;
  fingerprints include Node/npm/Flutter/Dart identity where applicable.
- Verification profiles share one deduplicated `toolchain-preflight` command
  using profile `all`. OPS-39/OPS-40 affected consumers and the payment audio
  validator invoke the same preflight; release workflows replace ad-hoc
  `flutter pub get` with the tracked preflight entrypoint.
- Focused toolchain tests passed `13/13`, verification tests `21/21`, lifecycle
  tests `16/16`, and the full runner passed all eight profiles with
  `stale=false`. The remaining gap—stale external package materialization
  behind a readable marker—was tracked by OPS-106 and is now carried as a
  follow-up in the current checkpoint.
- OPS-104 branch/worktree is `codex/ops-104-master-plan-reconcile` /
  `../opshub-ops-104`, created from exact
  `origin/staging@628d79ef5c938f1c804c7c14e168737ba3755b7b`.

## Historical workflow checkpoint (OPS-108 current at that time; OPS-106/OPS-103/OPS-107 complete)

- OPS-108 was the docs-only reconciliation slice. Its branch/worktree
  is `codex/ops-108-reconcile-master-plan-after-ops-106-103-107` /
  `../opshub-ops-108`, created from exact live
  `origin/staging@100f2ad319e72bb0334c64c6a8de0ff85b3b8782`. The canonical
  staging worktree remained clean and the remote SHA stayed unchanged during
  intake.
- The intake checkpoint (branch, HEAD, status/untracked paths, tracked index
  entries, worktree/index binary diff, file modes/deletions and untracked
  content hashes) was captured twice independently with identical SHA-256
  `64baaab93210f99dd8268e47616e54f9c8253baaa6afa1e04396521211052a65`.
- OPS-108 task preflight completed for both profiles. The Nest result is
  cached/ready with lockfile version 3, 61 direct dependencies, zero missing
  direct or locked packages, Nest CLI and Prisma generated entrypoints. The
  Flutter result is cached/ready with package-config schema 2, root package and
  all 174 referenced package roots present. No tracked changes were produced;
  only ignored task-local dependency/build state exists.
- The initial lifecycle command exceeded the 180-second shell wrapper timeout
  after hydration completed. The worktree was re-verified at the expected HEAD,
  with both profiles cached and the live staging SHA unchanged; no rollback or
  force cleanup was performed.
- OPS-106 exact proof remains: toolchain tests `18/18`, lifecycle tests `16/16`,
  Flutter analyze, Nest build, Go/release/deployment/security profiles and the
  exact runner all passed with `stale=false`. Its remaining follow-up is
  dependency-bootstrap closure for standalone command bypasses, shared Pub
  cache races and deeper Flutter package materialization checks.
- OPS-103 exact proof remains: UserService suite `73/73`, exact runner
  `stale=false`, and staging deploy `31815294365`; residual work is extraction
  of the import/welcome-email collaborator behind the stable facade.
- OPS-107 exact proof remains: MAP service suite `153/153`, controller/provider/
  sync suites passed, exact runner `stale=false`, and staging deploy
  `31815315261`; residual work is extraction of persistence/canonical identity/
  dedup/quarantine collaboration.
- The next implementation slices are dependency-bootstrap closure, then the
  named UserService and MAP extraction slices. No production completion is
  inferred from staging merge or QA readiness.

## Historical workflow checkpoint (OPS-109; dependency bootstrap closure)

- At that time OPS-109 was the tooling slice. Its branch/worktree was
  `codex/ops-109-close-dependency-bootstrap-bypasses-and-materialization-races`
  / `../opshub-ops-109`, created from exact live
  `origin/staging@fe936bdf8ff4d192fbb9e1248956fb0743353c19`. The intake
  checkpoint was captured twice with identical SHA-256
  `733cde31831b3f724bfed0459da37521d22656edd069b2b384dd88f2c42b20e8`.
- The slice closed the standalone validation bypass in
  `scripts/validate-contract-appendix.sh`, adds `--root` repair/doctor mode,
  strengthens Flutter readiness for materialized Dart package roots and
  platform-only plugins, serializes shared Pub-cache hydration and atomically
  publishes ignored state.
- Focused proof passed: toolchain/coverage suite `23/23`, syntax and
  shell parse checks pass, and the exact runner selects `harness` plus
  `verification-runner` for six changed paths with `stale=false`. The final
  publication proof must be rerun after any plan/docs edit and after the last
  source change.
- No product/runtime/API/UI behavior changed. The remaining gate at that time was exact
  final proof, PR/staging lifecycle and cleanup of this task worktree.

## Historical workflow checkpoint (OPS-110; UserService import and welcome email)

- At that time OPS-110 was the runtime slice. Its branch/worktree was
  `codex/ops-110-extract-userservice-import-and-welcome-email` /
  `../opshub-ops-110`, created from exact live
  `origin/staging@229603e23d1bf6d408e5de38465dec55ca71db8f`. The intake
  checkpoint was captured twice with identical SHA-256
  `b12e1d8f4e0b41c00a2b3cc7fd133b48659cf8fb36a48dddaa23836d7193e1f1`.
- The slice kept `UserService` as the public facade and extracted import
  preparation/persistence/access-change orchestration into
  `UserImportService`; welcome-email delivery is isolated in
  `UserWelcomeEmailService`. Routes, DTOs, DI tokens, permissions, response
  shapes, organization resolution and access-change reasons are unchanged.
- Characterization proof passed the UserService suite `73/73` and the
  collaborator suite `4/4`; the exact runner, Nest build, PR/CI, staging
  deploy `31824663356`, CodeQL `31824663334` and guarded lifecycle cleanup all
  passed. The merge commit is
  `ba6cba8ceba7f1b025d94d021f00071e411bd70a`; Linear remains `Ready for QA`
  pending production deployment.
- Rollback is the single OPS-110 merge commit; removing the two collaborators
  and restoring the facade implementation returns the prior behavior. No
  database or runtime data migration was required.

## Historical workflow checkpoint (OPS-111 and OPS-113 complete; OPS-112)

- OPS-111 `codex/ops-111-toolchain-execution-gate` was created from exact
  `origin/staging@ba6cba8ceba7f1b025d94d021f00071e411bd70a`, with identical
  intake checkpoint SHA-256
  `d6a585ee1b1d2dfa7b1b7e6cb423b5ee05153beae6a1607ea2ce2e003adca9a6`.
  PR #224 merged at `6ae638fafba1195611ceaf5b879255d2c0b1e93f`; Release Guard,
  shadow verification and CodeQL passed; guarded lifecycle cleanup removed the
  task worktree/local/remote branch. The shared gate, dependency-only Nest
  fingerprint, Windows `ENOTEMPTY` quarantine/retry and direct Nest/Flutter
  build/test coverage remain the current local-worktree authority.
- Exact-SHA staging deploy `31829555645` failed only in the backend image
  build: `backend-nest` is a self-contained Docker context, while the new
  local `prebuild` hook resolved `../scripts/run-with-toolchain.mjs` as missing
  `/scripts/run-with-toolchain.mjs`. Android, Windows and web artifacts passed;
  the release trap restored `ba6cba8c` healthy. This was a deployment
  regression, not a missing-dependency or product-runtime failure.
- OPS-113 `codex/ops-113-docker-preflight-hotfix` was created from exact
  `origin/staging@6ae638fa`, then merged in PR #225 at
  `056e01b4230b7e6c2eeaf5059b9624e13e289694`. The Docker build now executes
  the explicit `build` script with pre/post hooks suppressed only inside that
  backend-only image; local `npm run build/test` retains the preflight hook.
  Static coverage passed `6/6`; Docker-equivalent Sharp/security/Prisma/build
  commands, local preflight build, full Nest `111/111` suites (`1,236` passed,
  `6` skipped), and exact runner (`harness,nestjs`, `stale=false`) passed.
  Staging deploy `31832800738` passed all build, Docker/runtime, route and
  public health/version gates without rollback. Guarded lifecycle cleanup and
  remote-branch deletion completed; Linear is `Ready for QA` pending
  production.
- OPS-112 `codex/ops-112-reconcile-shadow-baseline` now runs from exact live
  `origin/staging@056e01b4230b7e6c2eeaf5059b9624e13e289694`. Its uncommitted
  telemetry diff was temporarily stashed while OPS-113 advanced staging, then
  restored after a clean fast-forward; no user work was overwritten. It adds
  schema-v2 cohort id, queue/start/end timestamps, queue/execution durations,
  total plus per-ladder retry counts, and first actionable failure timing to
  shadow reports. Historical replays remain non-promoting; five new live
  observations in one cohort are required before evaluating the 25%/30%
  optimization targets. The next gates are focused telemetry tests, exact-base
  verification, PR/CI, staging deploy and guarded lifecycle cleanup.

## Historical workflow checkpoint (OPS-118 complete; OPS-119)

- OPS-118 branch/worktree was `codex/ops-118-close-affected-consumer-dependency-boundary` /
  `../opshub-ops-118`, created from exact live
  `origin/staging@df10e6adb905e27d5547eff07a884e21efd7f435`. PR #231 merged at
  `c46dff3ae9379f663fcac3d8c960ce7c17361933`; staging deploy `31848065825`
  passed and guarded lifecycle cleanup removed the task worktree/local branch.
- The original OPS-39/OPS-40 validators performed one detached `all` preflight
  and then spawned raw Flutter/Nest commands. OPS-118 adds the shared
  `run-affected-consumer-suite.mjs` dispatcher; every Flutter/Nest suite now
  carries an explicit `flutter`/`nestjs` profile and is preflighted in its own
  command boundary. Go, Node-only, Git, Docker and remote-maintenance commands
  stay in their existing boundaries.
- Focused proof passed: dependency-boundary/toolchain tests `14/14`, OPS-40
  affected consumers `14 suites / 167 tests` plus Flutter `137` tests, and
  OPS-39 affected consumers `13 suites / 290 tests` plus Flutter `75` tests;
  Go/Caddy/whitespace contracts also passed. A corrected disposable canary
  from the exact SHA, with no `.dart_tool` or `backend-nest/node_modules`, ran
  both validators successfully; the first Nest hydration installed `943`
  locked packages and generated Prisma before the consumer suite. Sanitized
  evidence is retained in
  `docs/migrations/ops-118-dependency-boundary-canary.json`.
- OPS-118 final gates passed: exact `verify-task` after the final code/plan
  state returned `stale=false`, PR #231 checks passed, staging deploy passed,
  and the lifecycle finish gate passed. Authenticated QA and production
  promotion remain open as required by the release lifecycle.

## Historical workflow checkpoint (OPS-119 complete; OPS-120)

- OPS-119 branch/worktree was `codex/ops-119-close-operational-local-dependency-entrypoints` /
  `../opshub-ops-119`, created from exact live
  `origin/staging@c46dff3ae9379f663fcac3d8c960ce7c17361933` with the Nest
  profile hydrated. PR #232 merged at
  `b3913e8d973d2fd35fef03f986cdf79c88c819b6`; staging deploy `31850797873`
  passed and lifecycle cleanup removed the task worktree/local branch.
- The remaining local `verify:ops40:postgres` verifier spawned raw `npx.cmd`
  after creating its disposable database. OPS-119 routes that Prisma migration
  through `run-with-toolchain` with `--no-install`, updates the support-chat
  runbook to the repository-root command, and adds static regression coverage.
  Docker/self-contained image commands and remote maintenance remain separate
  boundaries.
- OPS-119 final gates passed: PowerShell syntax, `git diff --check`, focused
  dependency boundary coverage `10/10`, exact `verify-task --base origin/staging`
  with `stale=false`, disposable PostgreSQL fresh/rollback/upgrade proof,
  PR/CI, staging deploy and lifecycle finish. Authenticated QA and production
  promotion remain open as required by the release lifecycle.

## Historical workflow checkpoint (OPS-120; Windows MSIX Flutter boundary)

- Branch/worktree: `codex/ops-120-gate-windows-msix-flutter-toolchain` /
  `../opshub-ops-120`, created by the guarded lifecycle start gate from exact
  live `origin/staging@b3913e8d973d2fd35fef03f986cdf79c88c819b6` with the
  Flutter profile hydrated.
- The two Windows MSIX helpers currently invoke raw `dart @msixArgs`. OPS-120
  routes both through the Flutter `run-with-toolchain` boundary while keeping
  MSIX arguments, signing, output paths and certificate behavior unchanged.
  Sensitive command values are redacted from structured proof output and
  fingerprints; Docker/self-contained and remote-maintenance commands remain
  separate boundaries.
- Current proof: focused toolchain/boundary tests and both PowerShell syntax
  checks pass; Flutter dry-run shows the profile/readiness gate and redacts the
  certificate password. Exact runner, release workflow checks and staging
  deploy remain required before publication.

## Historical workflow checkpoint (OPS-121; dependency bootstrap resume boundary)

- OPS-121 branch/worktree is `codex/ops-121-dependency-bootstrap-resume-boundary` /
  `../opshub-ops-121-dependency-bootstrap-resume-boundary`, created by the
  guarded lifecycle start gate from exact live
  `origin/staging@d5b81d45ac9bd6a706e03dffa6b30028e5ef2dfb`. Canonical staging
  was clean before creation and remains the protected integration worktree.
- The slice adds `scripts/toolchain-doctor.mjs` for existing/resumed worktrees,
  makes the `all` preflight report NestJS and Flutter independently, adds
  targeted cold/profile regression tests, closes local operational NestJS npm
  script hooks, and rewrites current runbook/product examples through the
  repository toolchain gate. Docker-only and remote-maintenance commands stay
  explicit boundaries.
- Local proof so far: toolchain/doctor/entrypoint tests `30/30`, Node syntax,
  package JSON validation and `git diff --check` pass. The new worktree was
  created cold with no ignored dependencies and lifecycle hydration passed for
  both profiles. Doctor dry-run and cached repair returned sanitized JSON with
  Nest `943` installed packages and Flutter package-config schema `2`, zero
  missing package roots, and independent profile results.
- Remaining gates: exact `verify-task --base origin/staging` with
  `stale=false`, full affected consumer/toolchain proof, PR/CI, staging deploy,
  Linear implementation/proof note, and guarded `finish --allow-ignored
  --execute` cleanup.

## Historical workflow checkpoint (OPS-122 complete; OPS-73 dependency-readiness residual)

- OPS-122 was completed after PR #235 was squash-merged into `staging` at
  `d10241c0eafab66bd34390e7dda8d58a96e54147`. Staging deploy run `31857551682`
  passed its Windows, Android and deployment-health gates; its Linear proof
  note was recorded and read back before moving OPS-122 to `Ready for QA`.
- The canonical `staging` worktree was then verified clean and equal to
  `origin/staging@d10241c0eafab66bd34390e7dda8d58a96e54147`. OPS-122's only
  remaining lifecycle work is the normal QA/production gate; it no longer
  owns the active repository checkpoint.
- The next residual is OPS-73: prevent repeated missing Flutter/Nest
  dependencies and direct tool-entrypoint failures across fresh worktrees,
  local verification, Prisma migration checks, Docker and remote maintenance.
  The slice remains workflow/toolchain-only and does not change product
  dependency versions or runtime behavior.

## Historical workflow checkpoint (OPS-73; dependency readiness closure)

- Branch/worktree: `codex/ops-73-dependency-readiness-closure` /
  `../opshub-ops-73-dependency-readiness`, created from the exact live
  `origin/staging@d10241c0eafab66bd34390e7dda8d58a96e54147`. The canonical
  staging worktree was clean at start and no reset/rebase is permitted.
- Affected scope: `scripts/prepare-task-toolchain.mjs`, the tracked toolchain
  and verification profile tests, Nest Prisma migration entrypoints,
  `backend-nest/Dockerfile`, staging/home-server deployment commands, and the
  associated runbooks. Worktree-local `node_modules`/`.dart_tool` remain
  ignored; shared npm/Pub download caches are readiness inputs only.
- Readiness contract: Flutter must have valid plugin metadata, plugin roots and
  package-config roots; Nest must match required package versions/integrity
  against the tracked lockfile. All dependency-consuming commands go through
  the toolchain wrapper or `npx --no-install`; optional OS/CPU packages remain
  non-blocking. A malformed, missing or drifting installation fails closed
  before build/test/migration execution.
- Exact proof: toolchain tests `57/57`, lifecycle tests `16/16`, migration-EOL,
  Caddy/platform security contracts and the selected profiles
  (`harness,docs,verification-runner,release,nestjs,deployment`) passed. Nest
  build, security-dependency check, Flutter analyze, and the targeted Home
  Summary projection test (`3 passed`, `6 skipped`) also passed; the final
  runner reported `18` changed paths, `13` affected consumers and `stale=false`
  with matching before/after fingerprint. The exact sanitized JSON result is
  kept in the ignored task-local `tmp/ops-73-verify-final.json`; the plan does
  not embed that self-referential hash because the plan itself is part of the
  runner fingerprint.
- Residual checklist for this slice:
  - [x] Re-run the exact final `verify-task` after the plan edit; the final
    result is pass with `stale=false`.
  - [x] Inspect the final diff and `git diff --check`.
  - [x] PR #236 was squash-merged into `staging` at
    `be4b4a08b46886b9c150cd1db12ebf7bf7332027`; PR checks passed.
  - [x] Linear OPS-73 received the implementation/deployment proof and was
    moved to `Ready for QA` (not `Done`).
  - [x] Guarded lifecycle `finish --allow-ignored --execute` removed the task
    worktree/local/remote branch after the follow-up staging deploy passed.
- Rollback: revert the OPS-73 PR as one unit. Existing lockfiles, source DB,
  archive copies and ignored dependency caches are unchanged by this slice.

## Workflow checkpoint (OPS-113 complete; Docker preflight regression hotfix)

- OPS-73 was squash-merged as PR #236 at
  `be4b4a08b46886b9c150cd1db12ebf7bf7332027`, from base
  `d10241c0eafab66bd34390e7dda8d58a96e54147`. PR checks passed and the remote
  task branch was removed.
- Exact staging deploy run `31861438999` passed Android, Windows and web
  artifact publication, then failed in the backend Docker build at
  `npm run verify:security-deps` because its new package pre-hook referenced
  `/scripts/run-with-toolchain.mjs`, which is outside the backend-only Docker
  context. The deploy rollback restored the previous release and all rollback
  services were healthy.
- OPS-113 branch/worktree is
  `codex/ops-113-docker-preflight-regression` /
  `../opshub-ops-113-docker-preflight-regression`, created by the guarded
  lifecycle start from exact `origin/staging@be4b4a08`. The hotfix changes only
  the Docker-only invocation to `npm run verify:security-deps --ignore-scripts`
  and adds a static regression assertion; local/CI package lifecycle hooks keep
  the repository-root toolchain preflight.
- OPS-113 PR #237 squash-merged at
  `4dffcf60494eda3934c52eb46c97fa82b9338a28`. Exact staging deploy
  `31862881662` passed backend build, runtime switch, direct-origin and public
  health/version checks without rollback. The guarded lifecycle finish gate
  removed `../opshub-ops-113-docker-preflight-regression`, its local branch and
  its remote branch. Linear OPS-113 is `Ready for QA`; production remains the
  only completion gate. Rollback is the single OPS-113 hotfix commit.

## Historical workflow checkpoint (OPS-122 reconciliation)

- This docs-only slice is branch/worktree
  `codex/ops-122-reconcile-current-checkpoint` /
  `../opshub-ops-122-current-checkpoint`, created by the guarded lifecycle
  start gate from exact live `origin/staging@4dffcf60494eda3934c52eb46c97fa82b9338a28`.
  The canonical staging worktree was clean and remains untouched.
- It reconciles the sole active plan after OPS-73/OPS-113 publication,
  deployment and cleanup. It does not modify product/runtime code, dependency
  versions, the read-only Harness archive, or Linear production lifecycle.
- Required proof is docs diff check, exact `verify-task --base origin/staging`
  with `stale=false`, PR/CI, staging deploy and guarded lifecycle cleanup.
  Rollback is one docs-only squash revert.

## Workflow checkpoint (OPS-72 timing baseline v2; historical current slice)

- This slice is branch/worktree `codex/ops-72-timing-baseline-v2` /
  `../opshub-ops-72-timing-baseline-v2`, created by the guarded lifecycle start
  gate from exact live `origin/staging@661e930a10e198edc84d0d192d5f2f766ff777a4`.
  It changes only sanitized shadow evidence, its validator/tests and this plan;
  no product/runtime/API/UI/data behavior is in scope.
- The five comparable observations are PRs #228–#232, all cohort
  `ops72-live-v2`, `stale=false`, zero unmatched paths and zero retries. The
  pre-telemetry v1 baseline is PRs #181/#183/#184/#185/#186. Shadow-duration
  median is `6496ms` versus `7647ms` (`15.05%` reduction); GitHub job-duration
  median is `23000ms` versus `25000ms` (`8%` reduction).
- Both cohorts have zero environment reruns, so the 30% rerun-reduction target
  is unmeasurable. Every accepted observation passed, so no first-actionable-
  failure median is claimed. The evidence target is therefore `revise` and no
  profile is promoted to blocking.
- Next step: run a revised failure-injection/timing cohort with a comparable
  baseline, or explicitly revise the acceptance metric before closing OPS-72.
  Rollback is one evidence/validator/docs revert.

## Historical workflow checkpoint (OPS-123; reconciliation after OPS-72)

- This docs-only slice is branch/worktree
  `codex/ops-123-reconcile-ops72-checkpoint` /
  `../opshub-ops-123-reconcile-ops72-checkpoint`, created by the guarded
  lifecycle start gate from exact live
  `origin/staging@4dda2592de5d0691082756d0d6fb32d0b93e8607`.
- It updates the master-plan authority to the post-OPS-72 merge checkpoint and
  preserves the exact PR #239, deploy `31869668906`, validation and cleanup
  proof. No product/runtime/API/UI/data/dependency/archive behavior changes.
- Required proof is `git diff --check`, exact `verify-task --base origin/staging`
  with `stale=false`, PR/CI, staging deploy and guarded lifecycle cleanup.
  Rollback is one docs-only squash revert.

## Historical workflow checkpoint (OPS-124; command-time dependency readiness)

- This slice is branch/worktree
  `codex/ops-124-command-time-dependency-readiness` /
  `../opshub-ops-124-command-time-dependency-readiness`, created by the guarded
  lifecycle start gate from exact live
  `origin/staging@e25c5d5cf1040172e5d25d774db99dfc1c1b3f99`. The canonical
  staging worktree was clean and remains protected.
- It closes the remaining dependency-readiness race after OPS-73/OPS-121:
  command-time repair now requires a non-zero command result, preserves a
  sanitized dependency diagnostic, returns environment exit `5` with
  `recovery.status=failed-after-repair` when the retry remains broken, and
  maps `--profile all` repairs to the actual Flutter/Nest executable context.
- Flutter holds a shared Pub-cache lease across the complete gated command;
  Nest holds a per-worktree lease across dependency hydration, command reads,
  quarantine and repair. Same-process repair is re-entrant; other writers wait
  or fail closed after the stale-lock timeout. Readiness now requires physical
  Flutter package/plugin directories and declared direct Nest package
  main/module/browser/bin entrypoints.
- Affected scope is toolchain scripts, the Prisma recovery boundary, static
  dependency-entrypoint coverage, focused readiness/retry/lease tests and the
  current scripts runbook. No product/runtime/API/UI/data/dependency-version or
  archive behavior changes are intended.
- Local proof: all toolchain/boundary tests passed `73/73`; modified scripts
  pass `node --check`; Nest dry-run readiness passed with `943` installed
  packages and `76` entrypoints checked; exact `verify-task --base
  origin/staging` passed with profiles `harness,docs,nestjs` and 10 affected
  paths. PR #241 checks, CodeQL, Release Guard and Affected Verification
  Shadow passed; exact staging deploy `31875595813` passed Android, Windows,
  web, backend, direct-origin and public health/version checks. Linear proof
  was recorded and OPS-124 is `Ready for QA`; guarded lifecycle cleanup
  removed the task worktree/local branch and the remote task branch was
  deleted separately.
- Rollback: revert the OPS-124 PR as one unit. Ignored dependency directories,
  shared caches, source DB and Harness archive remain untouched.

## Workflow checkpoint (OPS-125; master-plan reconciliation after OPS-124)

- This docs-only slice is branch/worktree
  `codex/ops-125-master-plan-checkpoint-after-ops-124` /
  `../opshub-ops-125-master-plan-checkpoint-after-ops-124`, created by the
  guarded lifecycle start gate from exact live
  `origin/staging@5432a995fb1a68a70be96a95ba45592fb9e703c1`.
- It updates the sole active plan's current checkpoint, records OPS-124's
  merged/deployed/cleaned evidence, preserves OPS-72's explicit `revise`
  residual, and keeps Phase 8's `n8n/`/legacy-route/platform/release-
  allowlist ownership requirement open until independent owner and rollback
  evidence exists. No product/runtime/API/UI/data/dependency/archive behavior
  changes are in scope.
- The next bounded lane is a revised OPS-72 failure-injection/timing cohort
  touching the shadow runner/profile/evidence authority. Runtime User/Auth
  residual waves remain serialized after that workflow evidence; no new
  overlapping runtime branch is opened by this reconciliation.
- Required proof is `git diff --check`, exact `verify-task --base
  origin/staging` with `stale=false`, PR/CI and guarded lifecycle cleanup.
  Rollback is one docs-only squash revert.

## Workflow checkpoint (OPS-126; controlled failure-injection cohort)

- OPS-126 branch/worktree is
  `codex/ops-126-controlled-failure-injection-timing` /
  `../opshub-ops-126-controlled-failure-injection-timing`, created by the
  guarded lifecycle start gate from exact
  `origin/staging@f0f080d78871b8e3112eab18c3c6f9e834ab36ea`. The canonical
  staging worktree remained clean and protected.
- The slice adds a real `verifyTask`/`buildShadowReport` controlled-command
  seam, deterministic five-scenario evidence generation, fail-closed artifact
  validation and additive `firstObservedFailure` telemetry. No product,
  runtime, API, dependency-version or live shadow workflow behavior is changed.
- Tracked evidence is
  `docs/migrations/ops-72-failure-injection-cohort.json`. It records five
  controlled scenarios, raw report hashes and repository-relative raw paths;
  raw reports remain ignored under `tmp/ops-126-shadow/`. The aggregate is
  explicitly `controlled-evidence-only` with `promotionDecision=do-not-promote`
  and must not be used to claim the Phase 7B live targets.
- Controlled calibration produced a 53.33% decision-latency reduction and
  100% retry reduction across the five fixtures. These values are synthetic
  calibration inputs, not representative live observations; OPS-72 remains
  `revise` until the required live cohort meets its acceptance criteria.
- Required publication proof is focused verification/runner/toolchain tests,
  artifact validation with raw-hash recheck, `git diff --check`, exact
  `verify-task --base origin/staging` with `stale=false`, PR/CI and guarded
  lifecycle cleanup. Rollback is one OPS-126 squash revert.

## Historical workflow checkpoint (OPS-127; deterministic dependency bootstrap/resume guard)

- OPS-127 was created by the guarded lifecycle start gate from exact
  `origin/staging@10881fdff44f0357d251f777e3bac4d7fdd522c2`, published as PR
  #244, and squash-merged into `staging` at
  `00927eedb793d7c2b2c895a72b3b6fe1a7f4b205`. Staging deploy
  `31882302133` passed and the task worktree/local/remote branch were removed;
  no OPS-127 implementation worktree remains.
- The first slice closes current guidance/runbook bypasses: the validation
  ladder and home-server Flutter build now use the repository toolchain gate;
  the web smoke remediation points to the same gate. A fail-closed scanner
  checks current agent guidance, READMEs, runbooks, workflows and dependency
  scripts, with explicit Docker/remote/SDK allowlists.
- The scanner is registered in the Harness verification profile and has fixture
  coverage for raw Flutter/Nest commands, wrapper continuations, Docker
  maintenance and the explicit remote Prisma exception. No product/runtime/API,
  dependency-version or archive behavior changes are in scope.
- Start and publication proof passed: lifecycle all-toolchain hydration,
  scanner/boundary coverage, cold/resume canaries, exact affected verification
  with `stale=false`, PR checks, staging deployment and guarded cleanup. OPS-127
  remains `Ready for QA`; rollback is one squash revert.

## Historical workflow checkpoint (OPS-128; Windows Flutter Pub cache lock)

- OPS-128 started from exact `origin/staging@00927eedb793d7c2b2c895a72b3b6fe1a7f4b205`
  through the guarded lifecycle. The observed Windows gap was that an unset
  `PUB_CACHE` made the repository lock use `%USERPROFILE%/.pub-cache` while
  Flutter materialized packages under `%LOCALAPPDATA%/Pub/Cache`; parallel
  worktrees therefore were not serialized against the actual shared cache.
- The slice added a platform-injectable resolver, pins the resolved absolute
  `PUB_CACHE` for hydration and gated commands, fingerprints sanitized cache
  identity, bumps the readiness schema, and records cache/lock identity without
  exposing absolute paths. No product/runtime/API/permission/dependency-version
  behavior changed.
- Proof passed: real Flutter preflight (`schemaVersion=8`,
  `dependencyCache.source=LOCALAPPDATA`), gated `flutter analyze --no-pub`
  with no issues, toolchain tests `55/55`, lifecycle tests `16/16`,
  verification/entrypoint tests `25/25`, cross-process Pub lease test,
  boundary scan (`61 files`), and exact `verify-task --base origin/staging`
  with profile `harness`, 4 paths and `stale=false`.
- PR #245 squash-merged at
  `8b1aed00af76796bafe74d3ecdf268a7fadf9330`; staging deploy
  `31884524898` passed all client/backend/health gates. Linear OPS-128 is
  `Ready for QA`. Guarded `finish --allow-ignored --execute` removed the task
  worktree/local/remote branch; only canonical staging remains.
- Residual risk is limited to independent clones/manual IDE launches that do
  not enter the lifecycle; those must use `toolchain-doctor` or the shared
  runner before Flutter commands.

## Workflow checkpoint (OPS-129; master-plan reconciliation after OPS-128)

- This docs-only slice is branch/worktree
  `codex/ops-129-reconcile-ops128-cache-lock` /
  `../opshub-ops-129-reconcile-ops128-cache-lock`, created by the guarded
  lifecycle start gate from exact
  `origin/staging@8b1aed00af76796bafe74d3ecdf268a7fadf9330`. Canonical staging
  was clean and remains protected.
- It reconciles this sole active plan's current checkpoint and historical
  OPS-127/OPS-128 evidence. It does not modify runtime code, dependencies,
  archive evidence or Linear production lifecycle.
- Required proof is `git diff --check`, internal-link/plan disposition checks,
  exact `verify-task --base origin/staging` with `stale=false`, PR/CI, staging
  deploy and guarded lifecycle cleanup. Rollback is one docs-only squash
  revert.

## Workflow checkpoint (OPS-130; automate OPS-72 live shadow evidence assembly)

- This bounded tooling slice is branch/worktree
  `codex/ops-130-automate-ops72-live-shadow-evidence` /
  `../opshub-ops-130-automate-ops72-live-shadow-evidence`, created by the
  guarded lifecycle start gate from exact
  `origin/staging@5c457e6ec044894b4603fa2f4ecea6a928859c2c`. Canonical staging
  remained clean and protected.
- The PR adds a sanitized per-run manifest to the observational shadow
  workflow and a fail-closed collector that assembles exactly five same-cohort
  reports, re-hashes each raw artifact, verifies PR/run/SHA metadata and reuses
  the live-evidence validator. It does not promote profiles or change blocking
  checks, runtime behavior, dependency versions or production policy.
- Current OPS-72 evidence remains `revise`: the existing live cohort is 15.05%
  faster than baseline and has zero retries in both cohorts, so the 25% timing
  and 30% rerun targets are not yet accepted. The collector must preserve this
  disposition when the next five artifacts are assembled.
- Required proof is collector/validator tests, workflow syntax/profile scan,
  `git diff --check`, exact `verify-task --base origin/staging` with
  `stale=false`, PR checks, staging deploy and guarded lifecycle cleanup.
  Rollback is one tooling/docs squash revert.

## Workflow checkpoint (OPS-131; recurring dependency bootstrap hardening)

- This bounded tooling slice is branch/worktree
  `codex/ops-131-eliminate-recurring-dependency-bootstrap` /
  `../opshub-ops-131-eliminate-recurring-dependency-bootstrap`, created by the
  guarded lifecycle start gate from exact
  `origin/staging@837df86c2a781b256c72fbe0eb6bdb37cbae26e0`. The canonical
  staging worktree remained clean and the fresh worktree hydrated both NestJS
  and Flutter profiles before edits.
- The slice makes the shared Flutter CI action run an explicit repository
  preflight after SDK/Pub cache restore; adds a command-tee helper that keeps
  stdout/stderr live while retaining a bounded diagnostic tail; and permits one
  repair retry for a declared Flutter package/materialization path or Nest
  `node_modules`/Prisma path even when the initial readiness receipt was
  healthy. Source/product failures remain non-retryable and stale fingerprints
  still stop before a second command.
- Updated README and scripts runbook guidance makes the fresh/resume/IDE
  boundary explicit. No product dependency version, runtime/API/UI/permission,
  database or archive behavior changes are in scope.
- Exact verification from this worktree against `origin/staging` passed with
  `status=passed`, `code=0`, `stale=false`, selected profiles
  `harness,docs,verification-runner,release,flutter`, and 9 affected paths.
  The focused toolchain/boundary suites passed 85/85, lifecycle tests passed
  16/16, and the wrapped Flutter analyze completed with no issues. The
  command-tee syntax check, migration EOL scan, boundary scan, `git diff
  --check`, and real Flutter analyze are included in that proof. PR/CI,
  staging deploy `31894609071` and guarded finish cleanup also passed on the
  exact merged SHA. Linear OPS-131 is `Ready for QA`; production deployment
  remains required. Rollback is one OPS-131 squash revert; temporary command
  logs and dependency caches remain ignored.

## Workflow checkpoint (OPS-73; retained-owner review)

- This bounded Phase 8 evidence slice is branch/worktree
  `codex/ops-73-retained-owner-review` /
  `../opshub-ops-73-retained-owner-review`, created by the guarded lifecycle
  start gate from exact `origin/staging@e338e51bc212c050c9f70b95f0aca91d286b705d`.
  The canonical staging worktree remained clean and the worktree hydrated both
  toolchain profiles before edits.
- It adds the sanitized
  `docs/migrations/ops-73-retained-owner-review.json` ledger and its
  fail-closed validator/test. Four candidate groups are retained: n8n legacy
  exports, active VietQR/n8n compatibility routes, Flutter platform
  directories, and release/shadow allowlists. Each reviewed file has a
  current SHA-256/byte count, each candidate has owner references and an exact
  rollback method, and no workflow payload is copied into Git.
- The evidence explicitly records `no-safe-deletion-candidate`; it authorizes
  no deletion of n8n, legacy routes, platform assets or release controls. Any
  later source/hash drift fails validation and requires a refreshed review.
- Required proof is retained-owner validator/tests, exact `verify-task --base
  origin/staging` with `stale=false`, PR checks, staging deploy and guarded
  lifecycle cleanup. Rollback is one OPS-73 squash revert.

## Workflow checkpoint (OPS-132; OPS-72 live-cohort reconciliation)

- This docs/evidence slice is branch/worktree
  `codex/ops-132-reconcile-ops72-live-cohort` /
  `../opshub-ops-132-reconcile-ops72-live-cohort`, created by the guarded
  lifecycle start gate from exact
  `origin/staging@dd7d2ffbb1d04c17d8058f2543b643669fb5fbd5`. The canonical
  staging worktree remained clean and both toolchain profiles were hydrated.
- `docs/migrations/ops-72-live-shadow-progress-v2.json` records the three
  valid same-cohort manifests from PRs #247, #248 and #249. Each report has
  exact run/PR/base/head metadata, a SHA-256 report digest, `passed` shadow
  classification, zero unmatched paths and zero reruns. Raw artifacts remain
  ignored and no payload is committed.
- The progress aggregate is explicitly
  `pending-two-more-observations` with `promotionDecision=do-not-promote`;
  no timing or rerun percentage is calculated. The collector must still fail
  closed until five same-cohort manifests exist.
- Required proof is docs/progress validation, exact `verify-task --base
  origin/staging` with `stale=false`, PR checks, staging deploy and guarded
  lifecycle cleanup. Rollback is one OPS-132 squash revert.

## Workflow checkpoint (OPS-134; generated-root writeability and cold bootstrap)

- This bounded tooling slice is branch/worktree
  `codex/ops-134-generated-root-writeability-cold-bootstrap` /
  `../opshub-ops-134-generated-root-writeability`, created by the guarded
  lifecycle start gate from exact
  `origin/staging@8f3539dcc211d656924d4dc6f86fa63fffa6cfc0`. Canonical staging
  was clean and the fresh task worktree hydrated both toolchain profiles before
  edits.
- The observed failure was environmental, not a missing package graph: the
  canonical Windows `lib` and `lib/l10n` directories carried a ReadOnly
  attribute, so Flutter's synthetic localization generation rejected the
  `arb-dir` even though package-config and plugin roots were complete.
- The slice adds a narrow generated-root writeability contract to readiness and
  fingerprints. It clears only a Windows directory-level ReadOnly attribute on
  allowlisted repository roots, rejects symlinks/ACL denial, and performs a real
  write probe before dependency hydration. Dry-run remains non-mutating.
- Focused proof covers ReadOnly normalization, ACL fail-closed behavior, dry-run
  safety and missing Nest `node_modules` handling. PR #251, the full toolchain
  suite, cold/partial materialization canaries, exact runner, staging deploy
  `31901021962` and guarded cleanup all passed. Linear OPS-134 is `Ready for
  QA`; production remains the completion gate. Rollback is one OPS-134 squash
  revert.

## Workflow checkpoint (OPS-135; cold-worktree dependency canary)

- This bounded canary slice is branch/worktree
  `codex/ops-135-cold-worktree-dependency-canary` /
  `../opshub-ops-135-cold-worktree-dependency-canary`, created by the guarded
  lifecycle start gate from exact
  `origin/staging@46c8aa90d932f8cfadb25eddae80305180ca9d95`. Canonical staging
  was clean; the task worktree hydrated profile `all` before edits.
- The slice adds a path-filtered Windows workflow that restores the pinned
  Flutter SDK/Pub cache without repository hydration, asserts a cold checkout,
  seeds an allowlisted `lib/l10n` ReadOnly directory, and runs the shared
  `toolchain-doctor --profile all --force` before wrapped Flutter analyze and
  Nest build.
- `setup-flutter` keeps materialization enabled by default; only the canary
  opts out so cache presence cannot masquerade as worktree readiness. The
  canary verifier checks both profile graphs, Prisma output, Flutter package and
  plugin materialization, generated-root writeability and cleared ReadOnly state.
- Local cold proof passed from absent `backend-nest/node_modules`/`.dart_tool`:
  doctor prepared both profiles, normalized only `lib/l10n`, the verifier passed,
  Flutter analyze passed and Nest build passed. Toolchain suite passed `94/94`,
  boundary scan passed (`files=66`), retained-owner review passed, and exact
  `verify-task --base origin/staging --profile harness` passed with
  `stale=false` before this plan edit.
- PR #252 squash-merged into `staging` at
  `98d7316648a60e415e154b114c6bb5ec87f52286`; Windows cold canary run
  `31903049090`, exact staging deploy `31903246094`, and guarded lifecycle
  `finish --execute` all passed. Linear OPS-135 is `Ready for QA`; production
  completion is intentionally not inferred. Rollback is one OPS-135 squash
  revert; no runtime/API/UI/permission behavior or dependency versions
  changed.

## Workflow checkpoint (OPS-136; reconciliation after OPS-135)

- This docs-only slice is branch/worktree
  `codex/ops-136-reconcile-dependency-bootstrap-checkpoint` /
  `../opshub-ops-136-dependency-bootstrap-checkpoint`, created by the guarded
  lifecycle start gate from exact live
  `origin/staging@98d7316648a60e415e154b114c6bb5ec87f52286`. Canonical staging
  was clean and the fresh task worktree hydrated Nest/Prisma and Flutter
  profiles independently before edits.
- The durable dependency contract is now explicit: every task worktree starts
  with its own readiness hydration; every dependency-owning command proves the
  current graph, fingerprint and generated-root writeability immediately before
  execution; cache restore is acceleration only and never readiness proof.
- A cold checkout with no `backend-nest/node_modules` or `.dart_tool` must pass
  the shared doctor before the first gated build. A missing, stale, unwritable,
  or partially materialized graph fails closed as an environment failure before
  a product/test command can produce misleading noise. The path-filtered Windows
  canary remains the regression guard while OPS-72 collects its required live
  same-cohort observations.
- This slice changes plan/authority documentation only. Required proof is
  `git diff --check`, exact `verify-task --base origin/staging` with
  `stale=false`, PR checks, staging deploy and guarded lifecycle cleanup.
  Rollback is one OPS-136 squash revert.

## Workflow checkpoint (OPS-137; Phase 8 evidence determinism and checklist reconciliation)

- This bounded Phase 8 slice is branch/worktree
  `codex/ops-137-reconcile-master-plan-checklist-after-ops-136` /
  `../opshub-ops-137-master-plan-checklist`, created by the guarded lifecycle
  start gate from exact live
  `origin/staging@6814d4ba29d7dbd854590daea3c890f15174d3c7`. Canonical staging
  was clean and the task worktree hydrated Nest/Prisma and Flutter profiles
  independently before edits.
- The inventory verifier now treats only a path segment equal to `..` as
  traversal; generated names such as `lifecycle-runtime-2.8.7..jar` no longer
  create a false failure. The refreshed inventory and retained-owner review are
  tied to the exact base SHA, pass their validators, and retain all candidates
  because no independent deletion authority exists.
- The five valid post-OPS-130 shadow observations are now represented in
  `docs/migrations/ops-72-live-shadow-progress-v2.json` (#247–#251). The
  comparable shadow median is `6976ms` versus `7647ms` (`8.77%` reduction),
  rerun reduction remains unmeasurable because both cohorts have zero retries,
  and the decision remains `revise`/`do-not-promote`.
- This slice also reconciles the OPS-130/134/135 checklist and replaces the
  stale OPS-132 current-checkpoint wording. Phase 8 deletion, remaining runtime
  proof and Phase 10 production consolidation stay open. Rollback is one OPS-137
  squash revert.

## Workflow checkpoint (OPS-139; retained-owner evidence normalization)

- This evidence-only slice is branch/worktree
  `codex/ops-139-retained-owner-hashes` /
  `../opshub-ops-139-retained-owner-hashes`, created by the guarded lifecycle
  start gate from exact live
  `origin/staging@c16638a9082be5519fa82bb58c25077d9e8b7d90`.
- The clean-checkout failure was caused by the manifest hashing raw Windows
  CRLF checkout bytes while the Git-normalized blobs are LF. Eight reviewed
  file entries had this representation drift (four n8n reference exports,
  three VietQR authority files and the staging README); no payload content or
  deletion decision changed.
- The validator now compares each current file's Git-normalized blob with its
  recorded source revision and hashes the normalized bytes. The manifest stores
  normalized SHA-256/byte values, and `.gitattributes` pins n8n JSON to LF so
  future clean worktrees converge. The source inventory remains current-file
  evidence and `no-safe-deletion-candidate` is unchanged.
- OPS-138 organization-tree/assignment extraction resumed after OPS-139's
  retained-owner evidence passed. PR #264 restored the extracted collaborator
  on staging at `db427f6d`, deploy `31923613626` passed, and Linear is now
  `Ready for QA`; production completion is intentionally not inferred.
- Intake checkpoint hash: `a80312005c77b3e35580ae755fbe126622d094adfd1ea0053712d35fce6c2bcd`
  (two identical captures). Rollback is one OPS-139 squash revert. Phase 8
  deletion, remaining runtime proof, OPS-72 promotion and Phase 10 production
  consolidation remain open.

Historical Phase 0-1 artifacts, the generic verification foundation/canaries,
the disposable upstream updater lifecycle gate, and the shared Flutter test
environment remain implemented and verified. Save-file picker success/error
characterization is explicit across three export contexts. Archive copies are
local-only and retained; the canonical source remains read-only evidence.
OPS-65 PR #175, OPS-68 PR #176, and OPS-69 PRs #177/#178 are merged into
`staging`; each remains subject to its documented QA/production lifecycle
gates. OPS-131 is now merged/deployed at `e338e51b` and tracked as `Ready for
QA` after exact deploy `31894609071` and guarded cleanup. OPS-73's retained-owner
review is merged/deployed at `dd7d2ffb` and tracked as `Ready for QA` after
exact deploy `31896414830` and guarded cleanup. OPS-73's prior dependency
batches remain `Ready for QA`; OPS-137 is the last merged checkpoint at
`c16638a9`, OPS-139 is the retained-owner evidence normalization slice, and
OPS-141 is squash-merged through PR #260 at
`31149394b5bcf62028be331e03f3d36b1d2d1dd4`, staging-deployed by
`31917897049`, and tracked `Ready for QA` after exact proof and guarded
cleanup. OPS-143 is the historical master-plan reconciliation slice, created
from exact `origin/staging@02045ba7c5c772e734040b1b6593faff98526293` after
OPS-138, OPS-70 and OPS-71. OPS-145 is the latest runtime extraction slice,
merged by PR #269 at `c46cf5d9` and staging-deployed by `31931982872`; it is
tracked `Ready for QA` after guarded cleanup. OPS-146 is the current
reconciliation slice. OPS-138 is merged/deployed and tracked as `Ready for QA`;
OPS-70 and OPS-71 are merged/deployed and tracked `Ready for Release`. OPS-113
is also staged and tracked as `Ready for
QA` after exact deploy `31862881662` and guarded cleanup. OPS-122 and OPS-123's
reconciliations are historical; OPS-124 is merged/deployed and tracked as
`Ready for QA`, OPS-127 and OPS-128 are historical dependency-boundary
checkpoints, OPS-129 is a historical master-plan reconciliation, and OPS-130
is the completed live-shadow evidence assembly checkpoint. OPS-131 and OPS-73
are completed staging checkpoints. OPS-72 now has five valid post-OPS-130
manifests (#247–#251), but remains `revise`/`do-not-promote` because the timing
target is only `8.77%` and rerun reduction is unmeasurable. Phase 8 deletion
work, retained-owner evidence normalization, remaining runtime proof and OPS-75
final consolidation remain downstream gates.
Move this plan to
`docs/plans/completed/` only after the full initiative's final validation and
production lifecycle are complete.

The baseline inventory counted 32 active plan files. The current active tree
has 16 files (15 current plans plus its README); all moved paths retain a
one-to-one `sourcePath`, disposition and canonical target in the OPS-71 ledger.
OPS-44 retains a release-pending handoff, while OPS-53 retains one active
consolidation summary; neither Linear issue was closed by this cleanup.
The master plan must be moved to `docs/plans/completed/` only after all runtime,
toolchain, docs and production-release gates in the initiative pass. Until then
the current checkpoint above is the sole active execution authority.

## Workflow checkpoint (OPS-141; dependency-root readiness hardening)

- This bounded tooling slice is branch/worktree
  `codex/ops-141-harden-dependency-root-readiness` /
  `../opshub-ops-141-root-readiness`, created by the guarded lifecycle start
  gate from exact live
  `origin/staging@ca856d83d245e50e45418c28892326e892f195c7`. Canonical staging
  was clean and unchanged; the fresh task worktree hydrated NestJS/Prisma and
  Flutter independently before mutation.
- The observed gap is readiness under-reporting: the canonical worktree had
  complete Nest/Flutter graphs, but `.dart_tool`, `backend-nest/node_modules`
  and several generated roots carried Windows `ReadOnly` attributes. The
  existing contract checked the graph and generated peers but not both ignored
  dependency roots directly, so a cached receipt could still precede a first
  build failure.
- The slice adds those two ignored dependency roots to the same narrow
  writeability/repair allowlist and fingerprint used by preflight. It keeps
  dry-run read-only, fails closed for ACL/symlink/non-physical paths, and adds
  regression coverage for ReadOnly normalization, cold missing roots and
  dry-run safety. No lockfile, dependency version, runtime/API/UI behavior or
  Docker boundary changes are in scope.
- Final proof: focused writeability/prepare tests pass; full toolchain suite
  passes `102/102`; wrapped Flutter analyze and Nest build pass; the cold
  canary `31917740541` hydrated 941 Nest packages and 174 Flutter packages
  from absent roots before both commands passed; exact `verify-task` returned
  `stale=false`; staging deploy `31917897049` passed for merge SHA
  `31149394b5bcf62028be331e03f3d36b1d2d1dd4`; and guarded finish removed the
  task worktree/local branch. Rollback is one OPS-141 squash revert.

## Workflow checkpoint (OPS-142; reconcile after OPS-141)

- This docs-only slice is branch/worktree
  `codex/ops-142-reconcile-master-plan-after-ops-141` /
  `../opshub-ops-142-master-plan`, created by the guarded lifecycle start gate
  from exact live
  `origin/staging@31149394b5bcf62028be331e03f3d36b1d2d1dd4`. It updates only
  this master plan after OPS-141's merge/deploy proof; no runtime, dependency
  manifest, archive or upstream Harness files are in scope.
- The durable dependency direction is now explicit: every new task worktree
  hydrates both toolchain profiles by default; every dependency-consuming
  command rechecks readiness through the shared boundary; cold CI canary
  verifies both roots from absence; and the readiness fingerprint includes
  ignored dependency roots so stale receipts cannot bypass a first build.
- Next gate: OPS-72 remains `revise`/`do-not-promote` because its measured
  cohort is below the timing target and rerun reduction is not measurable.
  Phase 8 deletion, remaining Phase 9 runtime waves and Phase 10 production
  consolidation remain open; no status is promoted based on staging alone.

## Workflow checkpoint (OPS-70; retire archive writer)

- This bounded Harness cleanup slice is branch/worktree
  `codex/ops-70-retire-archive-exporter` /
  `../opshub-ops-70-retire-archive-exporter`, created by the guarded lifecycle
  start gate from exact live `origin/staging@db427f6d44d2dde5c219a982fc1d835e9378e536`.
- The two verified local archive copies and the sanitized 199-record
  disposition ledger are immutable migration evidence. The repository no
  longer needs a command that creates new SQLite archive copies, so the
  archive writer and its writer-specific test are retired. The read-only
  disposition/authority validators remain available.
- No source database, raw archive, runtime/API/UI behavior, dependency
  manifest or upstream Harness payload is changed. The dependency-hardening
  follow-up remains intentionally paused; existing toolchain gates stay in
  force.
- Required proof before publication: retirement verifier, migration EOL and
  remaining migration tests, docs contract checks, exact `verify-task` with
  `stale=false`, PR/CI, staging deploy and guarded lifecycle cleanup. Rollback
  is one OPS-70 squash revert.

## Workflow checkpoint (OPS-71; current-plan authority normalization)

- This docs-only Phase 6 slice is branch/worktree
  `codex/ops-71-normalize-active-plan-authority` /
  `../opshub-ops-71-normalize-active-plan-authority`, created by the guarded
  lifecycle start gate from exact live
  `origin/staging@5685b5e6b5714924a716a5b4dd77f0a4b9925514`.
- It aligns the active index with the current OPS-64 checkpoint, corrects the
  OPS-34 classification to active/blocked on Figma authority, adds concise
  owner/next-action/release-gap/proof blocks to OPS-45 and OPS-62, and makes
  the two OPS-39 plans' authority boundary explicit. Production-pending work
  remains open; no plan is moved to completed by this slice.
- No runtime, API, UI, dependency, archive, upstream Harness or Linear status
  behavior changes are in scope. Rollback is one OPS-71 squash revert.

## Workflow checkpoint (OPS-143; reconcile after OPS-138/OPS-71)

- This docs-only slice is branch/worktree
  `codex/ops-143-reconcile-master-plan-after-ops-138-ops-71` /
  `../opshub-ops-143-master-plan`, created by the guarded lifecycle start gate
  from exact live
  `origin/staging@02045ba7c5c772e734040b1b6593faff98526293`. Canonical staging
  was clean and unchanged; the task worktree hydrated only the Nest profile
  because this slice has no dependency-owning runtime command and Flutter
  hydration is explicitly deferred.
- The current authority is now explicit: OPS-138's collaborator extraction is
  present on staging after PR #264/merge `db427f6d`, OPS-70 archive-writer
  retirement is present after `5685b5e6`, and OPS-71 plan normalization is
  present after `02045ba7`. OPS-72 remains observational with a
  `revise`/`do-not-promote` decision; Phase 8 deletion, remaining runtime QA,
  and Phase 10 production evidence remain open.
- Local upstream Harness proof is recorded separately in Linear/OPS-64:
  exact `harness-v0.1.8` status/doctor are healthy and the installer wrapper
  update dry-run preserves managed files. A bare no-candidate
  `harness update --dry-run` still returns the upstream `git merge-file failed`
  gap without mutation; it is not counted as update proof. The legacy binary,
  `harness.db`, WAL/SHM and raw archive remain ignored read-only local evidence.
- Dependency hardening is a deferred residual-risk follow-up. Missing or stale
  Flutter/Nest dependencies remain an environment failure/unverified proof,
  never a reason to suppress an affected profile or retry a product failure.
  The exact base-aware runner was attempted for this docs change, but its
  auto-selected Harness profile hung in `flutter.bat --version --machine` while
  running `tests/toolchain`; the run was stopped without a result file or
  tracked mutation. The Windows-native Git Bash docs contract passed, while
  the WSL `bash` invocation produced a false `rg` permission failure. A
  separate workflow slice must add bounded toolchain command timeouts and keep
  this environment failure visible. Rollback is one OPS-143 squash revert.

## Workflow checkpoint (OPS-144; bound toolchain version probes)

- This bounded Harness/tooling slice is branch/worktree
  `codex/ops-144-bound-toolchain-version-probes` /
  `../opshub-ops-144-toolchain-timeout`, created from exact live
  `origin/staging@8f9eaef9459709b585928f8879b9f255b76eb70f`. Changed paths are
  limited to `scripts/prepare-task-toolchain.mjs` and its toolchain tests.
- Version probes now have a 15-second child-process timeout, return a sanitized
  `unavailable:timeout` sentinel, and cache by command context. The timeout
  policy is included in toolchain fingerprint metadata so a policy change
  invalidates stale readiness evidence. This prevents a missing/stale Flutter
  or Nest installation from hanging Harness/verify-task indefinitely.
- Focused and exact base-aware Harness validation passed: toolchain tests
  `34/34`, exact runner tests `104/104`, migration EOL, toolchain boundary and
  retained-owner checks all passed with `stale=false`. The runner output still
  contains expected fixture diagnostics for missing modules/Flutter packages;
  those remain visible environment evidence and are not treated as product
  success. No runtime/API/UI/dependency-version/archive behavior changed.
- Dependency hydration remains explicitly deferred for the next cleanup slices;
  affected runtime profiles must still fail closed until their dependencies are
  available. Rollback is one OPS-144 squash revert.

## Workflow checkpoint (OPS-145; MAP export and response mapping)

- This bounded Phase 9E slice is branch/worktree
  `codex/ops-145-map-export-response-mapping` /
  `../opshub-ops-145-map-export-response`, created from exact live
  `origin/staging@4074aa6977baf556c8bc24e9308ef896c8166519`. The isolated task
  start hydrated both Nest/Prisma and Flutter profiles from task-local roots.
- PR #269 squash-merged the slice at
  `c46cf5d9c5e64e8e7e855e8c8fd5290941e9dafe`; staging deploy run `31931982872`
  passed Android, Windows, web, backend, direct-origin route and health/version
  checks. Guarded `finish --execute --allow-ignored` passed; canonical staging
  is clean and the task worktree/local branch were removed. Linear OPS-145 is
  `Ready for QA`; production deployment remains open.
- `MapVietinService` remains the public facade. Stored statement response DTO
  mapping and XLSX row/header mapping now have one injected collaborator;
  service callbacks retain the existing canonical identifiers, income/order
  policy, Vietnamese copy, date/amount formatting and permission flags. Routes,
  DTOs, feature guards, API/data contracts and affected consumers are unchanged.
- Characterization and affected proof: MAP service suite `157/157`, Nest
  cross-stack MAP/VietQR/notification/payment suites `131/131`, and Flutter
  Payment Monitor/Bank Statement/VietQR suites `111/111`. Nest build passed;
  exact base-aware runner passed `104/104` with profiles `harness,docs,nestjs`
  and `stale=false`.
- Dependency hydration is visible and fail-closed through the shared boundary;
  no dependency version or lockfile change is in scope. Rollback is one OPS-145
  squash revert.

## Workflow checkpoint (OPS-146; post-OPS-145 plan reconciliation)

- This docs-only slice is branch/worktree
  `codex/ops-146-master-plan-checkpoint-after-ops-145` /
  `../opshub-ops-146-master-plan-checkpoint`, created from exact live
  `origin/staging@c46cf5d9c5e64e8e7e855e8c8fd5290941e9dafe`. No runtime,
  dependency, archive or product authority is in scope.
- The slice reconciles the active-plan index, this master-plan checkpoint and
  the OPS-64 `nextAction` in the OPS-71 disposition ledger. It preserves the
  production-not-done rule, Phase 6/8/9/10 gates and dependency fail-closed
  policy. Rollback is one OPS-146 squash revert.

## Workflow checkpoint (OPS-147; close Phase 8 artifact cleanup)

- This docs-only slice is branch/worktree
  `codex/ops-147-phase-8-close-artifact-cleanup` /
  `../opshub-ops-147-phase-8-cleanup`, created from exact live
  `origin/staging@4f6e09700af200e8d4dcbbaebd9395ce92c52b40`. The task worktree
  was clean before edits; only the Nest profile was prepared because no
  dependency-consuming command is in scope.
- It closes the Phase 8 evidence decision: inventory and retained-owner
  validators report no safe deletion candidate, all reviewed dependency/artifact
  batches have explicit proof, and the authorized deletion-batch count remains
  zero. No retained path, lockfile, dependency version, runtime behavior,
  Harness archive or raw local evidence is changed.
- Missing Flutter/Nest dependencies remain an environment failure for any
  later dependency-consuming proof; this docs closure neither suppresses that
  gate nor retries product failures to green. Phase 9 runtime waves and Phase
  10 production evidence remain open. Rollback is one OPS-147 squash revert.

## Workflow checkpoint (OPS-148; Home Summary comparison runtime)

- This Phase 9C Nest-only slice used branch/worktree
  `codex/ops-148-home-summary-comparison-runtime` /
  `../opshub-ops-148-home-summary-comparison-runtime`, created from exact live
  `origin/staging@154a34c10b5c6ff2f97b8473a6dc281fdab05ae5`. PR #272 squash-
  merged at `324c87d264df3b96ee6409d939aaa5dcf0a97091`; staging deploy
  `31936440130` passed Windows, Android, web, backend, direct-origin routes
  and public health/version checks; guarded finish cleanup passed.
- `HomeSummaryService` remains the stable facade. Comparison-period
  orchestration is owned by `HomeSummaryComparisonRuntime`; characterization
  remained 6 suites / 116 tests before and after, Nest build and exact runner
  passed with `stale=false`.
- The local Flutter Home affected proof could not run because the task
  worktree lacked `.dart_tool/package_config.json` and plugin metadata. This
  is environment failure/unverified evidence, not a suppressed profile or a
  product pass. Authenticated QA and production deployment remain open.

## Workflow checkpoint (OPS-149; Home Summary sales-progress runtime)

- This Phase 9C Nest-only slice is branch/worktree
  `codex/ops-149-home-summary-sales-progress` /
  `../opshub-ops-149-home-summary-sales-progress`, created from exact live
  `origin/staging@324c87d264df3b96ee6409d939aaa5dcf0a97091`. Flutter hydration
  is intentionally deferred for this backend-only slice; any Flutter affected
  proof remains fail-closed and explicitly unverified when its dependency root
  is unavailable.
- The slice extracts sales-progress range composition, report filters, actual
  aggregation, target allocation, active-SA counting and unavailable-state
  shaping into `HomeSummarySalesProgressRuntime`. Private facade wrappers keep
  `HomeSummaryService` compatibility while public API/DTO/DI/permission,
  Vietnamese copy, logging and product behavior remain unchanged.
- Focused Home Summary proof is `8 suites / 129 tests` with 6 skips, including
  a new 4-case runtime characterization matrix; Nest build passed. The
  publication gate is exact `verify-task --base origin/staging` with
  `stale=false`, followed by PR/staging deploy and guarded lifecycle cleanup.
- Dependency decision: continue independent Harness/cleanup slices, but never
  convert missing Flutter dependencies into a pass or retry product failures
  to green. Rollback is one OPS-149 squash revert.

## Workflow checkpoint (OPS-150; Home Summary main-KPI runtime)

- This Phase 9C Nest-only slice is branch/worktree
  `codex/ops-150-home-summary-main-kpi` /
  `../opshub-ops-150-home-summary-main-kpi`, created from exact live
  `origin/staging@cef2b17071cbe11537e349a656d3baac72d008e9`. Flutter hydration
  is intentionally deferred for this backend-only slice; any Flutter affected
  proof remains fail-closed and explicitly unverified while its dependency root
  is unavailable.
- The slice extracts main-KPI row loading, canonical-revenue lookup wiring,
  Sales Reports aggregation mapping and the empty KPI summary into
  `HomeSummaryMainKpiRuntime`. `HomeSummaryService` keeps the stable facade;
  `salesReportMainKpiWhere` remains service-owned because installment-details
  still uses it. Public API/DTO/DI/permission, Vietnamese copy, logging and
  product behavior remain unchanged.
- Focused proof passed: 2 suites / 62 tests and full Nest proof passed with
  `113 suites / 1246 passed / 6 skipped`; Nest build, Prettier check and
  `git diff --check` also passed. The final exact `verify-task --base
  origin/staging` selected `harness,docs,nestjs` over 5 affected paths with
  `stale=false`. The publication gate remains PR/staging deploy followed by
  guarded lifecycle cleanup; rollback is one OPS-150 squash revert.
