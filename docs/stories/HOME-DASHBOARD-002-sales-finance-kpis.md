# HOME-DASHBOARD-002: KPI Bán hàng và Tài chính

## Story

Người quản lý cần xem nhanh hiệu quả báo cáo bán hàng và tình trạng đối chiếu sao
kê trên cùng Trang chủ, theo đúng một ngày và một phạm vi đang chọn.

## Acceptance

- Dashboard tách rõ hai khu vực `Bán hàng` và `Tài chính`.
- Cả hai khu vực cùng dùng ngày và scope ở header; đổi một bộ lọc phải tải lại
  toàn bộ KPI trong hai khu vực. Riêng dropdown SA trong `Tổng quan cá nhân`
  làm các KPI `Bán hàng`/`Hành vi then chốt` đổi theo SA đã chọn, trong khi
  `Tổng quan Cửa hàng` và `Tài chính` vẫn giữ scope showroom/node ở header.
- `Bán hàng` chia thành ba nhóm nhỏ: `Doanh số`, `KPI chính` và
  `Hành vi then chốt`.
- Nhóm `Doanh số (đã bao gồm VAT)` hiển thị `Giá trị bán (đã bao gồm VAT)`,
  `Số đơn bán`, `Trung bình đơn hàng (đã bao gồm VAT)`,
  `Hoàn thành (đã bao gồm VAT)`, `Chờ hoàn thành (đã bao gồm VAT)` và
  `Tỉ lệ chuyển đổi`.
- Nhóm `KPI chính` giữ thứ tự metric và trên desktop rộng hiển thị ba dòng theo
  approved Home Figma: dòng 1 gồm doanh số khách hàng doanh nghiệp, doanh số
  khách hàng cá nhân, số lượng CTKM đổi điểm thi, số lượng CTKM HSSV và số
  lượng nhu cầu trả góp; dòng 2 gồm số lượng trả góp thành công, bảo hiểm mở
  rộng, laptop, PC bộ và PC ráp; dòng 3 gồm Apple (iPhone, MacBook, iPad), màn
  hình, máy in và phụ kiện. Tablet/mobile wrap tuần tự theo shared viewport
  breakpoint, không đổi thứ tự metric hoặc hành vi card.
- Import lịch sử từ exact Sales export 34 cột giữ nguyên API và aggregate Home:
  dùng doanh thu VAT, HRM ID, 14 chữ số đầu order, taxonomy exact-ID và chỉ đếm
  Apple cho iPhone/MacBook/iPad. PC ráp được tính theo canonical order bằng số
  trực tiếp cộng phần bộ ráp từ minimum sáu linh kiện ròng không âm; category
  biết nhưng ngoài KPI là 0, category không map được phải quarantine grain.
  Scientific coefficient quá 16 chữ số có nghĩa, quantity/tổng order vượt biên
  lưu trữ hoặc một canonical order map sang nhiều nhân viên cũng quarantine
  toàn bộ grain ngày/showroom; tổng cuối theo grain cũng phải được preflight để
  overflow chỉ quarantine grain đó và không làm fail các grain sạch khác.
  Không làm tròn số và không tự gán nhân viên.
- `Số lượng CTKM đổi điểm thi` chỉ đếm báo cáo `PURCHASED` chứa
  `EXAM_SCORE_EXCHANGE`; `Số lượng CTKM HSSV` chỉ đếm báo cáo `PURCHASED`
  chứa `STUDENT`. Một báo cáo mua hàng chứa cả hai mã tăng cả hai KPI. Báo cáo
  `NOT_PURCHASED` vẫn lưu loại khách/CTKM nhưng không tham gia hai KPI này.
- `Số lượng nhu cầu trả góp` tiếp tục đếm mọi báo cáo có
  `installmentNeed = true`, gồm cả `PURCHASED` và `NOT_PURCHASED`; thay đổi
  contract CTKM không được làm giảm KPI hoặc lý do không trả góp hiện hành.
- Giá trị bán chỉ lấy `SalesReportErpOrderCache.grandTotal` VAT-inclusive theo
  ngày/scope đang chọn. Không fallback report snapshot/capture/shipment/item;
  thiếu hoặc invalid cho doanh thu 0 nhưng giữ count/fact đủ điều kiện. Không
  cộng đơn 0 VND, đơn hủy/trả toàn bộ hoặc pending-payment; trả một phần vẫn
  cộng toàn bộ canonical `grandTotal`.
- `Trung bình đơn hàng = Giá trị bán / Số đơn bán`.
- `Hoàn thành (đã bao gồm VAT)` chỉ cộng các báo cáo mua hàng có trạng thái ERP
  đã sync là hoàn thành và tra giá trị cache theo `orderCode`; trả một phần
  không bị trừ doanh số.
