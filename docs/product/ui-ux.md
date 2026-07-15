# UI/UX

OpsHub is an internal operations app. UI decisions must optimize for fast staff
workflows, clear operational state, and consistent behavior across Android and
Windows. Avoid marketing-style pages, decorative layouts, or feature-specific
visual systems that make the app feel assembled from unrelated screens.

## Experience Principles

- Prioritize task completion: scan, search, submit, review, and recover from
  errors quickly.
- Keep density practical: use compact but readable cards, controls, and lists;
  avoid oversized hero sections inside operational flows.
- Show state clearly: every loading, empty, error, success, disabled, exported,
  and unsupported state must be visible and actionable when possible.
- Treat design-system drift as a launch bug: if a screen needs its own button,
  card, modal, notification bell, typography scale, or loading pattern, extend
  the shared component first instead of copy-pasting a local variant.
- Preserve platform expectations: mobile uses one-column touch-first layouts;
  desktop uses bounded page widths, stable action rows, and denser scanning.
- Do not hide platform limits: Windows-only features must be hidden where they
  are not supported and must show a clear unsupported screen if opened directly.

## Design Tokens

- Colors: every app color must come from `AppColors`. Add a token before adding
  a new recurring hue. Do not use `Color(0x...)` or `Colors.*` in feature UI
  unless it is framework-required and there is no suitable token.
- Figma `Foundation/*` variables map into the shared theme layer first:
  `AppColors`, `AppTextStyles`, `AppRadius`, `AppLayoutTokens`, and
  `AppTheme`. Keep legacy aliases such as `AppTheme.primaryBlue` during the
  migration so older screens keep their runtime behavior while new tokens roll
  out.
- Typography: use `AppTextStyles` or `Theme.of(context).textTheme`. Do not use
  one-off font scales unless the screen has a specific layout need. Do not use
  `FontWeight.w800`; the shipped font set normalizes emphasis to `w700` through
  `AppTextStyles.titleEmphasis` or the theme text scale.
- Radius: use `AppRadius` or `AppLayoutTokens.cardRadius` for feature UI.
- Spacing and layout: use `AppLayoutTokens` for page padding, card padding,
  section gaps, form gaps, inline gaps, and responsive breakpoints.

## Standard Components

- Authenticated pages use the shared `AppShell` instead of feature-local
  navigation chrome. Desktop uses a persistent sidebar and top bar, tablet uses
  a compact rail, and mobile uses an app bar with bottom navigation for
  `Trang chủ`, `Vận hành`, `Thông báo`, and `Tài khoản`. `Trang chủ` là
  dashboard tổng quan theo scope, còn `Vận hành` là catalog thao tác nghiệp vụ
  theo quyền. Feature screens should provide page content only and let the
  shell own global notification, support, account, and route navigation entry
  points. On mobile, the app bar places the delivery metrics pill on the left,
  the active destination title in the center, and support on the right.
  When quick actions are available, their launcher occupies the fifth, centered
  bottom-navigation slot instead of floating over the four route destinations.
  Phone layouts below 600 px use a compact 68 px navigation bar and a global
  0.92 typography density factor, including pre-auth screens; tablet and desktop
  typography and navigation dimensions are unchanged.
  Notification entry belongs only to the bottom `Thông báo` destination on
  mobile; do not render a second notification bell in the mobile app bar.
  Account/profile entry belongs to the bottom `Tài khoản` destination; do not
  duplicate the account avatar in the app bar when the screen content already
  shows user identity. Mobile drawer keeps the same app metadata footer as the
  desktop sidebar: version, developer credit, and copyright pinned below the
  scrollable menu. Desktop top bar account area shows the avatar plus two compact
  lines for staff name and SR, with the text block matching the avatar height and
  truncating long values; tablet keeps the account avatar compact.
  The shell top bar owns destination titles; feature content should use
  task/status-specific headings instead of repeating the same destination label
  in a header card. The mobile `Thông báo` destination opens the
  `/notifications` route as a full shell page with the bottom navigation still
  visible; it should reuse the global notification provider instead of
  introducing a feature-local inbox.
