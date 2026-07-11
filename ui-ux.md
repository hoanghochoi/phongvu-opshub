# UI/UX Notes

## Shared Date Range Picker

- All date range filters must reuse the canonical shared DateRangePicker. Do not create feature-local implementations.
- Desktop uses the canonical preset-sidebar and dual-calendar dialog; mobile
  uses the canonical one-month bottom sheet. Draft changes only reach a feature
  after `Áp dụng`.
- Feature/page code must not import calendar libraries or create date-range
  picker widgets locally.

## Home Dashboard KPI

- Dropdown chọn SR/phạm vi trên Home phải dùng chung component lọc của hệ thống, ưu tiên `AppCombobox` như các màn hình báo cáo/admin. Không tự vẽ dropdown riêng bằng popup/pill nếu không có lý do sản phẩm rõ ràng.
- Title card KPI phải ngắn, đọc nhanh, tránh tiền tố thừa như `Số`, `Số lượng`, `Doanh số`, `Tổng`, `Tổng số`. Giữ phần phân loại có ý nghĩa, ví dụ `Laptop`, `Khách doanh nghiệp`, `Tiền chuyển khoản`.
- Khu vực card KPI không được trải rộng tạo khoảng trống lớn. Desktop tối đa 7 cột; nhóm ít hơn 7 card thì card tự giãn đều theo đúng số card của nhóm.
- Nếu số card vượt quá số cột tối đa, chia hàng cân bằng để tránh hàng cuối chỉ còn 1 card lẻ khi có thể cân lại, ví dụ 8 card nên thành 4 + 4.
- Mobile phải giữ tối thiểu 2 cột khi nhóm có từ 2 card trở lên, tùy độ rộng màn hình mà card tự co giãn nhưng không rơi về 1 cột cho KPI grid.
- Donut/progress card phải có slot cố định cho title, vòng donut và legend để hai donut cùng hàng không bị lệch trục do text xuống dòng.
- Legend dưới donut không được làm đổi chiều cao panel; ưu tiên một dòng, ellipsis hoặc scale-down cho phần số liệu dài.
- Section header như `Doanh số`, `KPI chính`, `Hành vi then chốt`, `Tài chính` là tên khu vực nên được giữ khi giúp người dùng scan nhanh; rule bỏ tiền tố áp dụng cho title card bên trong.
