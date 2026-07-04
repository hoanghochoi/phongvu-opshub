# UI/UX Audit & Refactor Plan — Codex

Ngày audit: 03/07/2026
Phạm vi: Flutter app, web staging, public Help/Download, design system và widget tests
Môi trường runtime: `https://opshub-staging.hoanghochoi.com`
Checkpoint repo: branch `staging`, HEAD `15d6574f99965e5e6311b54773f1779731e3decd`
Build staging quan sát: `2026.07.03.100`
Chế độ: audit-only; không sửa code, không tạo/sửa/xóa dữ liệu

## Executive Summary

OpsHub đã có nền tảng UI tốt hơn rõ rệt so với baseline ngày 30/06: app shell đã
thống nhất, desktop có sidebar, mobile có bottom navigation, token và shared
component đã phủ phần lớn feature screen, loading/list state nhìn nhất quán hơn,
và các viewport được kiểm không còn lỗi overflow nghiêm trọng phổ biến.

Khoảng cách còn lại để đạt chuẩn enterprise hiện đại không nằm chủ yếu ở màu sắc
hay bo góc. Nó nằm ở kiến trúc thông tin, nội dung, độ dài workflow và
accessibility:

- Sidebar, Home và Tác vụ đang lặp cùng một danh sách workspace; người dùng có
  ba lớp điều hướng gần như tương đương trước khi vào hub con.
- Nhiều màn admin và finance phản chiếu trực tiếp domain model: `node`, `Lv0`,
  `ADMIN_USERS`, `policy`, `rule`, `MAP`, `ERP`, `pending`, `fully_paid`.
- Form “Báo cáo chưa mua” dài hơn nhiều viewport, chứa hàng chục checkbox và
  nhiều câu lựa chọn ghép bằng dấu `/`; đây là rủi ro hoàn thành tác vụ lớn nhất.
- Các màn chọn showroom dùng ba pattern khác nhau: dropdown dài không tìm kiếm,
  searchable multi-select, và nhập mã thủ công.
- Web semantics/focus chưa có bằng chứng đạt chuẩn. Code chỉ có 5 `Semantics(`
  cho toàn bộ `lib/`, không có test accessibility chuyên biệt, và accessibility
  tree trong runtime audit không đọc được UI thật.
- Public Help đang lộ nội dung biên tập nội bộ như Markdown, repo, deploy,
  pipeline static và cách gọi cá nhân.

Kết luận: **visual foundation khá, product UX chưa hoàn tất**. Không nên tiếp tục
“polish từng màn” rời rạc. Nên xử lý theo thứ tự: accessibility gate → IA/content
cleanup → report flow → unified picker/filter → density/responsive polish.

## Overall Assessment

| Trục | Đánh giá hiện tại | Nhận định |
| --- | --- | --- |
| Visual foundation | Tốt | Token, shell, card, input, state và light/dark đã có nền chung |
| Information Architecture | Trung bình | Điều hướng lặp; sub-workspace và hub chưa phân vai rõ |
| Information hierarchy | Trung bình | Shell title, hero card, chip và section title thường kể lại cùng một ý |
| Workflow efficiency | Trung bình yếu | Luồng scan/search khá rõ; Sales Report và admin config còn nặng |
| Content quality | Yếu ở admin/public Help | Technical copy, English mix, raw code và test data còn lộ |
| Responsive | Khá | 390 và desktop ổn; iPad portrait 834 px bị xếp vào mobile shell |
| Accessibility | Chưa đạt | Thiếu semantics/focus/screen-reader proof và regression tests |
| Maintainability | Khá | Shared layer tốt, nhưng các screen lớn 1.300–2.277 dòng còn khó phát triển |

### Điểm mạnh cần giữ

- `AppShell`, `AppLayoutTokens`, `AppColors`, `AppTextStyles`, `AppRadius` tạo
  nền tảng chung rõ ràng.
- `AppFeatureSection`/`AppFeatureGrid` giữ hub card nhất quán.
- `AppStatePanel` và `AppListSkeleton` đã hiện diện ở nhiều list quan trọng.
- Sao kê mobile có filter collapse hợp lý; showroom picker của Sao kê có tìm
  kiếm và multi-select tốt.
- Navigation và feature visibility bám quyền tài khoản.
- Light/dark theme không có lỗi contrast lớn dễ thấy ở surface chính.

### Phương pháp và giới hạn bằng chứng

- Đọc source of truth: README, `docs/product/ui-ux.md`, Feature Intake, Test
  Matrix, redesign audit/gap map và 37 route trong `app_router.dart`.
- Audit code 36 screen file, shared components và 73 Flutter test file.
- Kiểm runtime bằng tài khoản audit trên desktop 1280 px, tablet 834 px và mobile
  390 × 844; chờ tối thiểu 5 giây ở các màn tải dữ liệu trước khi kết luận.
- Đã mở các navigation hub, route chi tiết, account menu, notification panel,
  support dialog, dark mode, filter/dropdown, add/edit/reset dialog và bốn form
  cấn trừ.
- Không bấm `Lưu`, `Gửi`, `Tạo`, `Xóa`, `Xuất file`; không mở file picker,
  camera permission hoặc external Seatalk link. Các nhánh này được audit bằng
  code/test, không được coi là runtime-verified.
- `/assignment-pending`, warranty detail có receipt thật, camera/scanner và
  native screen reader vẫn cần manual proof riêng.

## UI Problems

## Issue UI-01

Accessibility tree và focus contract chưa đạt mức phát hành enterprise.

### Location

Screen: toàn app, đặc biệt Web Flutter
Component: interactive card, filter, dialog, tab, table/list, shell
File: `lib/app/`, `lib/features/`, `test/`

### Severity

Critical

### Impact

Người dùng screen reader hoặc chỉ dùng bàn phím có thể không đọc, định vị hoặc
hoàn thành tác vụ. Regression visual vẫn có thể pass dù semantics hỏng.

### Root Cause

