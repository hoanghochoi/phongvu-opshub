---
name: orchestrate-opshub-task
description: Coordinate evidence-first multi-agent delivery for PhongVu OpsHub across Flutter, NestJS, Go, security, UI/Figma, and release-readiness work. Use when a feature, bug, branch review, approved Figma implementation, or high-risk cross-stack task materially benefits from parallel discovery or independent review; skip tiny bounded changes that do not need delegation.
---

# Orchestrate OpsHub Task

## Overview

Use the primary session as the accountable orchestrator and delegate only
bounded work with explicit ownership. Preserve the repository's existing
Linear, lifecycle, Figma, security, logging, UI, and affected-consumer rules;
this skill adds routing and handoff structure, not a second source of truth.

## Non-negotiables

- Read the applicable `AGENTS.md`, `docs/WORKFLOW.md`, product/feature context,
  and the current task's acceptance criteria before delegation.
- Keep one production-code writer per worktree. Serialize a test writer with
  the production writer when their paths or fingerprint can overlap.
- Keep at most three child agents open at once (primary plus three fits the
  current four-slot runtime). Batch review waves instead of assuming eight
  simultaneous threads.
- Keep spec, exploration, reviewers, and release audit non-mutating by task
  contract. Agent sandbox permissions are inherited from the parent/session;
  do not treat role text as a technical isolation boundary.
- Treat custom-agent discovery and dispatch as separate checks. If a spawn
  returns no child/receiver or exposes no role metadata, stop that wave and
  report `Unverified`; do not accept the parent summary as proof. Use a built-in
  explorer/worker fallback only with the same explicit ownership contract, and
  never enable experimental features or edit user config implicitly.
- Do not create/transition Linear issues, create worktrees, publish, merge,
  deploy, or change protected branches unless the current task explicitly
  authorizes that exact action and repository gates pass.
- If a required authority, Figma revision, source SHA, proof command, or runtime
  capability is missing, return `Needs decision` or `Unverified`; do not infer.

## Route by task shape

| Shape | Minimum routing |
| --- | --- |
| Tiny/bounded | Primary only; delegate only if a concrete independent output exists. |
| Feature or normal change | `opshub_spec_analyst` + `opshub_repo_explorer`, plan checkpoint, one `opshub_implementer`, then targeted tests/review. |
| Bug | Add `opshub_test_engineer` for a reproduction before the writer; classify hotfix and full-fix lanes. |
| Branch review | `opshub_repo_explorer` plus `opshub_code_reviewer`; add security/UI only when triggered. Keep source review non-mutating. |
| Approved Figma implementation | `opshub_ui_ux_reviewer` + explorer before the writer; require exact approved frame/revision. |
| Protected release readiness | Root owns the handoff; optionally use `opshub_release_auditor` for an independent non-mutating gate review. |

## Standard wave

1. **Discover:** run spec and repository exploration in parallel; cite exact
   files, symbols, acceptance criteria, protected consumers, and unknowns.
2. **Plan:** root reconciles findings, records file ownership and proof, and
   stops for any material product/security/schema/Figma decision.
3. **Implement:** delegate exactly one writer in the approved worktree. The
   writer does not publish or self-approve.
4. **Verify:** run the focused test wave, then independent code/security/UI
   review waves as triggers require. Recompute affected proof after every edit.
5. **Handoff:** root reports exact commands/results, residual risk, manual QA,
   lifecycle state, and the one next action. Linear proof comment precedes any
   forward status transition.

## Ownership

- `opshub_implementer`: approved production files across Flutter/NestJS/Go and
  bounded tooling; no unrelated refactor or generated-file edits.
- `opshub_test_engineer`: assigned test paths only; may create a reproduction
  or test fixture, but never silently changes production behavior.
- Reviewers: no file edits by task contract. A test command that needs
  build/cache writes must run in the assigned worktree and be covered by
  before/after Git and Harness proof; the inherited parent permission remains
  the technical boundary.
- Root: decomposition, delegation, reconciliation, final accountability, and
  release/Linear handoff.

## Repository-specific checks

Apply the existing contracts rather than inventing replacements:

- Flutter: Provider/ChangeNotifier/GoRouter patterns, shared components,
  canonical DateRangePicker, responsive tokens, Vietnamese-first copy, and
  sanitized `AppLogger` coverage.
- Backend/realtime: NestJS/Prisma and Go service patterns, authorization at the
  server boundary, migrations and realtime contracts.
- UI/redesign: approved Figma revision, shared foundation/components, four
  breakpoints, Android/Windows proof, and old-consumer protection.
- Release: `scripts/task-lifecycle.mjs`, PR base `staging`, CI/staging QA,
  exact promotion authorization, and no direct `main` feature edits.

Use `scripts/validate_config.py` for deterministic static checks before opening
a new Desktop session. Load only the needed reference for the task:

- `references/role-matrix.md` — role ownership and inherited-permission contract.
- `references/feature-workflow.md` — Linear feature sequence.
- `references/bug-workflow.md` — reproduction and hotfix/full-fix sequence.
- `references/review-workflow.md` — non-mutating branch review and test caveats.
- `references/figma-workflow.md` — approved-frame and responsive proof gate.
- `references/routing-verification.md` — trusted-session/runtime metadata smoke.
- `references/output-contract.md` — compact evidence handoff format.

## Stop conditions

- Stop before mutation when the task lacks a safe target, issue/acceptance
  authority, approved Figma revision, recoverable plan, or executable proof.
- Stop before publish/release when source SHA, CI, staging deploy, QA, release
  lock, or exact authorization is stale or missing.
- If new evidence changes scope, invalidate the affected plan and request a
  revised approval; do not silently expand the task.

Every delegated handoff must use `references/output-contract.md`. Keep output
compact so the primary context remains focused on decisions and verification.
