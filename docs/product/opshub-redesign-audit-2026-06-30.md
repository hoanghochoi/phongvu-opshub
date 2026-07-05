# OpsHub UI/UX Redesign Audit

Ngày kiểm tra: 30/06/2026
Môi trường: staging web `https://opshub-staging.hoanghochoi.com/#/home`
Checkpoint repo: branch `staging`, HEAD `8ddeb0f`, worktree sạch
Phạm vi: audit read-only, không bấm Lưu/Tạo/Xuất/Gửi, không thay đổi dữ liệu

## Cập nhật trạng thái Redesign V2 - 03/07/2026

Audit này là baseline read-only của ngày 30/06/2026, không còn là trạng thái
implementation hiện tại. Trạng thái migration/acceptance mới được theo dõi ở
`docs/product/opshub-redesign-gap-map-2026-07-01.md` và `docs/TEST_MATRIX.md`.

Bằng chứng repo/Figma đã được bổ sung sau baseline:

- App đã có `AppShell` responsive cho desktop/tablet/mobile, thay các
  `GradientHeader` riêng ở các authenticated feature screens.
- Các hub/form/data-heavy runtime screen đã được migrate theo contract hiện có:
  Home, Tasks, Admin, FIFO, BH/SC, VietQR, Sao kê, Cấn trừ, Báo cáo, Sales
  Report, Góp ý, Profile, Settings, Auth pre-shell và các admin workspaces.
- Figma handoff inventory đã được dọn theo runtime: mỗi page mobile/tablet/
  desktop giữ 40 runtime frames active; `Data Workspace` và
  `FIFO Conversation Check` được retire/hidden; `Generic Report Workspace` và
  `Personnel Catalog Admin` đã có route thật.
- Web visual smoke mặc định kiểm 3 public auth routes, 1 pending auth route và
  31 authenticated shell routes trên desktop/mobile, tổng 70 route/viewport
  checks; guard test khóa route inventory và smoke script có PNG pixel sanity
  để bắt screenshot trắng/phẳng hoặc sai kích thước viewport.

Không dùng điểm `62/100` bên dưới làm điểm hiện tại; điểm đó là baseline trước
đợt migration. Tiến độ plan implementation đang ở khoảng 98%, còn lại phần
verify batch cuối và các smoke thủ công trên thiết bị/nền tảng thật như
camera/QR, Windows hardware và screen reader trước khi gọi là full visual
parity.

## Nguồn chuẩn tham chiếu

