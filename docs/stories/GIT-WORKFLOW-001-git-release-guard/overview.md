# GIT-WORKFLOW-001 Guarded Git Release Workflow

## Status

implemented

## Risk Reason

This change controls production branch mutation and deployment initiation. Risk
flags: Audit/security, External systems, Existing behavior, Runtime artifact,
Weak proof, and Multi-domain.

## Product Contract

- Feature work defaults to a Linear-linked task branch and PR into `staging`.
- Direct pushes require an explicit current-task command naming the action and
  protected target; authorization never waives technical gates.
- Production receives only the exact, CI-green, QA-approved
  `origin/staging` SHA through a non-force fast-forward.
- A successful promotion leaves fetched `origin/main` and `origin/staging` at
  the same SHA and triggers the existing production deployment workflow.
- Linear reaches `Done` only after production deployment succeeds.

## Affected Areas

- Flutter: no runtime change.
- API: no runtime change.
- Database: no change.
- Auth/security: dedicated least-privilege GitHub App token and protected
  environment secret.
- External systems: GitHub Actions/rulesets/environments and Linear lifecycle.
- Deployment: new guarded promotion workflow; existing staging and production
  deploy workflow triggers remain unchanged.

## Human Confirmation Needed

- Đại Ca must explicitly authorize each direct push or production promotion.
- A repository admin must create/install the release GitHub App, add it as the
  only protected-branch bypass actor, and choose production required reviewers.
- Linear workspace admins must create missing lifecycle statuses before enabling
  automation.