- `Chờ hoàn thành = Giá trị bán - Hoàn thành`, không âm.
- Nhóm `Hành vi then chốt` hiển thị `Số khách chưa mua`,
  `Số đơn chưa báo cáo`, `Báo cáo đã mua`, `Tỉ lệ báo cáo`, `Tỉ lệ 3 giải pháp`,
  `Tỉ lệ trải nghiệm`, `Tỉ lệ Zalo OA` và `Tỉ lệ tải App`.
- Bấm vào phần chữ của card `Số khách chưa mua` hoặc `Số đơn chưa báo cáo` mở
  modal chi tiết theo cùng ngày/scope/SA đang chọn. Modal phù hợp desktop,
  tablet, mobile và cho phép cuộn dọc/ngang khi màn hình nhỏ. Bảng khách chưa
  mua có Mã showroom, Tên SA, Tên khách hàng, Loại khách hàng, Ngành hàng, Lý do
  không mua; bảng đơn chưa báo cáo có Mã showroom, Tên SA, Mã đơn hàng, Giá trị đơn,
  Thời gian bán.
- Store Manager trở lên có quyền `ADMIN_SALES_REPORTS` bấm phần chữ của card
  `Báo cáo đã mua` để mở `Quản trị/Báo cáo bán hàng`; user không có quyền này
  chỉ xem số liệu.
- Bấm phần chữ của card `Số lượng nhu cầu trả góp` mở modal chi tiết gồm SR,
  Tên SA, Đối tác trả góp, Thành công và Ghi chú. Thành công hiển thị tick khi
  báo cáo bán hàng ghi nhận `installmentStatus = SUCCESS` (fallback dữ liệu cũ
  `NORMAL_INSTALLMENT`), không suy từ ERP payment method; Ghi chú hiển thị mã
  đơn hàng nếu thành công hoặc lý do thất bại/không trả góp nếu chưa thành
  công.
- Card có route hoặc modal phải có icon detail nhỏ ở góc trên bên phải và
  không làm đổi chiều cao/layout card hiện tại.
- `Tỉ lệ báo cáo = số đơn đã báo cáo / tổng số đơn hợp lệ`.
- `Tỉ lệ chuyển đổi = tổng số đơn / tổng số báo cáo`.
- Các tỉ lệ hành vi tính bằng số báo cáo có câu trả lời `Có` (`YES`) chia cho
  tổng số báo cáo trong cùng ngày/scope.
- `Tài chính` hiển thị tổng số tiền chuyển khoản, tổng số sao kê, tổng sao kê
  có đơn hàng, tổng sao kê chưa có đơn hàng và tỉ lệ sao kê có đơn hàng.
- User có quyền `Sao kê` bấm phần chữ của `Tổng sao kê chưa có đơn hàng` để mở
  màn `/bank-statement` với filter `Chưa có đơn hàng` và tự tìm kiếm ngay.
- `Tỉ lệ sao kê có đơn hàng = tổng sao kê có đơn / tổng số sao kê`.
- Khối `Tổng quan` đứng trước KPI, bỏ progress bar và dùng donut cho tiến độ
  báo cáo, sao kê và doanh số. Doanh số tách thành hai card:
  `Tổng quan cá nhân` và `Tổng quan Miền/Vùng/Cửa hàng`. Card cá nhân thể hiện
  tiến độ của user/SA đang chọn; với tài khoản quản lý, mặc định là `Chưa chọn
SA`, card hiển thị hướng dẫn `Chọn SA để hiển thị chỉ số` và các KPI
  `Bán hàng`/`Hành vi then chốt` vẫn giữ toàn bộ scope showroom/node ở header.
  Scope `Toàn hệ thống` vẫn hiển thị card `Tổng quan cá nhân` ở trạng thái chưa
  chọn thay vì ẩn card. Card Miền/Vùng/Cửa hàng thể hiện toàn bộ phạm vi quản
  lý đang chọn, giống nhau cho các user trong cùng SR và không đổi khi dropdown
  SA thay đổi. Trên desktop đủ rộng, bốn card tổng quan nằm một hàng: `Tiến độ
báo cáo` + `Tiến độ sao kê` gộp bằng một phần ba chiều ngang, hai card doanh
  số mỗi card một phần ba. Mỗi card gồm khoảng chọn, tuần và tháng; vòng dừng ở
  100% nhưng text vẫn thể hiện vượt chỉ tiêu.
- Grid KPI trên mobile thông thường hiển thị 2 card mỗi hàng; chỉ hạ còn 1 card
  khi vùng nội dung hẹp dưới 320 px. Bán hàng và Tài chính dùng cùng breakpoint.
