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

- 2026-05-29: `npx prisma validate` passed.
- 2026-05-29: `npx prisma generate` passed and generated Prisma Client
  v7.8.0.
- 2026-05-29: `npm test -- --runInBand src/map-vietin/map-vietin.service.spec.ts`
  passed 23 tests.
- 2026-05-29: `npm run build` passed.
- 2026-05-29: `flutter analyze --no-pub` passed with no issues.
- 2026-05-29: `flutter test --no-pub --reporter expanded` passed all 33
  tests, including bank statement model/provider coverage.

## Unverified Risk

- Live VietinBank MAP payload variants may include fields not covered by local
  fixtures.
- Full desktop click-through smoke is still manual unless run against a local
  backend and migrated database.