Accessibility mới được xử lý cục bộ. Toàn bộ `lib/` chỉ có 5 lần dùng
`Semantics(`, chưa có test focus order/keyboard/semantics/contrast chuyên biệt;
runtime accessibility snapshot không phản ánh các control đang hiển thị.

### Recommendation

- Định nghĩa accessibility contract cho Button, FeatureTile, Input, Dropdown,
  Checkbox group, Tab, Data row, Dialog và StatePanel.
- Bổ sung heading/label/value/hint/live-region và focus traversal rõ ràng.
- Thêm focus ring token, keyboard test và semantics widget test.
- Chạy NVDA trên Windows Web, TalkBack Android và VoiceOver iOS trước release.

### Estimated Complexity

High

## Issue IA-01

Ba lớp navigation lặp cùng workspace: Sidebar → Home → Tác vụ.

### Location

Screen: `/home`, `/tasks`, desktop sidebar
Component: `AppNavModel`, `HomeScreen`, `TasksScreen`, `AppFeatureGrid`
File: `lib/app/navigation/app_nav_model.dart`,
`lib/features/home/presentation/screens/home_screen.dart`,
`lib/app/navigation/tasks_screen.dart`

### Severity

High

### Impact

Tăng cognitive load, làm mờ vai trò của Home và Tác vụ, khiến người dùng không
biết đường nào là canonical. Cùng một chức năng xuất hiện 2–3 lần.

### Root Cause

Home và Tasks cùng lấy `visibleTaskDestinations`; desktop sidebar cũng lấy từ
cùng `destinations`. Home hiện là một task index có thêm profile card.

### Recommendation

- Desktop: sidebar là primary navigation; bỏ grid workspace khỏi Home hoặc chỉ
  giữ 4–6 “Gần đây/Thường dùng/Cần xử lý”.
- Mobile: giữ `Tác vụ` là full catalog; Home là dashboard trạng thái/shortcut.
- Không lặp cùng title/description ở Home và Tasks.

### Estimated Complexity

Medium

## Issue CONTENT-01

Technical/internal terminology lộ ra UI người vận hành.

### Location

Screen: Organization, Feature, Policy, User Admin, FIFO History, Sales Report,
VietQR, Payment Monitor, Bank Statement
Component: admin cards/editor dialogs, status chips, metadata rows
File: `lib/features/admin/presentation/`,
`lib/features/sales_report/presentation/`,
`lib/features/fifo/presentation/screens/fifo_history_screen.dart`,
`lib/features/payment_monitor/`, `lib/features/vietqr/`

### Severity

High

### Impact

Người dùng phải hiểu kiến trúc backend và mã quyền mới thao tác được; tăng lỗi
cấu hình, giảm độ tin cậy và vi phạm Vietnamese-first copy contract.

### Root Cause

UI render trực tiếp field/code từ domain model và dùng cùng thuật ngữ với API.

### Recommendation

- Mapping code → label tiếng Việt; code chỉ nằm trong “Chi tiết kỹ thuật” có thể
  copy ở admin-only surface.
- Đổi `node` → `đơn vị tổ chức`, `rule` → `quy tắc`, `feature` → `tính năng`,
  `User` → `người dùng`, `filter` → `bộ lọc`.
- Không hiện `ADMIN_*`, `BANK_STATEMENT_ALL_SCOPE`, raw status/timestamp ở
  primary text.
- Đổi `pending`/`fully_paid` sang `Chờ thanh toán`/`Đã thanh toán đủ`.

### Estimated Complexity

Medium

## Issue CONTENT-02

Public Help lộ nội dung biên tập và vận hành nội bộ.

### Location

Screen: `/help`, `#roadmap`
Component: public Markdown help renderer
File: `docs/help/content/index.md`, `docs/help/content/getting-started.md`,
`docs/help/content/roadmap.md`, `deploy/home-server/help.html`

### Severity

High

### Impact

Người dùng cuối thấy `Markdown`, `repo`, `deploy`, `pipeline static`, câu hướng
dẫn cho người biên tập và cách gọi cá nhân. Nội dung public trông như tài liệu
dev thay vì help center.

### Root Cause

Authoring notes và user-facing content dùng chung file/surface.

### Recommendation

- Xóa toàn bộ authoring/deploy note khỏi content public.
- Chuyển note cho maintainer sang README riêng không publish.
- Roadmap public chỉ giữ trạng thái/tính năng có ý nghĩa với nhân viên; không
  nhắc pipeline hay quy trình repo.

### Estimated Complexity

Low

## Issue UX-01

Form Báo cáo chưa mua quá dài và không progressive.

### Location

Screen: `/sales-reports/not-purchased`
Component: checkbox groups, category sections, submit action
File: `lib/features/sales_report/presentation/screens/sales_report_screen.dart`

### Severity

High

### Impact

Runtime cần scroll hơn 3.800 px trên desktop mới tới `Gửi báo cáo`; mobile còn
dài hơn. Người dùng phải đọc hàng chục checkbox, nhiều lựa chọn ghép bằng `/`,
dễ bỏ sót, chọn mâu thuẫn hoặc bỏ cuộc.

### Root Cause

Toàn bộ schema nghiệp vụ được trải phẳng trong một form; các câu hỏi không được
ẩn/hiện theo đáp án và không có progress/summary.

### Recommendation

Thiết kế wizard 4 bước:

1. Khách hàng.
2. Nhu cầu/ngành hàng.
3. Trải nghiệm và tư vấn — chỉ hỏi nhánh liên quan.
4. Lý do chưa mua + review trước khi gửi.

Dùng searchable multi-select, radio cho lựa chọn loại trừ nhau, sticky footer
`Quay lại / Tiếp tục`, autosave draft cục bộ và validation summary.

### Estimated Complexity

High

## Issue UX-02

Showroom picker và filter pattern không nhất quán.

### Location

