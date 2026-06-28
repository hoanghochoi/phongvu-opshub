# Báo cáo Sale Contract

## Intent

Sale ghi nhận hành vi tư vấn và kết quả mua/chưa mua ngay trong OpsHub, thay
cho Google Form, đồng thời lưu dữ liệu đủ chuẩn để dashboard dùng lại.

## Current Shape

- Home hiển thị ô `Báo cáo` khi user có feature `SALES_REPORT`.
- Màn hình `Báo cáo` có 2 luồng: `Mua hàng` và `Chưa mua hàng`.
- `Mua hàng` bắt buộc nhập `Mã đơn hàng` và bấm `Kiểm tra đơn hàng` trước khi
  mở phần form còn lại. Backend kiểm tra ERP thật qua server, rồi submit vẫn
  re-check ERP trước khi lưu.
- `orderCode` là unique trên bảng `SalesReport`; một đơn mua hàng chỉ được báo
  cáo một lần.
- Không có field nhập `MSNV`; backend lấy user, email, tên, mã nhân viên suy ra,
  showroom và organization node từ token/user hiện tại.
- `ADMIN_SALES_REPORTS` được gán bằng feature theo node tổ chức. Super Admin có
  quyền toàn app theo feature resolver hiện tại.

## Data Contract

- `SalesReport` lưu report type, hành vi tư vấn/trải nghiệm/Zalo/App, lý do
  chưa mua, category snapshot, reporter snapshot, showroom/org snapshot, trạng
  thái/tổng tiền đơn ERP và sanitized ERP snapshot.
- `SalesReportOrderItem` và `SalesReportPayment` tách riêng để dashboard lọc,
  nhóm và xuất dữ liệu.
- `SalesReportCategoryGroup` đồng bộ từ `data/categories.csv`, dùng `Cat group
  ID` làm code, `Cat group name` làm tên gốc và `catGroupNameVi` làm nhãn tiếng
  Việt.
- Snapshot report lưu cả code, tên gốc và tên Việt để dữ liệu lịch sử không bị
  lệch nếu CSV đổi sau này.

## Expected Proof

- Backend: Prisma validate/generate, Nest build, tests cho category sync,
  duplicate `orderCode`, purchased re-check ERP, not-purchased no ERP call,
  feature guard và export CSV.
- Flutter: Home/Admin entry theo feature, route guard, order check before submit,
  auto-fill category/need từ mock ERP, không gửi `MSNV`, form validation và
  export CSV.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
