# OPS-9 — Thiết kế kỹ thuật

## Dòng dữ liệu

```text
MapVietinTransaction commit
  -> PostgreSQL trigger revision + sanitized DomainOutboxEvent
  -> leased worker (FOR UPDATE SKIP LOCKED)
  -> BigQuery Storage Write API default stream
  -> transactions_current view (latest revision; tombstone bị ẩn)
```

Revision tăng khi các trường báo cáo thay đổi: store, transaction number, amount, orders/order source, status, paidAt, income type, firstSeenAt hoặc provider identifiers/source. Thay đổi PII/rawData không liên quan không tạo event.

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
