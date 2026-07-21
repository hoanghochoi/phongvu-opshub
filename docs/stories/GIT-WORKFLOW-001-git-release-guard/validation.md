# GIT-WORKFLOW-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Flutter | No runtime change; not required. |
| NestJS | No runtime change; not required. |
| Go realtime | No runtime change; not required. |
| Integration | Fixture proves dry-run no-op, exact fast-forward execute, and blocked divergence/stale SHA/missing QA/dirty state. |
| Platform | Parse every workflow YAML; inspect pinned actions and least-privilege App token inputs; keep an always-on `Release guard` check for PRs into `staging` or `main`. |
| Release | Preserve existing `staging` and `main` push consumers; GitHub CI pass/fail verifier; affected-runtime guard and final fingerprint. |

## Evidence

- `node --check scripts/promote-production.mjs`: pass.
- `node --check scripts/test-git-release-workflow.mjs`: pass.
- `node scripts/test-git-release-workflow.mjs`: 8/8 pass, including both
  success paths and every specified blocked path.
- `.github/workflows/release-guard-pr.yml` runs the fixture proof and patch
  whitespace check on every PR into `staging` or `main`; its static contract is
  covered by the 8/8 test suite.
- PyYAML parsed all six `.github/workflows/*.yml`: pass.
- `git diff --check`: pass.
- Existing consumers explicitly tested: `Deploy OpsHub Staging` remains bound
  to `staging` pushes; `Deploy OpsHub` remains bound to `main` pushes.
- GitHub read-only audit: current ruleset protects delete/non-fast-forward only;
  production is limited to `main` and `help-content`, has required reviewer
  `1618hoangnguyen`, and rejects admin bypass. Repository variable
  `OPSHUB_RELEASE_APP_ID` and production environment secret name
  `OPSHUB_RELEASE_APP_PRIVATE_KEY` are present; secret value and live token mint
  remain intentionally unreadable/unverified.

## Unverified Risk

- Live `Release guard` execution, GitHub App token mint, ruleset bypass,
  downstream production trigger, and Linear status automation require the
  branch to be published plus a controlled staging/release rehearsal.