- Desktop sidebar destinations must be grouped with visible section labels:
  `Tổng quan`, `Bán hàng`, `Kho`, `Tài chính`, `Kỹ thuật`, and `Cấu hình`.
  `Tổng quan` contains `Trang chủ`, `Vận hành`, and `Quản trị`; `Bán hàng`
  follows `VietQR` -> `Báo cáo bán hàng` -> `Tiền vào`; `Kho` follows `Kiểm tra FIFO`
  -> `Sắp xếp FIFO`; `Tài chính` follows `Sao kê` -> `Cấn trừ`; `Kỹ thuật`
  contains `Bảo hành`. The `Vận hành` page reuses the same operational groups
  and ordering. `Danh sách báo cáo bán hàng`, `Cập nhật tồn kho` and `Lịch sử FIFO`
  belong to `Quản trị`, not the operational `Báo cáo bán hàng` cockpit or a
  standalone FIFO menu. The sidebar remains flat and scrollable; do not add
  row chevrons unless a real nested menu is introduced. The desktop brand block
  shows the current slogan directly under the logo.
- Navigation visibility is role/feature-aware and must hide unavailable
  destinations in normal staff UI. Log the resolved visible/hidden counts
  through `AppLogger` so permission issues can be debugged without exposing
  raw feature codes to staff.
- Pages and forms must use `AppResponsiveContent` or `AppResponsiveScrollView`.
  The shared responsive wrappers cap desktop content at
  `AppLayoutTokens.contentMaxWidth` so feature pages do not stretch across the
  full window. Form-heavy screens should prefer `AppFormColumn` and
  `formMaxWidth`.
- Public auth pages use the shared Auth components: `AuthPage`,
  `AuthBrandPanel`, `AuthFormPanel`, `LoginCard`, `LoginForm`,
  `AuthSecondaryActions`, and `AuthFooter`. At widths `>= 1024px`, auth uses a
  split layout with brand/benefits on the left and a bounded form panel on the
  right, following `minmax(520px, 56%) minmax(420px, 44%)`. Below `768px`, auth
  becomes a single column: centered brand header, full-width login card, then
  footer. The login card is capped at `AppLayoutTokens.authMaxWidth` on desktop
  and fills the available mobile width without horizontal scroll.
- Auth secondary actions must stay visually below the primary CTA. Use compact
  link-style actions in one row for `Quên mật khẩu`, `Đăng ký`, and `Hướng dẫn`
  instead of stacked outline buttons. Keep the primary submit at 52px height,
  auth inputs at 48px height, shared radius/spacing tokens, visible focus and
  error states, disabled/loading states, and semantic labels/tooltips for icon
  controls such as password visibility.
- Primary actions use `AppPrimaryButton`; secondary actions use
  `AppSecondaryButton`; icon-only actions should use a stable square touch
  target and a tooltip.
- Command inputs that trigger scan/search/submit must keep the input field and
  its primary icon actions in the same horizontal row on mobile and desktop.
  Do not move QR/scan, search, or submit buttons below the input unless the
  viewport is too narrow to preserve a usable text field; auxiliary filters may
  sit on the next row.
- Paired actions must use `AppActionRow` plus shared button components and
  `AppButtonMetrics` so height, radius, padding, icon size, and text weight
  match. Mobile actions stack full-width; desktop actions are capped and aligned
  to the action edge so form buttons do not stretch across wide panels. If the
  shared component cannot express the needed variant, extend the shared
  component before using raw `FilledButton` or `OutlinedButton`.
- Disabled buttons must preserve the enabled component shape, height, radius,
  and layout position. Only color, opacity, and enabled state may change;
  avoid framework-default disabled pills or one-off grey states in feature UI.
- Empty, loading, error, and unsupported states use `AppStatePanel`.
- First-load states for operational lists use `AppListSkeleton`, not a bare
  centered spinner. Refreshing an already populated list may use a thin progress
  indicator, but it must not block reading the existing rows.
- Status messages use `AppStatusBanner` when they explain a page-level state.
- Metadata and status tags use `AppInfoChip`, `AppStatusChip`, or
  `AppStatusPill`. Metadata cần sao chép dùng chế độ tương tác của
  `AppInfoChip` để có cùng click/touch, keyboard focus, tooltip, semantics và
  biểu tượng copy trên mọi nền tảng Flutter.
