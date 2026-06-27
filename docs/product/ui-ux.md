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
- Preserve platform expectations: mobile uses one-column touch-first layouts;
  desktop uses bounded page widths, stable action rows, and denser scanning.
- Do not hide platform limits: Windows-only features must be hidden where they
  are not supported and must show a clear unsupported screen if opened directly.

## Design Tokens

- Colors: every app color must come from `AppColors`. Add a token before adding
  a new recurring hue. Do not use `Color(0x...)` or `Colors.*` in feature UI
  unless it is framework-required and there is no suitable token.
- Typography: use `AppTextStyles` or `Theme.of(context).textTheme`. Do not use
  one-off font scales unless the screen has a specific layout need.
- Radius: use `AppRadius` or `AppLayoutTokens.cardRadius` for feature UI.
- Spacing and layout: use `AppLayoutTokens` for page padding, card padding,
  section gaps, form gaps, inline gaps, and responsive breakpoints.

## Standard Components

- Pages and forms must use `AppResponsiveContent` or `AppResponsiveScrollView`.
  Form-heavy screens should prefer `AppFormColumn` and `formMaxWidth`.
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
- Status messages use `AppStatusBanner` when they explain a page-level state.
- Metadata and status tags use `AppInfoChip`, `AppStatusChip`, or
  `AppStatusPill`.
- Feature entry screens use `AppFeatureSection` and `AppFeatureGrid` so mobile
  and desktop tiles stay consistent.
- User-facing notification entry points must use the shared global
  `AppNotificationsBell` in the app header. New features that need in-app
  notifications should register their count, realtime refresh, and menu rows in
  the global bell provider/menu instead of adding a separate bell icon on their
  own feature screen. Badge counts represent unread rows for the signed-in user
  across devices: opening or refreshing the bell marks the rows currently shown
  in the menu as read through backend read receipts, while local read state is
  only a fallback until the next API refresh and new realtime rows light the
  badge again.
- Header tabs on colored or gradient app bars must set explicit selected,
  inactive, indicator, and divider colors from `AppColors`. Selected and
  inactive labels must remain readable on both Android and Windows; do not rely
  on default `TabBar` primary/grey colors on brand-blue backgrounds.

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
  such as `FIFO`, `VietQR`, `SR`, `CSV`, and `Windows`.
- Copy must explain the state and the next useful action. Prefer
  `Chưa tải được sao kê. Kiểm tra bộ lọc rồi thử lại.` over `Request failed` or
  `Lỗi API`.
- Do not expose backend, provider, token, stack trace, HTTP, database terms, or
  debug-style `key=value` summaries in user-facing UI. Map technical failures
  to plain operational language, for example `Phiên làm việc đã hết hạn. Vui
  lòng đăng nhập lại.`
- Do not expose role, department, policy, or feature codes such as `FIN_ACC`,
  `SUPER_ADMIN`, `ADMIN_*`, or `PAYMENT_SPEAKER` in normal UI copy. Map them to
  human labels or permission messages, for example `Bạn không có quyền sửa đơn
  hàng.`
- Technical identifiers may appear in logs, tests, docs, and admin-only
  configuration inputs when they are required to operate the system, but normal
  staff-facing status, blocker, snackbar, dialog, and error copy must stay
  user-facing.
- Use one product vocabulary consistently:
  - `showroom` or `SR`, not `store`, `branch`, or `shop` in visible UI.
  - `biên nhận` for warranty/repair receipts.
  - `đơn hàng` for order identifiers.
  - `giao dịch`, `tiền vào`, and `sao kê` for payment statement flows.
  - `bảo hành / sửa chữa` or `BH / SC` only when space is tight.
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
- Payment monitor list access is available on supported non-web clients,
  including Android and Windows, when the user has `PAYMENT_MONITOR`.
  The speaker path is Windows-only because it depends on desktop audio
  behavior. Home tiles, speaker controls, and provider logic must not conflate
  those platform capabilities.
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
