# OPS-10: Khôi phục baseline Design System cho Sales Report

## Goal

Khắc phục ba nhóm vi phạm baseline đang làm strict proof OPS-8 thất bại, nhưng
giữ thay đổi tách riêng khỏi scope Flutter web của OPS-8.

## Reproduction

Trên `origin/staging` tại `d476a80c4ae318fd7b58a318c9a17922076053a3`,
`test/design_system_migration_guard_test.dart` thất bại ở đúng ba contract:

1. Modal nhập Excel khóa thao tác đóng ngoài bằng
   `barrierDismissible: false`.
2. Sales Report dùng trực tiếp `TextButton.icon` và `Card` thay vì primitive
   dùng chung.
3. Nội dung hiển thị cho nhân viên còn viết tắt `SR` thay vì `showroom`.

## Accepted Behavior

- Modal nhập Excel đóng ngay khi chưa chọn tệp.
- Sau khi chọn một tệp hợp lệ, đóng ngoài, nút đóng và hành vi quay lại đều đi
  qua xác nhận hủy thay đổi dùng chung. Người dùng có thể tiếp tục chỉnh sửa
  hoặc thoát và hủy.
- Nhập thành công vẫn đóng modal, trả kết quả thành công và tải lại danh sách;
  không mở xác nhận hủy thay đổi.
- Nút chọn/đổi tệp dùng `AppLinkButton`; thẻ dòng cần lưu ý dùng
  `AppSurfaceCard`.
- Mọi nội dung hiển thị thuộc scope này dùng `showroom`, không lộ viết tắt
  nội bộ `SR`.
- Các nhánh chọn tệp, xem trước, nhập, lỗi và xác nhận hủy tiếp tục có log đã
  làm sạch qua `AppLogger`.

## Boundaries

- Không thay đổi API, schema dữ liệu, quyền, phân trang hoặc logic nhập Excel.
- Không sửa hay làm yếu `test/design_system_migration_guard_test.dart`.
- Không gộp thay đổi Flutter web của OPS-8 vào OPS-10.

## Changed Runtime Paths

- `lib/features/sales_report/presentation/screens/sales_report_import_dialog.dart`
- `lib/features/sales_report/presentation/screens/not_purchased_customers_screen.dart`
