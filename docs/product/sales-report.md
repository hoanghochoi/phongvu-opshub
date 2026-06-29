# Báo cáo Sale Contract

## Intent

Sale ghi nhận hành vi tư vấn và kết quả mua/chưa mua ngay trong OpsHub, thay
cho Google Form, đồng thời lưu dữ liệu đủ chuẩn để dashboard dùng lại.

## Current Shape

- Home hiển thị ô `Báo cáo` khi user có feature `SALES_REPORT` hoặc
  `ADMIN_SALES_REPORTS`.
- Màn hình `Báo cáo` có 2 luồng gửi `Mua hàng` và `Chưa mua hàng` khi user có
  `SALES_REPORT`.
- Màn hình `Báo cáo` hiển thị lối vào `Báo cáo sale` để xem danh sách và xuất
  CSV khi user có `ADMIN_SALES_REPORTS`; entry này không nằm trong menu
  `Quản trị`.
- `Mua hàng` bắt buộc nhập hoặc quét QR/barcode `Mã đơn hàng` và bấm
  `Kiểm tra đơn hàng` trước khi mở phần form còn lại. Sau khi đã kiểm tra, sale
  có nút `Kiểm tra đơn khác` để nhập/quét lại đơn mới. Backend kiểm tra ERP
  thật qua server, rồi submit vẫn re-check ERP trước khi lưu.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng về form.
- ERP/Listing chỉ được tự điền ngành hàng khi map được về nhóm ngành OpsHub:
  ưu tiên `productGroup.code` từ Listing khớp `Cat group ID` trong
  `data/categories.csv`, rồi mới dùng tên/alias làm fallback. Một báo cáo có
  thể chọn nhiều ngành hàng vì một đơn/khách có thể có nhiều nhu cầu; ngành đầu
  tiên được lưu làm ngành chính để filter/list cũ còn tương thích, toàn bộ
  ngành được lưu trong bảng selection và xuất CSV. Nếu không map được ngành
  hàng về nhóm ngành OpsHub thì sale bắt buộc chọn trước khi gửi báo cáo.
- Nhu cầu khách hàng và các câu hỏi hành vi tư vấn/trải nghiệm/Zalo/App đều là
  trường bắt buộc. Các câu hỏi hành vi mặc định là `Chọn`, không tự mặc định
  `Có`.
- Cả `Mua hàng` và `Chưa mua hàng` có tick `Trả góp`. Với `Mua hàng`, tick này
  ghi nhận trả góp thành công. Với `Chưa mua hàng`, tick này ghi nhận trả góp
  thất bại và bắt buộc nhập lý do thất bại. Khi tick trả góp, sale phải chọn ít
  nhất một đối tác trong danh sách cố định: `VNPAY - POS`, `PAYOO - POS`,
  `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`.
- `orderCode` là unique trên bảng `SalesReport`; một đơn mua hàng chỉ được báo
  cáo một lần.
- Không có field nhập `MSNV`; backend lấy user, email, tên, mã nhân viên suy ra,
  showroom và organization node từ token/user hiện tại.
- `ADMIN_SALES_REPORTS` được gán bằng feature theo node tổ chức. Super Admin có
  quyền toàn app theo feature resolver hiện tại.

## Data Contract

- `SalesReport` lưu report type, hành vi tư vấn/trải nghiệm/Zalo/App, lý do
  chưa mua, category snapshot chính, các ngành hàng đã chọn, reporter snapshot,
  showroom/org snapshot, trạng thái/tổng tiền đơn ERP, trạng thái/đối tác trả
  góp và sanitized ERP snapshot.
- `SalesReportCategorySelection` lưu toàn bộ ngành hàng được chọn theo từng
  báo cáo, gồm snapshot code/tên gốc/tên Việt.
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
- Flutter: Home/Report hub entry theo feature, route guard, order check before
  submit, QR/barcode scan mã đơn, auto-fill nhiều category/need từ mock ERP,
  installment partner validation, không gửi `MSNV`, form validation và export
  CSV.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
