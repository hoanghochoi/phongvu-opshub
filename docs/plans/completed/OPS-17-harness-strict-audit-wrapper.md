# Execution Plan: OPS-17 Harness Strict Audit Wrapper

Date: 2026-07-29

## Status

Completed

## Outcome

Provide a read-only consumer/orchestrator command that binds the canonical
schema-12 strict-audit summary to the reviewed schema-14 parity projection,
emits the stable OPS-17 JSON contract, and exits with `0`, `2`, `3`, or `78`
without changing the authoritative database, the projected target, the
sidecar, or upstream Harness core.

## Context

- Linear OPS-17 defines the exit policy and stable JSON fields.
- `docs/contracts/harness-local-authority-adapter-v1.md` and
  `scripts/adapter/harness_local_authority_v1.py` are the preservation-first
  authority supplied by OPS-15.
- `tests/fixtures/harness/local-authority-adapter-v1.json` is the redacted
  digest fixture; complete SQLite/sidecar proof artifacts remain external.
- `docs/FEATURE_INTAKE.md` keeps strict enforcement in the
  consumer/orchestrator layer, not in the upstream Rust CLI.

## Scope

In scope:

- A Python strict wrapper under `scripts/adapter/`.
- A versioned strict-audit input/output contract and redacted baseline fixture.
- Focused unit/CLI tests for exit `0`, audit failure `2`, conflict `3`, and
  provenance/parity failure `78`.
- Windows-native and Git-for-Windows invocation against the retained OPS-15
  parity artifacts, including before/after file-hash proof.
- Current TEST_MATRIX and Linear implementation/proof records.

Out of scope:

- Modifying `scripts/bin/harness-cli.exe`, upstream Rust, or upstream schemas.
- Writing, migrating, importing, retiring, or refreshing canonical Harness
  rows.
- Creating/applying Harness changesets or recording evidence into a DB.
- Changing OpsHub Flutter, NestJS, Go, or deployment runtime.

## Approach

1. Define a fail-closed audit envelope containing source revision/schema,
   normalized category counts, changeset IDs, and conflict IDs.
2. Reuse adapter v1 parity in-process and give provenance/parity failures
   highest precedence (`78`), then CAS/changeset conflicts (`3`), then non-zero
   strict categories (`2`), otherwise `0`.
3. Keep the command read-only; compare source/target/fixture/sidecar SHA-256
   before and after live proof.
4. Add deterministic unit/CLI tests plus Windows/Git Bash integration proof.
5. Publish through the guarded OPS-17 branch/PR lifecycle only after exact diff
   and affected-consumer review.

## Risks And Recovery

- Risk: a malformed or incomplete audit envelope could be treated as clean.
  Mitigation: required keys, integer/non-negative validation, and exact
  revision-pinned counts; unknown, missing, or changed values fail as `78`.
- Risk: wrapper drift could weaken adapter parity. Mitigation: call the reviewed
  adapter directly and surface its failures; do not duplicate schema mapping.
- Risk: proof accidentally mutates retained artifacts. Mitigation: read-only
  SQLite opens and before/after SHA-256 checks.
- Recovery: revert the OPS-17 commit/PR. No runtime/database rollback is needed
  because the task performs no authoritative state writes.

## Progress

- [x] Re-audit OPS-15 adapter/sidecar/fixture and retained external artifacts.
- [x] Add strict wrapper, contract, fixture, and tests.
- [x] Run the initial unit/CLI and live Windows/Git Bash parity proof.
- [x] Re-run final unit/CLI and retained-artifact proof after the
  provenance-binding review fix.
- [x] Obtain a second exact-diff review and prepare guarded publication to
  `staging`.
- [x] Define the external release handoff for merge, exact-SHA staging deploy,
  lifecycle finish, and Linear status transition.

## Decisions

- 2026-07-29: `schema_version` names the canonical source schema (`12`); target
  schema `14` and parity failures remain inside `state_parity`.
- 2026-07-29: Unknown, missing, or changed audit categories are provenance
  failures (`78`), not a clean audit. V1 binds the exact reviewed counts,
  source revision, snapshot digest, and mapped counts; the wrapper never trusts
  caller-supplied zeros.
- 2026-07-29: Conflict exit `3` takes precedence over category exit `2` only
  after parity/provenance has passed.
- 2026-07-29: Adapter fixture/type errors are provenance failures (`78`), not
  uncaught process errors; the wrapper returns stable JSON for these cases.
- 2026-07-29: Parity passes only with `result=PASS`, an empty valid failure
  list, exact mapped counts, and `changeset_created=false`.

## Validation

- Focused proof: Python unit/CLI tests for validation, stable JSON and all exit
  codes.
- Integration or end-to-end proof: retained OPS-15 schema-12 snapshot,
  schema-14 target and sidecar through Windows-native Python and Git Bash.
- Repository-required checks: Python compile, source/target/fixture/sidecar hash
  invariance, tracked path audit, and `git diff --check`.

## Result

Implementation revised after independent review found that caller-controlled
counts could manufacture a clean exit and contradictory parity could be
downgraded. V1 now binds the exact revision, snapshot, audit categories/counts,
mapped counts, empty parity failures, and `changeset_created=false`. Final proof
passed 17 unit/CLI tests, Python compilation, Windows-native and Git Bash
baseline exit `2`, tampered-target exit `78`, SHA-256 invariance for all six
artifacts, and `git diff --check`. Independent second review found no remaining
findings. PR merge, staging evidence, lifecycle finish, and Linear transition
remain external release gates. No database, changeset, upstream Harness core,
or OpsHub runtime has been modified.
