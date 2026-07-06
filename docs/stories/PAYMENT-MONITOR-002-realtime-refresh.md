# PAYMENT-MONITOR-002 - Cập nhật Tiền vào theo realtime

## Intake

- Loại: thay đổi hành vi hiện có và tối ưu tải.
- Phạm vi: Flutter `Tiền vào`, WebSocket thanh toán và đọc loa Windows.
- Lane: normal; có thay đổi luồng đang dùng, realtime và hành vi đa nền tảng,
  nhưng không đổi API, phân quyền hay dữ liệu.

## Contract

- Khi mở màn hình hoặc đổi showroom, ngày, trang, số dòng hay bấm tải lại, app
  chủ động tải danh sách giao dịch.
- Sau đó app không poll danh sách theo timer và không tự poll khi WebSocket chỉ
  vừa reconnect.
- Khi nhận `PAYMENT_NOTIFICATION` hoặc `PAYMENT_SPEAKER_STREAM` đúng showroom,
  app debounce rồi tải lại trang hiện tại.
- Nếu `Đọc loa` khả dụng và đang bật, app xử lý âm thanh từ stream hoặc hàng đợi
  ready tương ứng với loại sự kiện. Nếu loa tắt/không khả dụng, app chỉ tải lại
  giao dịch và không poll hàng đợi ready.
- Mọi nhánh nhận event, refresh thành công/thất bại và quyết định xử lý loa phải
  có `AppLogger` với context đã sanitize.

## Proof

- Test không tạo `Timer.periodic` cho payment monitor.
- Test event có loa: refresh danh sách và đọc notification ready.
- Test event loa tắt: refresh danh sách, không tải âm thanh/ready.
- Test reconnect: socket nối lại nhưng số lần fetch giao dịch không tăng.
- Chạy focused Flutter tests, `flutter analyze --no-pub`, `git diff --check`.

## Ghi chú vận hành

Nếu WebSocket mất kết nối, danh sách giữ dữ liệu gần nhất và người dùng vẫn có
nút tải lại thủ công. Đây là chủ đích để loại bỏ tải API nền định kỳ.
