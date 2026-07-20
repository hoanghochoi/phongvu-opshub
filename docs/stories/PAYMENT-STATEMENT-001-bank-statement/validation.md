# PAYMENT-STATEMENT-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Flutter | `flutter analyze`, `flutter test` |
| NestJS | `npx prisma validate`, `npx prisma generate`, focused MAP Jest tests, `npm run build` |
| Go realtime | Not affected |
| Integration | Statement service behavior plus controller headers and streamed XLSX bytes |
| Platform | Production API health, authenticated XLSX download/parse, eFAST scheduler counters, and post-remap database counts |
| Release | `git diff --check` and exact diff review before handoff |

## Evidence

- 2026-07-20 TNG/visibility correction: compact content beginning with `TNG`
  classifies as `PARTNER_INTERNAL` without showroom or suffix matching. The
  regression fixtures cover `TNG CP69`, `TNG CP55`, `TNG-CP57`, spaced `T N G`
  and the provider normalization path. List, global lookup, selected export and
  income-type editing expose partner/internal rows only to users belonging to
  `FIN_ACC`; non-FIN all-scope and `SUPER_ADMIN` fixtures remain `SALES`-only.
  The backfill migration updates only `incomeTypeSource=AUTO`. Prisma
  generate/validate passed, focused income-type/MAP Jest passed 145 tests, full
  Nest regression passed 81 suites / 811 tests, Nest build passed, the protected
  Payment Monitor/Bank Statement/VietQR Flutter consumers passed 72 tests, and
  Flutter analyze reported no issues. The migration has not been applied to a
  runtime in this local-commit-only change.
- 2026-07-20 XLSX transport hotfix: production logs matched the reported
  07:40 export and showed the workbook service completing successfully. The
  controller was returning a Node `Buffer` directly, which the Nest Express
  adapter serializes through `response.json`; the endpoint now returns a
  `StreamableFile`, matching the existing Sales Report export contract. A new
  controller regression verifies MIME/disposition headers and unchanged `PK`
  workbook bytes. Focused MAP/controller Jest passed 111 tests, the full Nest
  regression passed 81 suites / 804 tests, Nest build passed, and the protected
  Payment Monitor/Bank Statement/VietQR Flutter consumers passed 72 tests.
  Production API image `sha256:27fe835c...` is healthy. An authenticated live
  export returned the XLSX MIME type, 540,952 bytes, ZIP magic `504b0304`, and
  one parseable `Sao ke` worksheet without exporting row contents off-host.
  The first API start encountered a PostgreSQL deadlock and Docker restarted it
  once; the second start completed, health stayed green, and no fatal log was
  observed afterward. No database migration or client release was involved.

- 2026-07-19 local implementation: Sao kê no longer adds a `SALES` query
  restriction for SR users. The classifier and migration share the compact
  whitespace-insensitive content and payer-account rules. FIN_ACC/protected
  administrators can update the pill and the `MANUAL` source protects the
  choice from subsequent syncs. Prisma generate/validate passed, focused
  income-type/MAP Jest passed 138 tests, full Nest regression passed 80 suites /
  803 tests, and Nest build passed. Focused Bank Statement provider/screen tests
  passed 37 tests, `flutter analyze --no-pub` passed, and full Flutter passed
  569 tests with 3 platform skips. Production deployment remains
  a separate gate.
- 2026-07-18 reliability regression: focused MAP Jest passed 106 tests,
  `npm run build` passed, bank-statement provider tests passed 29 tests,
  bank-statement widget tests passed 7 tests, and `flutter analyze --no-pub`
  reported no issues. Coverage proves `MANUAL` and `OFFSET` survive sync,
  identifier-less MAP/eFAST duplicates are rejected in either arrival order
  and concurrent persistence is serialized before the fingerprint check,
  invalid `YYMMDD` keeps the inline editor open with the exact cause, and keyed
  card state follows the transaction when the list reorders.
  Full Nest regression also passed 80 suites / 780 tests. Full Flutter reached
  562 passed and 3 skipped with one unrelated design-system guard failure:
  `web visual smoke routes stay aligned with AppRouter` expects the gap-map
  document to contain `39 authenticated shell routes`; this patch changes
  neither the router nor that document.
