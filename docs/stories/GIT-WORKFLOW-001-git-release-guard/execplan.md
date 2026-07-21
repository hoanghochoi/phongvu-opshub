# GIT-WORKFLOW-001 Execution Plan

## Checkpoint

- Branch: `codex/ops-5-git-release-playbook`
- HEAD: `ddcfb053969dcefbd36d53dd26f9b347be99f8ce`
- Dirty worktree: clean
- Harness intake: `1`

## Steps

1. Record high-risk intake, path contracts, old deployment consumers, and
   checkpoint.
2. Add the promotion guard, fixture-based success/blocked dry runs, and manual
   production workflow.
3. Update `AGENTS.md`, backend deployment contract, playbook, story packet, and
   test matrix.
4. Validate Node syntax/tests, all workflow YAML, affected-runtime proof, and
   final diff.
5. After explicit admin setup, install the GitHub App/ruleset/environment and
   run a workflow dry-run before the first production promotion.

## Stop Conditions

- Source is not the current `origin/staging` SHA.
- Worktree/scope is dirty or changes during proof.
- CI, staging deploy, QA, environment approval, or ancestry fails.
- No dedicated GitHub App bypass actor exists.
- Any command would require force push or would promote an arbitrary branch.

## Ownership

- Files/modules: `AGENTS.md`, promotion workflow/guard/tests, deployment product
  contract, release playbook, story packet, and test matrix.
- Existing consumers: `Deploy OpsHub Staging` on `staging` push and
  `Deploy OpsHub` on `main` push.
- Out of scope: creating persistent GitHub App credentials without admin
  approval; deploying application runtime; performing a protected-branch push
  without Đại Ca's explicit branch-specific command.