- Shared QR/barcode scanning uses a visible centered frame as a positioning
  guide while the detector analyzes the full preview on every camera-capable
  platform. It must keep all scanner formats enabled, including Code 128 and
  Data Matrix product labels. Android uses auto-zoom and requests a sharper
  analyzer stream; Android/iOS allow tap-to-focus. Web/mobile browser scanning
  must still open the camera when browser support is available, with
  browser-managed focus and zoom. The web barcode runtime must be served from
  the app origin so the production `script-src 'self'` policy does not block
  camera initialization. Manual entry inside the camera screen is one compact
  horizontal row: one input plus a filled check icon with the accessible label
  `Hoàn thành`; do not repeat the instruction/helper block in the bottom panel.
  Scanner open/success/failure/retry branches must log through `AppLogger`
  without storing raw scanned values.
- Feature entry screens use `AppFeatureSection` and `AppFeatureGrid` so mobile
  and desktop tiles stay consistent.
- User-facing notification entry points must use the shared global notification
  provider. Desktop/tablet use `AppNotificationsBell` in the shell top bar for
  a quick menu; mobile uses the shell-owned `Thông báo` bottom-nav destination
  and `/notifications` full page. New features that need in-app notifications
  should register their count, realtime refresh, and menu rows in the global
  provider instead of adding a separate bell icon on their own feature screen.
  Existing feature-local bells must be removed when the global provider can
  represent the same work. Badge counts represent unread rows for the signed-in
  user across devices: opening or refreshing the bell or mobile notification
  page marks the rows currently shown as read through backend read receipts,
  while local read state is only a fallback until the next API refresh and new
  realtime rows light the badge again.
- User-facing logout actions must ask for confirmation before revoking the
  current session. The cancel branch keeps the user in place, while the confirm
  branch performs the existing logout flow and routes to Login.
- Header tabs on colored or gradient app bars must set explicit selected,
  inactive, indicator, and divider colors from `AppColors`. Selected and
  inactive labels must remain readable on both Android and Windows; do not rely
  on default `TabBar` primary/grey colors on brand-blue backgrounds.
- Figma screen migration must stay incremental: upgrade shared Button, Input,
  Dropdown, State, Card, Table, Scanner, and Notification patterns before
  migrating Home, Admin, Tiền vào, Sao kê, Cấn trừ, and Báo cáo screens.
  Batch 1 of the OpsHub Redesign System 2026 import established the shared
  shell, sidebar/bottom-nav permission model, and light/dark navigation tokens.
  The later UI audit retired the duplicated `/tasks` workspace index, and the
  current IA splits the old Home command-center into two surfaces:
  `Trang chủ` is the scoped dashboard, while `/operations` is the canonical
  staff workspace catalog. Legacy `/tasks` deep links return to `/home`. Later
  batches must migrate individual hub, form, dialog, loading, empty, error, and
  permission states into that shell.
- Các biểu mẫu (Form) nghiệp vụ thu thập dữ liệu có số lượng trường nhập liệu lớn hơn 10 trường (hoặc có chiều cao cuộn thực tế trên mobile > 1500px) bắt buộc phải được hiển thị dưới dạng luồng nhiều bước (Stepper/Wizard Flow), không trải phẳng toàn bộ form nhằm giảm tải nhận thức (cognitive load) cho nhân viên vận hành và tránh việc bị điền thiếu hoặc sai lệch thông tin khi phải cuộn quá dài.
- The feature-layer baseline for the 2026 migration is guarded by
  `test/design_system_migration_guard_test.dart`. New feature UI must use shared
  tokens/components instead of raw local `Colors.*`, `Color(0x...)`,
  `TextStyle`, input fields, cards, action buttons, dropdown fields,
  `InputDecoration`, or numeric radius literals.

## Filter Controls

- List, report, and admin-index filters must use dropdowns or anchored menus.
  Do not open dialogs for ordinary single-select filters; the shared date-range
  control opens one anchored desktop range popover so both dates are confirmed
  once without covering the page.
