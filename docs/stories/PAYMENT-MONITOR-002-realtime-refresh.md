# PAYMENT-MONITOR-002 - Cập nhật Tiền vào theo realtime

## Intake

- Loại: thay đổi hành vi hiện có và tối ưu tải.
- Phạm vi: Flutter `Tiền vào`, WebSocket thanh toán và đọc loa Windows.
- Lane: normal; có thay đổi luồng đang dùng, realtime và hành vi đa nền tảng,
  nhưng không đổi API, phân quyền hay dữ liệu.

## Contract

- Khi mở màn hình hoặc đổi showroom, ngày, trang, số dòng hay bấm tải lại, app
  chủ động tải danh sách giao dịch.
- Khi chuyển sang route khác trong lúc app vẫn foreground, provider giữ cache
  danh sách và tiếp tục lắng nghe realtime; không dừng monitor hoặc xoá dữ liệu
  đang hiển thị. Khi app xuống background, cache vẫn được giữ nhưng app không
  phát sinh request mới cho đến khi foreground trở lại.
- Sau đó app không poll danh sách giao dịch theo timer. Khi WebSocket handshake
  thành công hoặc im lặng quá lâu, app chỉ drain hàng đợi ready cho đường đọc
  loa nếu `Đọc loa` đang khả dụng và bật.
- Khi nhận `PAYMENT_NOTIFICATION` hoặc `PAYMENT_SPEAKER_STREAM` đúng một trong
  các showroom thuộc scope danh sách hiện tại, app debounce rồi tải lại trang
  hiện tại đúng một lần, kể cả khi user đang xem route khác. Event ngoài scope
  bị bỏ qua và không tạo request danh sách.
- Nếu `Đọc loa` khả dụng và đang bật, app xử lý âm thanh từ stream hoặc hàng đợi
  ready tương ứng với loại sự kiện, đồng thời có fallback ready-notification nhẹ
  mỗi 5 giây sau khi realtime im lặng để bù WebSocket miss. Fallback chỉ nhận
  notification trong recovery window 30 giây; `/ready` và `/stream` cùng chặn
  cả audio `PENDING` lẫn `READY` đã cũ để client khác không phát lại muộn. Nếu
  loa tắt/không khả dụng, app chỉ tải lại giao dịch và không poll hàng đợi ready.
- Event stream có `playbackMode=LOCAL_ASSET`, `currency=VND` và đúng
  `assetPackVersion` sẽ ghép asset Piper cài sẵn trước, claim nhẹ trên server
  rồi phát; đường thành công không tải audio và không gọi TTS. Thiếu/hỏng/lệch
  version hoặc kill switch tắt phải quay về stream audio hiện tại.
- Mọi nhánh nhận event, refresh thành công/thất bại và quyết định xử lý loa phải
  có `AppLogger` với context đã sanitize.
- Cooldown 429 được quản lý theo `HTTP method + path`, bỏ query string. Mỗi chu
  kỳ cooldown có đúng một ticket bypass cho thao tác trực tiếp: tải lại, đổi
  ngày/showroom/filter/page, mở lịch sử hoặc thao tác đơn hàng. Background,
  polling và realtime không bao giờ bypass.
- Nếu request bypass tiếp tục nhận 429, ticket vẫn được xem là đã dùng và
  `Retry-After` mới thay thời hạn cũ. Request thành công hoặc cooldown hết hạn
  mới reset chu kỳ. Nhiều thao tác khi request đang chạy được coalesce thành
  một request nhưng vẫn giữ nguồn user-initiated; đổi showroom không được biến
  lại thành `initial_load`.
- Option `allowRateLimitCooldownBypass` đi từ `ApiClient` qua repository tới
  provider và mặc định `false`, nên mọi call site chưa opt-in vẫn an toàn. Log
  chỉ ghi `activated`, `deferred`, `bypassed`, `expired`, `recovered` cùng
  method/path an toàn; không ghi query, token hay payload.

## Proof

- Test chỉ tạo timer fallback cho hàng đợi loa, không tạo timer poll danh sách
  giao dịch.
- Test event có loa: refresh danh sách và đọc notification ready.
- Test event loa tắt: refresh danh sách, không tải âm thanh/ready.
- Test đổi route khi loa tắt: giữ cache, không poll danh sách theo thời gian và
  chỉ refresh đúng một lần sau event realtime đúng showroom.
- Test scope nhiều showroom: event của showroom được phân công refresh danh
  sách; event ngoài scope không tạo request.
- Test app background: giữ cache và bỏ qua event cho đến khi foreground trở
  lại; không tạo request nền.
- Test reconnect/fallback: socket nối lại hoặc realtime im lặng không làm tăng
  số lần fetch danh sách, nhưng vẫn drain được ready backlog cho loa.
- Test freshness/metric: notification `READY` cũ không được client khác phát lại;
  latency trung bình chỉ dùng lần `STREAM_STARTED` đầu tiên của notification.
- Test cooldown: chỉ bypass một lần, 429 sau bypass không cấp ticket mới,
  success/expiry reset, endpoint isolation, queued user action giữ quyền bypass,
  background/realtime không bypass và đổi showroom vẫn giữ nguồn user action.
- Staging manual: làm đầy bucket cùng staging staff/IP, để app nhận 429 rồi bấm
  tải lại hai lần; API log đã sanitize phải thấy đúng một bypass request và lần
  hai bị chặn local. Tắt loa để không chạy đường ready/audio trong proof này.
- Chạy focused Flutter tests, `flutter analyze --no-pub`, `git diff --check`.

## Ghi chú vận hành

Nếu WebSocket mất kết nối, danh sách giữ dữ liệu gần nhất và người dùng vẫn có
nút tải lại thủ công. Đường đọc loa có fallback `/payment-notifications/ready`
nhẹ để bù missed event mà không khôi phục tải API nền định kỳ cho danh sách.
