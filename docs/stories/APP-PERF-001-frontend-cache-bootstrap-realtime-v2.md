# APP-PERF-001: Frontend cache, bootstrap và realtime v2 dùng chung

## Story

Nhân viên mở lại OpsHub cần thấy ngay chức năng và dữ liệu gần nhất đã tải,
trong khi ứng dụng chỉ gọi API khi dữ liệu thực sự hết hạn, bị invalidation hoặc
người dùng chủ động tải lại. Một lỗi mạng tạm thời không được làm menu biến mất,
không được xóa nội dung đang xem và không được tạo vòng lặp retry/polling.

## Intake

- Loại: maintenance và thay đổi hành vi hiện có.
- Lane: high-risk.
- Cờ rủi ro: auth, authorization, public contract, Redis/realtime,
  cross-platform, existing behavior, multi-domain và weak fleet-wide proof.
- Checkpoint trước triển khai: `staging` tại
  `1b174205d179f4de0f6f9ec57cbdfc35e2315203`, worktree sạch.

## Contract

### Bootstrap và quyền

- `GET /auth/bootstrap` gộp profile, feature access và policy access trong một
  response có `schemaVersion`, `generatedAt`, stable `version` và capability.
- Endpoint phát `ETag`, dùng `Cache-Control: private, no-cache`, chấp nhận
  `If-None-Match` và trả `304` khi snapshot không đổi.
- Flutter lưu last-known-good snapshot theo environment + user, không lưu JWT
  trong snapshot. Snapshot chỉ được thay sau response hợp lệ đầy đủ.
- Saved-session startup hydrate snapshot trước, rồi conditional refresh nền.
  Lỗi khác `401` giữ snapshot và hiển thị trạng thái chưa đồng bộ; `401` xóa
  session/cache và yêu cầu đăng nhập lại.
- Client chỉ fallback `/auth/get-user`, `/features/me`, `/policies/me` khi server
  cũ trả `404` hoặc `501`, không fan-out ba request sau lỗi mạng/`5xx`.
- Backend API/guard luôn là nguồn quyền cuối cùng. Cache chỉ điều khiển khả năng
  hiển thị và perceived performance.
- `resolveFeatureAccessMap()` không seed/upsert feature definitions trên mỗi
  request. Seed vẫn chạy khi module khởi động hoặc qua luồng quản trị cần thiết.
- Snapshot user thiếu secure token, hoặc token thiếu snapshot user, bị xóa như
  phiên mồ côi và không được dựng shell/menu đã đăng nhập.

### Query cache

- Query key gồm environment, user/session scope, endpoint và normalized params.
- Cache-aside hỗ trợ fresh/stale metadata, keyed in-flight dedupe, optional
  persistence, conditional GET và tag invalidation.
- Persistent cache chỉ dùng cho bootstrap/quyền, scope/options, Quick Actions,
  Home snapshot nhỏ, notification count, delivery metrics, Help và app version.
- Giao dịch, khách hàng, notification rows, warranty/admin lists và dữ liệu tài
  chính chi tiết chỉ cache trong RAM của phiên.
- Background failure giữ dữ liệu cũ với timestamp và retry backoff; manual retry
  được phép bypass cooldown một lần. Không tự retry `4xx` ngoài `429`.

### Lifecycle và request budget

- Provider constructor không gọi API nghiệp vụ.
- Home chỉ active tại `/home`; payment list chỉ active tại route Tiền vào;
  warranty và sales-report realtime chỉ active tại route liên quan.
- Windows speaker là service riêng, chỉ global khi thiết bị hỗ trợ, có quyền,
  người dùng bật loa và đang chọn đúng một showroom.
- Background dừng timer/retry không bắt buộc. Resume coalesce tối đa một refresh
  cho mỗi query tag.
- Quick Actions giữ contract cache 24 giờ/7 ngày hiện tại.

### Realtime v2

- Một authenticated `/ws/v2` cho mỗi session mang các topic Home, access,
  notifications, payment, warranty và sales-report. Public app-update socket
  vẫn tách riêng để hoạt động khi chưa đăng nhập.
- Gateway lọc audience, không forward audience và fail closed khi event nhạy
  cảm thiếu scope hợp lệ.
- Policy toàn phạm vi dùng namespace `policyCodes` riêng, không trộn vào mã tổ
  chức/phòng ban/showroom để tránh trùng chuỗi làm mở rộng audience.
- `ACCESS_CHANGED` yêu cầu đúng cặp kind/topic, chỉ gửi đúng recipient rồi đóng
  socket đó để ticket mới nhận claims mới; socket không liên quan vẫn giữ kết
  nối. Audience chỉ có feature code không đủ điều kiện routing.
