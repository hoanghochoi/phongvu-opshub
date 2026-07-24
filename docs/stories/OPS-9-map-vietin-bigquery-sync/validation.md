# OPS-9 — Bằng chứng kiểm thử

## Tự động

- `npx prisma validate --schema prisma/schema.prisma`
- `npm run test -- --runInBand map-vietin-bigquery`
- `node scripts/map-vietin-bigquery-schema.test.mjs`
- `npm run verify:migration:map-vietin-bigquery` (scratch PostgreSQL; tạo và xoá database kiểm thử)
- `npm run build`

## Ma trận hành vi

| Hành vi | Bằng chứng |
| --- | --- |
| Worker tắt mặc định | config spec; không khởi tạo BigQuery client |
| Claim đa replica + lease | worker SQL có `FOR UPDATE SKIP LOCKED`, event type filter, token/lease guard |
| Partial row errors | request có row error được coi là reject toàn batch; appender loại row lỗi, append lại phần hợp lệ rồi worker mới ack/retry riêng từng event |
| PII/rawData không export | mapper whitelist + migration verifier kiểm tra payload keys |
| Replay MAP/eFAST tương đương | scratch migration verifier đổi qua lại `Thành công`/`SUCCESS` và MAP/eFAST 100 lần nhưng giữ nguyên revision/event count |
| Mã đơn/statement identifier thay đổi | scratch migration verifier chứng minh orders và eFAST identifier enrichment tạo đúng một revision mới |
| Backfill restart-safe | checkpoint upper bound/keyset và enqueue/checkpoint cùng transaction |
| Delete | tombstone revision `is_deleted=true`; current view lọc tombstone |
| Rollback | migration verifier chạy rollback.sql và kiểm tra function/column/table |

## Known gaps

Integration append thật cần service account/staging BigQuery và không chạy trong CI mặc định. Cần staging soak để đo lag p95/p99 trước khi bật production.

## Evidence 2026-07-23

- Prisma schema validate: PASS.
- Focused worker + protected MAP consumers: PASS, 5 suites / 128 tests.
- BigQuery table/current-view DDL: PASS, 2 tests.
- Scratch PostgreSQL migration: PASS cho insert, PII-only update không tạo
  revision, order revision, dedupe, tombstone, transaction rollback và
  rollback.sql.
- Nest build và `git diff --check`: PASS.

## Hotfix revision storm 2026-07-24

- Production inspection found the worker disabled and a rapidly growing pending
  outbox caused by equivalent MAP/eFAST status/source representations.
- The hotfix uses a new forward migration; it does not edit the migration that
  production already applied.
- Scratch PostgreSQL verifier PASS: insert/outbox atomicity; 100 alternating
  MAP/eFAST replays kept one revision/event; eFAST identifier enrichment,
  orders and a non-equivalent status each created exactly one revision;
  PII-only update stayed ignored; tombstone, transaction rollback and hotfix +
  base migration rollback all passed.
- Prisma validation PASS; BigQuery DDL 2/2; focused BigQuery 3 suites/6 tests;
  affected backend consumers 15 suites/298 tests; full Nest 89 suites/869 tests;
  Nest build PASS.
- Protected Flutter consumers for Bank Statement, Payment Monitor, VietQR and
  Home passed 53 tests; `flutter analyze --no-pub` reported no issues.
- Existing production backlog is intentionally not modified by this hotfix.