- Rút gọn toàn bộ selector riêng lẻ thành `AppCombobox`: mọi luồng cần chọn
  Showroom hoặc filter danh sách phải dùng cùng component search-box realtime,
  mở dropdown ngay khi focus/click và lọc kết quả theo nội dung nhập. Showroom
  phải hiển thị theo dạng `CPxx - <Tên SR>` thay vì label chung chung như
  `Showroom: CPxx`.
- All date range filters must reuse the canonical shared DateRangePicker. Do not create feature-local implementations.
  The shared trigger opens one draft-state picker: desktop uses a compact
  anchored popover attached to the trigger button, with the preset sidebar and
  two calendars, and must not dim the whole screen with a full modal/dialog
  backdrop; mobile uses a one-month bottom sheet.
  Preset/date/Clear changes are committed only after `Áp dụng`; Cancel, close,
  and outside dismissal preserve the previous filter. Feature/page code must
  not import calendar libraries or call `showDateRangePicker` directly.
- Any staff-facing manual date input, including filters and form fields, uses
  visible format `dd/mm/yyyy` and auto-inserts `/` separators while typing. Do
  not show internal formats such as `yyyy-mm-dd` in normal UI.
- Single-select filters use one combobox field. Multi-select filters use the
  same anchored combobox with checkbox rows and compact selected summary.
- Filter dropdowns search realtime from the input field itself; do not add a
  second search field inside the dropdown panel.
- Filter panels must keep actions close to the control: apply, clear, and
  close behavior should be visible in the dropdown instead of requiring a modal
  workflow.
- Filter-panel action buttons such as `Tìm`, `Xóa filter`, and `Xuất file`
  should stay compact and visually grouped with the filters they apply to.
  On desktop, do not let a search button stretch across a full filter column
  when a compact button would be easier to scan. If export uses the current
  filters, place `Xuất file` next to `Tìm` instead of separating it into a
  lower list toolbar.
- Finance list screens such as `Tiền vào`, `Sao kê`, and `Cấn trừ` keep page
  size, select-all/selected count when supported, page arrows, and refresh in
  the filter card footer. Page headers should stay focused on title/status
  chips, not own pagination controls.
- Page navigation must use `AppPaginationControls`: previous/next icon buttons,
  one centered page summary, and optional refresh action. Do not create
  screen-local `Trang trước`/`Trang sau` buttons.
- Dialogs are reserved for confirmations, detail views, and large editors. If a
  UI only narrows or sorts a list, it is a filter and must stay dropdown-based.
- Peer editor/report actions launched from one workspace must use a consistent
  presentation surface. Do not open one flow in a modal and route its sibling
  flows to separate pages without an explicit product reason.
- A long modal editor keeps its context header card fixed above the scrollable
  body. The header must retain the task title, status, and close/back action
  while only the form content scrolls, on both mobile and desktop.

## Content And Microcopy

- User-facing text is Vietnamese-first, action-oriented, and written for staff
  doing the task, not for developers reading an implementation detail. Keep
  English only for stable product or file-format terms that staff already use,
  such as `FIFO`, `VietQR`, `CSV`, and `Windows`.
- Do not put personal address terms such as `Đại Ca`, internal jokes, or
  one-person support wording in product UI. Staff-facing copy must work for any
  signed-in employee.
- Copy must explain the state and the next useful action. Prefer
  `Chưa tải được sao kê. Kiểm tra bộ lọc rồi thử lại.` over `Request failed` or
  `Lỗi API`.
- Do not expose backend, provider, token, stack trace, HTTP, database terms, or
  debug-style `key=value` summaries in user-facing UI. Map technical failures
  to plain operational language, for example `Phiên làm việc đã hết hạn. Vui
  lòng đăng nhập lại.`
- Do not show placeholder/database values such as `NULL`, `null`, or empty
  implementation markers. Map them to the actual operational state, for example
  `Chưa có mã đơn`, `Chưa có thông tin`, or `Không rõ`.
