# SALES-REPORT-001: Báo cáo sale

## Story

Sale cần gửi báo cáo mua hàng/chưa mua hàng trong OpsHub để dữ liệu không còn
nằm rời ở Google Form và có thể dùng cho dashboard sau này.

## Acceptance

- Home hiện `Báo cáo` khi user có `SALES_REPORT` hoặc
  `ADMIN_SALES_REPORTS`.
- Màn hình `Báo cáo` hiển thị cockpit 2 cột trong ngày: trái là đơn chưa báo
  cáo, phải là đơn đã báo cáo; mỗi cột hiển thị 20 đơn/trang, có total đếm từ
  DB và nút chuyển trang riêng. Phía trên có `Báo cáo chưa mua`, `Tải lại` và
  action xuất file/danh sách khi user có quyền admin report.
- Cockpit lọc theo `Ngày`, `SR` và `User`; filter `SR`/`User` chỉ hiện trong
  scope quản lý và các nút xuất file dùng cùng filter đang chọn.
- Backend tự đồng bộ danh sách đơn ERP từ staff-bff theo ngày mỗi 3 phút và khi
  service khởi động, mặc định 50 đơn, rồi upsert snapshot rút gọn vào bảng
  cache riêng. Ngay trong lần sync, backend map `creator.email` sang user nội
  bộ và showroom/node được gán; payload sync thiếu dữ liệu không được xóa
  mapping đã lưu. Cache cũ đã có user nhưng thiếu showroom/node sẽ được
  backfill lại từ user nội bộ trong lần sync sau. Flutter không kích hoạt ERP
  sync; client đọc cache DB khi mở màn hình hoặc bấm `Tải lại`, và refresh
  realtime qua WebSocket khi backend báo có đơn mới hoặc mapping vừa được bổ
  sung trong scope liên quan.
- User thường chỉ thấy đơn/report của mình theo
  `data.orders.creator.email`, fallback về consultant/seller/source-user
  snapshot nếu ERP không trả creator. STORE_MANAGER hoặc chức danh quản lý theo
  node xem dữ liệu trong showroom/node con được gán; Super Admin xem toàn bộ
  cache/report trong DB.
- Bấm đơn chưa báo cáo mở dialog báo cáo mua hàng và dùng lại luồng
  `check-order` để tự fill dữ liệu cần thiết trước khi sale nhập phần còn lại.
- Form `Mua hàng` yêu cầu nhập hoặc quét QR/barcode mã đơn và check ERP trước
  khi nhập/gửi báo cáo; sau khi check có thể bấm `Kiểm tra đơn khác` để đổi đơn.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng vào form.
- ERP/Listing trả được ngành hàng/nhu cầu thì app tự fill; ngành hàng ưu tiên
  map duy nhất bằng `result.products[].categories[].code` tại `level = 1` khớp
  `Cat group ID` trong `data/categories.csv`; không suy đoán bằng category
  level 2/3, product group/type hay tên sản phẩm. Một báo cáo có thể chọn nhiều
  ngành hàng; nếu không có code level 1 hợp lệ thì bắt buộc sale chọn tay trước
  khi gửi.
  Tên nhóm gốc ngắn như `PC` chỉ match khi ERP/Listing trả đúng `PC`, không
  được tự tick `Máy tính bộ` chỉ vì tên sản phẩm/dịch vụ có chữ `PC`.
- Nhu cầu khách hàng và các câu hỏi hành vi sale là bắt buộc; hành vi tư vấn,
  trải nghiệm, quét Zalo và tải App PV mặc định là chưa chọn, không tự chọn
  `Có`, và các nhóm lựa chọn trong form dùng checkbox thay cho dropdown.
- Cả 2 form bắt buộc nhập `Tên khách hàng`; báo cáo mua hàng tự fill khi ERP
  trả được tên khách hàng nhưng vẫn cho sale nhập khi ERP không có dữ liệu.