Screen: VietQR, Tiền vào, Sao kê, Cấn trừ, Báo cáo, Admin Users
Component: `AppSelectField`, `AppMultiSelectFilterDropdown`, manual text input
File: `lib/features/vietqr/presentation/screens/vietqr_screen.dart`,
`lib/features/payment_monitor/presentation/screens/payment_monitor_screen.dart`,
`lib/features/bank_statement/presentation/screens/bank_statement_screen.dart`,
`lib/app/widgets/app_filter_dropdowns.dart`

### Severity

High

### Impact

Người dùng phải học lại cùng một thao tác. VietQR mở danh sách showroom rất dài
không tìm kiếm; Tiền vào bắt nhập mã; Sao kê lại có searchable multi-select tốt.

### Root Cause

Mỗi feature tự chọn component; `AppSelectField` vẫn được dùng khi option >10,
trái contract trong `docs/product/ui-ux.md`.

### Recommendation

Tạo một `ShowroomPicker` dùng chung với variant single/multi, search, recent,
assigned scope, error/retry và consistent label. Lấy Sao kê làm baseline.

### Estimated Complexity

Medium

## Issue HIERARCHY-01

Shell title, hero card, chip và section title lặp lại thông tin.

### Location

Screen: hầu hết authenticated route
Component: `_ShellTopBar`, feature header card, `AppStatusChip`, section title
File: `lib/app/navigation/app_shell.dart`, feature screen files

### Severity

Medium

### Impact

First viewport bị dùng để nhắc lại tên module thay vì control/data chính. Trên
mobile, hero card có thể chiếm 25–30% chiều cao trước khi tới tác vụ.

### Root Cause

Migration giữ cả global shell header lẫn feature-local “hero/status header”.

### Recommendation

- Hub: giữ một compact intro nếu cần count/status.
- Form/list: shell title + toolbar; bỏ hero card nếu không có alert/KPI hữu ích.
- Status chip chỉ hiện trạng thái thay đổi được hoặc giúp ra quyết định.

### Estimated Complexity

Medium

## Issue DENSITY-01

Card được dùng cho gần như mọi loại nội dung, kể cả data list mật độ cao.

### Location

Screen: Sales Report, Policy, Feature, VietQR, FIFO Check, Warranty Detail,
Admin lists
Component: `AppSurfaceCard`, data row card
File: các screen tương ứng trong `lib/features/`

### Severity

Medium

### Impact

Desktop scan ít dòng hơn, nhiều border/padding, khó so sánh cột và tăng scroll.
Static inventory đếm 202 card call; riêng một số screen có 10–12 card surface.

### Root Cause

Shared `AppSurfaceCard` trở thành container mặc định cho mọi semantic role.

### Recommendation

Tách rõ FeatureCard, SummaryCard, FormSection, DataRow, DesktopTable và
MobileCard. Data list desktop ưu tiên row/table với column alignment và density
toggle; card chỉ dùng ở mobile hoặc detail summary.

### Estimated Complexity

High

## Issue STATE-01

Cold start chỉ có spinner trống và một số error state thiếu recovery gần lỗi.

### Location

Screen: `/loading`; Sao kê mobile khi tải showroom lỗi
Component: router loading route, error banner/filter panel
File: `lib/app/navigation/app_router.dart`,
`lib/features/bank_statement/presentation/screens/bank_statement_screen.dart`

### Severity

Medium

### Impact

Ở mobile runtime, hard load có thể giữ spinner trống hơn 5 giây. Sao kê báo
`Chưa tải được danh sách showroom` nhưng không đặt action retry ngay trong lỗi.

### Root Cause

Global bootstrap dùng raw `CircularProgressIndicator`; recovery action bị tách
khỏi error context.

### Recommendation

- Dùng branded startup shell/skeleton với copy `Đang tải quyền và dữ liệu`.
- Sau ngưỡng 5–8 giây, hiện retry/offline guidance.
- Error banner luôn có action `Thử lại` tại chỗ và giữ dữ liệu cũ nếu có.

### Estimated Complexity

Medium

## Issue RESPONSIVE-01

iPad portrait 834 px bị phân loại là mobile shell.

### Location

Screen: toàn authenticated app ở tablet portrait
Component: `AppLayoutTokens.tabletBreakpoint`, `AppShell`
File: `lib/app/widgets/app_layout.dart`, `lib/app/navigation/app_shell.dart`

### Severity

Medium

### Impact

Tablet 834 px dùng bottom navigation thay vì compact rail như product contract;
không tận dụng bề ngang và tạo hành vi khác giữa tablet portrait/landscape.

### Root Cause

`tabletBreakpoint = 900`, trong khi iPad 10.9/11 inch portrait phổ biến là
834 px logical width.

### Recommendation

Đổi breakpoint theo capability/layout fit thay vì tên device; thử rail compact
từ 768/800 px nếu content còn tối thiểu 600 px. Chốt matrix 390, 600, 768, 834,
900, 1024, 1200, 1440.

### Estimated Complexity

Medium

## Issue CONTENT-03

Test/sanitized data xuất hiện như dữ liệu nghiệp vụ thật trên staging.

### Location

Screen: FIFO History, Admin Feedback
Component: result cards
File: seed/sanitize data và corresponding presentation screen

### Severity

Medium

### Impact

`STAGING_QUERY`, `Staging FIFO result`, `Staging feedback content` không giúp
audit content thật và có thể khiến tester tưởng tính năng đang lỗi.

### Root Cause

Sanitize script dùng generic placeholder thay vì realistic, clearly-labeled QA
fixture.

### Recommendation

Dùng fixture tiếng Việt có badge `Dữ liệu kiểm thử`, vẫn giữ cấu trúc/độ dài
giống production nhưng không chứa thông tin thật.

### Estimated Complexity

Low

## Issue GLOBAL-01

Delivery metric pill `TB --`/`--` luôn chiếm vị trí global nhưng không giải thích.

### Location

