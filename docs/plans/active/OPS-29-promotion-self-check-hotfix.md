# Execution Plan: OPS-29 Promotion Self-Check Hotfix

Date: 2026-07-27

## Status

Active

## Outcome

Production promotion verifies the CI evidence for the approved staging SHA
without treating checks emitted by the promotion workflow itself as source CI.
Failed or pending non-promotion checks and commit statuses must still block.

## Context

- Linear OPS-29 records the release incident and acceptance criteria.
- `scripts/promote-production.mjs` is the canonical fast-forward and CI guard.
- `.github/workflows/promote-production.yml` owns the protected production
  dispatch and GitHub App token.
- `docs/runbooks/git-release-playbook.md` is the operator contract.
- `docs/stories/GIT-WORKFLOW-001-git-release-guard/` owns design and proof.
- Failed run 30215947416 attached the promotion job check to staging SHA
  `4bd51aaf6a63ffbeb382da743fe089cbbef67c4d`; run 30215973142 then blocked on
  that check before pushing `main`.

## Scope

In scope:

- Recognize and exclude only GitHub Actions check runs that match the canonical
  production-promotion job identity.
- Report evaluated and ignored check counts.
- Add regression proof for the observed self-deadlock and for fail-closed
  behavior of unrelated checks/statuses.
- Document that operators dispatch the workflow from ref `main`.
- Re-run existing release and task-lifecycle proof.

Out of scope:

- Changing GitHub App credentials, environment reviewers, branch policies, or
  rulesets.
- Deleting or rewriting failed GitHub Actions audit history.
- Force-pushing or promoting production without a new explicit authorization.
- Changing application runtime, API, database, Flutter, NestJS, or Go behavior.

## Approach

1. Add a failing regression fixture representing the real failed promotion
   check plus successful staging checks.
2. Implement a narrow predicate requiring the canonical job name, the
   `github-actions` app, and a GitHub Actions run URL before exclusion.
3. Keep the empty-evidence and unrelated failed/pending check gates fail-closed.
4. Include ignored promotion-check count in promotion audit output.
5. Update workflow comments, playbook dispatch command, design, and validation
   evidence.
6. Run focused and full release workflow proof, publish through a PR to
   `staging`, verify staging deploy and a live read-only guard rehearsal.

## Risks And Recovery

- Risk: an overly broad filter could hide required CI. Mitigation: require all
  three identity signals and regression-test an unrelated failure with the
  self-check present.
- Risk: dispatching from `staging` can recreate the bad check. Mitigation:
  canonical command uses `--ref main`, while the production environment keeps
  enforcing its existing branch policy.
- Recovery: revert the OPS-29 PR through `staging`, deploy/QA the revert, and
  obtain fresh production authorization. Never rewrite `main`.

## Progress

- [x] Capture clean canonical staging checkpoint and incident evidence.
- [x] Create/link Linear OPS-29 and isolated task worktree.
- [x] Add regression test and implement the narrow self-check filter.
- [x] Update workflow/runbook/design/validation documentation.
- [x] Run focused and repository-required release proof.
- [ ] Commit, push, open PR, pass CI, merge to `staging`, deploy and QA.
- [ ] Record proof and move OPS-29 to `Ready for Release`.

## Decisions

- 2026-07-27: Treat this as a high-risk release hotfix because it changes a
  shared protected-branch gate, despite no application runtime change.
- 2026-07-27: Do not identify promotion checks by name alone; require the
  GitHub Actions app and an Actions run URL as additional provenance.
- 2026-07-27: Preserve failed workflow runs as audit evidence; fix the verifier
  instead of deleting history or weakening environment/ruleset protection.

## Validation

- Focused proof: `node --check scripts/promote-production.mjs`,
  `node --check scripts/test-git-release-workflow.mjs`, and
  `node scripts/test-git-release-workflow.mjs`.
- Integration proof: `node scripts/test-task-lifecycle.mjs`; live read-only
  GitHub API reproduction against the affected staging SHA; local promotion
  dry-run on the new staging SHA after merge.
- Repository-required checks: parse all workflow YAML files and
  `git diff --check`.

## Result

Implementation and pre-publish proof pass. Publish/staging QA/release proof
remain pending.
