# Execution Plan: OPS-52 Purchased Promotion KPIs

Date: 2026-08-09

## Status

Active

## Outcome

Home `SALES` aggregates count exam-score and student promotion KPIs only from
`PURCHASED` reports, while installment demand and no-installment reasons keep
counting both report types. Existing aggregates with a missing or stale Home
SALES KPI contract version are rebuilt through the existing projection queue.

## Context

- Product authority: `docs/product/sales-report.md`.
- Story/proof authority:
  `docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md`.
- Aggregation producer:
  `backend-nest/src/sales-reports/sales-reports.service.ts`.
- Projection consumers: Home summary live calculation plus durable
  `GLOBAL`, `STORE`, and `USER_STORE` SALES aggregates.
- Startup reconciliation and atomic replacement:
  `backend-nest/src/home-summary/home-summary-projection.service.ts`.
- Parent task approval: `Duyệt plan, implement` for OPS-52 at
  `1081c63d43e18f536820473ecce044c392c8d635`.

## Scope

In scope:

- Restrict the two promotion counters to purchased reports.
- Introduce an independent, monotonic Home SALES KPI projection contract.
- Persist both price and KPI contract versions in every rebuilt SALES metrics
  payload.
- Reconcile dates whose GLOBAL SALES aggregate is absent/stale by value or
  whose any SALES grain is missing/stale by either contract version.
- Keep sanitized startup reconciliation logs with reason and both versions.
- Update the Sales Reports reproduction, focused Home tests, PostgreSQL
  cross-grain proof, and durable product/story semantics.

Out of scope:

- Schema migrations, source-row backfills, package changes, generated files,
  Flutter UI/API shape changes, Git refs, commit, push, deploy, release.

## Approach

1. Move promotion counting behind the existing purchased-report branch while
   leaving installment counting before it.
2. Share a small Home contract constant between metrics population and the
   projection worker.
3. Persist the KPI version in the final metrics JSON and extend startup SQL to
   compare both independent versions.
4. Keep the existing single-transaction delete/reinsert/populate sequence for
   all three SALES grains.
5. Update focused tests and contracts, then run available formatting and proof.

## Risks And Recovery

- Risk: stale aggregates could retain the old KPI semantics. Mitigation:
  startup reconciliation unions existing/source dates and enqueues a date when
  any existing SALES grain has a missing or old price/KPI version; scratch
  PostgreSQL proof covers stale `STORE` and missing-version `USER_STORE` rows.
- Risk: broadening the report-type guard could alter revenue, dedupe, category,
  export, or installment behavior. Mitigation: only the two promotion counters
  move; existing purchased-only revenue/category logic and cross-type
  installment logic remain unchanged and are protected by focused tests.
- Risk: a rolling deployment could let an old worker rewrite old metrics after
  a new worker reconciles them. Mitigation: staging/production rollout must use
  one homogeneous worker source SHA (or drain old workers) before version and
  queue convergence are accepted.
- Recovery: contract versions never decrement. If the KPI semantics must be
  rolled back after release, ship the corrected semantics with a newly
  incremented Home SALES KPI contract version and let startup reconciliation
  rebuild affected dates. Do not rewrite source rows or restore stale aggregate
  JSON manually.

## Progress

- [x] Confirm branch, HEAD, dirty checkpoint, ownership, authority, and existing
      failing reproduction.
- [x] Implement purchased-only promotion counters and independent KPI version.
- [x] Update focused tests, PostgreSQL proof, and product/story contracts.
- [x] Run formatter, focused proof, PostgreSQL proof, Flutter proof, diff check,
      and ownership audit.
- [ ] Pending staging deploy and authenticated staging QA after publication.

## Decisions

- 2026-08-09: Classify as high-risk full fix because it changes an existing
  public KPI, background startup reconciliation, and upgrade-state handling.
- 2026-08-09: Start the independent Home SALES KPI contract at version `1`;
  `SALES_PRICE_CONTRACT_VERSION` remains unchanged and price-only.
- 2026-08-09: Rebuild derived aggregates through the existing queue and atomic
  replacement transaction; no migration or source-row backfill is needed.

## Validation

- Focused proof: Sales Reports reproduction plus Home Summary service and Home
  Summary projection Jest suites passed `3/3` suites and `177/177` tests.
- PostgreSQL proof suite passed `4/4`: the migration subprocess timeout invokes
  scratch cleanup, environment restoration covers initially present/absent
  `DATABASE_URL`, and an isolated migrated database independently selected four
  subordinate-grain dates for missing/stale price and missing/stale KPI versions
  while excluding the all-current control. Atomic replacement rebuilt `GLOBAL`,
  `STORE`, and `USER_STORE` with price version `2`, KPI version `1`, promotion
  counts `1/1`, installment count `2`, and the retained no-installment reason;
  the source `NOT_PURCHASED` report retained both promotion codes. The scratch
  database was dropped during teardown.
- Protected consumers: cross-type installment totals/reasons, purchased revenue
  and dedupe/category/export summaries, Home live KPI calculation, and durable
  GLOBAL/STORE/USER_STORE projection replacement.
- Flutter Home consumer passed `41/41` tests; `flutter analyze --no-pub`
  reported no issues.
- An offline lockfile-exact `npm ci` restored the checkpoint dependency tree,
  and `npx --no-install prisma generate` refreshed only the ignored local
  client. Full Nest then passed `103/103` suites with `1,122` passed tests and
  one intentional skip; all BIDV suites loaded and passed. `npm run build`
  passed. `package.json` and `package-lock.json` hashes remained unchanged.
- Changed-file Prettier passed. Final `git diff --check`, exact diff, and owned-
  path audit run after documentation closeout.
- Staging proof: pending deploy and authenticated KPI QA; not authorized in this
  implementation task.

## Result

Implementation and all required local proof are complete. Independent review
found no Blocker/High code issue; its PostgreSQL and stale-plan findings were
addressed. Publication, homogeneous-worker staging deployment, projection
convergence, authenticated CP58 QA, and production release remain pending and
are not authorized in this task.
