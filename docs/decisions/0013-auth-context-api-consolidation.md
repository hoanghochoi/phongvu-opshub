# Quyết định: hợp nhất resolver auth và cache scope dùng chung

## Trạng thái

accepted — 2026-07-16

## Bối cảnh

`/auth/bootstrap`, `/auth/me`, các route feature/policy compatibility,
`/auth/realtime-ticket` và `/home/summary/scopes` trước đây có thể hydrate cùng
một user, assignment và organization tree nhiều lần trong một phiên. Policy
rules còn bị đọc theo từng policy, làm tăng query PostgreSQL và CPU Node khi
nhiều replica cùng phục vụ startup/Home.

## Quyết định

- Giữ các public route cũ để không phá client; `/auth/bootstrap` là route chuẩn
  cho client mới.
- Hợp nhất phần hydrate nội bộ vào `AuthContextService`, cache theo toàn bộ
  version tuple `userId + tokenVersion + sessionVersion + accessVersion`.
- Dùng L1 process cache, Redis shared cache và lease/in-flight deduplication.
  Redis entry khác version không bao giờ được dùng làm fallback.
- `/auth/bootstrap` chạy ETag preflight trước resolver; `/auth/me`,
  `/auth/get-user`, `/features/me` và `/policies/me` đọc projection từ context.
- Batch policy definitions/rules và dùng organization tree cache; scope snapshot
  chỉ select trường cần thiết, không lưu password/token vào Redis.
- Giữ `/auth/realtime-ticket` và `/home/summary/scopes` là route riêng do khác
  semantics, payload và TTL; cả hai vẫn dùng context chung.
- Tăng `User.accessVersion` sau mutation quyền/topology thành công và publish
  invalidation sau commit.

## Rollout và rollback

Bật theo feature flag từng lớp: schema/context → auth routes → batch/tree →
shared Redis scopes → load/profile. Kill-switch quay về resolver cũ hoặc
process-local cache nếu Redis, error rate hoặc latency vượt ngưỡng. Chỉ chạy
ladder 25 → 50 → 100 QPS sau functional/integration proof.

## Hệ quả và kiểm chứng

Response contract public không đổi, nhưng startup có thể giảm hydrate/query
trùng lặp. Cần staging proof cho multi-replica cache hit, Redis outage,
invalidation, query/request, p95/p99, CPU Node và top PostgreSQL queries trước
khi kết luận đạt SLO.

## Atomic access-version invariant

`User.accessVersion` is incremented by PostgreSQL triggers in the same
transaction as permission, platform-session or organization-topology mutations. Recipient
lookup and `ACCESS_CHANGED` publication run only after commit; the publisher
does not perform a second out-of-transaction bump.

## Phụ lục contract bootstrap sau sự cố production 2026-07-17

- `user` trong `/auth/bootstrap` là snapshot tự chứa và bắt buộc có `id` cùng
  `email` lấy từ authenticated principal; profile compatibility không được ghi
  đè hai trường identity này.
- Client chỉ dùng email của saved session làm fallback khi response cũ thiếu
  email. Nếu response trả một email khác session hiện tại, client từ chối vì
  contract/identity mismatch.
- `304 Not Modified` chỉ hợp lệ khi client đang có access snapshot đã được đánh
  dấu `accessResolved=true`; nếu không, client retry một lần không có ETag.
- Compatibility refresh được dùng cho `404/501` hoặc response bootstrap `2xx`
  sai contract khi chưa có snapshot dùng được. `401` vẫn xóa session;
  network/`5xx` với snapshot hợp lệ giữ bản cũ ở trạng thái stale để tránh
  khuếch đại tải bằng ba request fallback.
