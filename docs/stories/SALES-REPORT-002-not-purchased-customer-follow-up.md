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
2. Chỉ card có số điện thoại hoặc Zalo cá nhân được hiển thị; mỗi báo cáo
   `NOT_PURCHASED` là một hồ sơ riêng.
3. Scope nhân viên/quản lý theo đúng assignee và showroom/node; quản lý phân
   công được cho SA hoạt động trong cùng showroom.
4. Card có tên, liên hệ, ngành hàng, mã SR, tiếp xúc đầu, lần chăm sóc gần nhất
   và pill số ngày đúng màu/thứ tự.
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

## Proof plan

- Prisma: `npx prisma validate`, `npx prisma generate`.
- NestJS: `npm run build`; test service scope/contact/outcome bằng Jest khi môi
  trường có dev dependency.
- Flutter: `dart analyze`/`flutter analyze`, widget test màn hình, route/nav và
  form báo cáo cũ.
- Repo: `git diff --check`, audit đúng file/hunk trước commit.
- Runtime còn cần sau deploy: chạy migration trên staging, kiểm tra backfill,
  gọi/Zalo trên thiết bị thật và xác nhận ERP creator của đơn comeback.
