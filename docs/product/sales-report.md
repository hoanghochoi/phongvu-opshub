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
- Màn hình `Báo cáo sale` của admin lọc danh sách và CSV theo loại báo cáo và
  khoảng `Từ ngày` / `Đến ngày` dựa trên thời điểm gửi báo cáo (`submittedAt`).
  Admin xuất được 2 file tiếng Việt: `HVTC` là mỗi dòng một báo cáo mua/chưa
  mua; `Doanh số` là một dòng tổng hợp doanh thu/số lượng theo type ngành hàng.
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
  trường bắt buộc. `Tên khách hàng` là trường bắt buộc trên cả 2 báo cáo; với
  báo cáo mua hàng app tự điền nếu ERP trả về tên khách, sale vẫn có thể nhập
  khi ERP không có dữ liệu. Các câu hỏi hành vi mặc định là chưa chọn, không tự
  mặc định `Có`.
- Các lựa chọn dạng danh sách trên form báo cáo hiển thị bằng checkbox, không
  dùng dropdown. Những nhóm chỉ được chọn một đáp án vẫn dùng checkbox theo kiểu
  chọn độc quyền để nhân viên thao tác nhất quán.
- Loại khách hàng gồm `Doanh nghiệp`, `Cá nhân`; `Học sinh - Sinh viên` là
  checkbox con của `Cá nhân`. Khi tick `Học sinh - Sinh viên`, app tự tick
  `Cá nhân`; khi chọn `Doanh nghiệp`, app khóa và bỏ chọn `Cá nhân` /
  `Học sinh - Sinh viên`. Với báo cáo mua hàng, app tự fill `Doanh nghiệp` khi
  ERP trả `customerType = BUSINESS`, còn giá trị rỗng được xem là `Cá nhân`.
  Với báo cáo chưa mua, sale chọn loại khách thủ công. DB lưu bằng
  `customerType` và flag riêng `customerIsStudent`.
- `CTKM áp dụng` là nhóm checkbox gồm `Đổi điểm thi`,
  `Học sinh - Sinh viên`, và `CTKM khác`.
- Cả `Mua hàng` và `Chưa mua hàng` có tick `Có nhu cầu trả góp`. Khi tick, sale
  chọn một hoặc nhiều đối tác trong danh sách cố định: `VNPAY - POS`,
  `PAYOO - POS`, `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`, `Mirae Asset`, `MPOS`; ghi nhận hồ sơ có được duyệt hay
  không, số tiền vay nếu có, và chọn `Lý do không trả góp`. Lý do này dùng cho
  cả 2 báo cáo vì khách có thể được duyệt nhưng không trả góp, hoặc không được
  duyệt nhưng vẫn mua bằng phương thức khác. Danh sách lý do gồm:
  `Khách chốt trả góp bình thường (Không có lý do)`,
  `Rớt hồ sơ: Tín dụng xấu (Nợ cũ, CIC...)`,
  `Rớt hồ sơ: Lỗi thẩm định/Thông tin`,
  `Khách từ chối: Lãi suất/Phí trả góp cao`,
  `Khách từ chối: Không đủ điều kiện giấy tờ/thẻ`,
  `Khách từ chối: Giá cao/So sánh đối thủ (TGDĐ, FPT, CPS...)`,
  `Khách từ chối: Chỉ tham khảo/Hẹn quay lại`.
- Mọi số tiền hiển thị/nhập trong UI sales-report dùng dấu phân cách hàng ngàn
  theo chuẩn `vi_VN`, ví dụ `5.000.000 VND`; payload gửi backend vẫn là số
  nguyên không có dấu phân cách.
- Khi lấy đơn hàng từ ERP, backend lưu loại khách hàng, phương thức thanh toán,
  snapshot đơn hàng đã sanitize, và từng sản phẩm trong bảng
  `SalesReportOrderItem`. Với từng sản phẩm, backend đọc `categories` trong
  payload Listing, ưu tiên level cao nhất để map `Type` trong
  `data/categories.csv`, rồi lưu `categoryType` để file Doanh số tính laptop,
  PC, PC ráp, Apple, màn hình, máy in, phụ kiện và dịch vụ bảo hiểm.
- File `HVTC` xuất một dòng cho mỗi báo cáo với các cột tiếng Việt: ngày báo
  cáo, email người báo cáo, mã nhân viên tư vấn ERP, tên/số điện thoại/nhu cầu
  khách hàng, các câu trả lời hành vi, loại báo cáo, lý do chưa mua và showroom.
- File `Doanh số` xuất một dòng tổng hợp theo bộ lọc hiện tại: số đơn hàng duy
  nhất, doanh thu doanh nghiệp/cá nhân, các lý do khách không trả góp, số lượng
  laptop, PC, PC ráp, Apple chỉ tính Macbook/iPhone/iPad, màn hình, máy in,
  phụ kiện và dịch vụ bảo hiểm.
- Giá trị trong CSV không bọc dấu nháy kép; dấu phẩy trong nội dung được đổi
  thành dấu chấm phẩy và xuống dòng được đổi thành khoảng trắng để không vỡ cột.
- `orderCode` là unique trên bảng `SalesReport`; một đơn mua hàng chỉ được báo
  cáo một lần.
- Không có field nhập `MSNV`; backend lấy user, email, tên, mã nhân viên suy ra,
  showroom và organization node từ token/user hiện tại.
- `ADMIN_SALES_REPORTS` được gán bằng feature theo node tổ chức. Super Admin có
  quyền toàn app theo feature resolver hiện tại.

## Data Contract

- `SalesReport` lưu report type, tên/số điện thoại/nhu cầu khách hàng, hành vi
  tư vấn/trải nghiệm/Zalo/App, lý do chưa mua, loại khách hàng, cờ học sinh -
  sinh viên, CTKM áp dụng, category
  snapshot chính, các ngành hàng đã chọn, reporter snapshot, showroom/org
  snapshot, trạng thái/tổng tiền/phương thức thanh toán đơn ERP, nhu cầu trả
  góp, hồ sơ duyệt/chưa duyệt, số tiền vay, lý do không trả góp, đối tác trả
  góp và sanitized ERP snapshot.
- `SalesReportCategorySelection` lưu toàn bộ ngành hàng được chọn theo từng
  báo cáo, gồm snapshot code/tên gốc/tên Việt.
- `SalesReportOrderItem` lưu từng sản phẩm trong đơn hàng thành từng row riêng,
  gồm SKU, seller SKU, tên sản phẩm, thương hiệu, nhóm hàng, số lượng, giá bán,
  giá sau giảm, thành tiền dòng, `categoryType` map từ `data/categories.csv` và
  raw snapshot đã sanitize.
- `SalesReportPayment` lưu phương thức thanh toán, số tiền, thời điểm thanh
  toán và mã giao dịch khi ERP trả về.
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
  submit, QR/barcode scan mã đơn, auto-fill nhiều category/need/customer type
  từ mock ERP, checkbox selectors, installment partner/approval/reason
  validation, không gửi `MSNV`, form validation và export CSV.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