- 2026-07-18 production repair: the checkpoint contains 70 JSONL rows across
  transactions, audits, notifications, delivery logs, transfer requests, and
  read receipts, with a verified SHA-256 manifest. Runtime diagnosis found six
  exact cross-source duplicate pairs. The transaction moved 13 delivery logs
  and one audit to the retained MAP rows, deleted six duplicate notifications
  and six eFAST transactions, then restored seven overwritten `AUTO` rows to
  the latest approved `OFFSET` audit. Immediate post-check returned
  `cross_dups=0`, all deleted-row/reference counts `0`, `offset_ok=7`, and one
  remaining CP61 row for the reported 9,146,000 VND transaction. The prevention
  patch is local only and is not production release proof.
- 2026-07-17: runtime production diagnosis confirmed LO account
  `118002647006` was uniquely configured but all 207 unassigned eFAST rows seen
  after that assignment still had `storeCode=null` because ingestion only read
  empty `pmtId`. Local regression coverage now proves source-account fallback,
  sync-time repair, organization-tree account-change remap, and preservation of
  the null-store review path when no account maps. Focused MAP/User Jest passed
  162 tests.
- 2026-07-17 production hotfix proof: the pre-change checkpoint captured 210
  matching `storeCode=null` rows. The scheduler remapped all 210 to LO; the
  post-change database count is `NULL=0`, `LO=210`, while the existing CP68 and
  CP75 assignments remain one row each. The first live sync reported
  `sourceAccountMapped=17`, `accountRemapped=210`, `quarantined=0`; the next
  sync reported `accountRemapped=0`, `quarantined=0`. The API container is
  healthy. The exact production-release patch passed 155 focused MAP/User Jest
  tests and `npm run build` before deployment.
- 2026-07-14: eFAST statement display/export and stored VietQR confirmation
  prefer `trxId` over numeric `trxRefNo`. Focused MAP/VietQR Jest passed 110
  tests and `npm run build` passed.
- 2026-07-17: income-type classifier tests cover the supplied BC, So GD goc,
  ShopeePay, Nhat Tin, GHTK, VNPAY and sales `CT DEN` examples. Focused MAP and
  income-type Jest passed; XLSX export tests verify `Loại giao dịch`, `Tài khoản
  nhận`, long identifiers and Vietnam-local timestamps. Flutter provider/screen
  tests verify model parsing and mobile filter collapse after search; Flutter
  analyze passed after removing compatibility deprecation notices.
- 2026-05-29: `npx prisma validate` passed.
- 2026-05-29: `npx prisma generate` passed and generated Prisma Client
  v7.8.0.
- 2026-05-29: `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`
  passed 23 tests.
- 2026-05-29: `npm run build` passed.
- 2026-05-29: `flutter analyze --no-pub` passed with no issues.
- 2026-05-29: `flutter test --no-pub --reporter expanded` passed all 34
  tests, including bank statement model/provider coverage.
- 2026-05-29: `npx prisma migrate deploy` applied the backfill migration on
  local Postgres; a seeded old MAP transaction was backfilled to
  `orders=[26052911111111,26053022222222]` with `orderSource=AUTO` while
  duplicate, invalid-date, and overlong numeric strings were ignored.

## Unverified Risk

- Live VietinBank MAP payload variants may include fields not covered by local
  fixtures.
- The 2026-07-19 visibility hotfix and income migration/backfill have not yet
  been proved on production; the managed shell is blocked from reaching the
  production SSH endpoint before authentication. Production rollout still
  requires migration, API health, query visibility, and sync-preservation proof.
- Full desktop click-through smoke is still manual unless run against a local
  backend and migrated database.
