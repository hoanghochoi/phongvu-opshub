# Execution Plan: OPS-19 Dependabot Remediation

Date: 2026-07-24

## Status

Completed

## Outcome

Remove the vulnerable `brace-expansion` 1.x and 2.x instances from the NestJS
development and production dependency trees, retain the already-patched
`body-parser@2.3.0`, and provide focused request-body enforcement proof plus
the full backend validation required for review.

## Context

- Linear: OPS-19 tracks Dependabot alerts #20, #21, and #22.
- Advisory authority:
  - `GHSA-3jxr-9vmj-r5cp` requires `brace-expansion@1.1.16`,
    `2.1.2`, or `5.0.7` for the affected major lines.
  - `GHSA-v422-hmwv-36x6` requires `body-parser@2.3.0` on the 2.x line.
- Runtime boundary: `backend-nest/src/main.ts` installs Express JSON and
  URL-encoded parsers using the operator-provided `REQUEST_BODY_LIMIT`.
- Baseline dependency paths:
  - development: ESLint/Jest/minimatch resolve vulnerable
    `brace-expansion@1.1.14` and `2.1.0`;
  - runtime: Google BigQuery/gaxios tooling reaches
    `rimraf -> glob -> minimatch -> brace-expansion@2.1.0`;
  - `body-parser@2.3.0` is already present from staging PR #7.
- Stable checkpoint captured twice before edits:
  - branch `codex/ops-19-fix-backend-dependabot`;
  - HEAD `44492d177115e917b6232ea688645f2cdbd8b1e6`;
  - clean worktree and index;
  - package lock blob `c9ec5c543f680ec3fd6d27a942603f6ad972466a`;
  - package manifest blob `48198d131131f4c9ef7856a51df31d8bf82b84e5`.

## Patch Contract

- Vulnerable component: transitive `brace-expansion` releases with
  exponential work for consecutive non-expanding brace groups.
- Preconditions: an affected dependency expands an attacker-influenced or
  otherwise unbounded glob pattern. No direct request-to-glob path has been
  proven in OpsHub, but a vulnerable 2.x copy ships in the production artifact.
- Security invariants:
  - no `brace-expansion <1.1.16`;
  - no `brace-expansion >=2.0.0 <2.1.2`;
  - no `brace-expansion >=3.0.0 <5.0.7`;
  - invalid request-body limits fail during parser construction instead of
    silently disabling enforcement.
- Compatibility to preserve:
  - normal NestJS startup with the documented `1mb` limit;
  - valid JSON and URL-encoded requests remain accepted;
  - oversized requests remain rejected with HTTP 413;
  - Jest, minimatch, rimraf, BigQuery, and gaxios consumers continue to build
    and test without API changes.

## Scope

In scope:

- Targeted lockfile refresh for `brace-expansion`.
- A small reusable request-body parser wiring boundary and focused regression
  tests proving valid, oversized, and invalid-limit behavior.
- Security proof in `docs/TEST_MATRIX.md` after commands have actually run.

Out of scope:

- Major dependency upgrades, global overrides unless the lock refresh cannot
  converge within existing semver ranges, unrelated audit findings, Dependabot
  dismissal, staging deployment, production promotion, or Linear `Done`.

## Approach

1. Run a package-lock-only targeted update for `brace-expansion`; inspect the
   exact dependency-only diff and add a narrowly versioned override only if an
   existing parent range fails to converge.
2. Extract the existing JSON/URL-encoded parser registration from bootstrap
   into a small testable helper without changing the configured limit or error
   contract.
3. Add focused tests through a real Express request boundary for valid JSON and
   URL-encoded payloads, HTTP 413 on oversized bodies, and fail-closed parser
   construction for an invalid limit.
4. Run dependency-tree, advisory, focused, full backend, build, and runtime
   artifact proof. Review alternate dependency paths and the final diff.