Screen: top bar desktop/mobile
Component: `PaymentDeliveryMetricsChip`, `_ShellMetricsPill`
File:
`lib/features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart`,
`lib/app/navigation/app_shell.dart`

### Severity

Medium

### Impact

Người dùng thấy một mã đo lường không có ngữ cảnh; mobile mất diện tích header,
đẩy title và icon vào vùng chật.

### Root Cause

Operational metric được đặt global cho mọi route, kể cả khi chưa có dữ liệu.

### Recommendation

Ẩn pill khi không có dữ liệu/quyền; khi có dữ liệu dùng label dễ hiểu như
`Loa 1,2 giây`, tooltip/semantics đầy đủ, chỉ hiện cho nhóm cần giám sát.

### Estimated Complexity

Low

## Issue AUTH-01

Auth mobile chưa nhất quán về hierarchy và copy fit.

### Location

Screen: Login, Forgot Password, Register ở 390 px
Component: `AuthScreenShell`, `AuthCard`, form fields
File: `lib/features/auth/presentation/widgets/auth_screen_shell.dart`,
`lib/features/auth/presentation/screens/register_screen.dart`,
`lib/features/auth/presentation/screens/forgot_password_screen.dart`

### Severity

Medium

### Impact

Forgot Password bỏ branding nhưng để khoảng trắng lớn; label `Họ hoặc bộ phận
(không bắt buộc)` bị ellipsis trên 390 px; flow nhìn như ba template khác nhau.

### Root Cause

Copy dài được đặt trong field label một dòng; auth variants chưa có cùng vertical
rhythm.

### Recommendation

Dùng label ngắn `Họ hoặc bộ phận`, helper `Không bắt buộc`; giữ compact brand
header nhất quán trên mọi auth route và test 320/360/390 px.

### Estimated Complexity

Low

## Issue SUPPORT-01

Support dialog hiển thị nguyên invite URL dài như primary content.

### Location

Screen: global Support dialog
Component: `_showSupportDialog`
File: `lib/app/navigation/app_shell.dart`

### Severity

Low

### Impact

Chuỗi URL dài phá hierarchy, khó đọc và không giúp người dùng quét QR nhanh hơn.

### Root Cause

Fallback kỹ thuật được hiển thị trực tiếp thay vì action.

### Recommendation

Giữ QR + hai action `Mở nhóm hỗ trợ`, `Sao chép liên kết`; chỉ hiện URL rút gọn
trong expandable detail khi cần.

### Estimated Complexity

Low

## UX Problems

- Home chưa phải dashboard; nó là bản sao của Tasks kèm profile card lớn.
- Sales Report không progressive, thiếu progress và conditional disclosure.
- Admin configuration dùng ngôn ngữ của hệ thống thay vì mental model của người
  vận hành.
- Các cùng-khái-niệm như showroom, date range, status và export có pattern khác
  nhau theo feature.
- Deep workspaces chưa có breadcrumb/path; shell chỉ highlight parent module.
- Một số action icon-only dựa vào tooltip, không đủ cho mobile/touch và screen
  reader nếu thiếu semantic label.

## Information Architecture Problems

### Sitemap hiện tại

```text
AppShell
├── Trang chủ → grid 9 workspace
├── Tác vụ → grid 10 workspace
├── Quản trị → 7 admin workspace
├── FIFO → 4 tác vụ
├── BH/SC → 2 tác vụ
├── VietQR
├── Tiền vào
├── Sao kê
├── Cấn trừ
├── Báo cáo → 2 tác vụ + nhiều form
├── Góp ý
├── Cài đặt
└── Tài khoản (mobile/account menu)
```

### Sitemap đề xuất

```text
AppShell
├── Tổng quan
│   ├── Cần xử lý
│   ├── Gần đây
│   └── Lối tắt đã ghim
├── Tác vụ
│   ├── Kho: FIFO, sắp xếp, nhập tồn
│   ├── Dịch vụ: BH/SC, góp ý
│   ├── Thanh toán: VietQR, tiền vào, sao kê, cấn trừ
│   └── Báo cáo
├── Quản trị
│   ├── Người dùng & phạm vi
│   ├── Cơ cấu & quyền
│   └── Dữ liệu vận hành
└── Tài khoản & cài đặt
```

Desktop sidebar chỉ nên có nhóm cấp 1 và 5–7 mục thường dùng. Full catalog nằm
ở Tác vụ; Home không lặp catalog.

## Information Hierarchy Problems

### Cấu trúc phổ biến hiện tại

```text
Sidebar active item
↓
Shell title + description
↓
Hero/status card lặp title + description
↓
Status/count chips
↓
Section title
↓
Form/filter card
↓
Result/list card
```

### Cấu trúc đề xuất

```text
Sidebar + compact page title/breadcrumb
↓
Contextual alert/KPI (chỉ khi có giá trị quyết định)
↓
Toolbar / primary action
↓
Content: form, table hoặc list
↓
Sticky action/pagination khi cần
```

## Duplicate Content

| Location | Current Content | Problem | Recommendation |
| --- | --- | --- | --- |
| Sidebar/Home/Tasks | Cùng 9–10 workspace và mô tả | Ba catalog song song | Home chỉ recent/pinned; Tasks là catalog |
| Shell + hero card | `Báo cáo`, `Sao kê`, `Cấn trừ`, `FIFO` lặp | Title redundancy | Giữ shell title; hero chỉ khi có KPI/alert |
| Home profile | `Trang chủ vận hành`, tên, email, chi nhánh | Profile đã có Account destination | Rút thành greeting 1 dòng hoặc bỏ |
| Hub intro + section | `FIFO` rồi `Chức năng FIFO` | Không thêm meaning | Dùng một title `Tác vụ FIFO` |
| Report screen | Shell `Báo cáo` + hero `Báo cáo` | Lặp tuyệt đối | Hero thành summary row hoặc bỏ |
| Status chip | `Chưa chọn SR`, `Chọn SR`, `Chỉ xem danh sách` | Status và instruction trộn | Dùng một helper/action rõ ràng |

