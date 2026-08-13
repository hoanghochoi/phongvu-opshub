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
auto-selected profiles with the full ladder and uploads a sanitized JSON report;
the existing blocking release checks remain unchanged. Infrastructure failures
may retry once only while the fingerprint is unchanged. Product/test failures
are never retried, and any change during a retry is a stale-proof failure.

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
