# PAYMENT-STATEMENT-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Flutter | `flutter analyze`, `flutter test` |
| NestJS | `npx prisma validate`, `npx prisma generate`, focused MAP Jest tests, `npm run build` |
| Go realtime | Not affected |
| Integration | Statement API behavior covered by service tests with Prisma mocks |
| Platform | Production API health, eFAST scheduler counters, and post-remap database counts |
| Release | `git diff --check` and exact diff review before handoff |

## Evidence

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
- The income migration and backfill have not been applied to production in this
  turn; production rollout still requires the normal staging/migration proof.
- Full desktop click-through smoke is still manual unless run against a local
  backend and migrated database.