- Giá trị thực đạt chỉ cộng báo cáo mua hàng có trạng thái ERP hoàn thành theo
  canonical cache `grandTotal` VAT-inclusive; đơn 0 VND, đơn hủy/trả toàn bộ
  không tính, trả một phần giữ toàn bộ giá trị.
- Chỉ tiêu lưu theo SR/tháng. Ngày và tuần được phân bổ theo số ngày nằm trong
  tháng; thiếu chỉ tiêu ở bất kỳ SR nào thì vẫn hiện thực đạt nhưng không tính
  phần trăm. Backend giữ nguyên `targetBeforeTax` đã lưu nhưng so sánh/hiển thị
  `round(targetBeforeTax * 1.08)` để không cần backfill lịch sử; card tiến độ ghi
  rõ `Giá trị đã bao gồm VAT`.
- Với `Tổng quan cá nhân`, SA nhận phần chỉ tiêu SR chia cho số SA active tại
  SR. Store manager hoặc tài khoản quản lý theo node được chọn SA trong phạm vi
  hiện tại để xem card cá nhân của SA đó; danh sách chọn không vượt ngoài các
  showroom thuộc Miền/Vùng/Cửa hàng đang xem. Backend định danh SA bằng email;
  tiến độ SA chỉ cộng đơn ERP đã hoàn thành từ báo cáo mua hàng, không lấy doanh
  số cache. Danh sách SA dùng combobox chung có search realtime theo tên hoặc
  email.
- Trên mobile, người dùng kéo mạnh xuống ở Trang chủ để tải lại dashboard theo
  bộ lọc hiện tại; thao tác này dùng cùng luồng refresh/log với nút tải lại.
- Tài chính đọc `MapVietinTransaction` theo cùng ngày Việt Nam và scope
  showroom/node ở header. Dropdown SA không đổi số liệu Tài chính. Scope cá
  nhân chỉ tính sao kê có mã đơn thuộc đơn hàng cá nhân; chọn showroom được gán
  mới tính toàn showroom đó.
- SA, Kỹ thuật, Kho và Thu ngân chỉ được chọn `Phạm vi cá nhân` hoặc từng
  showroom được gán; không được chọn vùng, miền hay toàn hệ thống.
- Super Admin mặc định xem `Toàn hệ thống`, đồng thời được chọn từng node đang
  hoạt động có showroom bên dưới như Miền, Vùng hoặc Showroom để xem dashboard
  theo phạm vi cụ thể.
- Quyền xem `Bán hàng` và `Tài chính` là hai tính năng riêng trong cây tổ chức.
  Super Admin tick tính năng nào tại node thì backend và UI mới trả/hiện khu vực
  tương ứng; quyền này độc lập với quyền mở màn hình `Sao kê`.
- Luồng tải dashboard có log bắt đầu, thành công, thất bại và các tổng đếm đã
  sanitize; không log nội dung chuyển khoản hay mã sao kê.
- `GET /home/summary` chỉ thêm `dailySeries` khi client gửi chính xác
  `includeDailySeries=true`. Chuỗi gồm tối đa 90 ngày tăng dần, zero-fill và bốn
  metric `totalRevenue`, `totalOrders`, `reportedOrders`, `totalReports`; tổng
  từng metric phải bằng KPI aggregate trong cùng response. Chuỗi dùng cùng
  scope Bán hàng/SA đã chọn, bị omit khi Bán hàng không khả dụng và không làm
  đổi DTO của client cũ không opt in.
- Derived SALES projection mang hai contract version độc lập cho giá và KPI.
  Khi startup gặp ngày có bất kỳ SALES aggregate nào thiếu/sai một trong hai
  version, thiếu GLOBAL aggregate, sai tổng GLOBAL hoặc ngày chỉ có source
  fact/cache/report, backend enqueue union ngày đó qua projection queue.
  Aggregate replacement tạo lại đủ `GLOBAL`, `STORE`, `USER_STORE` trong
  transaction hiện hữu nên generation lỗi giữ last-known-good; không rewrite
  source rows, không Prisma migration/backfill. Rollback semantics phải tăng
  KPI contract version thêm một lần, không được giảm version cũ.
- User có `Quản lý doanh số` theo node được cập nhật chỉ tiêu các SR trong
  subtree được cấp; SA nhận phần chỉ tiêu SR chia cho số SA active tại SR.

## Proof Target

- Backend: focused Home Summary/Sales Report Jest và Nest build.
- Flutter: focused Home widget tests và `flutter analyze`.
- Repo: `git diff --check` và rà exact diff.
