# Execution Plan: OPS-33 Canonical Sales Price Contract

Date: 2026-08-01

## Status

Active

## Outcome

All eligible ERP-order revenue consumers use only the VAT-inclusive
`SalesReportErpOrderCache.grandTotal` copied from `data.orders.grandTotal`.
Missing or invalid canonical totals contribute zero revenue without removing
otherwise eligible order/report/count/item facts. Partial returns keep the full
canonical total; cancellation, full return, pending-payment, and durable
non-positive-order exclusions remain unchanged. Contract Appendix continues to
use its dedicated shipment final-sell-price contract.

## Context

- Approved product authority: Đại Ca's OPS-33 direction on 2026-08-01,
  superseding stale return-netting and report-snapshot wording.
- Product and story authority:
  `docs/product/sales-report.md`,
  `docs/stories/SALES-REPORT-001-sales-report.md`, and
  `docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md`.
- Validation authority: `docs/TEST_MATRIX.md` and focused Nest/Flutter tests.
- Checkpoint: branch `codex/ops-33-sales-price-contract`, HEAD
  `4850c4ba6b9ee8022d47c7fb6b8c7a5e8bea35da`, clean worktree at intake.
- Writer ownership: this task is the sole production/docs/test writer for the
  exact paths listed below. No overlapping writer was present at intake.

## Scope

In scope:

- Documentation:
  `docs/plans/active/OPS-33-sales-price-contract.md`,
  `docs/product/sales-report.md`,
  `docs/stories/SALES-REPORT-001-sales-report.md`,
  `docs/stories/HOME-DASHBOARD-002-sales-finance-kpis.md`, and
  `docs/TEST_MATRIX.md`.
- Canonical revenue utility and ERP ingestion:
  `backend-nest/src/sales-reports/sales-report-revenue.ts`,
  `backend-nest/src/sales-reports/sales-report-erp.service.ts`, and focused
  specs.
- Sales Report export and BigQuery:
  `backend-nest/src/sales-reports/sales-reports.service.ts`,
  `backend-nest/src/sales-reports/sales-reports-bigquery-sync.service.ts`, and
  their focused specs.
- Home KPI, progress, daily/projection metrics, and bounded projection
  regeneration:
  `backend-nest/src/home-summary/home-summary.service.ts`,
  `backend-nest/src/home-summary/home-summary-projection.service.ts`, and their
  focused specs.
- Vietnamese VAT-inclusive copy in
  `lib/features/home/presentation/widgets/home_summary_page.dart`,
  `lib/features/sales_report/presentation/screens/sales_report_screen.dart`,
  `test/home_dashboard_test.dart`, and `test/sales_report_hub_test.dart`.

Out of scope:

- Prisma schema/migration changes, destructive backfill, source-row rewrites,
  live BigQuery refresh, Looker edits, deployment, release, or production
  mutation.
- Figma, layout/redesign, permission, route, API/data-shape, ERP shipment, and
  Contract Appendix behavior changes.

## Approach

1. Update product/story/test-matrix truth before runtime changes.
2. Remove the ERP list `totalAmount` fallback and enforce safe-integer parsing
   while preserving the existing non-positive durable exclusion.
3. Batch-load canonical cache totals for Sales Report export, Home report-based
   metrics/progress, and BigQuery revenue-by-store. Preserve counts/items when
   totals are missing or invalid and emit aggregate-only quality logs.
4. Keep Home order facts and eligibility rules, remove partial-return
   subtraction, convert stored pre-VAT targets to VAT-inclusive display/compare
   values, and version projection metrics. Startup reconciliation enqueues only
   dates whose derived SALES metrics do not carry the current contract version;
   the existing projection transaction replaces derived aggregates.
5. Add additive BigQuery provenance/quality columns and safe empty-table schema
   evolution without changing captured item values.
6. Update visible Vietnamese copy and focused regression tests, then format and
   run the smallest affected-consumer proof ladder.

## Risks And Recovery

- Revenue can decrease to zero where cache totals are absent/invalid. Preserve
  order/report/item/count facts and expose aggregate missing/invalid counts so
  staging can distinguish data quality from eligibility.
- Projection aggregates created by older code can be stale. A metrics contract
  version causes bounded per-date queue regeneration through the existing
  worker; it does not rewrite ERP cache, reports, or Home source facts.
- Recovery: a source revert alone is insufficient after version-2 projection
  aggregates have been generated. Before release, provide and rehearse a gate
  that makes the rollback build regenerate every supported SALES date before it
  becomes ready. Source rows remain unchanged; no reverse source-data migration
  is permitted.
- BigQuery changes are additive. Live refresh and Looker verification remain
  staging/manual gates; no local command may mutate BigQuery.

## Compatibility

