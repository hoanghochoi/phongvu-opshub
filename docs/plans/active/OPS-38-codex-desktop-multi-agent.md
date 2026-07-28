# Execution Plan: Codex Desktop project-scoped multi-agent workflow

Date: 2026-07-29

## Status

Active

## Outcome

Codex Desktop can load a repo-native, trusted project configuration and custom
agent workflow for OpsHub without weakening existing Git, Linear, release,
Figma, security, logging, or affected-consumer contracts.

## Context

- Linear: `OPS-38`.
- Source checkpoint: `origin/staging` and task branch at
  `6e0ef145958ca8b103810d8778409d377c3723f3`.
- Input archive was audited read-only; internal manifest passed and its SHA-256
  is `124f13a49ff9f31bdfccb219dd1ffc41c026cbb6c366e63b336184b1decbda94`.
- Canonical rules: `AGENTS.md`, `docs/WORKFLOW.md`,
  `docs/runbooks/git-release-playbook.md`, `docs/FEATURE_INTAKE.md`, and the
  UI redesign documents.
- Desktop is the target runtime. CLI portability is documented as a residual
  risk and is not changed by this task.

## Scope

In scope:

- Minimal project `.codex/config.toml` and repo-native custom agents.
- One repo skill with progressive-disclosure references and deterministic
  static validation.
- Selective `.gitignore` rules for tracked config/agents while retaining local
  archive/artifact ignores.
- Small routing guidance, decision record, test-matrix proof, and this plan.
- Desktop trust/new-session routing smoke using runtime metadata when exposed.

Out of scope:

- Flutter, NestJS, Go, deployment, or product runtime behavior.
- User-level Codex CLI upgrade or global Codex configuration changes.
- Commit, push, PR, merge, deploy, Linear completion, or production release.
- Copying the kit's root `AGENTS.md`, `INSTALL.md`, or raw `prompts/` directory.

## Approach

1. Scaffold the repo skill with the official skill creator, then replace the
   template with concise OpsHub routing and references.
2. Add minimal project config and eight scoped `opshub_*` agent definitions;
   keep at most three child agents active and serialize writers.
3. Add a validator for TOML/schema/role/permission/concurrency invariants and
   adapt the root routing section without duplicating existing policy.
4. Add the durable decision and test-matrix entry, run static/lifecycle/release
   proof, then open a new trusted Desktop session for routing smoke.
5. Re-inspect the exact diff, update this plan and the OPS-38 proof comment,
   and stop before publishing.

## Risks And Recovery

- A malformed project config can prevent Codex from loading project layers:
  validate before opening a new session and keep the task branch reversible.
- Parent live permissions are inherited by every child. Review roles are
  non-mutating by task contract, while Harness, worktree ownership, lifecycle
  guards, and before/after state proof enforce the safe workflow. Record the
  effective parent permission in every routing smoke.
- A new worktree may not be trusted automatically: mark only this task
  worktree trusted before the smoke test; do not change global trust broadly.
- If validation fails, revert only the task-branch files with a focused patch;
  never reset or rewrite `staging`/`main`.

## Progress

- [x] Create OPS-38, record checkpoint, and create task worktree from live
  `origin/staging`.
- [x] Scaffold and author the repo skill.
- [x] Add project config, agents, ignore rules, and routing/decision docs.
- [x] Run static and repository workflow proof.
- [x] Complete Desktop trusted/new-session routing smoke:
  - [x] Desktop-managed runtime `0.146.0-alpha.3.1` loaded the task worktree,
    reported multi-agent enabled, and enumerated all eight project roles.
  - [x] A fresh Desktop task dispatched child thread
    `019fa9ef-6d31-7a61-9ac3-9db5a18706eb` as `opshub_repo_explorer` using
    `gpt-5.6-terra` / medium / multi-agent v2. Runtime sandbox was
    `danger-full-access` with permission profile disabled, confirming that the
    child inherited the parent runtime permission; pre/post Git state was
    unchanged.
- [x] Record final proof and residual risks in Linear (comment posted and
  read back; issue remains In Progress); stop before publish.

## Decisions

- 2026-07-29: Desktop is the primary runtime for this issue; CLI upgrade is a
  separate follow-up.
- 2026-07-29: Reuse the kit's role concepts but do not install its generic
  release/branch instructions or raw prompts.
- 2026-07-29: Use three child-agent slots to match the current four-slot
  session limit (primary plus three children).

## Validation

- Focused proof: skill quick validation, Python TOML/role validator, and
  `git diff --check`.
- Workflow proof: `node scripts/test-task-lifecycle.mjs` and
  `node scripts/test-git-release-workflow.mjs`.
- Runtime proof: new trusted Desktop session, role listing and runtime
  metadata routing smoke; unavailable metadata is reported as Unverified.
- Repository-required checks: exact diff/scope review, worktree status, source
  SHA, ignored archive hash, and Linear proof comment before any status change.

## Result

Local implementation and static/workflow verification are complete. The
Desktop-managed runtime loaded this worktree, enumerated all eight project
roles, and dispatched a real `opshub_repo_explorer` child with the configured
Terra/medium identity. Runtime metadata proved that the child inherits the
parent permission (`danger-full-access` in the first smoke). The child stayed
behaviorally non-mutating and pre/post Git state matched. No runtime
application files were changed.
