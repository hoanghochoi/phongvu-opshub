# PAYMENT-MONITOR-002 - Cập nhật Tiền vào theo realtime

## Intake

- Loại: thay đổi hành vi hiện có và tối ưu tải.
- Phạm vi: Flutter `Tiền vào`, WebSocket thanh toán và đọc loa Windows.
- Lane: normal; có thay đổi luồng đang dùng, realtime và hành vi đa nền tảng,
  nhưng không đổi API, phân quyền hay dữ liệu.

## Contract

- Khi mở màn hình hoặc đổi showroom, ngày, trang, số dòng hay bấm tải lại, app
  chủ động tải danh sách giao dịch.
- Sau đó app không poll danh sách giao dịch theo timer. Khi WebSocket handshake
  thành công hoặc im lặng quá lâu, app chỉ drain hàng đợi ready cho đường đọc
  loa nếu `Đọc loa` đang khả dụng và bật.
- Khi nhận `PAYMENT_NOTIFICATION` hoặc `PAYMENT_SPEAKER_STREAM` đúng showroom,
  app debounce rồi tải lại trang hiện tại.
- Nếu `Đọc loa` khả dụng và đang bật, app xử lý âm thanh từ stream hoặc hàng đợi
  ready tương ứng với loại sự kiện, đồng thời có fallback ready-notification nhẹ
  mỗi 5 giây sau khi realtime im lặng để bù WebSocket miss. Fallback chỉ nhận
  notification trong recovery window 30 giây; `/ready` và `/stream` cùng chặn
  cả audio `PENDING` lẫn `READY` đã cũ để client khác không phát lại muộn. Nếu
  loa tắt/không khả dụng, app chỉ tải lại giao dịch và không poll hàng đợi ready.
- Mọi nhánh nhận event, refresh thành công/thất bại và quyết định xử lý loa phải
  có `AppLogger` với context đã sanitize.

## Proof

- Test chỉ tạo timer fallback cho hàng đợi loa, không tạo timer poll danh sách
  giao dịch.
- Test event có loa: refresh danh sách và đọc notification ready.
- Test event loa tắt: refresh danh sách, không tải âm thanh/ready.
- Test reconnect/fallback: socket nối lại hoặc realtime im lặng không làm tăng
  số lần fetch danh sách, nhưng vẫn drain được ready backlog cho loa.
- Test freshness/metric: notification `READY` cũ không được client khác phát lại;
  latency trung bình chỉ dùng lần `STREAM_STARTED` đầu tiên của notification.
- Chạy focused Flutter tests, `flutter analyze --no-pub`, `git diff --check`.

## Ghi chú vận hành

Nếu WebSocket mất kết nối, danh sách giữ dữ liệu gần nhất và người dùng vẫn có
nút tải lại thủ công. Đường đọc loa có fallback `/payment-notifications/ready`
nhẹ để bù missed event mà không khôi phục tải API nền định kỳ cho danh sách.
