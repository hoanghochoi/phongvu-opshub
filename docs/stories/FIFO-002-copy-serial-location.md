# FIFO-002: Sao chép serial và vị trí

## Story

Nhân viên kiểm tra FIFO cần lấy nhanh serial và vị trí lưu kho từ kết quả để
dán sang công cụ vận hành khác mà không phải nhập lại thủ công.

## Acceptance

- Chip serial và vị trí trong kết quả Kiểm tra FIFO nhận click chuột, touch và
  thao tác bàn phím trên các nền tảng Flutter.
- Chip tương tác có biểu tượng copy, tooltip và semantics mô tả đúng dữ liệu.
- Copy thành công hiện `Đã sao chép serial.` hoặc `Đã sao chép vị trí.` qua
  floating toast dùng chung.
- Copy thất bại hiển thị hướng dẫn thử lại bằng tiếng Việt.
- Luồng ghi `AppLogger` khi bắt đầu, thành công và thất bại; log chỉ chứa loại
  field, inventory id, độ dài giá trị và thời gian, không ghi raw serial/vị trí.
- SKU, ngày nhập và zone vẫn là metadata không tương tác.

## Proof Target

- Widget test xác nhận clipboard nhận đúng serial và vị trí khi tap chip.
- `flutter analyze --no-pub`.
- `git diff --check` và rà exact diff.
