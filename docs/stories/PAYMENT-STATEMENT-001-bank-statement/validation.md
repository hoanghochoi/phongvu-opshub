# PAYMENT-STATEMENT-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Flutter | `flutter analyze`, `flutter test` |
| NestJS | `npx prisma validate`, `npx prisma generate`, focused MAP Jest tests, `npm run build` |
| Go realtime | Not affected |
| Integration | Statement API behavior covered by service tests with Prisma mocks |
| Platform | Runtime smoke not required for this patch; Windows UI smoke remains manual |
| Release | `git diff --check` and exact diff review before handoff |

## Evidence

- 2026-07-14: eFAST statement display/export and stored VietQR confirmation
  prefer `trxId` over numeric `trxRefNo`. Focused MAP/VietQR Jest passed 110
  tests and `npm run build` passed.
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
- Full desktop click-through smoke is still manual unless run against a local
  backend and migrated database.