## Internal Information Exposed

| Location | Current Content | Problem | Recommendation |
| --- | --- | --- | --- |
| Organization detail | `Lv1 Khối`, `Node cha`, `User`, `SR`, `SALE` | Domain/API terminology | Label tiếng Việt; code trong technical detail |
| Feature assignment | `ADMIN_USERS`, `ADMIN_ORG_TREE` | Permission code ở primary UI | Tên quyền + optional code copy |
| Policy hint | `BANK_STATEMENT_ALL_SCOPE` | Lộ policy key | `Quyền xem toàn hệ thống` |
| Feature screen | `feature`, `node`, `rule cũ` | English/legacy wording | `tính năng`, `đơn vị`, `quy tắc cũ` |
| Sales order | `pending`, `fully_paid`, `ERP` | Raw status/system name | Map trạng thái; bỏ tên hệ thống |
| FIFO History | `STAGING_QUERY`, `Staging FIFO result` | Dummy data | Fixture QA tiếng Việt có badge |
| Admin Feedback | `Staging feedback content` | Dummy data | Fixture QA có ngữ cảnh |
| Public Help | Markdown/repo/deploy/pipeline/`Đại Ca` | Authoring note bị public | Chuyển sang maintainer docs |
| Global top bar | `TB --` | Metric viết tắt không giải thích | Ẩn khi rỗng; label rõ khi có data |
| Timestamp | `2026-07-01T13:37:42.521Z` | ISO technical format | `20:37 01/07/2026` theo VN time |

## Visual Design Problems

- Visual language đã nhất quán hơn, nhưng card/border density quá cao ở data
  screens.
- Hero card pastel dùng rộng đến mức giảm hierarchy; alert, summary và intro
  nhìn gần giống nhau.
- Status chip có nhiều màu nhưng chưa có taxonomy rõ giữa status, count,
  instruction và scope.
- Icon-only admin actions cần consistent destructive color và mobile label.
- Dark mode surface chính ổn; disabled text, muted metadata và warning chip vẫn
  cần đo contrast tự động thay vì chỉ nhìn bằng mắt.

## Component Audit

| Component | Current state | Verdict | Action |
| --- | --- | --- | --- |
| AppShell | Desktop/sidebar, tablet rail ≥900, mobile bottom nav | Keep + adjust | Sửa breakpoint/capability, breadcrumb slot |
| AppFeatureGrid | Responsive 1/2/3 column | Keep | Chỉ dùng cho catalog/hub, không lặp Home/Tasks |
| AppSurfaceCard | Dùng rất rộng | Split | Tách semantic variants; không dùng mặc định cho data row |
| AppPrimary/SecondaryButton | Shape/height nhất quán | Keep | Bổ sung loading/destructive/compact/focus contract |
| AppSelectField | Tốt cho ít option | Restrict | >10 option bắt buộc searchable picker |
| AppFilterDropdown family | Sao kê dùng tốt | Merge/standardize | Là baseline cho filter toàn app |
| CheckboxListTile groups | Dùng trong Sales Report | Replace for long lists | Grouped searchable multi-select/radio + conditional flow |
| AppStatePanel | Có shared states | Keep | Thêm retry action và live-region semantics |
| AppListSkeleton | Có ở nhiều list | Keep | Thêm global/detail skeleton variants |
| Feature hero card | Lặp title/description | Simplify/remove | Chỉ giữ khi có KPI, alert hoặc scope thay đổi |
| Delivery metrics pill | Global, hiện cả khi `--` | Redesign | Permission-aware, hide-empty, clear label |
| Notification panel | Drawer rõ, empty state tốt | Keep | Keyboard focus trap, heading semantics, mobile sheet |
| Support dialog | QR + raw URL | Simplify | QR + open/copy actions, ẩn raw URL |
| Desktop data list | Chủ yếu cards | Replace selectively | Table/row hybrid có density và column alignment |
| Dialog editors | Nhiều dialog kỹ thuật | Redesign | Plain-language labels, helper, focus, validation summary |

## Screen-by-Screen Audit

`Live` nghĩa là đã xem runtime ổn định; `Code/Test` nghĩa là audit từ source và
test nhưng chưa hoàn thành thao tác gây side effect.

