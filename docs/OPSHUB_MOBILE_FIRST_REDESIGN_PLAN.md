# OpsHub Mobile-First Redesign Plan

Ngày tạo: 05/07/2026

## Mục tiêu

Plan này gom lại audit UI/UX trước đó và các yêu cầu mới về trải nghiệm mobile:

- Chuẩn hóa kích thước nút, filter, card và vùng chạm qua shared tokens/components.
- Giữ mobile navigation một nghĩa: `Thông báo` nằm ở bottom navbar, header mobile không có bell trùng chức năng.
- Đưa `Thông báo` thành full page trong `AppShell`, giữ navbar như các trang khác.
- Sửa Android back để ưu tiên quay lại route trước; chỉ thoát app bằng double-back khi đang ở `/home` và không còn route trước.
- Desktop account area hiển thị avatar kèm 2 dòng `Họ tên` và `SR`; tablet/mobile không lặp thông tin này trên header.
- Tiếp tục giảm tải thao tác mobile ở các màn data-heavy, đặc biệt Sales Report, filter finance/admin và accessibility.

## Baseline đã hoàn tất

- `AppShell` là shell chính cho authenticated routes, desktop có sidebar, tablet có rail, mobile có app bar + bottom navigation.
- `/tasks` đã retired; `/operations` là catalog thao tác nghiệp vụ theo quyền, `/home` là dashboard theo scope.
- Home dashboard đã có KPI compact, scope/date controls và quick tools, không còn hero/top-card lớn.
- Nhiều screen đã chuyển sang content-only trong `AppShell`, dùng shared `AppSurfaceCard`, `AppStatePanel`, `AppFeatureGrid`, `AppButtonMetrics`, `AppLayoutTokens`.
- Filter finance đã có hướng gom `Tìm`, `Xóa filter`, `Xuất file` gần filter panel.
- Runtime Help đã chuyển thành Flutter route và có route logged-in trong shell.

## Gap còn mở

- Mobile thao tác vẫn chưa đồng bộ vì height 40/44/52 còn lẫn lộn giữa action/filter/icon controls.
- Header mobile từng còn `AppNotificationsBell` dù bottom nav đã có `Thông báo`, tạo hai entry cho cùng một chức năng.
- `/notifications` chưa phải route thật, nên mobile notification mở bằng popup/bottom sheet che navbar.
- Android system back có thể thoát app thay vì quay về route trước do primary navigation dùng route replace.
- Sales Report vẫn là form dài, nhiều checkbox, chưa đúng contract wizard cho form >10 trường hoặc mobile scroll >1500px.
- Accessibility chưa đủ gate riêng cho focus order, semantic labels, touch target và screen-reader smoke.

## Batch triển khai

### Batch 1 - Navigation và Notification

- Thêm route `/notifications` trong `ShellRoute`.
- Tạo `NotificationsScreen` full page, dùng lại `AppNotificationsProvider`, read receipts và notification list hiện có.
- Mobile bottom nav `Thông báo` route sang `/notifications`; không mở popup.
- Bỏ bell khỏi mobile app bar; desktop/tablet vẫn giữ bell quick menu.
- Thêm unread badge vào icon `Thông báo` ở mobile bottom nav khi provider có unread count.
- Android native back dùng route history nội bộ của `AppShell`: route trước -> `/home` fallback -> double-back exit.
- Desktop account chip giữ menu tài khoản, nhưng mở rộng cạnh avatar để hiển thị tên nhân sự và SR trong cùng chiều cao 42dp; tablet giữ avatar compact.

### Batch 2 - Shared Sizing Tokens

- Chuẩn hóa shared tokens:
  - primary/submit: 52dp;
  - mobile filter/action: 48dp;
  - compact desktop toolbar: 44dp;
  - icon-only action: 48x48;
  - list/card tap target: 56dp;
  - mobile sticky action bottom inset: 80px.
- Ưu tiên thay ở shared widgets trước: `AppButtonMetrics`, `AppLayoutTokens`, `AppFilterDropdown`.
- Không chỉnh từng screen thủ công nếu shared component đã giải quyết được.

### Batch 3 - Filter, Picker, Card Density

- Chuẩn hóa showroom/filter picker cho VietQR, Tiền vào, Sao kê, Cấn trừ và Sales Report.
- Mobile filter dùng bottom/full-height sheet hoặc anchored route-friendly pattern, có search, Apply/Clear rõ.
- Giảm nested card/intro card dư; card chỉ dùng cho action item, state summary, detail summary.
- Copy staff-facing đổi về tiếng Việt hành động: `User` -> `Nhân viên`, `filter` -> `bộ lọc` khi hiển thị.

### Batch 4 - Sales Report Wizard

- Chuyển Sales Report form dài thành wizard nhiều bước.
- Giữ request contract và provider/backend hiện tại; chỉ đổi presentation/state grouping.
- Bước đề xuất: thông tin đơn/SR -> thông tin khách -> lý do/ngành hàng/CTKM -> review và gửi.
- Có progress, sticky CTA, validation theo bước và review summary trước khi submit.

### Batch 5 - Accessibility và Visual Smoke Gate

- Thêm widget tests cho semantics/focus/touch-target ở shared controls.
- Smoke mobile 390x844 và 360x800 cho Home, Operations, Notifications, Sales Report, finance filter.
- Manual proof: Android back, iOS web swipe-back, mobile notification route, no horizontal overflow.

## Acceptance Checklist

- Mobile header không còn bell thông báo; chỉ còn bottom nav `Thông báo`.
- Tap `Thông báo` trên mobile mở `/notifications`, navbar vẫn hiển thị.
- Desktop/tablet bell vẫn mở quick menu và vẫn load/mark-read như trước.
- Desktop account chip hiển thị 2 dòng cạnh avatar: họ tên và SR; tablet/mobile header không hiển thị cụm này.
- Android back từ route con quay về route trước hoặc `/home`; chỉ double-back tại `/home` mới thoát app.
- Nút/filter/action mobile có touch target tối thiểu 48dp; icon action 48x48.
- Filter có search khi nhiều lựa chọn và action Apply/Clear gần ngữ cảnh.
- Không có sticky action bị bottom nav hoặc system gesture che.
- Không còn screen mới dùng raw button/card/filter local khi shared component đã có.

## Validation

```powershell
git diff --check
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/app_nav_model_test.dart test/app_shell_route_viewport_test.dart test/app_buttons_test.dart test/app_theme_tokens_test.dart
```

Manual smoke sau khi có build:

- Android native: mở `/operations`, vào một feature, dùng back gesture/button để quay lại route trước; tại `/home` double-back mới thoát.
- Mobile web/iOS: browser swipe-back vẫn hoạt động như trước.
- Mobile: tap bottom nav `Thông báo`, xác nhận full page và navbar không bị che.
- 390x844 và 360x800: không clipped button, không hidden sticky CTA, không horizontal overflow.

## Rollback

- Nếu `/notifications` route lỗi, có thể tạm quay mobile bottom nav về panel cũ bằng `AppNotificationsBell.showPanel(context)`, nhưng vẫn giữ plan dài hạn là full page.
- Nếu Android route history gây điều hướng ngược ngoài ý muốn, rollback riêng phần `AppShell` back handling, không cần rollback provider/backend notification.
- Không có migration DB hoặc backend API trong plan này.
