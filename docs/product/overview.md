# Product Overview

PhongVu OpsHub is an internal operations app for Phong Vu staff. It supports
daily store and warehouse workflows through a Flutter app backed by NestJS and a
Go realtime service.

## Users

- Store and warehouse staff using mobile workflows.
- Admin or operations users reviewing FIFO history.
- Backend operators deploying and maintaining services.

## Current Domains

- Auth: email/password registration and sign-in, JWT sessions, allowed Phong Vu
  staff email domains.
- FIFO: FIFO check, FIFO sorting, and history.
- Sort: SKU grouping and sorting workflow.
- Warranty: image capture/upload and repair status updates.
- Feedback: staff feedback submission.
- VietQR: manual bank-transfer QR generation for customer self-scan.
- Profile/Admin: personal profile, first-login branch selection, and user
  administration.
- Platform: NestJS API, Go realtime service, PostgreSQL, Redis, BigQuery.

## Non-Goals

- The `n8n/` folder is legacy reference material and is not part of runtime app
  behavior.
- Real `.env` files and service-account JSON must not be committed.
