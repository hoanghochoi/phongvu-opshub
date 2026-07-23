# OPS-15 — Harness upstream alignment

Status: active

## Scope

Bring the repository Harness surface in line with the upstream snapshot at
`d43b70254308b0e10efed2efbcbe595f1e771f63` without adding an OpsHub-specific
Harness core or a shared writable SQLite database. Product/runtime code is out
of scope.

## Local versus upstream

| Surface | Local before OPS-15 | Upstream direction | Decision |
| --- | --- | --- | --- |
| Agent entrypoint | Large OpsHub guide with custom Harness commands | Small stable core block plus repository workflow | Keep OpsHub policy, update command references to upstream CLI |
| Framework files | Ignored wrappers, schemas, docs and binaries | Tracked core payload, installer, onboarding skills and protocol docs | Track the upstream framework and tests |
| CLI | Portable SQLite wrapper, schema 12 | Rust compatibility CLI, protocol v1, schema 14, CAS/revisions and changesets | Use upstream prebuilt CLI; no wrapper logic changes |
| State | One local `harness.db` copied between worktrees | Per-worktree ignored DB; tracked baseline/changesets only in Harness source repos | Follow upstream consumer model; no shared writer |
| Audit | Local `audit --strict` gate over historical rows | Upstream `audit` has no `--strict` flag and reports drift/entropy | Do not invent a new strict semantics in this sync |
| Release | Local pin `harness-cli-v0.1.11` | Core `harness-v0.1.7`; latest available CLI artifact `harness-cli-v0.1.22` | Pin verified available artifacts; re-check when v0.1.23 is published |

## Applied changes in this branch

- Added upstream core payload, onboarding skills, workflow docs, protocol docs,
  compatibility schemas, installers, validation scripts, release workflows and
  Harness ADRs.
- Removed ignore rules that hid the Harness framework. Runtime DB/WAL/SHM,
  downloaded binaries, `.harness-core/` update state and temporary installer
  files remain ignored as required by the upstream consumer profile.
- Installed and checksum-verified `harness.exe` 0.1.7 and
  `harness-cli.exe` 0.1.22 locally in the worktree. Binaries remain ignored.
- Created a fresh schema-14 worktree DB with upstream `init` plus
  `import brownfield`. The legacy schema-12 DB is preserved outside the repo at
  `C:\tmp\ops-15-harness-root-db-pre-sync.db`; direct upstream migration was
  rejected because the legacy database lacks `audit_evidence_episode`.
- Removed four clean merged worktrees; 20 worktrees remain. Dirty, unmerged,
  protected and active worktrees were not touched.

## Audit finding

The upstream CLI accepts `audit` but rejects `audit --strict` as an unknown
argument. Plain upstream audit exits 0 while reporting 11 orphaned planned or
in-progress stories and entropy 100/100. This is an upstream contract change,
not a reason to patch the CLI. Any strict policy must be owned by an external
consumer/orchestrator or be proposed upstream in a separate issue.

## Follow-up implementation plan

1. Keep the tracked upstream framework as the only Harness core. Treat any
   OpsHub-specific adapter as a separate consumer surface, never as a fork of
   upstream Rust logic.
2. Ensure every linked worktree runs the pinned installer/bootstrap flow and
   materializes its own `harness.db` from repository documents or approved
   baseline/changesets.
3. Reconcile the 11 orphaned stories with real proof or accepted lifecycle
   status. Do not create synthetic traces or delete historical evidence.
4. Decide separately whether OpsHub needs an external strict wrapper. If yes,
   specify its exit policy and contract in a new upstream-compatible proposal;
   do not add `--strict` to the upstream CLI in this branch.
5. Validate on Windows native PowerShell/Git Bash and a second clean worktree:
   bootstrap, contract discovery, schema 14, core doctor, read/write isolation,
   changeset/snapshot behavior and `git diff --check`.
6. Record the exact commit, validation output, affected consumers and residual
   risks in Linear OPS-15 before any lifecycle transition.

## Evidence

- Upstream repository: https://github.com/hoanghochoi/harness-experimental
- Upstream snapshot: https://github.com/hoanghochoi/harness-experimental/tree/d43b70254308b0e10efed2efbcbe595f1e771f63
- Worktree branch: `codex/ops-15-harness-upstream`
- Base: `origin/staging` at `9fa9a5bcf1c98b3c6211ac1c35edbcb3a507f8dc`
