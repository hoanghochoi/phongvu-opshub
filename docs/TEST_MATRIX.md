# Test Matrix

This file maps product behavior to proof. Existing flows are marked
`existing_unverified` until fresh validation evidence is attached.

## Status Values

| Status | Meaning |
| --- | --- |
| planned | Accepted but not implemented |
| in_progress | Actively being built |
| existing_unverified | Existing code/docs claim the behavior, but no fresh proof is attached here |
| implemented | Implemented and proof exists |
| changed | Contract changed after earlier implementation |
| retired | No longer part of the product contract |

## Matrix

| Story | Contract | Unit | Integration | E2E | Platform | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AUTH-001 | Email/password registration, sign-in, accepted Phong Vu email domains, and JWT-backed sessions for Phong Vu staff | partial | no | no | mobile smoke needed | changed | 2026-05-15: flow changed to explicit registration; validation pending in current patch |
| FIFO-001 | FIFO check, export/unexport, sort workflows against OpsHub `fifo_inventory`, manual Excel inventory import, and admin history | partial | backend unit tests | no | mobile smoke needed | changed | 2026-05-24: moved FIFO inventory ownership to OpsHub DB, added admin manual inventory Excel parser/import endpoint and UI entry; parser verified against sample file shape. 2026-05-23: added SR-scoped FIFO API and sort delegation, exported toggle contract, FIFO screen replacement for chat, and navigation cleanup; pending full live VPS smoke |
| WARRANTY-001 | Warranty/repair image capture, upload, status updates | partial | no | no | upload and WebSocket smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| FEEDBACK-001 | Staff feedback submission through app and API | partial | no | no | mobile smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| VIETQR-001 | Manual VietQR transfer QR creation screen, API payload generation with optional amount/content, persisted payment intent, MAP transaction confirmation rule, QR-screen auto confirmation polling, and confirmed transaction detail display | yes | MAP live smoke partial | no | mobile smoke needed | changed | 2026-05-21: added Vietnam-local MAP timestamp parsing, matched transaction detail persistence, and Flutter confirmed-state UI; `npx prisma generate`, `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test` |
| PAYMENT-MONITOR-001 | Backend polls configured VietinBank MAP accounts, persists successful incoming transactions, creates scoped payment audio notifications, publishes store-filtered realtime events, and Windows PC plays `ting ting` plus generated/fallback speech for every newly observed amount independent from OpsHub QR/payment intents | yes | MAP/payment notification/realtime tests | no | Windows build proof | changed | 2026-05-21: added payment notification tables/service, scoped realtime filtering, Flutter realtime notification parsing, and Windows audio asset build proof; `npx prisma generate`, `npm run build`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts src/map-vietin/map-vietin.service.spec.ts src/vietqr/vietqr.service.spec.ts src/auth/auth.service.spec.ts`, `go test ./...`, `flutter analyze`, `flutter test`, `flutter build windows --debug` |
| PROFILE-ADMIN-001 | Profile avatar, one-time branch selection, store account import, scoped MANAGER admin, MAP credential settings, and admin user/user role/store management | partial | local DB smoke | mobile smoke | Android | changed | 2026-05-20: `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test` |
| PLATFORM-001 | NestJS, Go realtime, PostgreSQL, Redis local stack health | partial | no | no | health checks needed | existing_unverified | Product docs seeded from README/code inspection |
| UPDATE-001 | Mobile clients check backend version metadata and require APK updates when server build is newer or minimum supported build is raised | yes | no | mobile smoke needed | Android | changed | Pending validation in current patch |

## Evidence Rules

- Unit proof covers pure validators, service rules, and focused repositories.
- Integration proof covers API behavior, database persistence, Redis, BigQuery,
  uploads, and auth enforcement.
- E2E proof covers user-visible app flows.
- Platform proof covers mobile runtime, Docker services, deployment, health
  checks, and WebSocket behavior.
