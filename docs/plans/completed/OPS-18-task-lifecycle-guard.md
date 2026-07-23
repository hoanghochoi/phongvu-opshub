# Execution Plan: OPS-18 task lifecycle guard

Date: 2026-07-23

## Status

Completed locally and publish-ready; publishing remains a separate action.

## Outcome

After a task PR is merged into `staging`, the canonical local `staging`
worktree fast-forwards to the exact live `origin/staging` head and the clean
merged task worktree/local branch are removed. Starting a new task repeats the
staging synchronization and creates the task branch/worktree from that exact
verified SHA.

## Context

- Linear: OPS-18.
- Policy: `AGENTS.md`, `docs/WORKFLOW.md`, and
  `docs/runbooks/git-release-playbook.md`.
- Existing contract: `docs/stories/GIT-WORKFLOW-001-git-release-guard/`.
- Existing proof: `scripts/test-git-release-workflow.mjs` and the `Release
  guard` PR workflow.
- Checkpoint: branch `codex/ops-18-task-lifecycle-guard`, HEAD
  `0cc43097e8bcd60ef92303734558f21eecd95b67`, clean worktree, created from the
  then-current and equal local/remote staging SHA after PR #18 merged.

## Scope

In scope:

- A dry-run-by-default Node lifecycle command for guarded task `start` and
  merged-task `finish` operations.
- Fail-closed checks for dirty/diverged/stale canonical staging, invalid issue
  or branch names, unmerged/mismatched PRs, dirty/unregistered worktrees, and
  protected branches.
- Long-path-safe clean worktree removal and squash-merge-aware local branch
  deletion.
- Fixture proof, agent policy, release playbook, workflow story, scripts docs,
  and test-matrix updates.
- Cleanup completed in this task: ten remaining clean stale worktrees, nine
  local merged task branches, and the newly merged clean OPS-15 worktree/local
  branch were removed; four additional clean detached worktrees had already
  been removed by OPS-15 before execution.

Out of scope:

- Deleting or discarding any dirty worktree or stash.
- Deleting remote branches or changing GitHub `delete_branch_on_merge`.
- Committing, pushing, opening a PR, or changing protected branches.
- Changing runtime Flutter, NestJS, Go, deployment behavior, or Harness core.

## Approach

1. Implement a single lifecycle command that must run from the clean canonical
   `staging` worktree.
2. `start` fetches, fast-forwards only, verifies local staging against the live
   remote SHA, creates the Linear-linked task worktree at that SHA, and removes
   the just-created clean worktree/branch if the remote advances during setup.
3. `finish` verifies the merged staging PR, exact head branch/SHA, registered
   clean task worktree, and protected-branch exclusions; then synchronizes
   staging, proves the merge commit is reachable, removes the worktree, deletes
   the local squash-merged branch, and rechecks the live staging SHA.
4. Add fixture tests for success and blocked/rollback paths, then update the
   durable workflow contract and operating instructions.

## Risks And Recovery

- Worktree/branch deletion is destructive. The command requires merged-PR
  evidence, exact branch/head identity, a clean registered worktree, an
  explicit `--execute`, and never uses `--force` for worktree removal.
- Squash-merged task commits are not ancestors of staging. Local branch
  deletion uses PR head identity instead of `git branch --merged`.
- A remote staging race can create a stale task. A post-create live SHA check
  removes only the newly created clean worktree/branch and exits non-zero.
- If cleanup partially fails, local staging remains safely fast-forwarded and
  the command exits non-zero. Recovery is to inspect the exact remaining
  worktree/branch and rerun only after it is clean and matches the merged PR.
- Rollback the implementation by reverting this branch's tracked patch. The
  already removed clean historical worktrees remain recoverable from their
  merged PR/head SHAs; dirty and active worktrees were preserved.

## Progress

- [x] Create OPS-18 and move it to `In Progress`.
- [x] Revalidate repository state and fast-forward local staging to the latest
  remote head before creating this task.
- [x] Remove the approved clean stale worktrees and local merged branches.
- [x] Implement lifecycle command and fixture tests.
- [x] Update policy, playbook, story, scripts docs, and test matrix.
- [x] Run focused proof, existing release proof, YAML parse, and diff checks.
- [x] Re-audit staging/worktree/branch state and prepare Linear proof.

## Decisions

- 2026-07-23: Use live `git ls-remote` plus fetched refs. Fetched refs support
  deterministic fast-forward checks; the live SHA closes the stale-ref window
  before and after task creation/cleanup.
- 2026-07-23: Keep remote branch deletion outside the local command. GitHub
  repository settings and historical remote cleanup need a separate publish
  authorization.
- 2026-07-23: Do not write the authoritative Harness DB from this
  upstream-aligned branch. Current repository policy makes the Markdown plan
  the durable task record.

## Validation

- Focused proof: `node scripts/test-task-lifecycle.mjs` passed 11/11,
  covering dry-run, exact start SHA, fast-forward-only sync, post-sync dirty
  artifact blocking, diverged staging, stale remote rollback, merged-task
  cleanup, unmerged PR, dirty task worktree, and protected branch rejection.
- Integration proof: `node scripts/test-git-release-workflow.mjs` passed 8/8;
  existing Release Guard, Deploy OpsHub Staging, and Deploy OpsHub contracts
  remained green. The PR workflow now invokes both suites.
- Repository-required checks: all 8 workflow YAML files parsed; `node --check`
  passed for the three Node scripts; `git diff --check` passed; the actual
  canonical staging guard blocked the 10 legacy untracked artifacts as
  expected. After explicit approval, those artifacts were moved to
  `C:\tmp\opshub-legacy-harness-quarantine-20260723-ops18`; their hashes were
  preserved, `harness.db` remained byte-identical, and the real canonical
  `start` dry-run passed at the live staging SHA.

## Result

Implemented and locally verified on branch `codex/ops-18-task-lifecycle-guard`
at base `0cc43097e8bcd60ef92303734558f21eecd95b67`. The local repository now
has 11 registered worktrees: no clean merged stale worktree remains; dirty
legacy worktrees, OPS-5/OPS-14 active worktrees, and OPS-18 are preserved.
Canonical local `staging` equals `origin/staging` at `0cc43097` and is clean
after the ten old Harness wrapper/artifact files exposed by the OPS-15
transition were quarantined outside the repository. The authoritative legacy
`harness.db` was preserved with SHA-256
`7b529ccf63f9e3709d04e5f470d524325d51c8d7030d18cb6e208d66bb3255e5`.
GitHub
`delete_branch_on_merge` remains `false`, and remote branch cleanup/settings
were intentionally not changed in this local implementation phase.
