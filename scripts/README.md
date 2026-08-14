# Scripts

This directory contains repository validation, upstream Harness installation,
and explicitly isolated migration/archive readers.

The default workflow is defined by `AGENTS.md` and `docs/WORKFLOW.md`. Normal
questions and repository changes do not require a database, bootstrap, intake,
story row, matrix query, trace, score, audit, or proposal. OpsHub no longer
builds, installs, tests, or publishes the historical SQLite `harness-cli` or
protocol-v1 producer surface.

## Core Maintenance CLI

The installer places the upstream `harness` binary at
`scripts/bin/harness` on macOS/Linux or `scripts/bin/harness.exe` on Windows.
Its supported interface is:

```text
scripts/bin/harness status [--json]
scripts/bin/harness doctor [--json]
scripts/bin/harness update --dry-run
scripts/bin/harness update
scripts/bin/harness update --continue --dry-run
scripts/bin/harness update --continue
scripts/bin/harness update --abort
```

The pinned payload is `harness-v0.1.8`. The upstream binary owns install,
provenance, three-way updates, checksum/release identity, conflict staging,
continuation, abort, and recovery. It does not own product behavior, task
selection, Linear, application commands, or a database.

`install-harness.sh` and `install-harness.ps1` are thin platform bootstraps.
They verify an immutable candidate and delegate core semantics to it. They do
not discover schemas, initialize SQLite, download `harness-cli`, or write a
control-plane database.

## Generic verification runner

Use `scripts/verify-task.mjs` as the repository-owned changed-path entrypoint:

```text
node scripts/verify-task.mjs
node scripts/verify-task.mjs --base origin/staging --json tmp/verify-task.json
node scripts/verify-task.mjs --base origin/staging --profile verification-runner --dry-run
node scripts/verify-task.mjs --base origin/staging --full
```

Profiles in `scripts/verification-profiles.mjs` declare affected consumers,
prerequisites and structured commands. Unknown paths fail closed; explicit
profiles are additive; fingerprints include Git state, runner/config hashes
and command definitions. Exit codes are `0` pass, `2` contract, `3`
product/test, `4` stale and `5` environment/infrastructure.

CI uses `scripts/verify-task-shadow.mjs` in additive shadow mode. It compares
auto-selected profiles with the full ladder and uploads a sanitized schema-v2
JSON report; the existing blocking release checks remain unchanged. The report
records a cohort id, queue/start/end timestamps, derived queue/execution
durations, retry counts and the first actionable failure when one exists.
Infrastructure failures may retry once only while the fingerprint is unchanged.
Product/test failures are never retried, and any change during a retry is a
stale-proof failure. Legacy schema-v1 reports remain readable by the evidence
validator, but five comparable live observations in one cohort are required
before calculating or promoting optimization percentages.

For the OPS-72 evidence replay, run the collector from the repository root:

```text
node scripts/collect-ops72-shadow-metrics.mjs --output docs/migrations/ops-72-shadow-metrics.json
```

It checks out the five pinned merged-PR heads in temporary sibling worktrees,
records exact parent/head/profile/fingerprint evidence, and removes those
worktrees. The resulting report intentionally keeps `targetStatus` at
`pending-live-shadow-data` until five live PR observations provide comparable
rerun and time-to-actionable-failure measurements.

The five live observations are recorded in
`docs/migrations/ops-72-live-shadow-evidence.json`. Validate the sanitized
ledger with:

```text
node scripts/verify-ops72-live-shadow-evidence.mjs
```

Use `--raw-root <path>` to independently re-hash downloaded CI artifacts at
`<path>/<run-id>/verify-task-shadow.json`; raw artifacts remain ignored and are
never committed. Timing and optimization targets remain pending until a
comparable baseline exists.

## Legacy boundary

Protocol v1, the SQLite control plane, and `harness-cli` are end-of-life. The
current tree has no schemas, adapters, bootstrap/materialization scripts,
compatibility installer profile, protocol contract, or CLI release train.
Historical source remains available through Git history and the last immutable
`harness-cli-v0.1.22` release for consumers that maintain their own archive
workflow. Do not run that binary from this checkout.

The local `harness.db`, WAL/SHM files, downloaded legacy binaries, and raw
archive copies are consumer-owned read-only migration inputs. This repository
does not import, refresh, rewrite, or delete them. Sanitized manifests and
disposition evidence live in `docs/migrations/`.

## Migration readers

The following scripts are retained only to validate the sanitized archive and
disposition evidence. They must not write the canonical DB or turn archived
rows into current task authority:

- `archive-harness-legacy.py`;
- `review-harness-disposition.py`; and
- `promote-harness-authority.py`.

## Pre-merge validation

Run the focused runner for changed paths. Release and repository contract tests
are maintained by the upstream Harness source repository; OpsHub does not
publish a fork or a replacement release workflow.

The OpsHub task lifecycle remains in `scripts/task-lifecycle.mjs`; feature
branches target `staging` and production promotion follows
`docs/runbooks/git-release-playbook.md`.

## Toolchain execution gate

Repository-owned build and test commands should use the structured gate so a
resumed or manually-created worktree repairs dependencies before the command
starts:

```text
node scripts/run-with-toolchain.mjs --profile flutter -- flutter analyze
node scripts/run-with-toolchain.mjs --profile flutter -- flutter test
node scripts/run-with-toolchain.mjs --profile flutter -- flutter build web --release
node scripts/run-with-toolchain.mjs --profile nestjs --cwd backend-nest -- npm run build
node scripts/run-with-toolchain.mjs --profile nestjs --cwd backend-nest -- npm test -- --runInBand
node scripts/run-with-toolchain.mjs --profile nestjs --cwd backend-nest -- npx --no-install prisma migrate deploy
node scripts/run-with-toolchain.mjs --profile all --preflight-only
```

