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
| State | Local OpsHub `harness.db` plus project Markdown are the authority | Upstream per-worktree DB/schema is an execution target, not a source refresh | Preserve local state; migrate/replay only through an approved adapter |
| Audit | Local `scripts/harness audit --strict` over the authoritative historical rows | Upstream `audit` has no `--strict` flag and is valid only for a compatible schema-14 state | Keep local strict semantics at consumer/orchestrator layer |
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
- Created a disposable schema-14 validation DB with upstream `init` plus
  `import brownfield`; it is not an authority copy. The authoritative local
  schema-12 DB remains at the root worktree and is preserved outside the repo at
  `C:\tmp\ops-15-harness-root-db-pre-sync.db`. Direct upstream migration was
  rejected because the local DB lacks upstream `audit_evidence_episode` and
  other schema-9 compatibility structures.
- Removed four clean merged worktrees; 20 worktrees remain. Dirty, unmerged,
  protected and active worktrees were not touched.

## Audit finding

The authoritative local wrapper reports 4 orphaned stories, 7 unverified
stories, 2 unverified decisions, 70 normal/high-risk intakes without traces,
3 dangling intake links, and entropy 100/100. This is the real baseline.

The disposable upstream brownfield import reported 11 orphaned stories and
entropy 100/100, but those rows are parser artifacts from the tail table in
`docs/TEST_MATRIX.md`; the imported DB also dropped local operational history.
The generated `.harness/changesets/ops15-reconcile-11.changeset.jsonl` was
quarantined and is not valid for the authoritative local DB. No local story was
retired or overwritten by that changeset.

The local DB has 37 stories, 92 intakes, 7 decisions, and 36 traces; the
disposable upstream import has 30 stories, 1 intake, 30 decisions, and 0
traces. Any strict policy must therefore be owned by the consumer/orchestrator
and must treat local DB/docs as canonical until an explicit schema/state
adapter is reviewed.

## Follow-up implementation plan

1. Keep the tracked upstream framework as the only Harness core. Treat any
   OpsHub-specific adapter as a separate consumer surface, never as a fork of
   upstream Rust logic.
2. Ensure every linked worktree runs the pinned installer/bootstrap flow and
   materializes its own `harness.db` from repository documents or approved
   baseline/changesets.
3. Treat local DB/docs as canonical; do not run upstream `import brownfield`
   against the authoritative DB and do not apply the quarantined changeset.
4. Design and review a schema/state adapter that preserves local stories,
   intakes, decisions, traces, and strict audit semantics without changing the
   upstream core.
5. Keep strict enforcement in the consumer/orchestrator layer; specify its
   exit policy and JSON contract in OPS-17, not as an upstream `--strict` flag.
6. Validate on Windows native PowerShell/Git Bash and a second clean worktree:
   bootstrap, contract discovery, schema 14, core doctor, read/write isolation,
   changeset/snapshot behavior and `git diff --check`.
7. Record the exact commit, validation output, affected consumers and residual
   risks in Linear OPS-15 before any lifecycle transition.

## Evidence

- Upstream repository: https://github.com/hoanghochoi/harness-experimental
- Upstream snapshot: https://github.com/hoanghochoi/harness-experimental/tree/d43b70254308b0e10efed2efbcbe595f1e771f63
- Worktree branch: `codex/ops-15-harness-upstream`
- Base: `origin/staging` at `9fa9a5bcf1c98b3c6211ac1c35edbcb3a507f8dc`
- Authoritative local audit: 4 orphaned, 7 unverified stories, 2 unverified
  decisions, 70 intakes without traces, entropy `100/100`.
- Disposable import audit: 11 parser-artifact orphaned rows; its generated
  changeset is quarantined and must not be applied to local state.
