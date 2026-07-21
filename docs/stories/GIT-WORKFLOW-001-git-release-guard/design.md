# GIT-WORKFLOW-001 Design

## Proposed Design

`scripts/promote-production.mjs` is the single promotion guard. It hard-codes
the `staging -> main` relationship, fetches both remote refs, rejects dirty or
stale state, proves ancestry, optionally verifies GitHub check runs/statuses,
and defaults to a no-write dry-run. Execution performs one non-force refspec
push, fetches again, and requires both refs to equal the approved SHA.

`.github/workflows/promote-production.yml` supplies the real release gate. A
manual dispatch requires exact QA/release phrases, pauses on the protected
`production` environment, mints a repository-scoped GitHub App token, and runs
the guard with GitHub CI verification. The App token is required instead of
`GITHUB_TOKEN` so the `main` push can trigger the existing production workflow.

Policy and operational details live in `AGENTS.md` and
`docs/runbooks/git-release-playbook.md`. Rulesets remain an external repository
configuration because their bypass actor ID is installation-specific.

## Alternatives Considered

- Merge a normal `staging -> main` PR: rejected as the promotion mechanism
  because merge/rebase can create a different SHA; the PR may still be used for
  release review only.
- Use `GITHUB_TOKEN`: rejected because its push does not trigger the downstream
  production workflow and it is not the dedicated bypass actor.
- Use a personal access token: rejected due broad, person-bound credentials.
- Force-update `main`: forbidden; divergence is a stop condition.

## Data And Contract Changes

- API: none.
- Database: none.
- Redis/WebSocket: none.
- Environment: repository variable `OPSHUB_RELEASE_APP_ID`; protected
  `production` secret `OPSHUB_RELEASE_APP_PRIVATE_KEY`; GitHub App repository
  permissions Contents write, Checks read, Commit statuses read.

## Rollback Plan

Before external enablement, revert the workflow/script/docs patch. After a
production promotion, do not rewrite `main`; create a revert branch, pass it
through `staging` deploy/QA, then explicitly promote the revert SHA.