The command after `--` is passed as structured `cwd + executable + argv`; no
shell command string is stored. Flutter `analyze`, `test` and `build` commands
automatically receive `--no-pub` after the shared preflight, preventing an
implicit second Pub-cache writer. Exit codes are `0` pass, `2` contract,
`3` product/test failure and `5` environment/preflight failure. Use `--json`
for a sanitized schema-v1 result containing the readiness result, command
fingerprint and duration.

Nest package lifecycle hooks call the gate in prebuild/pretest/prestart and
related development commands, so direct `npm run build`/`npm test` cannot skip
the readiness check. The hook never runs a second npm script recursively; it
only hydrates/checks the selected profile.

## Fresh task toolchain preflight

Fresh task worktrees intentionally do not carry ignored dependency directories.
The lifecycle prepares both runtime toolchains immediately after creating a
task branch, so the normal command is sufficient:

```text
node scripts/task-lifecycle.mjs start \
  --issue OPS-123 --slug short-description \
  --worktree ..\opshub-ops-123 --execute
```

`--prepare-profile nestjs` uses the dependency-relevant fields from
`backend-nest/package.json` (dependencies, devDependencies, optional/peer
dependencies, overrides, engines and packageManager), `package-lock.json`,
Prisma schema/config and the local Node platform as a fingerprint. Workflow
scripts such as `prebuild` do not invalidate dependency readiness, so adding a
gate cannot trigger a needless second `npm ci`. When the fingerprint is not
ready, the preparer runs `npm ci --include=dev --ignore-scripts` followed by
`npx --no-install prisma generate`. A cached Nest result is accepted only when the hidden
install lock is valid, every locked package has its `package.json`, direct
dependencies are present, and the generated Prisma entrypoints exist.
`--prepare-profile flutter` fingerprints `pubspec.yaml`/`pubspec.lock` plus the
Flutter revision in `.metadata`, then runs `flutter pub get --enforce-lockfile`.
A cached Flutter result is accepted only when the package config has a valid
schema, a root package for this worktree, and every referenced package root has
its own `pubspec.yaml` and materialized `packageUri` directory (or a declared
platform-only plugin directory); a stale or partial package config therefore
triggers hydration. Local Flutter hydration serializes writers to the shared
Pub cache so parallel task worktrees cannot publish a partial cache hit.
Flutter's generated platform/l10n files are reconciled against a narrow
allowlist and restored when they are created by hydration; unexpected tracked
or non-ignored files fail closed. A repository-relative ignored state file at
`tmp/opshub-toolchain-state.json` caches each profile independently:

```text
node scripts/prepare-task-toolchain.mjs --profile nestjs --dry-run
node scripts/prepare-task-toolchain.mjs --profile nestjs --json tmp/prepare.json
node scripts/prepare-task-toolchain.mjs --profile nestjs --force
node scripts/prepare-task-toolchain.mjs --profile flutter --dry-run
node scripts/prepare-task-toolchain.mjs --profile all --force
node scripts/prepare-task-toolchain.mjs --root ..\opshub-ops-123 --profile all --force
```

The `--root` form is the repair/doctor command for an existing task worktree;
it can be run from the canonical repository without changing directory. It
hydrates the selected worktree, rechecks its actual package graph and rewrites
only its ignored readiness state. Standalone validation scripts must run the
same preflight before any Flutter or Nest command; Flutter test commands then
use `--no-pub` so an implicit second dependency writer cannot bypass the gate.

If Windows `npm ci` reports `ENOTEMPTY`, `directory not empty` or an `rmdir`
failure while replacing `backend-nest/node_modules`, the preparer quarantines
that ignored dependency directory under
`backend-nest/.opshub-node_modules-recovery-<pid>-<timestamp>/`, retries
`npm ci` once, and removes the quarantine after Prisma readiness is confirmed.
A symlink, locked directory or failed rename is reported as an environment
failure with the recovery path; the gate never deletes tracked files or
silently accepts a partial install. Close the process holding the directory
and rerun the same preflight/doctor command.

The default lifecycle profile is `all`; `--prepare-profile nestjs|flutter` is
reserved for an explicitly narrow task. Verification and affected-consumer
profiles invoke the same `all` preflight before `flutter analyze --no-pub` or
`npm run build`, so a fresh worktree cannot reach the analyzer/build with
missing dependencies. Hydration is still fail-closed:
a lockfile change, unexpected tracked mutation or non-ignored generated file is
an environment failure. Known transient dependency materialization errors get
one retry only when the manifest fingerprint is unchanged; product/test
failures are never retried. A failed prepare is an environment failure and the
lifecycle removes the newly-created task worktree/branch, including reviewed
ignored output.

GitHub Actions uses a versioned Pub cache key containing the runner, Flutter
version/revision and the tracked `pubspec.yaml`, `pubspec.lock` and `.metadata`;
changing the cache policy or Flutter SDK therefore cannot reuse an older cache
silently.

OPS-39/OPS-40 affected-consumer validators use
`scripts/run-affected-consumer-suite.mjs`. Every Flutter/Nest suite carries its
own profile and runs through `run-with-toolchain`; a detached preflight in an
earlier shell block or job cannot authorize a later raw consumer. Go, Node-only,
Git, Docker and remote-maintenance commands remain in their own boundaries.