| Route / Screen | Component / File | Evidence | Main finding | Recommendation |
| --- | --- | --- | --- | --- |
| `/loading` | router loading scaffold | Live + Code | Bare spinner, cold start >5s | Branded loading + timeout/retry |
| `/login` | `EmailCheckScreen` | Live 1280/834/390 | Clean, responsive; good baseline | Keep, add semantics/focus proof |
| `/register` | `RegisterScreen` | Live 390 | Long label truncates | Short label + helper; test 320–390 |
| `/forgot-password` | `ForgotPasswordScreen` | Live 390 | Branding/rhythm differs from Login | Reuse compact auth header |
| `/assignment-pending` | `AssignmentPendingScreen` | Code/Test | Not runtime-verified | Verify mobile/help/support path |
| `/home` | `HomeScreen` | Live 1280/834/390 | Duplicates Tasks; profile card oversized mobile | Dashboard/recent/pinned only |
| `/tasks` | `TasksScreen` | Live 1280 | Same catalog as Home | Make canonical workspace catalog |
| `/profile` | `ProfileScreen` | Live desktop/mobile | Clear; card-heavy; avatar edit overlay dense | Flatten sections; preserve actions |
| `/admin` | `AdminMenuScreen` | Live | Hub clear but another nested catalog | Group by admin jobs, not system modules |
| `/admin/users` | `UserAdminScreen` | Live + dialogs | Raw org code; technical `Node/Lv`; many filters | Plain labels; shared picker; table desktop |
| `/admin/roles` | `RoleAdminScreen` | Live | Read-only list, much empty space | Add permission summary or compact list |
| `/admin/organization` | `OrganizationTreeAdminScreen` | Live + dialogs | Strong split pane; raw domain model | Rename fields, breadcrumb path, technical detail |
| `/admin/policies` | `PolicyAdminScreen` | Live + dialog | `policy/rule/system role`; icon-only toolbar | Vietnamese copy; labeled toolbar; table |
| `/admin/features` | `FeatureAdminScreen` | Live desktop/mobile + dialogs | Raw codes/node/rule; mobile ellipsis | Hide codes, detail drawer, accessible editor |
| `/admin/personnel` | `PersonnelCatalogAdminScreen` | Live | English names/codes dominate rows | Vietnamese label first; code secondary |
| `/admin/inventory-import` | `InventoryImportScreen` | Live | Simple; status chips useful | Keep; add template/download/error recovery |
| `/admin/feedback` | `FeedbackAdminScreen` | Live | Test data; no useful filter/search at scale | Realistic fixture; date/rating/module filters |
| `/admin/sales-reports` | `SalesReportAdminScreen` | Live | ISO timestamp, card list low density | VN date, desktop table, detail drawer |
| `/fifo-menu` | `FifoMenuScreen` | Live | Clear hub; title duplication | Compact hub, keep 4 actions |
| `/fifo-check` | `FifoCheckScreen` | Live | Primary scan/input visible; nested surfaces | Keep task-first, reduce hero/empty card layers |
| `/fifo-history` | `FifoHistoryScreen` | Live | Dummy query/result; cards low density | Fixture badge, compact rows/table |
| `/fifo/inventory-import` | `InventoryImportScreen` | Same component + Code | Alias route | Keep one canonical route, redirect alias |
| `/sort` | `SortScreen` | Live | Input/result flow clear; hero duplication | Flatten header; keep result near input |
| `/warranty-main` | `WarrantyMainScreen` | Live | Two choices clear; redundant `Về trang chủ` | Remove explicit Home button under shell |
| `/warranty` | `WarrantyScreen` | Live | Compact upload form | Keep; verify camera/file permission states |
| `/check-warranty` | `CheckWarrantyScreen` | Live | Search clear; `Có scanner` wording | `Có máy quét`; remove redundant back button |
| `/check-warranty/details/:receiptNumber` | `WarrantyDetailsScreen` | Code/Test | No stable receipt runtime proof | Manual real-record/image-viewer QA |
| `/vietqr` | `VietQrScreen` | Live + dropdown | Long unsearchable showroom list; MAP copy | Shared searchable picker; remove system name |
| `/payment-monitor` | `PaymentMonitorScreen` | Live | Manual showroom code; MAP/permission copy | Shared picker, plain-language scope |
| `/bank-statement` | `BankStatementScreen` | Live desktop/mobile | Best filter pattern; mobile error lacks retry | Reuse picker; inline retry; remove `filter` |
| `/offset-adjustments` | `OffsetAdjustmentScreen` | Live + 4 forms | Four primary buttons look equal/overweight | Segmented create menu + one primary CTA |
| `/feedback` | `FeedbackScreen` | Live | Form hierarchy good, card-heavy | Keep; verify upload progress/error and a11y |
| `/reports` | `ReportWorkspaceScreen` | Live | Clear 2-card hub | Keep; consider direct last-used shortcut |
| `/sales-reports` | `SalesReportScreen` | Live | Raw status, two-column summary, duplicated title | Status mapping, compact cockpit |
| `/sales-reports/purchased` | purchased form | Live | ERP copy; dependency shown only by disabled fields | 3-step flow with reason/help |
| `/sales-reports/not-purchased` | not-purchased form | Live full scroll | Extreme form length and checkbox load | 4-step conditional wizard |
| `/settings` | `SettingsScreen` | Live light/dark | Clean; Windows disabled state good | Keep; hide global empty metric |
| `/help` | public help renderer | Live | Internal authoring text exposed | Separate public content from maintainer docs |
| `/download` | static download page | Live | Device recommendation and versions clear | Keep; audit download focus/analytics separately |

## Responsive Audit

| Viewport | Result | Risk |
| --- | --- | --- |
| 1280 × 720 desktop | Sidebar and bounded content work; no broad overflow observed | Data density low; hero/card repetition |
| 834 × 1112 tablet portrait | Grid works, but app uses mobile bottom nav | Contract mismatch; tablet rail starts only at 900 |
| 390 × 844 mobile | Home 2-column cards, bottom nav and collapsed finance filters work | Long forms, large profile/hero blocks, `--` metric pill |

Required regression matrix: 320, 360, 390, 600, 768, 834, 900, 1024, 1200,
1440; text scale 100/130/200%; keyboard open on mobile; landscape; safe area.

## Accessibility Audit

| Criterion | Status | Required proof |
| --- | --- | --- |
| Contrast | Partial | Automated token matrix + actual widget screenshots |
| Keyboard navigation | Unverified/high risk | Tab/Shift+Tab/Enter/Escape across shell, dialog, filter, table |
| Focus visibility | Unverified | 2 px focus ring and no focus loss after route/dialog close |
| Screen reader | Fail/unproven on Web | NVDA, TalkBack, VoiceOver task scripts |
| Semantic names/roles | Incomplete | Widget semantics tests for all shared controls |
| Heading/landmark structure | Missing proof | Page title, section heading, navigation/content landmarks |
| Touch target | Mostly visual pass | Automated minimum 48 dp checks for icon/action controls |
| Dynamic state announcement | Missing proof | Loading/error/success/notification live-region |
| Text scaling/reflow | Missing proof | 200% text scale at 320/390/834/1280 |

Accessibility is a release gate, not Phase-7 polish.

## Simplification Proposal

### Home

Current:

```text
Global header
→ Profile hero card
→ Workspace title
→ 9 workspace cards
→ Bottom nav/sidebar repeats same destinations
```

Recommended:

```text
Greeting + current showroom (one line)
→ Cần xử lý / recent activity
→ 4 pinned or recent tasks
→ “Xem tất cả tác vụ”
```

### Finance list

