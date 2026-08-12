# Execution Plan: OPS-64 Upstream Harness, Workflow And OpsHub Cleanup

Date: 2026-08-13

## Status

Active — Phase 2 disposable lifecycle proof, Phase 4 runner/canaries, and
Phase 7A Flutter test-environment proof are verified. Phase 3 promotion,
protocol-v1 retirement, docs/plans cleanup, CI shadow runs, runtime waves and
production release remain open.

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
- Current slice: `OPS-65` (Phase 0 baseline/master plan), Phase 0-1 archive
  tooling, and Phase 2 upstream adoption on the `OPS-64` task branch.
- Branch: `codex/ops-64-harness-cleanup-phase-0-1`.
- Exact base at task start: `6525b6e3805eb666a86066cfe98469d5dba4af53`.
- `origin/staging` matched that SHA when the lifecycle start gate passed.
- Canonical staging worktree was clean. Existing worktrees were preserved and
  were not reset, removed, or rewritten.
- Implementation worktree: `../opshub-ops-64-harness-cleanup-phase-0-1`.

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

- Deleting legacy Harness files or release workflows.
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
- [x] Complete Phase 3A disposition on independent checkpoint
  `codex/ops-68-disposition-ledger` / `0f4e21c6`: exactly 199 records, source
  and archive parity, two protocol-v1 decisions superseded by ADR 0029, 41
  already-authoritative targets, 27 deduplicated Linear follow-ups and 129
  historical-only records. The proof was read back before any status change.
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
- [ ] Publish `OPS-65` and `OPS-68` through the guarded feature-PR flow. Until
  their PRs merge into `staging` and `finish` passes, Phase 5+ mutations are
  blocked by lifecycle policy; no direct push or PR authority is assumed.

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

- Branch/worktree: `codex/ops-68-disposition-ledger`, local commit `0f4e21c6`.
- `python -m unittest discover -s tests/migration -p 'test_*.py' -q`: 8 pass.
- `review-harness-disposition.py --input ...`: PASS, 199 records; ledger SHA
  `918de42d98e02f14e21c0f2802b1c7f5d63bf426e3668fb8e961a94a7a5c9bee`.
- Source archive SHA remained
  `29951f9e16a6c69e4cbd6b8c697f23fa9ca88d513784c00b3dd35353a7ddd955` and
  was unchanged before/after the immutable read. The canonical repository DB
  was not opened or modified.
- The sanitized ledger contains valid UTF-8, zero duplicate entity/id pairs,
  zero missing required targets and no absolute local paths or raw payloads.
- Linear implementation/proof comment was recorded on `OPS-68` and read back;
  the issue remains Backlog because no status transition was authorized.

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
The Linear implementation/proof note is recorded on `OPS-65`, but no status
transition, push, PR or production proof has occurred. The exact final SHA has
passed the full local validation ladder for this slice. Review the exact diff
and run the lifecycle publication gates before opening the next child issue.
Move this plan to
`docs/plans/completed/` only after the full initiative's final validation and
production lifecycle are complete.

The baseline inventory counted 32 active plan files. They are intentionally
not moved or deleted in this slice: Phase 6 must classify each plan against
current Linear/release authority, and the OPS-44/OPS-53 fragments need a
separate docs-only review before any consolidation mutation.
