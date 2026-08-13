# Execution Plan: OPS-64 Upstream Harness, Workflow And OpsHub Cleanup

Date: 2026-08-13

## Status

Active — Phase 7B live shadow evidence and Phase 8 artifact/dependency/toolchain
cleanup are merged in staging. Five live shadow observations pass; one
historical contract gap (#182) was explicitly captured and fixed in the OPS-72
follow-up. OPS-74 runtime waves are in progress: OPS-81, OPS-82 and OPS-83 are
merged and staging-deployed; OPS-84 query/list state and OPS-85
realtime/background-lease are merged and staging-deployed; OPS-87 audio
runtime and OPS-88 Payment Monitor actions are merged and staging-deployed;
OPS-90 scope/access and OPS-91 projection runtime are the current Home Summary
runtime slices; OPS-89 cache runtime is merged and staging-deployed. Comparable timing baseline, remaining
runtime waves and production release remain open.

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
- Current slice: `OPS-91` Home Summary projection runtime extraction, on a fresh
  lifecycle worktree created from live `origin/staging@1891a7a961c738b36bbc307c00ff92ce2c651123`.
  The focused NestJS characterization matrix passed `110/110` before and after
  extraction; `npm run build` passed. Projection feature gating, freshness,
  aggregate metrics and daily-series loading are owned by
  `home-summary-projection.runtime.ts`; the stable `HomeSummaryService` facade
  retains orchestration, comparison/CSV overlay, sales aggregation, legacy
  sync and private compatibility wrappers. Affected Flutter Home proof passed
  `60/60` after worktree dependency preflight.
  OPS-89 cache state, in-flight dedupe, refresh-ahead, daily-series extension,
  support caches, scope-option caching and projection invalidation remain in
  `home-summary-cache.runtime.ts`.
  OPS-72, OPS-73, OPS-74 header, OPS-81 KPI/summary, OPS-82 detail-renderer
  and OPS-83 analytics/progress slices are merged at the current checkpoint.
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
- Current OPS-73 Go/deployment branch: `codex/ops-73-go-deployment-artifact-audit`.
- Current OPS-73 Go/deployment base/HEAD checkpoint:
  `ccff928f703c3a5dc0969798e6d02905d7c164ce`.
- `origin/staging` matched `ccff928f703c3a5dc0969798e6d02905d7c164ce` when
  the current lifecycle start gate passed.
- Canonical staging worktree was clean. Existing worktrees were preserved and
  were not reset, removed, or rewritten.
- Current implementation worktree: `../opshub-ops-91`.
- OPS-91 branch: `codex/ops-91-home-summary-projection-runtime`.
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
- Current OPS-69 implementation worktree:
  `../opshub-ops-69-current-authority-promotion`.
- Current OPS-69 branch:
  `codex/ops-69-current-authority-promotion-and-linear-follow-ups`.
- Current OPS-69 base SHA and live `origin/staging` checkpoint:
  `ee74d0efb9b16cda0725d8940b0a1e544d0ba006`.
- OPS-69 was created from that exact lifecycle checkpoint; it is not yet
  published or merged.
- OPS-70 implementation worktree: `../opshub-ops-70-retire-protocol-v1`.
- OPS-70 branch: `codex/ops-70-retire-protocol-v1-and-harness-producers`.
- OPS-70 base SHA: `e83c24bb7ae6cd83af379ec003818ad74b6fcbe0`; canonical staging
  and `origin/staging` matched it at task start.
- OPS-70 squash merge: `ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1`; lifecycle
  `finish --execute` passed.
- OPS-71 base SHA: `ff8b9e9a1765d572a7ed5b72772f5c2b5ced4ea1`; canonical staging,
  `origin/staging` and the OPS-71 task worktree matched before cleanup.

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
- [ ] Run Phase 7B CI shadow metrics, Phase 8 artifact cleanup, Phase 9 runtime
  waves and Phase 10 final consolidation.

Phase 8 inventory checkpoint (OPS-73):

- [x] Inventory-only slice: add `docs/migrations/ops-73-artifact-inventory.json`
  with exact branch/HEAD, tracked/ignored paths, dependency manifests, asset
  hashes, runtime hotspots, owner rules and generated-file policy.
- [x] Validate the inventory with `scripts/verify-artifact-inventory.mjs`;
  deletion batches must remain empty until an independent reference/build/
  package/migration/rollback review proves a candidate safe to remove.
- [ ] Preserve `n8n/`, legacy runtime routes, platform assets and release
  allowlist entries until their operational owner and rollback path are proven.

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

Phase 7B live observation checkpoint (OPS-72):

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
- Aggregate target status is `pending-live-timing-baseline`: timing and rerun
  reduction percentages are intentionally null until comparable baseline data
  exists. No profile is promoted to blocking by this evidence alone.

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

## Result

Phase 0-1 artifacts, the generic verification foundation/canaries, the
disposable upstream updater lifecycle gate, and the shared Flutter test
environment are implemented and verified on the task branch. Save-file picker
success/error characterization is now explicit across three export contexts.
Archive copies
are local-only and retained; the canonical source remains untouched. Runtime
code change in this slice is limited to the test-only `AppLogger.flushForTesting`
coordination hook; production logging behavior is unchanged.
The Linear implementation/proof note is recorded on `OPS-65`, and OPS-65 PR
#175 is merged into `staging`; it remains open until production deployment.
OPS-68 is merged into `staging` with its lifecycle finish gate passed. OPS-69
now carries the corrected Phase 3A hash linkage and Phase 3B promotion report;
it is not complete until its exact final SHA is published, reviewed and merged.
Move this plan to
`docs/plans/completed/` only after the full initiative's final validation and
production lifecycle are complete.

The baseline inventory counted 32 active plan files. The current active tree
has 15 files (14 current plans plus its README); all moved paths retain a
one-to-one `sourcePath`, disposition and canonical target in the OPS-71 ledger.
OPS-44 retains a release-pending handoff, while OPS-53 retains one active
consolidation summary; neither Linear issue was closed by this cleanup.
