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
| FIFO-001 | FIFO check, export/unexport, sort workflows against OpsHub `fifo_inventory`, daily BigQuery inventory refresh, supplemental manual Excel import, and admin history | partial | backend unit tests | no | mobile smoke needed | changed | 2026-05-26: rebuilt FIFO cache contract around canonical BigQuery columns plus `opshub_*` metadata; serial check uses 20-day FIFO date tolerance, display-reserved handling, and short production labels. Manual Excel import maps the Vietnamese serial inventory export into canonical columns and stays additive. Targeted backend tests passed; pending live BigQuery env/deploy smoke and mobile smoke. 2026-05-24: manual import now preserves FIFO `import_date` priority as BigQuery date > existing DB date > file date; when no original/DB date exists, the file date is used for FIFO sorting and also stored separately in `manual_import_date`. Also moved FIFO inventory ownership to OpsHub DB and added admin manual inventory Excel parser/import endpoint and UI entry; parser verified against sample file shape. 2026-05-23: added SR-scoped FIFO API and sort delegation, exported toggle contract, FIFO screen replacement for chat, and navigation cleanup; pending full live VPS smoke |
| WARRANTY-001 | Warranty/repair image capture, upload, status updates | partial | no | no | upload and WebSocket smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| FEEDBACK-001 | Staff feedback submission through app and API | partial | no | no | mobile smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| VIETQR-001 | Manual VietQR transfer QR creation screen, API payload generation with optional amount/content, persisted payment intent, MAP transaction confirmation rule, QR-screen auto confirmation polling, and confirmed transaction detail display | yes | MAP live smoke partial | no | mobile smoke needed | changed | 2026-05-21: added Vietnam-local MAP timestamp parsing, matched transaction detail persistence, and Flutter confirmed-state UI; `npx prisma generate`, `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test` |
| PAYMENT-MONITOR-001 | Backend polls configured VietinBank MAP accounts, persists successful incoming transactions, creates scoped payment audio notifications, publishes store-filtered realtime events, and Windows PC plays `ting ting` plus generated/fallback speech for every newly observed amount independent from OpsHub QR/payment intents | yes | MAP/payment notification/realtime tests | no | Windows build proof | changed | 2026-05-26: payment notification TTS now reads `Phong Vũ đã nhận: <amount> đồng` through VieNEU voice id `custom:suong-vo` (`Suong Vo`) at speed `0.98` and pitch `1.00`. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `git diff --check`. 2026-05-26: mute toggle now disables speaker only while transaction sync continues; muted notifications are acknowledged as `SILENCED` so they are not replayed later, and the payment monitor screen shows sync loading in a separate stable chip. Validation: `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts`, `npm run build`, `flutter analyze`, `flutter test`, `git diff --check`. 2026-05-21: added payment notification tables/service, scoped realtime filtering, Flutter realtime notification parsing, and Windows audio asset build proof; `npx prisma generate`, `npm run build`, `npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts src/map-vietin/map-vietin.service.spec.ts src/vietqr/vietqr.service.spec.ts src/auth/auth.service.spec.ts`, `go test ./...`, `flutter analyze`, `flutter test`, `flutter build windows --debug` |
| PROFILE-ADMIN-001 | Profile avatar, one-time branch selection, store account import, scoped MANAGER admin, MAP credential settings, and admin user/user role/store management | partial | local DB smoke | mobile smoke | Android | changed | 2026-05-20: `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test` |
| UI-UX-001 | Android and Windows operational UI uses consistent auth density, desktop max-width layout contracts, shared form spacing, shared empty/loading/error/status states, and 16 KB Android native-library build readiness | yes | no | Windows smoke partial | Android build and Windows smoke | changed | 2026-05-25: implemented `docs/ux-ui-audit-2026-05-25.md` follow-up pass; `git diff --check`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, `zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk`, Windows debug smoke. Follow-up form/layout consistency pass normalized auth/profile/store selection/admin/FIFO/sort/warranty/feedback/VietQR/payment/chat scanner input spacing and responsive wrappers; re-ran `git diff --check`, `flutter analyze`, `flutter test`, and Windows debug smoke. Android device install was blocked by `INSTALL_FAILED_USER_RESTRICTED` without forced uninstall. |
| PLATFORM-001 | NestJS, Go realtime, PostgreSQL, Redis local stack health | partial | no | no | health checks needed | existing_unverified | Product docs seeded from README/code inspection |
| UPDATE-001 | Mobile clients check backend version metadata and require APK updates when server build is newer or minimum supported build is raised | yes | no | mobile smoke needed | Android | changed | Pending validation in current patch |

## Evidence Rules

- Unit proof covers pure validators, service rules, and focused repositories.
- Integration proof covers API behavior, database persistence, Redis, BigQuery,
  uploads, and auth enforcement.
- E2E proof covers user-visible app flows.
- Platform proof covers mobile runtime, Docker services, deployment, health
  checks, and WebSocket behavior.