- Form lưu loại khách hàng bằng `customerType`; báo cáo mua hàng tự fill
  `Doanh nghiệp` khi ERP trả `billingInfo.customerType = BUSINESS` hoặc
  `billingInfo.taxCode` có giá trị; nếu cả hai không thể hiện doanh nghiệp thì
  xem là `Cá nhân`. `Học sinh - Sinh viên` là checkbox con của
  `Cá nhân`, được lưu bằng flag riêng `customerIsStudent`; tick HS-SV tự tick
  `Cá nhân`, còn chọn `Doanh nghiệp` thì khóa/bỏ chọn `Cá nhân` và HS-SV.
- Form có nhóm checkbox `CTKM áp dụng`: `Đổi điểm thi`,
  `Học sinh - Sinh viên`, `CTKM khác`.
- Backend re-check ERP khi submit và chặn duplicate `orderCode`.
- Check/submit lưu trạng thái vòng đời ERP và dữ liệu hoàn trả. Pending được
  giữ trong tiến độ nhưng chưa tính doanh số; hủy/trả toàn bộ bị loại; trả một
  phần trừ giá trị trả trước khi bỏ VAT 8%.
- Backend rà trạng thái mỗi 20 phút, tối đa 50 đơn với concurrency 2: ưu tiên
  pending và vẫn dành quota cho đơn completed 30 ngày gần nhất để bắt hoàn trả
  muộn. Redis lease ngăn nhiều replica chạy trùng; lỗi từng đơn được retry ở
  lượt sau.
- Form `Chưa mua hàng` không gọi ERP, bắt buộc ngành hàng và lý do chưa mua.
- Cả 2 form có tick `Có nhu cầu trả góp`. Khi tick, sale phải chọn một hoặc
  nhiều đối tác trong list: `VNPAY - POS`, `PAYOO - POS`,
  `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`, `Mirae Asset`, `MPOS`; chọn hồ sơ được duyệt hay chưa,
  nhập số tiền vay nếu có, và chọn lý do không trả góp trong danh sách cố định.
  Các số tiền trên UI dùng dấu phân cách hàng ngàn theo chuẩn `vi_VN`.
- ERP order check lưu phương thức thanh toán, loại khách hàng, snapshot đơn hàng
  đã sanitize, và từng sản phẩm thành từng row trong `SalesReportOrderItem`.
  Backend map thêm `categoryType` bằng `Type` trong `data/categories.csv`, ưu
  tiên category level cao nhất trong payload `categories` từ Listing.
- Admin xuất 3 file CSV tiếng Việt: `HVTC` một dòng mỗi báo cáo mua/chưa mua
  theo các cột hành vi khách hàng; `Doanh số` một dòng tổng hợp số đơn duy
  nhất, doanh thu doanh nghiệp/cá nhân, lý do không trả góp và số lượng theo
  type laptop/PC/PC ráp/Apple/màn hình/máy in/phụ kiện/bảo hiểm mở rộng;
  `Trả góp` chỉ lấy các row có `installmentNeed = true`, gồm các cột tiếng Việt
  `Ngày báo cáo`, `Email người báo cáo`, `Số tiền vay trả góp`,
  `Đối tác trả góp`, `Kết quả duyệt hồ sơ`, `Loại báo cáo`,
  `Phương thức thanh toán cuối cùng`, `Lý do không trả góp`.
- Admin có `ADMIN_SALES_REPORTS` theo node tổ chức xem/query/export báo cáo
  trong phạm vi được gán; Super Admin thấy toàn app.
- Khi admin để filter `Ngày` ở trạng thái trống, UI vẫn hiển thị `Tất cả ngày`
  nhưng query/export mặc định chỉ lấy 30 ngày gần nhất và hiện dòng nhắc nhỏ
  để người dùng biết đây không phải toàn bộ lịch sử.
- Ngành hàng lấy từ `data/categories.csv`, hiển thị tiếng Việt và lưu snapshot
  song song code/tên gốc/tên Việt.
- Không có payload nhập tay `MSNV`.

## Proof Target

- Backend: Prisma validate/generate, Nest build, focused sales-report Jest khi
  bổ sung test suite.
- Flutter: `flutter analyze`, focused widget/provider tests khi bổ sung test
  suite.
- Repo: `git diff --check`.

## Notes

- Dashboard UI chưa thuộc story này; DB/API/export phải đủ để dashboard nối vào
  sau.
- ERP credential nhập qua env trên server, không commit vào repo.
