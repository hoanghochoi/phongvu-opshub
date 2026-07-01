# OpsHub Redesign System Gap Map

Ngày cập nhật: 01/07/2026

## Đã đưa vào repo trong Batch 1

- Authenticated app dùng `AppShell` responsive:
  - desktop sidebar cố định;
  - tablet rail;
  - mobile app bar + bottom navigation `Trang chủ`, `Tác vụ`, `Tài khoản`.
- `/tasks` là workspace index dùng chung permission model với Home/sidebar.
- Navigation ẩn destination không có quyền và log visible/hidden counts qua
  `AppLogger`.
- Theme có thêm token Figma cho primary hover/pressed/surface, status
  surfaces, sidebar light/dark, contextual surface/text/border helpers, và
  breakpoint desktop `1200`.
- Home được chuyển thành nội dung command center để global support,
  notification, account menu và app navigation nằm ở shell.

## Route/frame gap được ghi nợ kỹ thuật

Các frame sau có trong Figma nhưng chưa implement hoặc chưa expose route trong
Batch 1. Không thêm route tạm nếu chưa có runtime contract rõ.

| Figma frame | Trạng thái code hiện tại | Hướng xử lý |
| --- | --- | --- |
| Data Workspace | Chưa có route/runtime screen tương ứng | Tạo story/contract trước khi implement |
| Generic Report Workspace | Hiện repo chỉ có Sales Report hub/form/admin | Quyết định có cần report hub riêng hay Figma frame sẽ nhập vào `/sales-reports` |
| Admin Feature Management | Có screen code nhưng chưa expose route/menu | Ghi nợ route/menu + permission proof |
| Personnel Catalog Admin | Có screen code nhưng chưa expose route/menu | Ghi nợ route/menu + permission proof |
| FIFO Conversation Check | Có screen code nhưng chưa expose route/menu | Xác nhận flow còn dùng hay retire trước khi expose |
| Dialog/loading/empty/error state inventory | Nhiều dialog/state vẫn feature-local | Migrate theo batch sau qua shared shell/dialog/state pattern |

## Proof còn thiếu trước khi gọi là visual parity

- Đã có AppShell widget screenshot smoke light + dark cho desktop/tablet/mobile
  trong `.screenshot/figma_merge` (ignored, không commit ảnh).
- Chưa có Windows/Android/Web runtime smoke thật với light + dark cho từng
  breakpoint.
- Các hub/form/data-heavy screens vẫn cần migrate theo batch sau; Batch 1 chỉ
  khóa nền shell, route `/tasks`, token và permission model.
