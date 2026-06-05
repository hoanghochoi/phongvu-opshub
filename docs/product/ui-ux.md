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
- Empty, loading, error, and unsupported states use `AppStatePanel`.
- Status messages use `AppStatusBanner` when they explain a page-level state.
- Metadata and status tags use `AppInfoChip`, `AppStatusChip`, or
  `AppStatusPill`.
- Feature entry screens use `AppFeatureSection` and `AppFeatureGrid` so mobile
  and desktop tiles stay consistent.

## Content And Microcopy

- User-facing text is Vietnamese-first. Keep English only for stable product or
  file-format terms that staff already use, such as `FIFO`, `VietQR`, `SR`,
  `CSV`, `Windows`, and `Export CSV`.
- Copy must explain the state and the next useful action. Prefer
  `Chưa tải được sao kê. Kiểm tra bộ lọc rồi thử lại.` over `Request failed` or
  `Lỗi API`.
- Do not expose backend, provider, token, stack trace, HTTP, or database terms
  in user-facing UI. Map technical failures to plain operational language, for
  example `Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại.`
- Use one product vocabulary consistently:
  - `showroom` or `SR`, not `store`, `branch`, or `shop` in visible UI.
  - `biên nhận` for warranty/repair receipts.
  - `đơn hàng` for order identifiers.
  - `giao dịch`, `tiền vào`, and `sao kê` for payment statement flows.
  - `bảo hành / sửa chữa` or `BH / SC` only when space is tight.
- Success messages must confirm the concrete result: `Đã lưu ảnh biên nhận`,
  `Đã export CSV`, `Đã cập nhật mã đơn hàng`, or `Đã sao chép serial`.
- Error messages must avoid blame and include recovery: `Chưa tải được ảnh. Vui
  lòng thử lại.` or `Không đọc được cài đặt khởi động cùng Windows.`
- Empty states must say why the view is empty and how to continue: `Không có
  giao dịch trong khoảng ngày đã chọn.` or `Chọn filter rồi bấm Tìm để tải giao
  dịch.`
- Button labels must be short verbs or verb phrases: `Tìm`, `Lưu`, `Thử lại`,
  `Về trang chủ`, `Mở Cài đặt`, `Export CSV`. Avoid vague labels such as `OK`
  when a specific action is available.
- Production formats must be consistent: money as `1.250.000 VND`, date/time as
  `HH:mm:ss dd/MM/yyyy`, and counts with units such as `20 dòng`, `3 ảnh`, or
  `56 giao dịch`.
- When copy appears in logs and UI, logs may include sanitized technical context;
  UI must stay human-readable and action-oriented.

## Platform Contracts

- Android and Windows are the primary UI proof targets for current OpsHub work.
- Payment monitor is Windows-only because it depends on desktop audio behavior
  and long-running local polling. Route guards, Home tiles, and provider logic
  must share the same platform capability helper.
- If a feature is platform-specific, direct route access on unsupported
  platforms must not run the feature flow. It must render a shared unsupported
  state and log the branch through `AppLogger`.

## Logging And Proof

- New or changed user-facing flows must log start, success, failure, and key
  branch decisions through `AppLogger` with sanitized context.
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