# Execution Plan: OPS-20 Contract Appendix Tax Accuracy

Date: 2026-07-24

## Status

Active

## Outcome

Contract Appendix preview and save always fetch current PPM tax for every unique
order SKU without memory or Redis tax caching, use ERP `uomName` as the initial
unit, and preserve exact per-line integer-VND reconciliation through preview,
snapshot history, and Word clipboard output.

## Context

- Linear: `OPS-20`.
- Product authority: `docs/product/contract-appendix.md`.
- Story: `docs/stories/CONTRACT-APPENDIX-001-contract-appendix/`.
- Runtime: `backend-nest/src/erp/erp-ppm-product.service.ts`,
  `backend-nest/src/sales-reports/sales-report-erp.service.ts`, and
  `backend-nest/src/contract-appendices/`.
- Flutter consumers: `lib/features/contract_appendix/`.
- Checkpoint: clean lifecycle-created worktree
  `codex/ops-20-fix-contract-appendix-tax` at
  `5251fb1b10ddfde8b6b5934f78c880c8ecfe42b4`, exactly matching the live
  `origin/staging` SHA at task start.

## Scope

In scope:

- Remove PPM product-tax memory/Redis cache reads and writes while retaining the
  shared ERP login/token cache and authorized request path.
- Keep one live lookup operation per preview/save, deduplicate order SKUs, and
  preserve the provider-safe 50-SKU request chunk.
- Carry ERP `uomName` through normalized order items and use it as the initial
  Contract Appendix unit without a hard-coded value.
- Add regression proof for SKU `220909037` at 0% VAT, stale 8% followed by live
  0%, mixed 0%/8% lines, quantity greater than one, totals, snapshot, UI, and
  clipboard.
- Update product, story, environment, backend README, and test-matrix truth.
- Publish through a squash PR to `staging`, verify staging deployment and QA,
  and stop at Linear `Ready for Release`.

Out of scope:

- ERP authentication/token-cache changes.
- Contract Appendix schema/migration or history rewrites.
- Production promotion, direct push to `staging`/`main`, or Linear `Done`.

## Approach

1. Simplify `ErpPpmProductService.lookupTaxes` to live-only batches and remove
   cache configuration/types/dependencies.
2. Extend `SalesReportErpOrderItem` normalization/sanitization with `uomName`;
   consume it in Contract Appendix and reject missing unit data instead of
   inventing `Cái`.
3. Strengthen Nest calculator/service/ERP tests and Flutter preview/clipboard
   fixtures for the reported SKU and mixed tax rates.
4. Add a cross-platform affected-consumer wrapper and document path contracts.
5. Run focused, full, diff, build, and live/staging proof; update this plan with
   observed results.
6. Re-review exact scope, commit, push, open/merge a PR into `staging`, run the
   lifecycle finish gate, then verify staging deploy and QA before status change.

## Risks And Recovery

- More PPM traffic: deduplicate SKUs, retain 50-SKU provider chunks, log counts
  and duration, and keep manual-tax fallback for provider failure.
- Missing `uomName`: fail with Vietnamese action-oriented copy rather than
  silently generating a legally incorrect unit; an explicit existing override
  remains accepted when present.
- Shared ERP item shape: focused Sales Report ERP tests protect existing order
  consumers; only an additive nullable field is introduced.
- Recovery: no migration or destructive data change. Revert the task commit/PR
  to restore prior behavior; immutable saved snapshots remain readable.

## Affected Runtime Contract

Path contracts:

- `backend-nest/src/erp/erp-ppm-product.service.ts`
- `backend-nest/src/erp/erp.types.ts`
- `backend-nest/src/sales-reports/sales-report-erp.service.ts`
- `backend-nest/src/contract-appendices/**`
- `lib/features/contract_appendix/**`
- `test/contract_appendix_*_test.dart`
- `docs/product/contract-appendix.md`
- `docs/stories/CONTRACT-APPENDIX-001-contract-appendix/**`

Affected verify command:

```text
bash scripts/validate-contract-appendix.sh
```

Protected existing consumers:

- ERP shared authorization and token refresh.
- Sales Report order lookup/item normalization.
- Contract Appendix preview, save/quote conflict, history/retention, access
  guard, mobile/desktop layout, and Word HTML/TSV clipboard.

## Progress

- [x] Lifecycle start dry-run and execute passed at the checkpoint SHA.
- [x] Linear start note posted; issue moved to `In Progress` and read back.
- [x] Root cause located in preview tax caching and missing `uomName` mapping.
- [x] Implement runtime and test changes.
- [x] Run focused and full local validation.
- [ ] Publish and merge the staging PR.
- [ ] Verify staging deploy/QA and move Linear to `Ready for Release`.

## Decisions

- 2026-07-24: Deliver one full fix rather than a temporary hotfix because cache
  removal, unit mapping, and existing calculator proof are one bounded,
  reversible change with no migration.
- 2026-07-24: Preserve ERP login/token caching; disable only product-tax
  memory/Redis caching.
- 2026-07-24: Deduplicate the whole order then keep provider-safe 50-SKU chunks;
  every preview and save still performs a fresh live lookup.
- 2026-07-24: Treat absent ERP `uomName` as invalid source data unless the user
  supplied an explicit unit override; do not restore a hard-coded fallback.

## Validation

- Focused proof: `bash scripts/validate-contract-appendix.sh`.
- Integration proof: live PPM SKU `220909037` returns 0% and a real order
  preview uses ERP `uomName`; run on staging because local ERP credentials are
  currently unavailable.
- Repository-required checks: Nest build/full tests, Flutter analyze/full
  tests, `git diff --check`, exact staged diff review, PR CI, staging deploy,
  and QA smoke.

Observed local proof:

- Focused Nest: 6 suites / 43 tests passed.
- Focused Flutter: 10 tests passed.
- Nest build passed; full Nest: 89 suites / 873 tests passed.
- Flutter analyze passed; full Flutter: 611 passed / 3 skipped.
- Local live PPM was attempted but the machine has no ERP credential; staging
  live proof remains mandatory and is not inferred from fixtures.

## Result

Pending implementation and observed proof.
