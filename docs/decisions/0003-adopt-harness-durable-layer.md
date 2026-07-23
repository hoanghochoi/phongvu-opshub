# 0003 Adopt Harness Durable Layer

> Historical decision. OPS-15 supersedes the ignored-framework choice below by
> tracking the upstream Harness surface, but local OpsHub DB/docs remain the
> data authority until a preservation-first adapter is approved. Keep this
> record for provenance; use `docs/WORKFLOW.md` and `AGENTS.md` for the current
> authority and command boundaries.

Date: 2026-05-24
Amended: 2026-07-18

## Status

accepted

## Context

OpsHub already adopted the Harness markdown workflow, but ongoing FIFO,
warranty, deployment, and release work creates repeated operational state:
intakes, story proof, decisions, backlog items, and traces. Keeping all of this
only in markdown makes query and evidence updates fragile.

The upstream `harness-experimental` workflow supplied the initial durable
SQLite shape. OpsHub now has local adaptations for Windows, read-only audits,
UTF-8 diagnostics, and affected-runtime regression protection.

## Decision

Adopt the durable layer for OpsHub as an adapted merge:

- Keep OpsHub-specific `AGENTS.md`, product docs, stories, decisions, and test
  matrix as the readable source of truth.
- Keep the reviewed Harness framework and `harness.db` workstation-local and
  ignored unless the user explicitly requests a distribution change.
- Use `scripts/harness` as the authoritative local entrypoint. The optional Rust
  binary may accelerate compatible reads, but must not own schema or mutations.
- Store generated operational state in local `harness.db`, ignored by git.
- Do not copy upstream Rust source, generic demo decisions, or release tooling
  into OpsHub.
- Keep `scripts/bin/harness-cli` optional and ignored. The shell entrypoint uses
  `sqlite3` or the dependency-free `node:sqlite` adapter when needed.
- On Windows PowerShell, invoke
  `${env:ProgramFiles}\Git\bin\bash.exe --login scripts/harness ...` explicitly;
  bare `bash.exe` may resolve to an unconfigured WSL shim.
- `Agent environment = Windows native` keeps that rule even if the integrated
  terminal shell is WSL. Manual WSL sessions may use `bash scripts/harness ...`
  for read-only checks and `bash scripts/validate ...`; arbitrary stored proof
  commands remain on the Windows-native Git Bash route unless they use a
  reviewed cross-platform wrapper. Windows and WSL must not write concurrently.
- For a Windows-mounted checkout inspected from WSL, prefer available Git for
  Windows `git.exe` and normalize file mode, line-ending settings, and byte-order
  path sorting. This keeps changed-path detection and proof fingerprints equal
  across Git Bash and WSL while avoiding slow Linux-Git scans over `/mnt/c`.
- Prefer native `sqlite3`, then compatible `node`/`node.exe` with `node:sqlite`,
  before interoperable `sqlite3.exe`. Standalone SQLite clients use the `.timeout`
  command rather than a result-producing busy-timeout PRAGMA.
- Keep `doctor` and `audit` read-only by default. Any tool-status refresh or
  encoding repair requires an explicit mutation flag and a backup.
- For normal/high-risk runtime work, store an intake checkpoint and story
  `path_contracts` plus `affected_verify_command`. A recorded affected proof is
  valid only for the exact captured branch/HEAD, worktree blob, staged/index,
  Git-normalized mode/deletion, guard source, story contract/command/status, and
  intake state. Revalidate that snapshot before returning in every mode and
  before recording.
- Evaluate a rename as deletion of the old path plus addition of the new path;
  both sides must resolve to protected contracts.
- Require exactly one file-backed migration for each version `001` through
  `010`. Versions `011` and `012` are embedded and reserved; the next file is
  `013`, and future versions must remain contiguous. Each file migration and its
  version/FK postconditions commit atomically or roll back together. Refuse a DB
  newer than the local manifest and never replay a gap below `MAX(version)`.

## Consequences

- Agents can query and record structured harness state through
  `scripts/harness`.
- Existing markdown remains useful for review and code navigation.
- OpsHub avoids generic upstream decision history that would confuse local
  architecture records.
- Each checkout initializes/imports its own local durable DB.
- Shared chokepoints are verified against protected existing consumers, not only
  against the new module that triggered the change.
- A dirty worktree at intake remains usable: unchanged pre-existing dirty files
  are excluded using stable checkpoint state, while later edits, staged-only
  changes, deletions, and both sides of renames are detected.
- End-state revalidation is fail-closed, but it is not an exclusive writer
  lease. A future isolated-worktree/lease improvement is still required to rule
  out a transient change that is restored before the final snapshot.

## Validation Impact

Docs-only and harness changes should run:

```powershell
$gitBash = "${env:ProgramFiles}\Git\bin\bash.exe"
& $gitBash --login scripts/harness init
& $gitBash --login scripts/harness import brownfield
& $gitBash --login scripts/harness query matrix
& $gitBash --login scripts/harness doctor --strict
& $gitBash --login scripts/harness story verify-affected --intake <id> --run --record --strict
& $gitBash --login scripts/harness story verify-affected --intake <id> --check --strict
git diff --check
```