- Nielsen Norman Group: [10 Usability Heuristics](https://www.nngroup.com/articles/ten-usability-heuristics/)
- W3C: [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- Material Design 3: [M3 foundations and components](https://m3.material.io/)
- Apple: [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- Heuristic nội bộ: `docs/product/ui-ux.md` của OpsHub, ưu tiên workflow vận hành nội bộ, staff-first, dense-but-readable, Vietnamese-first.

## Phạm vi đã kiểm chứng

- Desktop/web viewport gần hiện tại: `1004 x 720`.
- Tablet viewport: `768 x 1024`.
- Mobile viewport: `390 x 844`.
- Đã xem: Home, drawer, Admin hub, Admin Users, Admin Roles, Organization Tree, Policies, Admin Feedback, Admin Sales Reports, FIFO hub, FIFO Check, FIFO History, Sort FIFO, VietQR, Bank Statement, Offset Adjustment, Payment Monitor unsupported, Sales Report hub/form, Feedback, Profile, Settings.
- Đã kiểm: keyboard Tab trên web, Flutter web semantics snapshot, contrast token chính, loading/skeleton mặc định trên một số list.

## Dữ liệu còn thiếu

- Chưa test native iOS/Android bằng VoiceOver/TalkBack.
- Chưa test camera/scanner permission, keyboard mobile native, safe area trên thiết bị thật.
- Chưa audit đầy đủ dialog create/edit/delete vì cần tránh tạo/sửa dữ liệu staging.
- Chưa audit dark mode bằng thao tác đổi preference vì có thể lưu trạng thái người dùng.
- Chưa audit tất cả role/permission-specific screen variants.

# Tóm tắt tổng quan

OpsHub đang có nền tảng tốt ở mức component/token: màu sắc tập trung trong `AppColors`, typography có scale riêng, nhiều màn hình đã dùng `AppResponsiveContent`, `AppFeatureSection`, `AppStatePanel`, `AppListSkeleton`, và copy tiếng Việt ngày càng nhất quán.

Vấn đề lớn nhất không nằm ở visual style đơn lẻ, mà nằm ở app shell và responsive foundation. Nhiều form/list bị cắt ngang trên web/tablet/mobile, đặc biệt `VietQR`, `Cấn trừ`, `Báo cáo`, `Profile`, `Settings`, và admin filters. Trên web, accessibility tree không phản ánh nội dung thật của màn hình; keyboard focus không hiện rõ. Với sản phẩm vận hành nội bộ, các lỗi này ảnh hưởng trực tiếp đến khả năng hoàn thành tác vụ.

# Định hướng sản phẩm đề xuất

Nên viết lại định hướng sản phẩm theo hướng:

> OpsHub là operation command center cho nhân viên Phong Vu/ACare, tối ưu cho tác vụ lặp lại hằng ngày: quét, tìm, lọc, đối chiếu, xác nhận, báo cáo và xử lý lỗi. Giao diện phải task-first, role-aware, Vietnamese-first, đọc nhanh trên cả mobile và desktop, giữ logic nghiệp vụ hiện có nhưng chuẩn hóa navigation, form, filter, list, status và handoff cho dev.

Định hướng này thay cách nhìn “tập hợp các feature cards”. Sản phẩm nên có 4 lớp trải nghiệm:

1. **Command shell**: sidebar/topbar/breadcrumb/notification/profile nhất quán.
2. **Task modules**: FIFO, BH/SC, VietQR, Sao kê, Cấn trừ, Báo cáo, Góp ý.
3. **Admin console**: quản trị người dùng, vai trò, cơ cấu, chính sách, feedback/report.
4. **Design system**: token, component, pattern, template, state và platform rule dùng chung.

Không cần đổi logic nghiệp vụ. Cần đổi cách nhóm, hiển thị, phân cấp, responsive và state.

# Điểm UI (/100)

**62/100**

Lý do:

- Điểm mạnh: visual sạch, màu chủ đạo rõ, card-grid nhất quán ở các hub, icon có tính gợi nhớ, typography dễ đọc trên nhiều screen.
- Điểm trừ: header quá nặng trên desktop, layout form bị cắt, data density chưa phù hợp enterprise, một số màn hình trắng/trống khi loading, nhiều component có kích thước/width không theo cùng breakpoint.

# Điểm UX (/100)

**56/100**

Lý do:

- Điểm mạnh: Home và hub giúp vào nhanh các module; nhiều empty state có nội dung hành động; filter `Sao kê` có hướng collapse trên mobile.
- Điểm trừ: user flow web/desktop thiếu sidebar/breadcrumb, nhiều tác vụ chính không nằm trong first viewport hoặc bị cắt, filter pattern không đồng nhất, form phụ thuộc từng bước nhưng không có progress/stepper rõ.

# Điểm Accessibility

**34/100**

Lý do:

- Flutter web accessibility snapshot không đọc được UI hiển thị; chỉ thấy `Enable accessibility` và field cũ không thuộc screen đang xem.
- Keyboard Tab trên Home không cho focus ring rõ trên card/action; active element là `FLUTTER-VIEW`.
- Một số contrast token cần cảnh báo: white trên `gradientEnd #3B82F6` khoảng `3.68:1`, đủ cho large text nhưng không an toàn cho normal/small text; `neutral400` trên nền sáng khoảng `2.39:1`.
- Chưa có bằng chứng screen reader label, focus order, landmark/heading structure trên web.

# Điểm Design Consistency

**61/100**

Lý do:

- Hub cards có pattern khá đồng nhất.
- Form/list/filter/admin screen chưa đồng nhất về breakpoint, width, loading, empty state, button grouping, table/list density, và cách expose technical copy.
- Có token/component trong code, nhưng nhiều feature vẫn cần enforcement ở design system và guardrail Figma/dev.

# Các vấn đề nghiêm trọng

| Mức độ | Vấn đề | Ảnh hưởng | Nguyên nhân | Đề xuất |
| --- | --- | --- | --- | --- |
| Critical | Responsive clipping trên form/filter/action | Người dùng không thấy hoặc không bấm được nút, field, pagination | Breakpoint/layout foundation không áp dụng đồng nhất, child width vượt viewport Flutter | Chuẩn hóa App Shell + responsive grid/form templates, test 390/768/desktop |
| Critical | Accessibility web không đọc được UI thật | Screen reader/keyboard user không hoàn thành tác vụ | Flutter web semantics/focus chưa expose đúng | Audit semantics, focus traversal, labels, focus ring, TalkBack/VoiceOver proof |
| High | Desktop navigation thiếu sidebar/breadcrumb | Khó tìm màn hình, phụ thuộc browser/system back | Mobile app shell được dùng gần như nguyên bản cho web | Desktop shell có sidebar collapsed, breadcrumbs, active state |
| High | Filter/list pattern không đồng nhất | Staff mất thời gian học lại mỗi module | Mỗi feature tự xử lý filter/action | Tạo Filter Bar/Filter Drawer/List Toolbar pattern trong design system |
| High | Technical/internal copy lộ ra UI | Làm nhiễu, khó hiểu, giảm tin cậy | Admin data hiển thị raw code/timestamp | Map code sang label, raw code đưa vào secondary/meta/copy detail |
| Medium | Loading/empty state chưa đồng nhất | Người dùng tưởng app treo hoặc không biết bước tiếp theo | Một số list render trắng trước khi có data | Dùng skeleton/state panel trên mọi first-load |

# Đánh giá chi tiết từng màn hình

| Màn hình | IA /10 | User flow | Layout/UI/Accessibility | Đề xuất |
| --- | ---: | --- | --- | --- |
| Home | 7 | Vào feature nhanh, nhưng web chỉ có hamburger và cards | Card-grid sạch; header cao; desktop không có sidebar; mobile 2 cột hơi chật | Desktop sidebar + Home dashboard nhẹ; mobile có bottom nav/action area; giữ card-grid nhưng thêm grouping theo domain |
| Drawer | 5 | Truy cập profile/admin/settings/help/logout | Drawer trên desktop quá rộng, không có active state, logout ngang hàng các mục khác | Desktop sidebar persistent; drawer mobile có section, active item, danger zone riêng |
| Admin hub | 7 | 4 mục chính dễ hiểu | Dùng card pattern, nhưng không có breadcrumb/back rõ trên web | Thêm breadcrumb `Home / Quản trị`, action/help link contextual |
| Quản lý người dùng | 6 | Search + filter + clear | Filter nhiều hàng, mobile/tablet có item bị cắt; skeleton có nhưng first-load chỉ nhìn thấy list skeleton | Dùng admin table/list responsive, filter drawer trên mobile, sticky action `Thêm/Import` |
| Quản lý vai trò | 6 | Chọn role từ list | Có lúc render trắng trước khi hiện role; list thừa khoảng trắng desktop | Skeleton ngay lúc load, role card có count/permission summary |
| Cơ cấu tổ chức | 6 | Chọn node -> xem/sửa chi tiết | Split pane đúng với desktop nhưng tablet bị chật; technical labels `Lv0`, `Lv1`, `SALE`, `User`, `SR` cần giải thích | Tree + detail panel có density compact, breadcrumb node path, action group có label |
| Quản lý chính sách | 5 | Tab `Chính sách/Quy tắc` | Raw policy code trong title gây nhiễu; list divider thấp contrast; admin-only code cần secondary | Dùng policy table/card có label staff-first, code trong monospace secondary/copy |
| Danh sách góp ý | 5 | Xem feedback list | ISO timestamp, rating text, email raw; thiếu filter/search/status | Card có rating stars/chip, date format `HH:mm dd/MM/yyyy`, filter theo ngày/rating/module |
| Admin báo cáo bán hàng | 6 | Lọc loại report, tải lại, xem list | Nút `Tải lại` bị cắt desktop; pagination bị cắt; list card dễ đọc | Table/card hybrid, sticky filter/action, pagination visible |
| FIFO hub | 7 | 3 tác vụ rõ | Hub sạch, nhưng desktop thừa nhiều khoảng trắng | Giữ card-grid, thêm mô tả ngắn và shortcut scan |
| Kiểm tra FIFO | 4 | Cần nhập/quét SKU/serial | First viewport chỉ thấy empty prompt, không thấy field/action rõ | Đưa scan/input/action vào primary zone, empty state bên dưới |
| Sắp xếp FIFO | 5 | Nhập/quét SKU/BIN | Hướng dẫn có, empty state lệch xuống dưới; input/action không rõ trong first viewport | Step input đầu màn, state result gần input, scan CTA rõ |
| Lịch sử FIFO | 6 | Search/filter, xem cards | Search full width quá lớn, tab gradient không giống tab system, label `Query` tiếng Anh | Filter bar compact, tab segmented, label Việt hóa `Truy vấn` |
| VietQR | 6 | Nhập số tiền/nội dung/SR -> tạo QR | Form đơn giản nhưng desktop/mobile bị cắt ngang; placeholder thay label chưa đủ | Form max-width đúng viewport, label/helper/error riêng, sticky primary action |
| Sao kê | 6 | Chọn filter -> Tìm -> xem giao dịch | Desktop filter bị cắt; mobile có collapsed filter tốt nhưng automation không thấy semantics; empty state rõ | Chuẩn hóa filter drawer, action `Tìm/Xóa/Xuất` cùng group, table/card density theo device |
| Cấn trừ | 5 | Chọn loại/filter -> Tìm/Xuất -> xem hồ sơ | Top type buttons quá lớn và bị cắt; filter multi-column bị cắt trên tablet; cards quá rộng | Đổi top buttons thành segmented/tabs scrollable, filter collapse dưới 900px |
| Theo dõi tiền vào unsupported | 6 | Giải thích không hỗ trợ web -> về Home | Copy đúng hướng, nhưng layout lệch và text có dấu hiệu bị cắt | Center state panel thật sự, thêm CTA tải app Windows/Android nếu có |
| Báo cáo hub | 7 | Chọn mua/chưa mua | Hai lựa chọn rõ, card pattern đúng | Giữ, thêm badge/last submitted nếu cần |
| Báo cáo mua hàng | 5 | Nhập mã đơn -> kiểm tra -> điền thông tin | Step dependency có nhưng không có stepper; form bị cắt; disabled fields thấp contrast | Stepper 1-2-3, validation inline, disabled state có lý do |
| Báo cáo chưa mua | 5 | Nhập SĐT -> chọn ngành/liên hệ/lý do | Checkbox list dài, label bị cắt trên mobile; Hick's Law risk | Multi-select dropdown/search, group categories, sticky submit |
| Góp ý | 6 | Chọn module -> nội dung -> ảnh -> gửi | Form dễ hiểu; desktop/mobile có dấu hiệu width cắt; image upload state cần rõ hơn | Form template chung, upload component có count/size/progress/error |
| Profile | 5 | Xem/sửa thông tin, đổi mật khẩu | Nút đổi mật khẩu bị cắt trên desktop/tablet; info cần group rõ | Profile template 2 column desktop, 1 column mobile, action row không overflow |
| Settings | 5 | Đổi theme, xem Windows setting | Segmented theme bị cắt; disabled Windows state có copy rõ | Segmented control responsive, platform badge, disabled reason + next action |

# Danh sách lỗi

## Critical

1. **Clipping ngang trên nhiều screen**: `VietQR`, `Sao kê`, `Cấn trừ`, `Báo cáo`, `Profile`, `Settings`, `Admin Users`.
   - Ảnh hưởng: tác vụ có thể không hoàn thành vì nút/field bị ngoài vùng nhìn.
   - Chuẩn liên quan: WCAG reflow, Material responsive layout, Fitts's Law.

2. **Accessibility web không expose UI**:
   - Evidence: dom/accessibility snapshot không có card/label visible; keyboard focus không rõ.
   - Ảnh hưởng: screen reader/keyboard user gặp blocker.

## High

3. **Desktop app shell chưa đúng enterprise pattern**:
   - Hiện trang con thiếu sidebar/breadcrumb/back rõ.
   - Jakob's Law: user desktop SaaS mong đợi sidebar, active route, breadcrumbs.

4. **Filter behavior không đồng nhất**:
   - `Sao kê` mobile collapse; `Cấn trừ` vẫn multi-column; admin filters wrap không ổn định.
   - Ảnh hưởng: người dùng học lại mỗi màn hình.

5. **Technical copy/raw data lộ ra UI**:
   - Ví dụ: policy codes, ISO timestamp, `Query`, `Lv0/Lv1`, `ADMIN_*`.
   - Ảnh hưởng: tăng cognitive load, trái Vietnamese-first/user-facing copy.

6. **Primary task không nằm trong first viewport**:
   - FIFO Check/Sort hiện empty state lớn nhưng input/action không rõ.
   - Ảnh hưởng: user không biết cần thao tác ở đâu.

## Medium

7. **Data density desktop chưa phù hợp**:
   - Nhiều list dùng card cao, filter/button lớn, khó scan số lượng dòng lớn.

8. **State loading/empty/error chưa đồng đều**:
   - Có screen skeleton tốt, có screen trắng/trống quá lâu.

9. **Contrast disabled/secondary state cần chuẩn hóa**:
   - `neutral400` trên nền sáng không đạt AA cho text cần đọc.

10. **Touch/focus/hover/pressed states chưa được nhìn thấy rõ**:
   - Hover có tooltip ở một số action, focus ring web chưa rõ.

## Low

11. **Header gradient lặp lại quá mạnh**:
   - Dễ nhận diện brand, nhưng chiếm diện tích và làm UI một màu.

12. **Icon style và màu chip chưa có taxonomy rõ**:
   - Nhiều màu pastel đẹp nhưng chưa gắn semantic meaning nhất quán.

# Component Audit

| Component | Hiện trạng | Vấn đề | Đề xuất |
| --- | --- | --- | --- |
| Button | Có `AppPrimaryButton`, `AppSecondaryButton`, icon action | Một số action bị cắt, loading/disabled chưa audit hết | Figma variants: size, icon, loading, destructive, compact, full-width, focus |
| Input/Text Field | Có icon + label/placeholder | Form width overflow; helper/error chưa nhất quán | Tạo field template label/helper/error/counter, width rules |
| Dropdown/Select | Có AppSelect/Filter dropdown | Mobile pattern không đồng nhất; >10 items cần search | Single-select, multi-select, searchable, date range, anchored panel |
| Checkbox/Radio | Checkbox trong sales report | Long labels bị cắt; tap target cần xác minh | Checkbox row full-width, multiline, group label, error state |
| Switch/Segmented | Settings theme, Offset type buttons | Segmented bị cắt, type buttons quá lớn | SegmentedControl responsive + horizontal scroll khi cần |
| Card | Hub cards tốt | Cards dùng cho cả data list gây low density | Tách FeatureCard, DataCard, SummaryCard, ActionCard |
| Modal/Dialog | Chưa audit đầy đủ | Cần state/focus trap/screen reader | Dialog spec: confirmation/detail/editor, max width, actions |
| Bottom Sheet | Chưa thấy pattern rõ | Mobile filter nên dùng sheet/drawer | Filter bottom sheet with apply/clear/sticky footer |
| Navigation | Drawer + top header | Desktop thiếu sidebar/breadcrumb/active | AppShell variants: mobile top+bottom, tablet rail, desktop sidebar |
| Tab | Policy tabs, FIFO tab-like gradient | Style không đồng nhất | Tabs/segmented with selected/inactive/focus tokens |
| Table/List | Chủ yếu card lists | Enterprise scan kém khi nhiều dòng | Responsive table desktop, card mobile |
| Search/Filter | Có nhiều filter | Width/grouping không đồng nhất | FilterBar + FilterDrawer + saved filter summary |
| Pagination | Có trên finance/report | Bị cắt ở một số viewport | Pagination compact/mobile + page size dropdown |
| Toast/Snackbar | Chưa audit trực tiếp | Cần rule copy/action | Snackbar/toast spec: success/error/action duration |
| Empty/Loading/Error | Có AppStatePanel/Skeleton | Placement và first-load chưa đều | State templates theo list/form/detail |
| Skeleton | Có AppListSkeleton | Một số screen trắng | Bắt buộc cho first-load list/detail |

# Accessibility

| Tiêu chí | Trạng thái | Lỗi | Đề xuất |
| --- | --- | --- | --- |
| Contrast | Partial pass | Header gradient lighter zone, disabled text, warning text cần review | Token contrast matrix AA trong Figma |
| Font size | Mostly pass | Một số metadata/list text cần nhỏ trên mobile | Minimum body 14, caption chỉ cho meta phụ |
| Touch target | Partial pass | Icon/topbar/filter row cần xác minh; card OK | 44pt iOS, 48dp Material, min target token |
| Focus state | Fail web evidence | Tab không hiện focus ring rõ | Focus ring 2px token, focus traversal order |
| Keyboard nav | Fail web evidence | Active element chỉ `FLUTTER-VIEW` | Semantic focusable controls, shortcuts cho desktop |
| Screen reader | High risk | Snapshot không đọc được UI | Semantic labels, headings, buttons, state announcements |
| Color blind | Partial | Status dùng màu + text, nhưng icon/tone chưa taxonomy | Status must include text/icon, không chỉ dùng màu |
| WCAG AA | Not met yet | Reflow/focus/name-role-value chưa đạt bằng chứng | Accessibility QA gate theo viewport + screen reader |

# UX trên Mobile

- Home có thể đọc được, nhưng 2-column card trên mobile làm mỗi card hẹp; nên cân nhắc 1-column cho tác vụ phức tạp hoặc 2-column chỉ cho shortcut nhẹ.
- Thumb zone: action quan trọng nên ở dưới hoặc sticky footer; hiện tại nhiều form đặt action bị cắt/xa.
- Bottom navigation chưa rõ; hamburger yếu cho tác vụ lặp lại.
- Filter mobile nên là bottom sheet/drawer có Apply/Clear sticky footer.
- Keyboard: form cần auto-scroll field đang focus, input type đúng, helper/error sát field.
- Safe area: cần test native notch/home indicator.
- Scroll experience: một số empty state nằm quá thấp hoặc bị cắt.

# UX trên Web/Desktop

- Cần desktop shell riêng: sidebar/rail, breadcrumb, active state, global search optional, notification/profile rõ.
- Dashboard Home nên ưu tiên shortcut + recent/alerts, không chỉ feature grid.
- Data density cần tăng: admin/finance/report nên có table desktop và card mobile.
- Multi-column form phải có max width, responsive collapse, và không dùng horizontal clipping.
- Filter/action row nên sticky hoặc nằm gần list; export gần filter nếu dùng filter hiện tại.

# Interaction Design

- Animation/transition: chưa thấy lỗi lớn, nhưng loading transition có lúc blank.
- Hover: có tooltip `Menu`, nhưng hover state của cards/buttons cần nhất quán.
- Pressed/disabled: disabled fields trong report quá mờ, cần kèm lý do.
- Focus: fail trên web evidence.
- Success/error/loading feedback: có AppStatePanel/AppStatusBanner, cần enforce trên mọi first-load/form submit/export.
- Micro-interaction: scanner/input/report step cần thêm feedback ngay khi scan/validate.

# So sánh với sản phẩm hiện đại

| Sản phẩm | Nguyên tắc nên học | Áp dụng cho OpsHub |
| --- | --- | --- |
| Stripe | Dense dashboard, table/filter rõ, docs-like clarity | Finance/admin list cần table + filter toolbar rõ |
| Linear | Sidebar, keyboard-friendly, state/status chips gọn | Desktop shell + issue/status patterns |
| Notion | Progressive disclosure, inline editing rõ | Admin policy/org tree chỉ hiện raw code khi cần |
| Slack | Navigation + notification consistent | Global bell/sidebar, active workspace-like context |
| Airbnb | Form flow có step, validation gần field | Sales report/VietQR/Feedback forms |
| Apple | Platform convention, touch target, clarity | iOS/mobile safe area, navigation back/bottom action |
| Google Material 3 | Responsive layout, component states | Tokens, state layers, M3 text fields/buttons |
| Microsoft Fluent | Enterprise density, command bar, data table | Admin console/table/list/action bar |

# Giải pháp đề xuất

| Vấn đề | Nguyên nhân | Giải pháp | Lợi ích | Ưu tiên | Độ khó |
| --- | --- | --- | --- | --- | --- |
| Clipping form/filter | Breakpoint/wrapper không đồng nhất | Tạo `ResponsiveFormTemplate`, `FilterBar`, `FilterDrawer`; QA 390/768/desktop | Hoàn thành tác vụ ổn định | P0 | M |
| Web accessibility fail | Flutter semantics/focus chưa đúng | Audit semantics, focus traversal, labels, focus ring, automated/manual screen reader | Đạt WCAG cơ bản | P0 | L |
| Navigation desktop yếu | Mobile shell reuse | Desktop sidebar + breadcrumb + active route + page action slot | Tìm feature nhanh, giảm lostness | P1 | M |
| Data density thấp | Card list dùng quá nhiều | Table desktop + Card mobile pattern | Scan nhanh hơn | P1 | M |
| Raw technical copy | Backend/admin codes hiện primary | Label mapping + code secondary/detail | Dễ hiểu, giảm lỗi thao tác | P1 | S |
| Filter không đồng nhất | Feature-local implementation | Unified filter pattern with presets, search, clear/apply | Học 1 lần dùng mọi nơi | P1 | M |
| Long checkbox list | Hick's Law | Searchable multi-select/grouped categories | Nhanh, ít scroll | P2 | M |
| Empty/loading lệch | State template chưa enforce | State placement rules + skeleton for first-load | Giảm cảm giác treo app | P2 | S |

# Roadmap Redesign

## Phase 0: Discovery and inventory

- Chốt product direction, personas, task priority, role matrix.
- Lập screen inventory theo route, platform, permission, state.
- Audit native Android/iOS/Windows với screenshot thật.

## Phase 1: Foundations

- Figma variables: color, typography, spacing, radius, elevation, state, breakpoint.
- Define app shell: mobile, tablet, desktop.
- Accessibility baseline: contrast matrix, focus ring, target size.

## Phase 2: Core components

- Button, input, dropdown, filter, date range, checkbox, tabs, table, card, state, snackbar, dialog.
- Build variants and interaction states trước khi vẽ lại screens.

## Phase 3: High-risk screens

- Fix templates cho `VietQR`, `Sao kê`, `Cấn trừ`, `Báo cáo`, `Profile`, `Settings`, `Admin Users`.
- Prototype user flows: search/filter/export, report submit, QR create, admin edit.

## Phase 4: Platform adaptation

- Mobile: bottom navigation, sticky footer, scanner flow, keyboard behavior.
- Tablet: master-detail, split pane, filter drawer.
- Desktop: sidebar, command bar, table density.

## Phase 5: Handoff and QA

- Dev handoff with component specs, token mapping to Flutter.
- Visual QA checklist per breakpoint.
- Accessibility QA: keyboard, screen reader, contrast, focus.

# Đề xuất Design System

## Foundations

- **Color tokens**:
  - `color.brand.primary`, `color.brand.primaryHover`, `color.brand.primaryPressed`
  - `color.surface.canvas`, `surface.card`, `surface.raised`, `surface.overlay`
  - `color.text.primary`, `text.secondary`, `text.muted`, `text.inverse`, `text.disabled`
  - `color.border.default`, `border.strong`, `border.focus`, `border.error`
  - `color.status.success|warning|error|info`
  - `color.state.hover|pressed|selected|disabled|focusRing`
- **Typography tokens**:
  - `heading.l/m/s`, `title.l/m/s`, `body.l/m/s`, `label.l/m/s`, `caption`, `code`
  - Date/money/order IDs có thể dùng `code` khi giúp scan tốt hơn.
- **Spacing tokens**:
  - 4, 8, 12, 16, 20, 24, 32, 40.
  - `page.padding.mobile`, `page.padding.desktop`, `form.gap`, `section.gap`.
- **Radius**:
  - Card 8, input/button 10-12, modal 12, pill full.
- **Elevation**:
  - `none`, `card`, `popover`, `modal`, `drawer`.
- **Breakpoints**:
  - Mobile: `<600`
  - Tablet: `600-899`
  - Desktop: `900-1199`
  - Wide desktop: `>=1200`
- **Grid**:
  - Mobile 4 columns, tablet 8 columns, desktop 12 columns, max content 1180/1280.

## Patterns

- App shell: mobile topbar + bottom nav; tablet rail; desktop sidebar.
- Filter: desktop inline compact; tablet drawer; mobile bottom sheet.
- List: desktop table; mobile cards; tablet hybrid.
- Form: one column mobile, two columns desktop only when labels/fields fit.
- Scanner: scan-first full-screen pattern with manual fallback.
- State: loading/empty/error/unsupported/success with action.

# Cấu trúc file Figma

1. `00 Cover - OpsHub Redesign`
2. `01 Product Direction`
3. `02 Foundations`
   - Color variables
   - Typography styles
   - Spacing/radius/elevation
   - Breakpoints/grid
   - Accessibility notes
4. `03 Design Tokens`
   - Light mode
   - Dark mode
   - Density: comfortable/compact
   - Platform: mobile/tablet/desktop
5. `04 Icons`
   - Feature icons
   - Navigation icons
   - Status icons
6. `05 Components`
   - Atomic components and variants
7. `06 Patterns`
   - App shell
   - Filter/search
   - Forms
   - Tables/lists
   - Dialogs/sheets
   - States
8. `07 Templates`
   - Home/dashboard
   - Feature hub
   - Admin console
   - Finance list
   - Report form
9. `08 Screens`
   - Current-state reference
   - Redesigned screens by module
10. `09 Prototype`
    - Mobile primary tasks
    - Desktop admin/finance tasks
11. `10 Developer Handoff`
    - Token mapping to Flutter
    - Component specs
    - Responsive rules
    - Accessibility checklist
12. `Archive`
    - Old explorations and rejected options

# Danh sách Component

- Buttons: primary, secondary, tertiary, destructive, icon, split, loading.
- Inputs: text, number, money, phone, password, textarea, read-only.
- Dropdowns: select, searchable select, multi-select, date range, menu.
- Tables: data table, compact table, selectable rows, expandable row.
- Cards: feature card, data card, summary card, action card, notification card.
- Dialog: confirmation, detail, editor, destructive confirm.
- Navigation: sidebar, drawer, rail, bottom nav, breadcrumb, topbar.
- Bottom Sheet: filter sheet, action sheet, detail sheet.
- Search: global search, list search, filter search.
- Filter: filter bar, filter chip, filter drawer, saved filter summary.
- Badge/Tag/Chip: status, count, role/scope, priority.
- Avatar: initial, image, upload overlay.
- Tooltip: icon/action/tool help.
- Charts: KPI, trend, empty/error state.
- Progress: linear, circular, step progress, upload progress.
- Timeline: approval/history events.
- Calendar/Date: preset date range, custom date range.
- Empty State: no data, no permission, unsupported, first-use.
- Error State: network, permission, validation, server.
- Skeleton: list, card, table, detail.
- Toast/Snackbar: success, error, warning, action.
- Form Components: field group, validation summary, sticky action footer, stepper.

# Cải tiến User Flow

## App shell

Current: Home card -> feature -> browser/system back.
Redesign: Sidebar/breadcrumb + active route + global notification/profile. Desktop user luôn biết đang ở đâu và quay về đâu.

## Finance filter flow

Current: mỗi màn hình filter khác nhau, có màn bị cắt.
Redesign: Filter summary collapsed by default on mobile/tablet; desktop filter bar compact; action `Tìm`, `Xóa`, `Xuất file` nằm cùng cụm.

## Report flow

Current: form phụ thuộc từng bước nhưng chỉ thể hiện bằng disabled fields.
Redesign: Stepper:

1. Nhập mã đơn/SĐT.
2. Kiểm tra/lấy thông tin.
3. Bổ sung ngành/lý do/đối tác.
4. Gửi báo cáo.

Mỗi step có validation inline và lý do disabled.

## Admin flow

Current: tree/list/detail không đồng nhất, raw code nhiều.
Redesign: Admin console:

1. Search/filter.
2. List/table.
3. Detail drawer/panel.
4. Edit dialog with confirmation.

## Scanner/input flow

Current: một số màn hình hiện empty state lớn trước khi thấy control.
Redesign: Scan/input là primary zone đầu màn; result/empty/error nằm ngay dưới.

# Ước lượng khối lượng thiết kế

| Hạng mục | Ước lượng |
| --- | ---: |
| Product direction + IA refresh | 3-5 ngày |
| Screen inventory + state matrix | 3-4 ngày |
| Foundations/tokens Figma | 4-6 ngày |
| Core components + variants | 8-12 ngày |
| App shell mobile/tablet/desktop | 4-6 ngày |
| Redesign high-risk screens | 10-15 ngày |
| Prototype + usability review | 4-7 ngày |
| Developer handoff + QA checklist | 4-6 ngày |

Tổng ước lượng: **5-8 tuần** cho 1 product designer senior + 1 design system owner part-time + dev pairing. Nếu có team 2 designers, có thể rút về **3-5 tuần** cho scope Figma/Handoff trước khi dev implement.

# Kết luận

Cần redesign theo thứ tự: foundation/layout/accessibility trước, screen polish sau. Nếu vẽ lại từng màn hình ngay mà chưa chốt app shell, breakpoint, filter pattern và component variants, lỗi clipping/consistency sẽ lặp lại.
