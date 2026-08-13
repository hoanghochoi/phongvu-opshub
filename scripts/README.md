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