Current:

```text
Shell title
→ Hero title/description/chips
→ Large filter card
→ Count/pagination card
→ Result cards
```

Recommended:

```text
Page title + scope summary
→ Compact filter toolbar / mobile filter sheet
→ Result count + export
→ Desktop rows/table / mobile cards
→ Sticky pagination
```

### Sales Report

Current:

```text
Header
→ All questions expanded
→ Dozens of checkboxes
→ >3,800 px scroll
→ Submit
```

Recommended:

```text
Step 1 Customer
→ Step 2 Need/product
→ Step 3 Consultation/experience (conditional)
→ Step 4 Reason + review
→ Submit
```

### Admin configuration

Current:

```text
System terms/codes
→ Card list
→ Icon-only edit/delete
→ Technical editor dialog
```

Recommended:

```text
User job label
→ Searchable table/list
→ Detail drawer with plain labels
→ Edit dialog
→ Optional “Chi tiết kỹ thuật” disclosure
```

## Component Removal Plan

| Component/pattern | Action | Reason |
| --- | --- | --- |
| Home full workspace grid | Remove/replace | Duplicates Tasks and sidebar |
| Generic feature hero on every screen | Simplify/remove | Repeats shell title, consumes first viewport |
| Raw URL in Support dialog | Hide/replace | Action is more useful than string |
| Empty global `TB --` pill | Remove when empty | No user meaning, consumes header space |
| Feature-local showroom selectors | Merge | Same concept, inconsistent behavior |
| Long checkbox walls | Replace | High cognitive load and scroll |
| Card-as-data-row desktop | Replace selectively | Poor enterprise scan density |
| Redundant `Về trang chủ/Về BH/SC` under shell | Remove | Global navigation already provides path |
| Raw technical codes as primary text | Hide/relegate | Violates user-facing copy contract |
| Duplicate Home/Tasks descriptions | Remove | Information redundancy |

## Information Cleanup Plan

| Location | Current Content | Problem | Recommendation |
| --- | --- | --- | --- |
| Auth intro | `feature được gán` | English technical term | `tính năng được cấp` |
| Organization | `Tìm node` | Internal term | `Tìm đơn vị tổ chức` |
| Organization | `Lv0 Domain`, `Lv1 Khối` | Schema label | `Tên miền`, `Khối` |
| Policy | `Thêm policy`, `policy rule` | English mix | `Thêm chính sách`, `Thêm quy tắc` |
| Feature | `Gán node`, `Thêm rule cũ` | English/legacy | `Cấp theo đơn vị`, `Thêm quy tắc cũ` |
| Bank Statement | `Chọn 1 filter chính` | English | `Chọn ít nhất một tiêu chí tìm kiếm` |
| Warranty | `Có scanner` | English | `Có máy quét` |
| Sales Report | `User: Tất cả` | English | `Nhân viên: Tất cả` |
| Purchased Report | `kiểm tra ERP` | Internal system | `kiểm tra đơn hàng` |
| Payment/VietQR | `giao dịch MAP` | Internal system | `giao dịch thanh toán` |
| Status | `pending`, `fully_paid` | Raw enum | Vietnamese status labels |
| Help | Markdown/repo/deploy/pipeline | Maintainer content | Remove from public page |
| Help | `Đại Ca` | Personal address term | Neutral user-facing copy |
| Report timestamp | ISO UTC string | Hard to scan | VN local formatted date/time |

## Detailed Refactor Roadmap

### Phase 1 — Quick Wins

**Goal:** dọn nội dung và thành phần gây nhiễu, không đổi business logic.
**Work:** Vietnamese mappings, Help cleanup, hide-empty metric, short auth labels,
support actions, realistic QA fixtures.
**Components:** copy mapper, status labels, Help content, metrics pill.
**Risk:** admin cần code kỹ thuật để support; giữ trong expandable detail.
**Done:** không còn English/internal code ở primary text; content grep và visual QA
pass.

### Phase 2 — Information Architecture

**Goal:** phân vai rõ Home, Tasks, Sidebar và hubs.
**Work:** Home dashboard/recent/pinned; Tasks canonical catalog; group sidebar;
breadcrumb/context path cho sub-workspace.
**Components:** `AppNavModel`, `AppShell`, Home, Tasks, hub template.
**Risk:** route/permission regression.
**Done:** mỗi destination có một canonical entry; route guard tests và navigation
smoke pass.

### Phase 3 — Layout

**Goal:** giảm tầng container và tăng data density.
**Work:** remove redundant hero; create compact page toolbar; desktop table/row;
tablet master-detail; sticky actions/pagination.
**Components:** PageHeader, Toolbar, DataList/Table, FormSection.
**Risk:** visual churn trên nhiều screen.
**Done:** primary action/data nằm trong first viewport ở representative screens;
desktop scan density tăng tối thiểu 30%.

### Phase 4 — Components

**Goal:** một pattern cho cùng khái niệm.
**Work:** `ShowroomPicker`, FilterBar/FilterSheet, DateRange, status mapping,
dialog editor, grouped multi-select, stepper.
**Components:** shared widget layer trước, feature migration sau.
**Risk:** callback/state contract khác nhau giữa providers.
**Done:** VietQR/Payment/Sao kê/Cấn trừ/Admin dùng shared picker/filter; guard test
ngăn local variant mới.

### Phase 5 — Responsive

**Goal:** behavior đúng ở phone, tablet portrait/landscape, desktop.
**Work:** breakpoint fit audit; tablet rail ở 768/834 khi đủ chỗ; 320–1440 matrix;
text scaling; keyboard/safe area.
**Components:** `AppLayoutTokens`, `AppShell`, forms, tables, dialogs.
**Risk:** rail làm content quá hẹp ở split-pane screens.
**Done:** zero overflow/clipping; all actions reachable; screenshots and widget
tests pass matrix.

### Phase 6 — Accessibility

