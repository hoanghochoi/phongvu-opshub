# GIT-WORKFLOW-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Flutter | No runtime change; not required. |
| NestJS | No runtime change; not required. |
| Go realtime | No runtime change; not required. |
| Integration | Fixture proves dry-run no-op, exact fast-forward execute, and blocked divergence/stale SHA/missing QA/dirty state. |
| Platform | Parse every workflow YAML; inspect pinned actions and least-privilege App token inputs. |
| Release | Preserve existing `staging` and `main` push consumers; GitHub CI pass/fail verifier; affected-runtime guard and final fingerprint. |

## Evidence

- `node --check scripts/promote-production.mjs`: pass.
- `node --check scripts/test-git-release-workflow.mjs`: pass.
- `node scripts/test-git-release-workflow.mjs`: 8/8 pass, including both
  success paths and every specified blocked path.
- PyYAML parsed every `.github/workflows/*.yml`: pass.
- `git diff --check`: pass.
- Existing consumers explicitly tested: `Deploy OpsHub Staging` remains bound
  to `staging` pushes; `Deploy OpsHub` remains bound to `main` pushes.
- GitHub read-only audit: current ruleset protects delete/non-fast-forward only;
  production is limited to `main` and `help-content` but has no required
  reviewer and still permits admin bypass; release App variable/secret are not
  configured.

## Unverified Risk

- Live GitHub App token mint, ruleset bypass, required reviewer, downstream
  production trigger, and Linear status automation require external admin setup
  and a controlled staging/release rehearsal.