- Protected consumers: Home total/completed/pending/average KPIs, daily series,
  selected personal/scope target progress and details; Sales Report REVENUE and
  INSTALLMENT exports; BigQuery report/revenue-by-store/item facts; ERP cache
  ingestion; Contract Appendix shipment path; duplicate/count/category/
  installment consumers; compact and desktop Flutter copy.
- Preserve exact capture item price values and existing report/payment/item
  columns. Add provenance only.
- Preserve pending-payment, cancellation, full-return, non-positive order,
  permission, date/scope, and report eligibility rules.

## Progress

- [x] Confirm branch/HEAD/clean checkpoint, authority, ownership, and no
      overlapping writer.
- [x] Update product/story/test-matrix contracts.
- [x] Implement canonical ERP cache revenue across export, Home, and BigQuery.
- [x] Version and recovery-test bounded Home projection regeneration.
- [x] Add VAT-inclusive Flutter/export copy.
- [x] Add focused regression proof.
- [x] Format, validate, inspect final diff/status, and record result.
- [x] Run the serialized correctness, security/data-quality/BigQuery, current-UI
      copy, and Contract Appendix affected-consumer review wave.
- [x] Resolve final-review findings and rerun proof on the corrected fingerprint.

## Decisions

- 2026-08-01: `data.orders.grandTotal` cached in
  `SalesReportErpOrderCache.grandTotal` is the only order-revenue authority and
  is VAT-inclusive. Report snapshots, captures, shipments, item sums, and
  `totalAmount` are not revenue fallbacks.
- 2026-08-01: Stored `SalesTarget.targetBeforeTax` remains unchanged; consumers
  compare/display `round(targetBeforeTax * 1.08)` to avoid a migration/backfill
  while keeping historical zero-return percentages materially stable.
- 2026-08-01: Derived Home projection metrics are regenerated through the
  existing queue and transactional aggregate replacement, keyed by a metrics
  contract version; no source tables are rewritten.

## Final Review Checkpoint

The independent correctness, security/data-quality/BigQuery, and current-UI
reviews are resolved for the bounded local implementation. ERP detail/status
paths preserve the list-owned cache total; detail-only orders create a null
canonical value. Daily projection revenue loads cache rows by selected report
order codes. Startup recovery unions fact/aggregate dates with raw eligible
`SalesReportErpOrderCache` and `SalesReport` dates, including completed-only
dates with no derived row.

BigQuery report facts expose additive canonical gross/source/quality fields;
item capture fields keep their historical meaning. Refresh reads `maxRows + 1`,
fails before writes on truncated or unexpectedly empty sales-report snapshots,
batches 5,001 canonical lookups as 5,000 + 1, stages every table before publish,
backs up served tables, restores published tables on failure, and preserves a
recovery backup when restoration is incomplete. Changed errors use sanitized
name/message/code summaries. Home, Sales Report, progress, and export surfaces
use Vietnamese VAT-inclusive wording without technical microcopy.

Local proof does not establish true atomic multi-table BigQuery publication or
old-build rollback semantics after version-2 projection generation. Release
therefore remains gated on a populated and intentionally empty staging BigQuery
copy/rollback rehearsal, Looker field/parity review, staging projection
regeneration/rollback rehearsal, staging deploy/QA, and production release.

## Validation

- Focused proof: ERP mapping/Contract Appendix, Sales Report export, Home
  summary/projection, BigQuery mapping/schema evolution, and Flutter Home/Sales
  Report widget tests.
- Integration or end-to-end proof: local Nest focused suites and Flutter widget
  tests; live BigQuery refresh and Looker comparison are staging/manual only.
- Repository-required checks: Prettier/Dart format, Nest build when feasible,
  Flutter analyze when feasible, and `git diff --check` plus exact diff/status.

## Result

The corrected local implementation milestone is verified. ERP list ingestion
has no `totalAmount` fallback; Sales Report export, Home
facts/KPIs/progress/projections, and BigQuery revenue-by-store use the
VAT-inclusive canonical cache total and fail closed to zero without dropping
eligible counts/items. Home projection metrics carry contract version 2 and
startup enqueues stale/missing derived dates through the existing transactional
queue path. BigQuery provenance/schema additions are additive; Contract
Appendix shipment pricing and captured item facts remain isolated.

Final local proof on the corrected source/test fingerprint: five focused Nest
suites passed 206/206 tests; full Nest passed 98/98 suites and 1,083/1,083 tests;
Nest build and Prisma validate passed; Flutter Home/Sales Report passed 53/53
tests; the Contract Appendix validator passed 6/6 Nest suites (46/46 tests) and
10/10 Flutter tests; Flutter analyze found no issues; changed-file Prettier and
Dart format checks, forbidden canonical fallback/return-netting/technical-copy
searches, VAT-copy proof, and `git diff --check` passed. No Prisma
migration/backfill, BigQuery mutation, Looker edit, deployment, release, or
source-row rewrite was performed. The staging/BigQuery/Looker/release gates in
the final review checkpoint remain open.
