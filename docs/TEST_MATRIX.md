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
| FIFO-001 | FIFO check, sort workflows, and admin history | partial | no | no | mobile smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| WARRANTY-001 | Warranty/repair image capture, upload, status updates | partial | no | no | upload and WebSocket smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| FEEDBACK-001 | Staff feedback submission through app and API | partial | no | no | mobile smoke needed | existing_unverified | Product docs seeded from README/code inspection |
| VIETQR-001 | Manual VietQR transfer QR creation screen and API payload generation | yes | no | no | mobile smoke needed | implemented | 2026-05-09: `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test` |
| PROFILE-ADMIN-001 | Profile avatar, one-time branch selection, store account import, and admin user/user role/store management | partial | local DB smoke | mobile smoke | Android | changed | 2026-05-16: `npm run build`, `npm test -- --runInBand`, `flutter analyze`, `flutter test`; Android smoke verified admin menu, store list, create/update/delete refresh flow |
| PLATFORM-001 | NestJS, Go realtime, PostgreSQL, Redis local stack health | partial | no | no | health checks needed | existing_unverified | Product docs seeded from README/code inspection |
| UPDATE-001 | Mobile clients check backend version metadata and require APK updates when server build is newer or minimum supported build is raised | yes | no | mobile smoke needed | Android | changed | Pending validation in current patch |

## Evidence Rules

- Unit proof covers pure validators, service rules, and focused repositories.
- Integration proof covers API behavior, database persistence, Redis, BigQuery,
  uploads, and auth enforcement.
- E2E proof covers user-visible app flows.
- Platform proof covers mobile runtime, Docker services, deployment, health
  checks, and WebSocket behavior.