5. Record exact results in the test matrix and Linear, then hand off the local
   changeset for review without merging or promoting protected branches.

## Risks And Recovery

- Lock refresh may update unrelated transitive packages: reject or narrow the
  diff before validation.
- Parser extraction may change middleware order: keep registration at the same
  bootstrap location and exercise both content types through HTTP.
- A local audit service/network failure may block advisory proof: keep the
  result unknown rather than inferring a pass.
- Recovery: revert only the OPS-19 worktree changes or discard the unmerged task
  worktree through the guarded lifecycle. Canonical `staging` remains
  untouched by implementation.

## Progress

- [x] Read OPS-19, advisories, dependency paths, repository guards, and existing
  request-body wiring.
- [x] Finish the prior merged task through the lifecycle gate and create the
  OPS-19 worktree from live `origin/staging`.
- [x] Record a stable clean checkpoint and affected-consumer plan.
- [x] Refresh the dependency lock and implement focused request-body proof.
- [x] Run initial ordered security closure and affected-consumer validation.
- [x] Update the test matrix with the observed local proof and residual gaps.
- [x] Rerun final proof on the complete source/test/docs fingerprint.
- [x] Update the Linear implementation/proof record.
- [x] Complete final coordinator review and hand off the changeset.

## Decisions

- 2026-07-24: Treat `body-parser@2.3.0` as inherited fixed state from staging
  PR #7; do not duplicate or downgrade that dependency change.
- 2026-07-24: Prefer the semver-compatible lock refresh over `npm audit fix
  --force` or a broad override.
- 2026-07-24: Dependabot alerts remain open until the patched staging changes
  reach the default production branch; never dismiss them to simulate closure.

## Validation

- Applicability/buildability:
  - `npm ci`
  - focused Jest for request-body parser and environment configuration
  - `npm run build`
- Security closure:
  - enumerate every lockfile copy and assert patched version floors;
  - run the consecutive-brace trigger against every installed copy with a
    bounded child-process timeout;
  - prove invalid parser limits throw before request handling;
  - `npm audit` and `npm audit --omit=dev`.
- Preserved behavior:
  - valid JSON and URL-encoded payloads succeed;
  - oversized payloads return HTTP 413;
  - full `npm test -- --runInBand`.
- Runtime artifact and repository checks:
  - production-only dependency tree;
  - Docker runtime image build when Docker is available;
  - `git diff --check` and exact final diff review.

## Result

The candidate patch updates the vulnerable 1.x copy to `1.1.16` and every
vulnerable 2.x copy to `2.1.2`; fixed 5.x copies and
`body-parser@2.3.0` are unchanged. Request-body parser registration remains at
the same bootstrap point and focused HTTP proof covers valid JSON and
URL-encoded payloads, HTTP 413 for oversized payloads, and fail-closed invalid
limits.

Validation passed focused Jest (2 suites/27 tests), Nest build, full
Jest (89 suites/869 tests), Prettier for changed TypeScript, ESLint for the new
helper/spec, dependency-tree inspection, `git diff --check`, and the
consecutive-brace trigger against all seven installed package copies
(352-429ms for 2,000 groups). Full-file ESLint on `main.ts` still reports its
pre-existing unsafe-access/floating-promise debt; the OPS-19 diff only removes
the direct Express import and replaces the two parser calls. Both npm audit
modes remain nonzero because of five unrelated Hono/Prisma, fast-uri, and sharp
findings. Docker runtime image proof is unavailable because the local Docker
daemon is not running. An exploratory large valid-option expansion exhausted a
512MB child process; this is not the GHSA consecutive non-expanding-groups
trigger, and no untrusted OpsHub glob path is proven, so it remains a recorded
residual rather than broadening this patch. Final fingerprint validation and
coordinator review passed with no additional finding: middleware order and
request-body behavior are preserved, every lockfile change is a targeted
brace-expansion patch release, and the complete source/test/docs fingerprint
passed full Jest again before publication.
