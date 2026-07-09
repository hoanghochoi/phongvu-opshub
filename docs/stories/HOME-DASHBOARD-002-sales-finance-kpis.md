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
- Nhóm `Doanh số` hiển thị `Doanh số tổng`, `Số đơn bán`,
  `Trung bình đơn hàng`, `Doanh số hoàn thành`, `Pending` và
  `Tỉ lệ chuyển đổi`.
- Nhóm `KPI chính` hiển thị hai dòng trên desktop: dòng 1 gồm doanh số khách
  hàng doanh nghiệp, doanh số khách hàng cá nhân, số lượng CTKM đổi điểm thi,
  số lượng CTKM HSSV, số lượng nhu cầu trả góp và số lượng trả góp thành công;
  dòng 2 gồm số lượng bảo hiểm mở rộng, laptop, PC bộ, PC ráp, Apple
  (iPhone, MacBook, iPad), màn hình, máy in và phụ kiện. Tablet/mobile được
  wrap theo breakpoint dashboard hiện có để không vỡ layout.
- `Doanh số tổng` lấy tổng giá trị đơn trong cache theo ngày/scope đang chọn,
  không cộng đơn 0 VND, đơn hủy/trả toàn bộ và trừ giá trị trả một phần.
- `Trung bình đơn hàng = Doanh số tổng / Số đơn bán`.
- `Doanh số hoàn thành` chỉ cộng các báo cáo mua hàng có trạng thái ERP đã
  sync là hoàn thành; đơn trả một phần trừ giá trị trả trước khi cộng.
- `Pending = Doanh số tổng - Doanh số hoàn thành`, không âm.
- Nhóm `Hành vi then chốt` hiển thị `Số khách chưa mua`,
  `Số đơn chưa báo cáo`, `Tỉ lệ báo cáo`, `Tỉ lệ 3 giải pháp`,
  `Tỉ lệ trải nghiệm`, `Tỉ lệ Zalo OA` và `Tỉ lệ tải App`.
- Bấm vào phần chữ của card `Số khách chưa mua` hoặc `Số đơn chưa báo cáo` mở
  modal chi tiết theo cùng ngày/scope/SA đang chọn. Modal phù hợp desktop,
  tablet, mobile và cho phép cuộn dọc/ngang khi màn hình nhỏ. Bảng khách chưa
  mua có Tên SA, Tên khách hàng, Loại khách hàng, Ngành hàng, Lý do không mua;
  bảng đơn chưa báo cáo có Tên SA, Mã đơn hàng, Thời gian bán.
- `Tỉ lệ báo cáo = số đơn đã báo cáo / tổng số đơn hợp lệ`.
- `Tỉ lệ chuyển đổi = tổng số đơn / tổng số báo cáo`.
- Các tỉ lệ hành vi tính bằng số báo cáo có câu trả lời `Có` (`YES`) chia cho
  tổng số báo cáo trong cùng ngày/scope.
- `Tài chính` hiển thị tổng số tiền chuyển khoản, tổng số sao kê, tổng sao kê
  có đơn hàng, tổng sao kê chưa có đơn hàng và tỉ lệ sao kê có đơn hàng.
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
- Doanh số thực đạt chỉ cộng báo cáo mua hàng có trạng thái ERP hoàn thành;
  đơn 0 VND, đơn hủy/trả toàn bộ không tính, trả một phần trừ giá trị hàng trả
  rồi mới quy đổi về trước VAT 8%.
- Chỉ tiêu lưu theo SR/tháng. Ngày và tuần được phân bổ theo số ngày nằm trong
  tháng; thiếu chỉ tiêu ở bất kỳ SR nào thì vẫn hiện thực đạt nhưng không tính
  phần trăm.
- Với `Tổng quan cá nhân`, SA nhận phần chỉ tiêu SR chia cho số SA active tại
  SR. Store manager hoặc tài khoản quản lý theo node được chọn SA trong phạm vi
  hiện tại để xem card cá nhân của SA đó; danh sách chọn không vượt ngoài các
  showroom thuộc Miền/Vùng/Cửa hàng đang xem. Backend định danh SA bằng email;
  tiến độ SA chỉ cộng đơn ERP đã hoàn thành từ báo cáo mua hàng, không lấy doanh
  số cache. Khi danh sách SA lớn hơn 10, UI chuyển sang picker có ô tìm kiếm
  theo tên hoặc email.
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
- User có `Quản lý doanh số` theo node được cập nhật chỉ tiêu các SR trong
  subtree được cấp; SA nhận phần chỉ tiêu SR chia cho số SA active tại SR.

## Proof Target

- Backend: focused Home Summary/Sales Report Jest và Nest build.
- Flutter: focused Home widget tests và `flutter analyze`.
- Repo: `git diff --check` và rà exact diff.
