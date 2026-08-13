# 0029 Adopt Upstream Repository Protocol And Retire Protocol V1

Date: 2026-08-13

## Status

Accepted for the OPS-64 migration initiative. The cutover is staged; legacy
SQLite/protocol-v1 files remain available until the retirement gates in the
master plan pass.

## Context

OpsHub grew a consumer-specific Harness layer around a local SQLite database,
protocol-v1 lifecycle commands, compatibility adapters, and release workflows.
That layer records useful history, but it creates a second operational
authority beside Git, product/runtime contracts, and Linear. It also requires
agents to understand OpsHub-specific state machinery before they can use the
repository workflow.

The upstream `repository-harness` project now provides the repository protocol
needed by this consumer. Release `harness-v0.1.8` is the cutover baseline. Its
`harness` binary installs and updates a repository-centered payload through a
provenance-aware, three-way merge with dry-run, conflict continuation, abort,
status, and doctor operations. The tagged payload includes the explicit-only
`improve-harness` skill, application-runbook template, and Harness-improvement
template.

Legacy records must remain recoverable while their current authority is
reviewed. A row-for-row import into an upstream database would recreate the
dual-truth problem and would make historical execution state look like current
product intent.

## Decision

1. OpsHub adopts `hoangnb24/repository-harness` release `harness-v0.1.8` as
   the repository-protocol baseline. The tracked pin is
   `scripts/harness-release-tag`; future core updates use the upstream
   `harness update` transaction and an explicitly reviewed release.
2. The public local Harness interface for ordinary repository work is the
   upstream core only:

   ```text
   scripts/bin/harness status [--json]
   scripts/bin/harness doctor [--json]
   scripts/bin/harness update --dry-run
   scripts/bin/harness update
   scripts/bin/harness update --continue --dry-run
   scripts/bin/harness update --continue
   scripts/bin/harness update --abort
   ```

   The upstream core does not own intake, stories, decisions, backlog, traces,
   SQLite state, work selection, orchestration, or evaluation.
3. OpsHub remains the authority for product behavior, release/lifecycle rules,
   Linear/Figma policy, validation commands, application runbooks, runtime
   contracts, and all content outside the marked Harness block. Upstream owns
   only its marked generic block, generic core templates, and the explicit-only
   generic skills/resources declared in `scripts/harness-install-files.txt`.
4. The default upstream payload includes `$improve-harness`,
   `docs/templates/application-runbook.md`, and
   `docs/templates/harness-improvement.md`. These remain approval-gated and do
   not auto-run or create a task database.
5. `harness.db`, WAL/SHM files, old binaries, and the legacy archive are not
   imported, rewritten, or deleted by this decision. Archive manifests and the
   disposition ledger are Git evidence; raw archive copies remain local-only.
   Current behavior and accepted decisions are promoted to their Git or Linear
   owners, not copied row-for-row into Markdown.
6. Upstream updates must use dry-run/merge and three-way conflict semantics.
   A conflict, checksum/release identity mismatch, stale candidate, or missing
   affected-consumer authority stops the phase. Consumer-owned instructions are
   never replaced by an override-style bulk copy.
7. OpsHub is a consumer of upstream Harness. It does not fork, publish, or
   release the upstream core. Any generic improvement proposed for upstream
   requires a separate explicit authorization before public posting.

## Supersession boundary

This decision supersedes Harness-only parts of decisions `0003`, `0004`,
`0005`, `0022`, and `0024` that make SQLite/protocol-v1 state or OpsHub-owned
Harness release machinery a current/default authority. Those records remain in
Git as historical provenance and compatibility rationale. It does not
supersede product, API, permission, security, deployment, UI, or runtime
decisions, and it does not delete the legacy implementation before the staged
archive, disposition, canary, and retirement gates pass.

## Consequences

Positive:

- Fresh repository installs have one generic, provenance-aware maintenance
  path and no required database control plane.
- Upstream fixes can be adopted through a reviewed tagged update rather than a
  permanent OpsHub fork.
- Consumer policy and product truth remain local and discoverable.
- The legacy DB and evidence retain a reversible archive/disposition boundary.

Tradeoffs and risks:

- The upstream binary and release availability are external dependencies; a
  checksum authenticates the selected release bytes but not the publisher.
- Existing protocol-v1 consumers need a compatibility window and explicit
  migration before legacy files can be removed.
- Local archive copies are currently on the same host/physical disk and do not
  provide off-host disaster recovery.
- Generic upstream payload changes can conflict with customized OpsHub policy;
  agents must resolve them with human authority and rerun proof.

## Validation impact

Phase 2 must verify the pinned release identity and, in disposable targets:

- fresh install/adoption;
- `status --json` and `doctor --json` with no mutation;
- `update --dry-run` with no file changes;
- non-overlapping update;
- overlapping text/structural conflict with retained resolution workspace;
- `--continue` and `--abort`; and
- interrupted-update recovery.

The Phase 2 evidence records the exact upstream tag/commit, binary checksum,
selected payload, target hashes before/after each dry-run, and any residual
authority or recovery risk. Full retirement is a later phase and requires a
fresh checkout, runtime validation, and proof that no remaining consumer needs
the retired producer surface.
