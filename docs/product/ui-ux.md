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
  `Trang chủ`, `Thông báo`, and `Tài khoản`. Feature screens should provide page
  content only and let the shell own global notification, support, account, and
  route navigation entry points. On mobile, the app bar places the delivery
  metrics pill on the left, the active destination title in the center, and
  support plus the notification bell on the right. Account/profile entry
  belongs to the bottom `Tài khoản` destination; do not duplicate the account
  avatar in the app bar when the screen content already shows user identity.
  The shell top bar owns destination titles; feature content should use
  task/status-specific headings instead of repeating the same destination label
  in a header card. The mobile `Thông báo` destination opens the shared
  notification panel; it should reuse the global notification provider instead
  of introducing a feature-local inbox until a dedicated inbox route is accepted.
- Desktop sidebar destinations must be grouped with visible section labels:
  `Tổng quan`, `Nghiệp vụ`, and `Cấu hình`. The sidebar remains flat navigation;
  do not add row chevrons unless a real nested menu is introduced.
- Navigation visibility is role/feature-aware and must hide unavailable
  destinations in normal staff UI. Log the resolved visible/hidden counts
  through `AppLogger` so permission issues can be debugged without exposing
  raw feature codes to staff.
- Pages and forms must use `AppResponsiveContent` or `AppResponsiveScrollView`.
  The shared responsive wrappers cap desktop content at
  `AppLayoutTokens.contentMaxWidth` so feature pages do not stretch across the
  full window. Form-heavy screens should prefer `AppFormColumn` and
  `formMaxWidth`.
- Primary actions use `AppPrimaryButton`; secondary actions use
  `AppSecondaryButton`; icon-only actions should use a stable square touch
  target and a tooltip.
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
  `AppStatusPill`.
- Shared QR/barcode scanning uses a visible centered frame as a positioning
  guide while the detector analyzes the full preview on every camera-capable
  platform. It must keep all scanner formats enabled, including Code 128 and
  Data Matrix product labels. Android uses auto-zoom and requests a sharper
  analyzer stream; Android/iOS allow tap-to-focus. Web/mobile browser scanning
  must still open the camera when browser support is available, with
  browser-managed focus and zoom. Scanner open/success/failure branches must log
  through `AppLogger` without storing raw scanned values.
- Feature entry screens use `AppFeatureSection` and `AppFeatureGrid` so mobile
  and desktop tiles stay consistent.
- User-facing notification entry points must use the shared global
  `AppNotificationsBell` in the app header and the shell-owned mobile
  `Thông báo` bottom-nav destination. New features that need in-app
  notifications should register their count, realtime refresh, and menu rows in
  the global bell provider/menu instead of adding a separate bell icon on their
  own feature screen. Existing feature-local bells must be removed when the
  global bell can represent the same work. Badge counts represent unread rows
  for the signed-in user across devices: opening or refreshing the bell or
  mobile notification tab marks the rows currently shown in the menu as read
  through backend read receipts, while local read state is only a fallback until
  the next API refresh and new realtime rows light the badge again.
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
  The later UI audit retired the duplicated `/tasks` workspace index, so Home is
  the canonical staff workspace catalog while legacy `/tasks` deep links return
  to `/home`. Later batches must migrate individual hub, form, dialog, loading,
  empty, error, and permission states into that shell.
- The feature-layer baseline for the 2026 migration is guarded by
  `test/design_system_migration_guard_test.dart`. New feature UI must use shared
  tokens/components instead of raw local `Colors.*`, `Color(0x...)`,
  `TextStyle`, input fields, cards, action buttons, dropdown fields,
  `InputDecoration`, or numeric radius literals.

## Filter Controls

- List, report, and admin-index filters must use dropdowns or anchored menus.
  Do not open dialogs for filter selection.
- Date range filters must use one shared dropdown component with common presets
  and inline custom start/end controls. Do not use date-picker dialogs for
  list filters.
- Any staff-facing manual date input, including filters and form fields, uses
  visible format `dd/mm/yyyy` and auto-inserts `/` separators while typing. Do
  not show internal formats such as `yyyy-mm-dd` in normal UI.
- Single-select filters use one dropdown field. Multi-select filters use an
  anchored dropdown with checkbox rows and selected-value chips or a compact
  selected summary.
- Any filter dropdown with more than 10 selectable items must include search
  inside the dropdown panel before the list.
- Filter panels must keep actions close to the control: apply, clear, and
  close behavior should be visible in the dropdown instead of requiring a modal
  workflow.
- Filter-panel action buttons such as `Tìm`, `Xóa filter`, and `Xuất file`
  should stay compact and visually grouped with the filters they apply to.
  On desktop, do not let a search button stretch across a full filter column
  when a compact button would be easier to scan. If export uses the current
  filters, place `Xuất file` next to `Tìm` instead of separating it into a
  lower list toolbar.
- Dialogs are reserved for confirmations, detail views, and large editors. If a
  UI only narrows or sorts a list, it is a filter and must stay dropdown-based.

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
  `56 giao dịch`.
- When copy appears in logs and UI, logs may include sanitized technical context;
  UI must stay human-readable and action-oriented.

## Platform Contracts

- Android and Windows are the primary UI proof targets for current OpsHub work.
- Flutter web is an additional staff operations surface served from the domain
  root in production and staging. The SPA fallback must preserve `/api`, `/ws`,
  `/download`, `/help`, `/uploads`, `/downloads`, `/staging-download`, and
  `/health` before serving `index.html`.
- Payment monitor list access is available on Android, Windows, and web when
  the user has `PAYMENT_MONITOR`. The speaker path is Windows-only because it
  depends on desktop audio behavior. Home tiles, speaker controls, and provider
  logic must not conflate those platform capabilities.
- Web must not start payment audio handling or show speaker controls. The
  `Tiền vào` entry opens the transaction list on web, while the `Đọc loa`
  controls remain hidden or disabled outside supported Windows clients.
- If a feature or sub-feature is platform-specific, direct route access on
  unsupported platforms must not run that sub-feature flow. It must render a
  shared unsupported state or hide the unsupported control and log the branch
  through `AppLogger`.

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
