# OPS-9 — Đồng bộ giao dịch MAP Vietin sang BigQuery

## Phạm vi

- PostgreSQL là nguồn sự thật và vẫn ghi giao dịch trong transaction hiện hữu.
- Trigger tạo revision + `DomainOutboxEvent` sau khi transaction nguồn commit; BigQuery không nằm trên critical path.
- Worker BigQuery mặc định tắt, claim theo lease đa replica, retry có backoff/jitter và dead-letter sau số lần giới hạn.
- Backfill mặc định tắt, chụp upper bound một lần, phân trang keyset tối đa 500 dòng và enqueue cùng transaction với checkpoint.
- Payload chỉ gồm whitelist phục vụ báo cáo: mã giao dịch, revision, ngày giao dịch, showroom, statement number, số tiền, orders, trạng thái, nguồn, các mốc thời gian và tombstone.

## Ngoài phạm vi

- Không thay đổi logic tính báo cáo PC ráp hoặc luồng `sales-reports/**`.
- Không gửi `rawData`, content, payer/account, user/email/token/credential lên BigQuery.
- Không chạy DDL tự động trong runtime; provisioning là lệnh operator riêng.

## Vận hành

1. Chạy migration PostgreSQL.
2. Dùng `npm run provision:map-vietin-bigquery` với service account chỉ có quyền tạo schema/table/view và `bigquery.tables.updateData` cho writer.
3. Bật worker sau khi kiểm tra raw table/current view; backfill chỉ bật có chủ đích.
4. Theo dõi log `MAP BigQuery metrics` (pending, oldest lag, dead letters) và xử lý dead-letter trước khi replay.
