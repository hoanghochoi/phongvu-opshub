# OPS-9 — Thiết kế kỹ thuật

## Dòng dữ liệu

```text
MapVietinTransaction commit
  -> PostgreSQL trigger revision + sanitized DomainOutboxEvent
  -> leased worker (FOR UPDATE SKIP LOCKED)
  -> BigQuery Storage Write API default stream
  -> transactions_current view (latest revision; tombstone bị ẩn)
```

Revision tăng khi các trường báo cáo thay đổi: store, transaction number,
amount, orders/order source, status canonical, paidAt, income type, firstSeenAt
hoặc provider identifiers. Thay đổi PII/rawData và raw provider source không
liên quan không tạo event.

Sau hotfix revision canonical, các nhãn thành công tương đương của MAP/eFAST
(`Thành công`, `SUCCESS` và các alias thành công đã được nhận diện) cùng xuất
thành `SUCCESS`. `provider_source` được suy ra ổn định từ identifier đã merge;
dao động trường `rawData.source` không tự tạo revision. Thay đổi mã đơn,
statement identifier hoặc trạng thái nghiệp vụ không tương đương vẫn tạo một
revision mới.

`dedupeKey = map-vietin-bigquery:<transactionId>:<revision>` bảo đảm enqueue
idempotent và không va chạm namespace với event khác. Default stream chấp nhận
duplicate delivery ở mức transport; current view chọn revision mới nhất nên
consumer vẫn đọc một dòng hiện hành.

Backfill dùng checkpoint có upper bound `(firstSeenAt, id)` cố định. Mỗi trang chọn keyset, gọi hàm enqueue trong cùng transaction rồi cập nhật cursor; crash trước commit sẽ chạy lại trang an toàn.

## SLO và rủi ro

- Mục tiêu export lag: p50 ≤ 3s, p95 ≤ 10s, p99 ≤ 30s.
- RPO = 0 sau Postgres commit; RTO ≤ 30 phút sau BigQuery recovery.
- BigQuery/API outage chỉ làm outbox pending tăng; không chặn MAP transaction.
- Cần cảnh báo khi pending/oldest lag/dead-letter vượt ngưỡng và runbook replay riêng.
