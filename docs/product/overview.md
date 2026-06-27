# Product Overview

PhongVu OpsHub is an internal operations app for Phong Vũ staff. It supports
daily store and warehouse workflows through a Flutter app backed by NestJS and a
Go realtime service.

## Users

- Store and warehouse staff using mobile workflows.
- Admin or operations users reviewing FIFO history.
- Backend operators deploying and maintaining services.

## Current Domains

- Auth: email/password registration and sign-in, JWT sessions, allowed Phong Vũ
  staff email domains.
- FIFO: FIFO check, FIFO sorting, and history.
- Sort: SKU grouping and sorting workflow.
- Warranty: image capture/upload and repair status updates.
- Góp ý: staff suggestions and issue reports from the final Home action.
- VietQR/MAP payments: manual bank-transfer QR generation, incoming payment
  monitor, and bank statement reconciliation for MAP transactions that may not
  include an order code in the transfer content.
- Profile/Admin: personal profile, admin-assigned organization nodes, and user
  administration.
- Settings: client-side preferences such as Windows startup behavior.
- Support: Home header exposes the Seatalk support group QR and invite link for
  staff help without requiring a feature permission.
- Staff help: public `/help` page exposes Markdown-authored usage guidance and
  roadmap content with images; `/download` and the Home side menu link to it.
- Client diagnostics: authenticated clients upload a sanitized previous-day
  activity summary once per day for operational debugging. The upload uses the
  existing app-log pipeline and does not include the raw log file.
- Platform: NestJS API, Go realtime service, PostgreSQL, Redis, BigQuery, and
  Windows release distribution.

## Non-Goals

- The `n8n/` folder is legacy reference material and is not part of runtime app
  behavior.
- Real `.env` files and service-account JSON must not be committed.
