# Execution Plan: OPS-27 Brace Expansion Maintenance

Date: 2026-08-10

## Status

Active

## Outcome

Refresh only the seven transitive `brace-expansion` lock entries to safe,
semver-compatible maintenance releases: `1.1.18`, `2.1.4`, and `5.0.9`.

## Source Checkpoint

- Branch: `codex/ops-27-brace-expansion-maintenance-fixes`.
- HEAD/base/live `origin/staging`:
  `c12a50a1594e3463d79967d70ba448e1aa558ada`.
- Initial worktree: clean.
- Writer ownership: this plan and `backend-nest/package-lock.json` only.

## Approach

Run a targeted package-lock-only npm refresh with lifecycle scripts, audit, and
funding output disabled. Do not change `package.json`, parent packages,
overrides, source, tests, verifiers, or unrelated lock entries.

## Protected Consumers

- Nest CLI/build and ESLint tooling.
- Jest and ts-jest test tooling.
- Prisma and TypeScript ESLint tooling.
- BigQuery Storage/google-gax, FIFO, inventory, sales, user, and MAP BigQuery
  writer/outbox flows.

## Stop And Recovery

- Stop if the source SHA changes or npm changes anything beyond this plan, the
  seven entries' `version`, `resolved`, and `integrity` fields, and the two
  5.0.9 entries' authoritative `engines.node` metadata. The root orchestrator
  accepted those two engine fields after verifying local Node 24 and all
  backend Docker stages' Node 22 target satisfy `20 || >=22`.
- Stop on unexpected parent, copy-count, major-line, or lock-structure churn.
- Recovery is deletion of this new plan plus restoration of the seven original
  lock entry fields from the recorded source checkpoint; do not reset or clean
  the worktree.

## Progress

- [x] Confirm branch, source SHA, clean worktree, ownership, and seven-copy
  baseline.
- [x] Refresh and review the lockfile.
- [x] Run initial graph and diff verification; target versions and copy counts
  pass, with two additional npm-generated `engines.node` metadata changes
  awaiting scope acceptance.
- [x] Run the approved local proof ladder and record pass/fail/blocked gates.

## Validation

- Initial proof: exact diff review, `git diff --check`, enumerate every
  `brace-expansion` entry and consumer constraint, and run
  `npm ls brace-expansion --all --package-lock-only`.
- Source fingerprint: branch `codex/ops-27-brace-expansion-maintenance-fixes`,
  HEAD/live base `c12a50a1594e3463d79967d70ba448e1aa558ada`, lock blob
  `0ef649570aa1eed6da8b7205108dbd1151528477`. The final plan blob is recorded
  externally after the final edit because a file cannot embed its own stable
  content hash.
- Exact dependency/security commands: `npm ci --no-audit --no-fund`,
  `npm ls brace-expansion --all`, `npm ls brace-expansion --omit=dev`,
  `npm audit --json`, `npm audit --omit=dev --json`, and
  `npm run verify:security-deps`.
- Exact tooling commands: non-mutating
  `eslint "{src,apps,libs,test}/**/*.ts"`, `prisma validate`,
  `prisma generate`, and `npm run build`.
- Focused Jest command:
  `npm test -- --runInBand src/map-vietin-bigquery/map-vietin-bigquery.config.spec.ts src/map-vietin-bigquery/map-vietin-bigquery-storage-writer.service.spec.ts src/map-vietin-bigquery/map-vietin-bigquery-row.mapper.spec.ts src/sales-reports/sales-reports-bigquery-sync.service.spec.ts src/support-chat/support-chat-outbox.worker.spec.ts src/fifo/opshub-fifo-inventory.service.spec.ts src/inventory/inventory.service.spec.ts src/user/user.service.spec.ts`.
- Full Jest command: `npm test -- --runInBand --silent`.
- Deterministic install: `npm ci --no-audit --no-fund` installed 944 packages;
  lock hash remained `0ef649570aa1eed6da8b7205108dbd1151528477`.
- Dependency graph: seven copies, exactly `1.1.18` (one), `2.1.4` (four),
  and `5.0.9` (two); both all-dependency and production-only `npm ls` pass.
- Audits: full graph reports 2 high and 3 moderate residuals; production-only
  reports 1 high and 3 moderate. None is `brace-expansion`. Residual packages
  are `fast-uri`, `js-yaml` (dev-only), Prisma/`@prisma/dev`, and `valibot`.
- `npm run verify:security-deps`: pass.
- Prisma validate and generate: pass. Nest build: pass.
- Focused affected-consumer proof: 8 suites and 93 tests pass for MAP BigQuery,
  Sales BigQuery, Support Chat outbox, FIFO, Inventory, and User/Google sync.
- Full Jest: 104 suites pass; 1,129 tests pass and 1 test is skipped.
- Non-mutating ESLint: baseline failure, 9,876 errors and 753 warnings across
  180 files; no lint file was modified.
- MAP BigQuery migration verifier: blocked because `DATABASE_URL` is absent.
- Broader platform-security verifier: unrelated baseline failure at Caddy API
  replica discovery (`3 !== 2`) before dependency assertions.

## Result

The lockfile-only security remediation is locally implemented and its graph,
install, build, Prisma, focused-consumer, and full-Jest gates pass. Npm also
refreshed the two 5.x entries' authoritative `engines.node` metadata from
`18 || 20 || >=22` to `20 || >=22`, compatible with local Node 24 and the
Node 22 runtime target. Keep this plan active because ESLint has broad baseline
failures, DB-backed migration proof lacks `DATABASE_URL`, the platform verifier
has an unrelated baseline failure, staging/runtime proof is not authorized in
this local-only phase, and GitHub alert #28 remains unverified through REST.