- Do not expose role, department, policy, or feature codes such as `FIN_ACC`,
  `SUPER_ADMIN`, `ADMIN_*`, or `PAYMENT_SPEAKER` in normal UI copy. Map them to
  human labels or permission messages, for example `Bạn không có quyền sửa đơn
  hàng.`
- Technical identifiers may appear in logs, tests, docs, and admin-only
  configuration inputs when they are required to operate the system, but normal
  staff-facing status, blocker, snackbar, dialog, and error copy must stay
  user-facing.
- Transient success/error notifications use the shared floating toast at the
  top-right of the current user viewport. Desktop width is bounded at 360px;
  compact screens keep 16px side spacing. Do not use bottom, full-width
  `SnackBar` surfaces for these notifications.
- Use one product vocabulary consistently:
  - `showroom`, not `SR`, `store`, `branch`, or `shop` in visible UI.
  - `biên nhận` for warranty/repair receipts.
  - `đơn hàng` for order identifiers.
  - `giao dịch`, `tiền vào`, and `sao kê` for payment statement flows.
  - `bảo hành/sửa chữa`, not `BH / SC`, for warranty/repair flows.
- Success messages must confirm the concrete result: `Đã lưu ảnh biên nhận`,
  `Đã xuất file`, `Đã cập nhật mã đơn hàng`, or `Đã sao chép serial`.
- Error messages must avoid blame and include recovery: `Chưa tải được ảnh. Vui
  lòng thử lại.` or `Không đọc được cài đặt khởi động cùng Windows.`
- Empty states must say why the view is empty and how to continue: `Không có
  giao dịch trong khoảng ngày đã chọn.` or `Chọn filter rồi bấm Tìm để tải giao
  dịch.`
- Button labels must be short verbs or verb phrases: `Tìm`, `Lưu`, `Thử lại`,
  `Về trang chủ`, `Mở Cài đặt`, `Xuất file`. Avoid vague labels such as `OK`
  when a specific action is available.
- Detail and history dialog titles must name the current product entity, not a
  reused source entity. For example, a bank-statement history dialog should say
  `Lịch sử sao kê` and use the statement/reference number shown in `Sao kê`,
  not `Lịch sử đơn hàng` with an order code.
- Production formats must be consistent: money as `1.250.000 VND`, date/time as
  `HH:mm:ss dd/MM/yyyy`, and counts with units such as `20 dòng`, `3 ảnh`, or
  `56 giao dịch`. Compact dashboard cards may shorten long money values with
  `M`/`B`, for example `179,4M VND`, when full values would clip or wrap.
- When copy appears in logs and UI, logs may include sanitized technical context;
  UI must stay human-readable and action-oriented.

## Platform Contracts

- Android and Windows are the primary UI proof targets for current OpsHub work.
- Bảng hoặc card/modal có nội dung tràn hai chiều phải dùng
  `AppTwoAxisScrollView`. Mỗi trục có `ScrollController` riêng; trên Windows,
  Linux và macOS thumb/track luôn hiện và phải kéo được bằng chuột. Không lồng
  các `Scrollbar` không controller vì sẽ tranh `PrimaryScrollController` và
  làm mất thao tác drag trên desktop.
- Text inputs have exactly one context-menu owner per platform: mobile web uses
  the browser-native selection/paste menu, desktop web uses Flutter's toolbar,
  and native Android/iOS uses the platform Flutter toolbar. Shared text inputs
  must isolate editable selection from an ancestor `SelectionArea`; do not
  enable both browser and Flutter paste menus on mobile web.
- Trên các thiết bị di động (Mobile), các thành phần điều khiển hành động quan trọng ở chân trang (như sticky action bar, submit button) bắt buộc phải chèn một khoảng đệm an toàn tối thiểu `80px` (bằng chiều cao Bottom Navigation Bar cộng thêm khoảng cách an toàn) để tránh bị che đè bởi thanh điều hướng hệ thống hoặc navigation chrome của ứng dụng.
- Flutter web is an additional staff operations surface served from the domain
  root in production and staging. The SPA fallback must preserve `/api`, `/ws`,
  `/download`, `/help`, `/uploads`, `/downloads`, `/staging-download`, and
  `/health` before serving `index.html`.