**Goal:** WCAG 2.2 AA baseline cho task chính.
**Work:** semantics, focus order/ring, keyboard shortcuts, live regions, dialog
focus trap, contrast matrix, screen-reader task scripts.
**Components:** tất cả shared interactive primitives và shell.
**Risk:** Flutter Web semantics behavior khác native.
**Done:** NVDA/TalkBack/VoiceOver hoàn thành Login, FIFO, VietQR, Sao kê, Report;
automated semantics/focus tests pass.

### Phase 7 — Visual Polish

**Goal:** hoàn thiện hierarchy/taxonomy sau khi workflow ổn.
**Work:** chip color taxonomy, density variants, icon alignment, motion, empty
illustration, dark/disabled contrast.
**Components:** tokens, cards, chips, tables, states.
**Risk:** polish che giấu regressions UX nếu làm sớm.
**Done:** visual regression approved ở light/dark và 3 platform classes.

## Priority Matrix

| Priority | Issues | Why now |
| --- | --- | --- |
| Critical | UI-01 accessibility | Blocker cho người dùng hỗ trợ công nghệ; visual smoke không bắt được |
| High | IA-01, CONTENT-01, CONTENT-02, UX-01, UX-02 | Tác động trực tiếp hiểu/hoàn thành tác vụ và public trust |
| Medium | HIERARCHY-01, DENSITY-01, STATE-01, RESPONSIVE-01, CONTENT-03, GLOBAL-01, AUTH-01 | Giảm tốc độ scan, recovery và consistency |
| Low | SUPPORT-01 | Quick polish, ít rủi ro |

## Acceptance Checklist

- [ ] Home không còn lặp full catalog của Tasks/sidebar.
- [ ] Không còn title/subtitle/hero lặp mà không mang KPI, alert hoặc context.
- [ ] Không còn `feature`, `node`, `rule`, `policy`, `filter`, `User`, `ERP`,
      `MAP` trong normal user-facing copy.
- [ ] `ADMIN_*`, policy key và raw enum chỉ nằm trong technical detail admin.
- [ ] Public Help không còn Markdown/repo/deploy/pipeline/personal address.
- [ ] Không còn placeholder/dummy content không gắn badge QA trên staging.
- [ ] VietQR, Tiền vào, Sao kê, Cấn trừ dùng shared showroom picker.
- [ ] Option list >10 luôn tìm kiếm được.
- [ ] Sales Report chưa mua có progress, conditional questions và review step.
- [ ] Không cần scroll hơn một step để tìm action tiếp theo trong form wizard.
- [ ] Data list desktop dùng row/table khi cần scan/compare.
- [ ] Card không lồng card nếu không có semantic boundary rõ.
- [ ] Loading/error/empty/success có copy và action phục hồi phù hợp.
- [ ] `TB --` bị ẩn; metric có label rõ khi xuất hiện.
- [ ] Tablet 768/834 được kiểm rail vs bottom nav bằng content-fit proof.
- [ ] Không overflow ở 320/360/390/600/768/834/900/1024/1200/1440.
- [ ] Text scale 200% không mất content/action.
- [ ] Keyboard focus order và focus ring pass mọi shared control.
- [ ] NVDA/TalkBack/VoiceOver hoàn thành 5 task cốt lõi.
- [ ] Contrast đạt WCAG AA cho normal text và interactive state.
- [ ] Tooltip không phải cách duy nhất truyền đạt ý nghĩa.
- [ ] Typography, color, spacing, radius và status taxonomy thống nhất.
- [ ] Runtime logs vẫn ghi start/success/failure/branch bằng `AppLogger` cho mọi
      flow được refactor, không lộ secret/sensitive payload.
- [ ] Docs product, story và Test Matrix được cập nhật cùng implementation.

## Estimated Effort

| Phase | Product/UX | Flutter | QA/A11y | Total person-days |
| --- | ---: | ---: | ---: | ---: |
| Quick wins | 2–3 | 3–5 | 1–2 | 6–10 |
| IA | 3–5 | 4–7 | 2–3 | 9–15 |
| Layout/density | 4–6 | 8–12 | 3–5 | 15–23 |
| Shared components | 4–6 | 10–15 | 4–6 | 18–27 |
| Responsive | 2–4 | 5–8 | 4–6 | 11–18 |
| Accessibility | 3–5 | 8–12 | 6–10 | 17–27 |
| Visual polish | 3–5 | 3–5 | 2–4 | 8–14 |

Tổng thô: **84–134 person-days** nếu làm toàn bộ scope. Với 1 product designer,
2 Flutter engineers và QA part-time: khoảng **8–12 tuần**, chia release nhỏ theo
phase. Sales Report và accessibility nên có story/high-risk validation riêng.

## Risks

- Refactor IA có thể làm lệch feature visibility/route guard theo role.
- Mapping technical code sang label có thể làm support thiếu dữ liệu; cần
  technical detail/copy action thay vì xóa code hoàn toàn.
- Wizard Sales Report phải giữ nguyên request contract và draft behavior; cần
  regression test payload cho mọi nhánh.
- Shared picker phải giữ explicit user override và scope policy của từng module.
- Flutter Web semantics có khác biệt với Android/Windows; không được dùng widget
  test thay cho screen-reader smoke thật.
- Staging sanitized data không đại diện đầy đủ độ dài/nội dung production.
- Camera, file picker, export/download, speaker audio và external link vẫn cần
  device/manual proof.

## Final Recommendation

Không rewrite app và không thay business logic. Giữ design system/shared shell
hiện tại làm nền, nhưng dừng thêm feature-local UI variant. Bắt đầu bằng một
release “Content + Accessibility Gate”, sau đó làm IA và shared picker/filter,
rồi mới chuyển Sales Report sang wizard và data lists sang density enterprise.

Tiêu chí gọi redesign hoàn tất phải là: **task completion + plain-language
content + accessibility proof + responsive matrix**, không chỉ là token coverage,
Figma frame đủ route hoặc visual smoke không có screenshot trắng.
