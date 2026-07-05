# UI-UX-002: Nhóm điều hướng và toast góc trên phải

## Story

Nhân viên cần nhìn menu theo đúng miền nghiệp vụ và nhận thông báo ngắn gọn mà
không bị một thanh full-width che phần dưới màn hình.

## Acceptance

- `Quản trị` nằm trong `Tổng quan`; không còn destination FIFO tổng hợp.
- `Danh sách báo cáo sale`, `Cập nhật tồn kho` và `Lịch sử FIFO` nằm trong màn
  hình `Quản trị`.
- Sidebar và màn hình `Vận hành` dùng cùng cấu trúc:
  - Bán hàng: VietQR -> Báo cáo sale -> Tiền vào.
  - Kho: Kiểm tra FIFO -> Sắp xếp FIFO.
  - Tài chính: Sao kê -> Cấn trừ.
  - Kỹ thuật: Bảo hành.
- Menu vẫn lọc theo feature hiện có và cuộn được khi chiều cao cửa sổ ngắn.
- Mọi thông báo tạm thời dùng toast chữ nhật nổi ở góc trên phải, cách mép 16px,
  rộng tối đa 360px và giữ màu/nội dung/thời lượng hiện có.
- Có kiểm thử source guard để không tái sử dụng `showSnackBar` trong `lib/`.

## Proof Target

- Focused navigation, Operations, Admin, route viewport và toast widget tests.
- Full Flutter regression, `flutter analyze --no-pub`, `git diff --check`.
