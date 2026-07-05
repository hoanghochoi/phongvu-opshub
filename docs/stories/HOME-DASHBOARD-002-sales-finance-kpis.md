# HOME-DASHBOARD-002: KPI Bán hàng và Tài chính

## Story

Người quản lý cần xem nhanh hiệu quả báo cáo sale và tình trạng đối chiếu sao
kê trên cùng Trang chủ, theo đúng một ngày và một phạm vi đang chọn.

## Acceptance

- Dashboard tách rõ hai khu vực `Bán hàng` và `Tài chính`.
- Cả hai khu vực cùng dùng ngày và scope ở header; đổi một bộ lọc phải tải lại
  toàn bộ KPI trong hai khu vực.
- `Bán hàng` bỏ card `Tổng số báo cáo hợp lệ`, đổi `Tỷ lệ phủ báo cáo` thành
  `Tỉ lệ báo cáo`, và thêm `Tỉ lệ chuyển đổi`.
- `Tỉ lệ báo cáo = số đơn đã báo cáo / tổng số đơn hợp lệ`.
- `Tỉ lệ chuyển đổi = tổng số đơn / tổng số báo cáo`.
- `Tài chính` hiển thị tổng số tiền chuyển khoản, tổng số sao kê, tổng sao kê
  có đơn hàng, tổng sao kê chưa có đơn hàng và tỉ lệ sao kê có đơn hàng.
- `Tỉ lệ sao kê có đơn hàng = tổng sao kê có đơn / tổng số sao kê`.
- Khối `Tổng quan` đứng trước KPI, bỏ progress bar và dùng donut cho tiến độ
  báo cáo, sao kê và doanh số. Doanh số gồm ngày lớn bên trái, tuần/tháng xếp
  bên phải; vòng dừng ở 100% nhưng text vẫn thể hiện vượt chỉ tiêu.
- Grid KPI trên mobile thông thường hiển thị 2 card mỗi hàng; chỉ hạ còn 1 card
  khi vùng nội dung hẹp dưới 320 px. Bán hàng và Tài chính dùng cùng breakpoint.
- Doanh số thực đạt chỉ cộng báo cáo mua hàng có trạng thái ERP hoàn thành;
  đơn hủy/trả toàn bộ không tính, trả một phần trừ giá trị hàng trả rồi mới
  quy đổi về trước VAT 8%.
- Chỉ tiêu lưu theo SR/tháng. Ngày và tuần được phân bổ theo số ngày nằm trong
  tháng; thiếu chỉ tiêu ở bất kỳ SR nào thì vẫn hiện thực đạt nhưng không tính
  phần trăm.
- Tài chính đọc `MapVietinTransaction` theo cùng ngày Việt Nam và showroom
  scope với Bán hàng. Scope cá nhân chỉ tính sao kê có mã đơn thuộc đơn hàng
  cá nhân; chọn showroom được gán mới tính toàn showroom đó.
- SA, Kỹ thuật, Kho và Thu ngân chỉ được chọn `Phạm vi cá nhân` hoặc từng
  showroom được gán; không được chọn vùng, miền hay toàn hệ thống.
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
