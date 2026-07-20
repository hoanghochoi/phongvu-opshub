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
