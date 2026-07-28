# Execution Plan: OPS-36 Statement Order ERP And Tracking

Date: 2026-07-28

## Status

Completed locally; publication and environment QA remain release gates.

## Outcome

Sao kê và Tiền vào dùng một thao tác `Cập nhật mã đơn` trên UI hiện tại. Backend
xác minh toàn bộ mã đơn qua ERP trước khi ghi, cho phép thay/xóa mã cũ chỉ trong
ngày phát sinh khi mọi mã cũ đã `CANCELLED` hoặc `RETURNED_FULL`, và tự hoàn tất
endpoint compatibility cũ mà không tạo yêu cầu chờ Kế toán mới. Kế toán và
Super Admin có thể Bỏ/Theo dõi lại giao dịch trong đúng scope showroom. Tracking
status được phản ánh nhất quán qua API, filter, Home, XLSX và BigQuery.

## Context

- Linear: OPS-36, related to OPS-6.
- Product authority: explicit approved conversation for ERP lifecycle, same-day
  replacement/deletion, compatibility behavior, tracking permissions and KPI.
- UI authority: explicit direction to reuse the existing Sao kê/Tiền vào UI;
  Figma/redesign is out of scope and not a gate.
- Product and story truth: `docs/product/vietqr.md`,
  `docs/stories/PAYMENT-STATEMENT-001-bank-statement/`.
- Runtime producers: `backend-nest/src/map-vietin/`, Prisma schema/migrations,
  `backend-nest/src/sales-reports/sales-report-erp.service.ts`.
- Protected consumers: Bank Statement, Payment Monitor, Home summary/projection,
  order-transfer history/review, realtime compatibility, XLSX export and
  Map Vietin BigQuery current view/backfill.
- Checkpoint: branch `codex/ops-36-statement-order-erp-unfollow`, HEAD
  `f1c898492ace48ec9fac455d0b51d2e28ad83628`, clean worktree, created from the
  matching live `origin/staging` through `scripts/task-lifecycle.mjs start`.
- Existing reliability, showroom-scoped tenancy, SLO/RPO/RTO and deployment
  topology remain unchanged. This feature handles internal financial data and
  PII; logs must contain counts/summaries only, never order codes or ERP payloads.

## Scope

In scope:

- Add `FOLLOWING`/`UNFOLLOWED`, update metadata and a dedicated tracking audit;
  backfill current transactions to `FOLLOWING`.
- Add a scoped, authorized tracking PATCH endpoint with pending-request blocker,
  idempotency and audit.
- Centralize order mutation so PATCH and the compatibility POST use the same ERP
  validation, date guard, optimistic concurrency and atomic persistence.
- Preserve legacy pending requests for review/reject/expiry; compatibility POST
  creates an `APPROVED` request and no pending notification.
- Keep one update action on current Bank Statement and Payment Monitor widgets,
  including loading/error/no-op/delete behavior and tracking controls/status.
- Apply tracking semantics to statement filters, Home KPI/rate, XLSX and
  BigQuery schema v2/current view/backfill.
- Update product contract, story, test matrix and this plan with executable proof.

Out of scope:

- Any visual redesign, new route, Figma implementation or shared design-system
  change.
- Removing legacy pending review/history/realtime handling.
- Changing ERP token/cache behavior, organization topology, release process,
  production data manually or deployment infrastructure.
- Commit, push, PR, staging deploy or production promotion without separate
  explicit authority.

## Approach

1. Extend Prisma and add a reversible migration for tracking metadata/audit,
   indexes and idempotent `FOLLOWING` backfill.
2. Import `SalesReportsModule` in MAP and add one ERP-validated mutation pipeline:
   normalize/no-op first; snapshot transaction/pending/tracking; validate old/new
   lifecycle outside the DB transaction; atomically recheck snapshot and write
   transaction, order audit and optional approved compatibility request.
3. Keep existing legacy review flow only for pre-deploy `PENDING` records. Add
   tracking endpoint/DTO/controller, permissions and Vietnamese user-facing errors.
4. Make filter/XLSX/Home projection and legacy Home fallback tracking-aware.
5. Add `order_tracking_status` to the BigQuery row contract, DDL/current view and
   a schema-v2 payload migration that enqueues an idempotent snapshot backfill.