- Payment monitor list access is available on Android, Windows, and web when
  the user has `PAYMENT_MONITOR`. The speaker path is Windows-only because it
  depends on desktop audio behavior. Home tiles, speaker controls, and provider
  logic must not conflate those platform capabilities.
- `Tiền vào` loads transactions on entry and after explicit user actions, then
  refreshes when the payment WebSocket reports a new transaction. It must not
  poll the transaction list on a fixed timer or when the socket merely
  reconnects. A realtime event refreshes the list on every supported platform;
  only an eligible Windows client with `Đọc loa` enabled also handles audio.
- Web must not start payment audio handling or show speaker controls. The
  `Tiền vào` entry opens the transaction list on web, while the `Đọc loa`
  controls remain hidden or disabled outside supported Windows clients.
- If a feature or sub-feature is platform-specific, direct route access on
  unsupported platforms must not run that sub-feature flow. It must render a
  shared unsupported state or hide the unsupported control and log the branch
  through `AppLogger`.

## Global Text Selection And Dialog Dismissal

- Tất cả nội dung chữ hiển thị trong route, card, modal, dialog và overlay phải
  có thể chọn/copy bằng chuột hoặc thao tác chọn văn bản của nền tảng. Contract
  được đặt tại `MaterialApp.builder` bằng `AppGlobalSelectionScope`; feature
  không được dựa vào `SelectionArea` cục bộ để vá riêng từng màn hình.
- Text input vẫn là chủ sở hữu vùng chọn riêng qua `SelectionContainer.disabled`
  để chọn/copy/paste trong ô nhập không xung đột với vùng chọn toàn app.
- Dialog/modal sạch phải đóng khi click/chạm vùng ngoài, nhấn Back hoặc Escape.
  Không được thêm `barrierDismissible: false` vào runtime UI.
- Dialog/modal có dữ liệu đã sửa nhưng chưa lưu phải dùng `AppDirtyFormGuard`.
  Click ngoài, Back, Escape hoặc nút đóng đều phải hỏi xác nhận bằng tiếng Việt;
  chỉ hủy toàn bộ bản nháp sau khi user chọn `Thoát và hủy`. Lưu thành công phải
  đóng trực tiếp, không hiện cảnh báo hủy.
- Input, combobox, checkbox/switch tùy biến trong editor phải phát
  `AppFormChangedNotification` để shared guard nhận biết trạng thái dirty.

## Logging And Proof

- New or changed user-facing flows must log start, success, failure, and key
  branch decisions through `AppLogger` with sanitized context.
- Local and uploaded log context must redact secrets, authorization values,
  email addresses, and local Windows user profile paths. Windows logs live at
  `%APPDATA%\com.example\OpsHub\logs\opshub.log`.
- Log retention must preserve complete JSON lines. Malformed fragments may be
  discarded during compaction; retention must not cut a record in the middle.
- Minimum UI validation for code changes:
  - `dart format --output=none --set-exit-if-changed <changed Dart files>`
  - `git diff --check`
  - `flutter analyze --no-pub`
  - `flutter test --no-pub --reporter expanded`
- Build or visual proof should be added when layout, platform behavior, or
  assets change. Prefer Android mobile and Windows desktop screenshots or smoke
  notes for Home, target feature screens, and changed states.
- If visual or runtime proof is blocked, the final report and test matrix must
  say what was verified, what remains unverified, and the remaining risk.

## Launch Guard Greps

Before marking UI polish or finance/admin UX work done, run targeted greps and
fix any user-facing hits instead of explaining them away:

```bash
rg -n "Đại Ca|NULL|FontWeight\\.w800|includeGlobalNotifications: false|_OrderTransferBell|color == Colors\\.red" lib
rg -n "TextButton\\(|ElevatedButton\\.icon|OutlinedButton\\.icon|FilledButton\\.icon|FilledButton\\(" lib/features/bank_statement/presentation lib/features/offset_adjustment/presentation lib/features/notifications/presentation
```

The second grep may still find acceptable framework use in legacy/admin-only
surfaces, but finance review dialogs and notification actions must use the
shared `AppDialog*` button helpers unless there is a documented component gap.
