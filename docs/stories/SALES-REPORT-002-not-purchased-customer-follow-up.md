# SALES-REPORT-002 - Chăm sóc lại

## Intake

- Loại: new initiative.
- Domain: sales report, auth/scope, ERP attribution, realtime và shared modal UI.
- Lane: high-risk vì thay đổi schema, backfill dữ liệu lịch sử, quyền theo node,
  phân công chéo nhân viên và tạo báo cáo mua hàng liên kết ERP.
- Checkpoint trước triển khai: `staging` tại
  `2561ba00ff9031923c447b6e5efc5836871e28d3`; worktree sạch tại thời điểm chốt.

## Acceptance criteria

1. Menu Bán hàng có chức năng chính thức `Chăm sóc lại`.
2. Trong 14 ngày đầu từ lần triển khai đầu tiên trên từng môi trường, hiển thị
   toàn bộ hồ sơ đúng scope để rà soát liên hệ. Mốc kết thúc được ghi một lần,
   không gia hạn khi restart/redeploy. Sau mốc đó, chỉ card có số điện thoại
   đúng `0` + 9 chữ số hoặc ít nhất một mã `PHONE`/`ZALO_PERSONAL`/`ZALO_OA`
   trong `customerContactChannels` được hiển thị; marker và nội dung rác cũ
   được migration chuẩn hóa hoặc đưa về rỗng.
   Mỗi báo cáo `NOT_PURCHASED` là một hồ sơ riêng.
3. Scope nhân viên/quản lý theo đúng assignee và showroom/node; quản lý phân
   công được cho SA hoạt động trong cùng showroom; `SUPER_ADMIN` xem toàn bộ hồ
   sơ kể cả khi không có showroom/node được gán.
4. Card có tên, liên hệ, ngành hàng, mã SR, tiếp xúc đầu, lần chăm sóc gần nhất
   và pill số ngày đúng màu/thứ tự.
   Super Admin có thêm bộ lọc `Mã SR / Showroom`, mặc định xem tất cả SR và
   khi chọn một SR thì danh sách tải lại đúng `storeCode` đã chọn.
5. Modal giữ header khách hàng cố định, hiển thị lịch sử, tự mở lần chăm sóc kế
   tiếp và cho chọn bốn kết quả.
6. `PURCHASED` tạo báo cáo `COMEBACK` bằng form mua hàng hiện tại, giữ báo cáo
   gốc và chỉ lấy người bán từ `order.creator.email` ERP.
7. Hai trạng thái terminal nằm trong `Đã ẩn`; assignee mở lại được. Hồ sơ đã mua
   không xuất hiện lại.
8. Mobile hỗ trợ gọi/Zalo; desktop/web sao chép liên hệ. Mọi nhánh chính có
   `AppLogger` và backend log đã được làm sạch dữ liệu nhạy cảm.
9. Realtime dùng `SALES_REPORT_ORDERS_UPDATED` để tải lại danh sách khi hồ sơ
   được chăm sóc, phân công hoặc mở lại.
10. Quản lý báo cáo nhập được file Excel lịch sử qua bước xem trước/xác nhận;
    chỉ dòng chưa mua hợp lệ đúng scope được tạo thành báo cáo
    `HISTORICAL_IMPORT` và follow-up `OPEN`. Dòng đã mua, lỗi hoặc trùng được bỏ
    qua có thống kê. Nhân viên chưa khớp để chưa phân công nhưng giữ email/MSNV
    nguồn; bốn câu hỏi không có trong file ghi `NOT_CAPTURED`. Dòng thiếu mô tả
    sản phẩm vẫn được nhận và lưu trống; ngành hàng lệch cách ghi được ghép vào
    danh mục hiện hành gần nhất, còn giá trị trống hoặc không đủ gần vẫn bị đánh
    dấu lỗi. Checksum và fingerprint ngăn xác nhận sai file hoặc nhập trùng,
    batch audit không giữ nguyên file/PII.
11. Tab card `Lịch sử chăm sóc` nằm giữa `Cần chăm sóc` và `Đã ẩn`, trả mọi hồ
    sơ đúng scope có ít nhất một lần chăm sóc và xếp lần gần nhất trước. Job
    BigQuery báo cáo bán hàng đồng bộ thêm bảng wide-format: một dòng cho mỗi
    khách/hồ sơ, mỗi lần chăm sóc thêm một cột RECORD `follow_up_N`.

## Proof plan

- Prisma: `npx prisma validate`, `npx prisma generate`.
- NestJS: `npm run build`; test service scope/contact/outcome bằng Jest khi môi
  trường có dev dependency.
- Flutter: `dart analyze`/`flutter analyze`, widget test màn hình, route/nav và
  form báo cáo cũ.
- Repo: `git diff --check`, audit đúng file/hunk trước commit.
- Runtime còn cần sau deploy: chạy migration trên staging, kiểm tra backfill,
  gọi/Zalo trên thiết bị thật và xác nhận ERP creator của đơn comeback.
- Import Excel: parser/service test bao phủ template, chuẩn hóa thời gian/phone/
  kênh, lý do khác, scope, owner chưa khớp, checksum và tạo follow-up; widget
  test bao phủ quyền hiển thị, preview, commit và tự tải lại danh sách.
- Lịch sử/BigQuery: service test bao phủ `status=HISTORY`, widget test vị trí và
  truy vấn tab; BigQuery test bao phủ một dòng mỗi hồ sơ và cột RECORD động.
