# HOME-DASHBOARD-003: Home near-realtime bằng projection bền vững

## Story

Nhân viên đang mở Trang chủ cần thấy KPI mới trong vài giây sau khi dữ liệu đã
được ghi vào OpsHub, trong khi API vẫn phản hồi ổn định khi xem 1, 7, 30 hoặc 90
ngày và không làm chậm transaction nghiệp vụ.

## Lane

High-risk: thay đổi data model, migration, scheduler, API contract, Redis,
WebSocket và Flutter lifecycle trên nhiều runtime.

## Acceptance

- Dữ liệu nguồn và outbox được ghi cùng transaction hoặc cùng transaction của
  từng chunk; projection không chạy đồng bộ trong transaction nguồn.
- Worker poll outbox mỗi giây, dùng `NOTIFY` làm wake-up hint, coalesce cùng
  grain trong 500 ms/tối đa hai giây; riêng burst MAP debounce hai giây/tối đa
  năm giây và không rebuild cùng grain song song.
- MAP sync dùng fingerprint cache RAM có TTL/LRU giới hạn để loại payload lặp
  trước DB; cache miss vẫn so sánh no-op trước `upsert`. Trigger projection bỏ
  qua UPDATE không đổi ngày/showroom/số tiền/danh sách đơn.
- Daily aggregate có grain `GLOBAL`, `STORE`, `USER_STORE`; chỉ lưu metric cộng
  dồn. Phần trăm/rate được tính khi đọc.
- `GET /home/summary` giữ toàn bộ DTO KPI hiện tại và thêm `freshness` gồm
  `projectionGeneratedAt`, `projectionLagSeconds`,
  `sourceUpdatedAtBySource`, `isStale`.
- Projection trễ hơn 15 giây vẫn trả bản hoàn chỉnh gần nhất với trạng thái
  stale. Chưa có bản hoàn chỉnh trả HTTP 503 với thông báo tiếng Việt; GET
  không rebuild đồng bộ.
- `/ws/v2` dùng ticket xác thực hiện tại và phát `HOME_SUMMARY_UPDATED` chỉ có
  `affectedDates` cùng `projectionVersion`, không chứa KPI hoặc dữ liệu nhạy
  cảm.
- Flutter dùng một `RealtimeConnectionManager` tối thiểu cho Home, loại event
  trùng/out-of-order, debounce 500 ms và chỉ gọi lại API khi ngày đang xem giao
  với `affectedDates`.
- `HomeSummaryRepository.summaryFreshTtl` là nguồn TTL duy nhất, cố định 60
  giây cho cả repository cache và route revalidation. Quay lại Home trước 60
  giây không gọi HTTP; tại hoặc sau 60 giây chỉ có một revalidation được
  deduplicate.
- Mất kết nối không làm Home polling liên tục. Reconnect và app resume chỉ
  force-network một lần để tự chữa missed event. Realtime invalidation vẫn là
  cơ chế chính; không thêm timer polling.
- Nếu revalidation lỗi, Home giữ snapshot stale cùng `fetchedAt` gốc. Lần route
  activation đủ điều kiện kế tiếp phải thử lại, không được kéo dài tuổi cache
  giả bằng thời điểm lỗi.
- API 429 trả `Retry-After` chuẩn; Flutter giữ cooldown theo method/endpoint,
  còn MAP server tôn trọng `Retry-After` của provider nên request đang bị giới
  hạn không tiếp tục tạo tải mạng.
- Backfill ERP tối đa 90 ngày có checkpoint/resume, page size 50, một worker,
  delay một giây, retry 2/4/8/16/30 giây và upsert idempotent.
- Reconciliation rà hôm nay mỗi phút, bảy ngày gần nhất mỗi giờ và chín mươi
  ngày gần nhất mỗi đêm.
- `/home/summary/details/v2` dùng keyset cursor, mặc định 50/tối đa 100; endpoint
  cũ được giữ hai release. Fact table và legacy Home path được giữ sau feature
  flag trong một release.
- Log có start/success/failure, source commit time, queue delay, rebuild duration,
  grain count, projection lag và publish result; không log payload nguồn.

## SLO

- DB commit đến projection complete: p95 không quá 5 giây, p99 không quá 15
  giây.
- Commit nội bộ đến Home repaint: p95 không quá 7 giây.
- MAP đến Home: p95 không quá 10 giây trong khung đồng bộ nhanh.
- ERP/eFAST đến Home: p95 không quá 70 giây trong khung đồng bộ nhanh.
- Home API: p95 không quá 500 ms, p99 không quá một giây, max không quá ba giây.

## Local Implementation Proof

- Prisma format/validate/generate và Nest build đã chạy thành công.
- Migration chain đã được deploy vào database tạm, tạo đủ 5 bảng, 3 source
  trigger, 2 hot-path partial index và seed `90/90/90`; `rollback.sql` đã dọn
  sạch database tạm. Staging database chưa được thay đổi.
- 42 Jest test tập trung đã pass cho projection/outbox, retry, reconciliation,
  stale/503, details v2, ERP offset và checkpoint resume.
- 31 Go test, 24 Flutter Home/realtime test và full Flutter suite 458 test đã
  pass; `flutter analyze` không có lỗi.
- Load gate 250 concurrent/2.000 request, burst 5.000 source row, parity
  1/7/30/90 ngày và RAM host vẫn phải chạy trên staging trước rollout.

## Proof Target

- Prisma validate/generate; migration up/down trên staging; schema analyzer và
  index optimizer không còn lỗi nghiêm trọng.
- Jest cho outbox claim/retry, queue coalescing, projection parity, freshness,
  stale/503, details v2 và checkpoint resume; Nest build/full test.
- Go test cho `/ws/v2`, auth ticket, audience, event envelope và Redis-loss
  close/resync behavior.
- Flutter analyze/test cho manager lifecycle, reconnect/resume, dedupe,
  out-of-order, date overlap, debounce, TTL 59/60 giây, stale fallback giữ
  `fetchedAt` gốc, realtime ưu tiên và freshness parse/render.
- Load proof riêng sau staging: 250 request đồng thời/2.000 request tổng, burst
  5.000 source row, KPI parity 1/7/30/90 ngày và RAM host dưới 20 GB.

## Deferred Follow-up

- Phase 2: một authenticated socket mỗi platform session, gateway index theo
  audience, tách API/worker và Redis control/realtime, distributed limits.
- Phase 3: chat 1-1/group trên PostgreSQL sequence + outbox + object storage.
- Phase 4: meeting qua `MeetingMediaProvider`; media đi client đến SFU/TURN.
