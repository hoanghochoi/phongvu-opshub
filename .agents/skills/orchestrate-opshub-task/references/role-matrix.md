# OpsHub agent role matrix

| Role | Model | Permission source | Owns | Trigger |
| --- | --- | --- | --- | --- |
| `opshub_spec_analyst` | `gpt-5.6-sol` / high | inherited parent; non-mutating contract | authority, acceptance, risk lane, edge cases | unclear or consequential scope |
| `opshub_repo_explorer` | `gpt-5.6-terra` / medium | inherited parent; non-mutating contract | execution paths, symbols, dependencies, affected consumers/tests | before implementation/review |
| `opshub_implementer` | `gpt-5.6-sol` / high | inherited parent; writer contract | one approved production-code surface across Flutter/NestJS/Go/tooling | after plan approval |
| `opshub_test_engineer` | `gpt-5.6-terra` / high | inherited parent; assigned test writes only | assigned tests/reproduction fixtures only | bug reproduction or delegated test wave |
| `opshub_code_reviewer` | `gpt-5.6-sol` / high | inherited parent; non-mutating contract | correctness, regressions, stale proof, architecture | every normal/high-risk code change |
| `opshub_security_reviewer` | `gpt-5.6-sol` / high | inherited parent; non-mutating contract | trust boundaries, secrets, auth/object access, dependency risk | auth, data, external, or security trigger |
| `opshub_ui_ux_reviewer` | `gpt-5.6-sol` / high | inherited parent; non-mutating contract | approved Figma, responsive, accessibility, UI states | visual/interaction target changes |
| `opshub_release_auditor` | `gpt-5.6-sol` / high | inherited parent; non-mutating contract | lifecycle, CI, QA, release evidence; never release action | protected release-readiness request |

The parent session's live permission choice is the technical permission source
for every child. Review roles remain non-mutating by developer instruction and
Harness workflow, while writer/test roles may write only within their assigned
worktree paths. Capture runtime metadata when exposed and always compare
before/after Git state for no-op or review waves; do not claim role-level
sandbox isolation.

Never run two production writers in one worktree. A test writer may run only in
a serialized wave and only within its assigned test paths.
