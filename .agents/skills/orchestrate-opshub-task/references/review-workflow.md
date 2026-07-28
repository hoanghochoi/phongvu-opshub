# Branch review workflow

This workflow is source-review non-mutating by task contract. Establish exact branch, base,
merge-base, changed paths, deleted/renamed paths, and before/after status before
delegating.

1. `opshub_repo_explorer` maps changed execution paths and protected consumers.
2. `opshub_code_reviewer` checks correctness, state transitions, permissions,
   data integrity, architecture, missing tests, and stale proof.
3. Add `opshub_security_reviewer` for trust-boundary/auth/data/external changes
   and `opshub_ui_ux_reviewer` for visual/interaction changes.
4. Keep review waves at three children or fewer and deduplicate findings in the
   root. Reviewers do not edit or approve their own work.

`flutter test`, builds, and some analyzers can create caches/artifacts. Run such
commands only in the assigned worktree and record the inherited parent
permission plus tracked/ignored-state proof. If the command is not authorized
for the current wave, inspect existing CI evidence and mark it unverified.

Conclude with Blocker/High/Medium/Low/Not actionable findings, exact evidence,
required regression tests, and PR readiness. Do not review `main` as a target.
