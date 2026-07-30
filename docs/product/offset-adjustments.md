# Offset Adjustments

OpsHub exposes a dedicated `Cấn trừ` flow for SR-submitted correction requests
that must be reviewed by ACC before being treated as complete.

## Contract

- Staff opens `Cấn trừ` from the home feature list only when the
  `OFFSET_ADJUSTMENTS` feature is enabled for the user's direct organization
  node group. A policy may control capability or data scope inside the feature,
  but it cannot reopen a disabled feature.
- The `Cấn trừ` screen starts directly with the create-action row, filter card,
  and list; it no longer shows the former header card titled `Yêu cầu xử lý`.
- SR users create and edit only their own showroom requests. ACC, FIN_ACC, and
  SUPER_ADMIN reviewers can view requests across SRs, filter by SR, and review
  submitted requests. ACC/FIN_ACC can be resolved from either the user's
  department code or their assigned organization-tree ancestors.
- The main list keeps `Tất cả ngày` as the empty date-filter label, but when
  the user leaves the date range empty the query/export defaults to the latest
  30 days and the UI shows a small helper note about that fallback. When a
  custom range is selected it filters by `submittedAt`, uses server-side
  paging, and sorts newest first.
- The list supports filters for SR, type, old/new/order code, exact amount, and
  status. Reviewer SR filtering supports selecting multiple SRs or leaving the
  selection empty for all visible SRs.
- Reviewers see pending confirmation notifications through the shared global
  notification bell. Submitting SR users see their own rejected requests in the
  same bell with the rejection reason and a clear prompt to reopen `Cấn trừ` and
  resubmit. There is no separate bell icon on the `Cấn trừ` screen. Opening
  notifications must not mutate the main list filters.
- Reviewers can export the current filtered list to CSV from `Xuất file`,
  either for all offset types or for one selected type.
- Row borders follow the statement color contract: green for ACC-approved,
  red for waiting ACC review, and yellow for rejected requests waiting for SR
  correction.
- Each row shows a type tag. `Cấn trừ đơn` rows also show a count chip for how
  many visible requests reuse the same old order code, independent of the
  current filters.
- Tapping a row opens a detail dialog. Review actions are visible only to
  reviewers. Reject requires a reason; VNPAY QROFF completion requires ACC to
  enter `Mã CT`.
- Rejected requests notify the submitting SR through the offset realtime event.
  After SR resubmits, reviewers receive the same offset realtime event and can
  confirm again.
- ERP orders are not required to belong to the same showroom as the Offset
  request. The request showroom remains the OpsHub authorization/reporting
  scope, while the ERP selling channel is recorded from the order lookup.
  The list/detail/CSV surfaces label both `Kênh bán` (ERP, per referenced
  order) and `Kênh tạo hồ sơ` (`Cấn trừ trên OpsHub`) so the two sources are
  not conflated.

## Request Types

- `Cấn trừ đơn`: old order, new order, amount, and optional note. Saving is
  blocked when old and new order codes are the same.
- `VNPAY QROFF`: order, QR scan date, edit-content kind, transaction code, and
  amount. Order code and transaction code must be unique within VNPAY QROFF.
  ACC must enter `Mã CT` when completing the request.
- `Zalo Pay`: order, Zalo Pay scan date, edit-content kind, transaction code,
  and amount. Order code and transaction code must be unique within Zalo Pay.
- `Shopee Pay`: order, Shopee Pay scan date, edit-content kind, transaction
  code, and amount. Order code and transaction code must be unique within
  Shopee Pay.

## ERP Validation On Save

- The backend validates ERP only when SR creates a request or resubmits a
  rejected request. Reviewer completion does not repeat the ERP lookup.
- Cheap local validation and duplicate checks run before ERP. If ERP cannot
  prove the required order state or value, create/resubmit fails closed and
  writes no request, history, or realtime event.
- `Cấn trừ đơn` requires the old order to be `CANCELLED` or
  `COMPLETED_PARTIAL_RETURN`. The new order must be `PENDING`, `COMPLETED`, or
  `COMPLETED_PARTIAL_RETURN`, must expose `grandTotal`, and the offset amount
  must be less than or equal to that value.
- `VNPAY QROFF`, `Zalo Pay`, and `Shopee Pay` require an existing order with a
  verified `grandTotal`; their lifecycle does not otherwise restrict saving.
  The offset amount must be less than or equal to the order value.
- Missing orders, unverified lifecycle, missing order value, ERP timeout/error,
  and an over-limit amount return Vietnamese, action-oriented errors without
  exposing ERP codes or payloads.
- ERP lookup is not showroom-filtered by the request showroom. When ERP
  returns an order consultant email, it is retained as a sanitized owner
  fallback for the existing Sales Report order-to-SR mapping path; no raw ERP
  payload is stored or logged.
- Create/resubmit and their history row commit atomically. Resubmit also guards
  the rejected status and `updatedAt` snapshot after the ERP wait. Realtime is
  published only after commit; a Redis failure is logged and does not turn a
  committed request into a false user-facing failure.

## Batch Completion

- ACC, FIN_ACC, and Super Admin reviewers may select up to 100 unique eligible
  requests across pages of the same query. Changing the query/filter or a
  realtime resync clears selection; select-all affects eligible rows on the
  current page only.
- Only `PENDING_ACC` requests outside `VNPAY_QROFF` are eligible. VNPAY remains
  an individual completion because it requires `Mã CT`; the UI explains this
  on its disabled checkbox.
- `POST /offset-adjustments/batch-complete` is scoped to the reviewer's visible
  showrooms and is atomic. Missing, out-of-scope, stale, non-pending, or VNPAY
  input rolls back the whole batch.
- Selected rows are locked in canonical ID order before mutation. Stale,
  serialization, or deadlock conflicts return Vietnamese reload guidance rather
  than exposing database errors.
- Every successful request keeps the existing reviewer metadata, history, and
  realtime event shape. Success clears selection and refreshes the page and
  pending count; failure retains selection so the reviewer can correct it.

## Realtime Isolation

- Offset adjustments publish to Redis channel `OFFSET_ADJUSTMENT_UPDATED` and
  WebSocket event type `OFFSET_ADJUSTMENT_NOTIFICATION`.
- Offset adjustment payloads must not reuse `PAYMENT_NOTIFICATION_READY`,
  `PAYMENT_NOTIFICATION`, `/payment-notifications/ready`, `/audio`, or `/ack`.
- Go realtime keeps the existing payment notification branch filtered by
  `storeCode`. Offset notifications use a separate branch: reviewers can
  receive all selected SRs, while SR users receive only their own showroom.
- The first implementation shares the existing Redis connection because offset
  events are lightweight. If load smoke shows payment speaker impact, the
  offset publisher/subscriber can move to a separate Redis connection through
  `OFFSET_REDIS_URL` or `OFFSET_REDIS_HOST/PORT`.

## Out Of Scope V1

- OS push notifications.
- Delete or cancel requests.
- File attachments.
- Editing an ACC-approved request.