- Event ưu tiên version/id/affected scope để invalidate cache; HTTP vẫn là
  nguồn dữ liệu đầy đủ. Payment speaker chỉ mang metadata tối thiểu cần phát.
- Legacy `/ws` được giữ hai release; bootstrap chỉ quảng bá v2 topic đã sẵn sàng.

### UX trạng thái

- Có cache: render ngay, refresh nền không khóa nội dung.
- Không cache và load quá 300 ms: dùng skeleton đúng hình nội dung.
- Cached/stale data luôn có thời điểm cập nhật và action `Thử lại`.
- Permission refresh lỗi hiển thị:
  `Đang dùng quyền đã lưu. Chưa đồng bộ được thay đổi mới.`
- Không hiển thị HTTP, role/policy/feature code, stack trace hoặc raw payload.

## Cache policy

| Dữ liệu | Storage | Fresh TTL | Invalidation |
| --- | --- | ---: | --- |
| Auth/quyền | persistent | 15 phút | startup, resume, access event |
| Home scopes | persistent | 24 giờ | scope/permission change |
| Home summary | snapshot nhỏ + memory | 60 giây | filter, route, realtime |
| Quick Actions | existing persistent | 24 giờ/7 ngày | TTL, admin save |
| Notification count | persistent | 15 phút | realtime, resume |
| Notification rows | memory | 5 phút | open inbox, realtime |
| Delivery metrics | persistent snapshot | 5 phút | realtime, fallback 15 phút |
| Finance/admin/customer rows | memory | 30-60 giây | route/filter/mutation |
| Help/app version | persistent + ETag | 24 giờ | conditional GET |

## Acceptance

- Saved-session startup với snapshot hợp lệ thực hiện tối đa một conditional
  bootstrap trước dữ liệu của route đang active.
- Menu được giữ khi bootstrap lỗi mạng/`5xx`; UI có warning và retry. `401` vẫn
  đăng xuất đúng contract.
- Nhiều consumer cùng query key tạo đúng một HTTP request.
- Không gọi transaction-list API trước khi mở Tiền vào.
- Không còn delivery-metrics polling mỗi phút; fallback tối thiểu 15 phút chỉ
  khi foreground và chip thực sự active.
- Home realtime coalesce burst, chỉ refresh range giao nhau, inactive route chỉ
  đánh dấu dirty và refresh một lần khi quay lại.
- Client mở một authenticated v2 socket thay vì socket riêng theo feature.
- AppLogger có start/success/failure/cache-hit/dedupe/invalidation/backoff với
  context đã sanitize.
- UI light/dark/mobile/desktop giữ AppShell, tokens, accessibility và copy
  tiếng Việt hiện có.

## Request reduction target

Baseline từ một local Windows log 24 giờ, không đại diện toàn fleet:

- Payment delivery metrics: 769 load starts.
- Home summary: 467 load starts.
- Home realtime-triggered refresh: 426 starts.

Sau cùng workload tương đương, mục tiêu là giảm ít nhất 80% delivery-metrics
requests và 60% Home realtime-triggered GET, đồng thời không còn retry storm.

## Proof

- Local: changed Dart files qua formatter; `flutter analyze --no-pub` sạch;
  full `flutter test --no-pub --reporter compact` pass 520 test, 2 skip có chủ
  đích. Bao phủ cache, bootstrap/304/fallback/401, orphan session, auth race,
  lifecycle, coalescing và cùng-user revoke.
- Local: changed Nest files qua Prettier; `npm run build` pass; full Jest pass
  69/69 suite, 672/672 test. Bao phủ bootstrap/ETag, feed aggregate, publish
  access, policy namespace và topology invalidation.
- Local: `go test -count=1 ./...`, `go vet ./...` và `git diff --check` pass;
  audience fail-closed, selected-store narrowing, Redis resync và recipient
  disconnect đều có regression test.
- Chưa chạy Windows/Android/Web UI smoke, staging runtime/request counter hoặc
  production compatibility. Baseline 769/467/426 và mục tiêu giảm request chỉ
  được xác nhận sau workload staging tương đương, không suy ra từ unit test.

## Rollout

1. Query-cache foundation và auth bootstrap.
2. Route/lifecycle gating, metrics cadence và payment speaker separation.
3. Migrate authenticated events sang v2, giữ server legacy hai release.
4. Conditional GET cho các read endpoint còn lại.
5. Staging request/runtime proof trước main/production.
