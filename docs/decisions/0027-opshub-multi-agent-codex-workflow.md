# 0027 OpsHub project-scoped multi-agent Codex workflow

## Status

implemented locally; Desktop routing verified with inherited parent permissions

## Context

The supplied multi-agent kit contains useful role separation and evidence
handoffs, but its generic branch/release instructions conflict with OpsHub's
guarded lifecycle. Its raw prompts are not the current reusable Codex surface,
the root `AGENTS.md` must not be overwritten, and the repository is full-stack
while the kit assumes Flutter-only implementation. Project `.codex/` is also
currently ignored, so an unmodified install would be local-only and invisible
to Git.

## Decision

Adopt a repo-native project layer for Codex Desktop:

- track only a minimal `.codex/config.toml` and eight scoped `opshub_*` agents;
- cap child agents at three and serialize production/test writers;
- place reusable workflows in the explicit `$orchestrate-opshub-task` skill with
  progressive-disclosure references and a deterministic validator;
- preserve existing OpsHub instructions, lifecycle, release, Figma, security,
  UI, logging, and affected-consumer contracts;
- treat CLI compatibility and user-level configuration as a separate follow-up;
- require a trusted worktree and a new Desktop session before routing proof.

## Consequences

- Desktop users receive a shared, reviewable workflow without global Codex
  pollution or raw prompt duplication.
- The project layer becomes a trusted configuration surface and therefore needs
  normal code review and static validation.
- Static validation is complete on the OPS-38 task worktree: 8 agent files,
  concurrency cap 3, skill metadata, lifecycle fixtures, and release-workflow
  fixtures all pass. Desktop-managed runtime `0.146.0-alpha.3.1` also loaded the
  task worktree and enumerated all eight roles. A fresh Desktop task dispatched
  `opshub_repo_explorer` as `gpt-5.6-terra` / medium / multi-agent v2. Its live
  sandbox was `danger-full-access` with permission profile disabled, confirming
  that child agents inherit the parent runtime permission. Review roles remain
  non-mutating by task contract; Harness, worktree ownership, lifecycle checks,
  and before/after state proof are the safety controls.
- Older CLI clients may ignore or reject the project layer; this remains an
  explicit compatibility risk until a separate client-upgrade decision.
- No application runtime behavior changes; proof focuses on config, skills,
  lifecycle/release guards, and actual Desktop routing metadata.