6. Adapt existing Flutter models/repositories/providers/widgets: retain the current
   editor/dialog/layout, expose one update action, allow blank input only for an
   already-mapped transaction, and add Bỏ/Theo dõi lại controls without redesign.
7. Update focused regression tests and contract docs, then run the validation
   ladder. Recompute/rerun affected proof if HEAD or participating files change.

## Risks And Recovery

- ERP latency or partial failures could cause incorrect writes. Mitigation:
  fail-closed all lookups, validate every code outside the transaction, log only
  lifecycle counts and duration, and write nothing unless all results pass.
- A concurrent update after ERP validation could apply stale evidence. Mitigation:
  compare `updatedAt`, orders, pending state and tracking status inside one DB
  transaction; surface an action-oriented reload/retry error on conflict.
- Trigger/view drift could break BigQuery. Mitigation: add the nullable warehouse
  column before schema-v2 events, update mapper/current view together, test row
  shape, and retain the column on rollback for compatibility.
- Tracking semantics could skew existing Home metrics/filter results. Mitigation:
  explicitly preserve total count/amount across all rows and limit only order KPIs
  and non-ALL order filters to `FOLLOWING`; protect both projection and fallback.
- Recovery before publication: revert only OPS-36 patches in the task worktree or
  remove the isolated task worktree/branch through the lifecycle gate. Database
  rollback preserves a nullable BigQuery column and restores old payload functions;
  no production migration is run by this task.

## Progress

- [x] Create/update OPS-36 and record approved UI-baseline decision.
- [x] Establish clean lifecycle checkpoint and isolated task worktree.
- [x] Inspect product/story, current MAP/ERP/Home/BigQuery/Flutter surfaces.
- [x] Add Prisma schema, migration and tracking/order-mutation backend tests.
- [x] Implement ERP-validated atomic update and compatibility behavior.
- [x] Implement tracking API/filter/Home/XLSX/BigQuery semantics.
- [x] Consolidate existing Flutter actions and add tracking behavior/tests.
- [x] Update product/story/test matrix and complete executable validation.
- [x] Record exact implementation/proof on OPS-36 and read it back.

## Decisions

- 2026-07-28: Reuse the existing UI and do not wait for or implement Figma.
- 2026-07-28: A no-op returns the current transaction without ERP calls, writes,
  audit rows or compatibility requests.
- 2026-07-28: ERP lookup is outside the DB transaction; optimistic concurrency and
  all writes are inside one transaction.
- 2026-07-28: `ALL` includes every tracking status. Other order-status filters and
  order KPIs use only `FOLLOWING`; total statement amount/count stay inclusive.
- 2026-07-28: Existing `PENDING` records retain the legacy workflow. New compatibility
  POST calls are persisted immediately as `APPROVED` with ERP resolution and no
  pending notification.

## Validation

- Focused backend: MAP lifecycle/no-op/date/race/authorization/compatibility/
  tracking/XLSX passed `140/140`; Home service/projection and BigQuery mapper
  stayed green in the full run.
- Backend integration: Prisma validate/generate, `npm run build`, and full Jest
  passed `90 suites / 918 tests`.
- Flutter: affected Bank Statement/Payment Monitor/design guard batch passed
  `119/119`; `flutter analyze --no-pub` reported no issues; full Flutter passed
  `635` with `3` skips and no failures.
- BigQuery/migration: DDL tests passed `3/3`; disposable PostgreSQL verified the
  idempotent 5,000-row schema-v2 backfill, observed write-lock behavior,
  tracking revision, dedupe, tombstone, monotonic tracking rollback and layered
  rollback in `977 ms`.
- Protected consumers verified: Sao kê, Tiền vào, Home legacy and projection,
  legacy pending review/history, filter/XLSX, realtime compatibility, and
  BigQuery schema-v2/current-view/backfill.
- Final `git diff --check` passed; no-index whitespace checks for the untracked
  migration, rollback, plan and repository test reported no whitespace errors.
  Generated l10n/plugin files were confirmed byte-equivalent to the index and
  removed from the dirty scope without staging content changes.

## Result

Implementation and local executable proof are complete. The feature remains
unpublished: no commit, push, PR, staging deploy, device/browser QA, live ERP
smoke, or production migration was performed. Proof was recorded on OPS-36 and
read back while the issue remained `In Progress`. The next release step is to
publish through a reviewed PR to `staging` when explicitly authorized.
