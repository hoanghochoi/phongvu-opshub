# Báo cáo Sale Contract

## Intent

Sale ghi nhận hành vi tư vấn và kết quả mua/chưa mua ngay trong OpsHub, thay
cho Google Form, đồng thời lưu dữ liệu đủ chuẩn để dashboard dùng lại.

## Current Shape

- Home hiển thị ô `Báo cáo` khi user có feature `SALES_REPORT` hoặc
  `ADMIN_SALES_REPORTS`.
- Màn hình `Báo cáo` là cockpit đơn hàng trong ngày: cột trái là đơn chưa báo
  cáo, cột phải là đơn đã báo cáo. Mỗi cột hiển thị 20 đơn/trang, có scroll
  theo màn hình và nút chuyển trang riêng; số lượng ở header là total đếm từ DB
  theo scope hiện tại. User thường chỉ thấy dữ liệu của mình theo email/snapshot
  người bán; user có `ADMIN_SALES_REPORTS` xem trong phạm vi node tổ chức được
  gán, gồm các showroom/node con; Super Admin xem toàn bộ cache/report trong DB.
- Cockpit có nút `Báo cáo chưa mua`, `Tải lại`; user có quyền admin report có
  thêm nút xuất CSV và lối vào danh sách báo cáo chi tiết.
- Backend tự đồng bộ danh sách đơn từ staff-bff ERP mỗi 3 phút và khi service
  khởi động, rồi upsert snapshot rút gọn vào bảng cache riêng. Flutter không
  kích hoạt ERP sync; client chỉ đọc dữ liệu realtime/near-realtime từ cache DB
  khi mở màn hình, khi bấm `Tải lại`, và mỗi 3 phút khi màn hình còn mở.
- Khi sale bấm một đơn chưa báo cáo, app mở form báo cáo mua hàng trong dialog,
  tự kiểm tra lại mã đơn qua luồng `check-order` hiện tại rồi fill tên khách,
  nhu cầu, loại khách, ngành hàng và thông tin đơn cần thiết.
- Màn hình `Báo cáo` hiển thị lối vào `Báo cáo sale` để xem danh sách và xuất
  CSV khi user có `ADMIN_SALES_REPORTS`; entry này không nằm trong menu
  `Quản trị`.
- Màn hình `Báo cáo sale` của admin lọc danh sách và CSV theo loại báo cáo và
  khoảng `Từ ngày` / `Đến ngày` dựa trên thời điểm gửi báo cáo (`submittedAt`).
  Admin xuất được 3 file tiếng Việt: `HVTC` là mỗi dòng một báo cáo mua/chưa
  mua; `Doanh số` là một dòng tổng hợp doanh thu/số lượng theo type ngành hàng;
  `Trả góp` chỉ lấy báo cáo có `installmentNeed = true`.
- `Mua hàng` bắt buộc nhập hoặc quét QR/barcode `Mã đơn hàng` và bấm
  `Kiểm tra đơn hàng` trước khi mở phần form còn lại. Sau khi đã kiểm tra, sale
  có nút `Kiểm tra đơn khác` để nhập/quét lại đơn mới. Backend kiểm tra ERP
  thật qua server, rồi submit vẫn re-check ERP trước khi lưu.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng về form.
- ERP/Listing chỉ được tự điền ngành hàng khi map được về nhóm ngành OpsHub:
  ưu tiên mã nhóm rõ ràng từ Listing như
  `result.products[].categories[].code` hoặc `productGroup.code` khớp
  `Cat group ID` trong `data/categories.csv`, rồi mới dùng tên/alias làm
  fallback. Một báo cáo có thể chọn nhiều ngành hàng vì một đơn/khách có thể có
  nhiều nhu cầu; ngành đầu tiên được lưu làm ngành chính để filter/list cũ còn
  tương thích, toàn bộ ngành được lưu trong bảng selection và xuất CSV. Nếu
  không map được ngành hàng về nhóm ngành OpsHub thì sale bắt buộc chọn trước
  khi gửi báo cáo.
  Tên nhóm gốc ngắn như `PC` chỉ được match khi ERP/Listing trả đúng giá trị
  đó, không được match substring trong tên sản phẩm/dịch vụ như `... PC miễn
  phí`.
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
  ERP trả `billingInfo.customerType = BUSINESS` hoặc
  `billingInfo.taxCode` có giá trị; nếu cả hai không thể hiện doanh nghiệp thì
  xem là `Cá nhân`.
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
- File `Trả góp` xuất một dòng cho mỗi báo cáo có nhu cầu trả góp, gồm:
  `Ngày báo cáo`, `createdByEmail`, `installmentLoanAmount`,
  `installmentPartnerCodes`, `installmentApproved`, `reportType`,
  `Phương thức thanh toán cuối cùng`, `installmentNoInstallmentReason`.
  `Phương thức thanh toán cuối cùng` đọc từ `erpPaymentMethods`: có payment
  method installment thì ghi `Trả góp`, không có thì ghi `Trả thẳng`.
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
- `SalesReportErpOrderCache` lưu snapshot rút gọn của đơn ERP trong ngày để
  cockpit tách đơn chưa/đã báo cáo mà không phụ thuộc sale nhớ tự mở form. Dữ
  liệu gồm mã đơn, ngày tạo, trạng thái, showroom/node, người tư vấn/người bán
  nếu ERP trả về, tổng tiền, phương thức thanh toán, metadata lần sync nền và
  snapshot đã sanitize. API cockpit đếm total chưa báo cáo trực tiếp trên cache
  DB, loại trừ các `orderCode` đã có báo cáo mua hàng trong cùng ngày/scope, rồi
  trả từng trang 20 đơn cho client.
- `SalesReportCategoryGroup` đồng bộ từ `data/categories.csv`, dùng `Cat group
  ID` làm code, `Cat group name` làm tên gốc và `catGroupNameVi` làm nhãn tiếng
  Việt.
- Snapshot report lưu cả code, tên gốc và tên Việt để dữ liệu lịch sử không bị
  lệch nếu CSV đổi sau này.

## Expected Proof

- Backend: Prisma validate/generate, Nest build, tests cho category sync,
  duplicate `orderCode`, purchased re-check ERP, not-purchased no ERP call,
  scheduled ERP cache sync, order cockpit cache-only list, feature guard và
  export CSV.
- Flutter: Home/Report hub entry theo feature, route guard, order check before
  submit, cockpit 2 cột chưa/đã báo cáo, phân trang 20 đơn/cột, refresh 3 phút,
  QR/barcode scan mã
  đơn, auto-fill nhiều category/need/customer type từ mock ERP, checkbox
  selectors, installment partner/approval/reason validation, không gửi `MSNV`,
  form validation và export CSV.
- Manual smoke sau deploy: cấu hình ERP env trên VPS, check một mã đơn thật,
  gửi một báo cáo mua hàng và xác nhận duplicate bị chặn.
