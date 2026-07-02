# OpsHub Redesign System Gap Map

Ngày cập nhật: 03/07/2026

## Đã đưa vào repo trong Batch 1

- Authenticated app dùng `AppShell` responsive:
  - desktop sidebar cố định;
  - tablet rail;
  - mobile app bar + bottom navigation `Trang chủ`, `Tác vụ`, `Tài khoản`.
- `/tasks` đã được migrate thành content-only workspace index trong `AppShell`:
  header card `Tác vụ của bạn` hiển thị số tác vụ khả dụng/số tác vụ cần thêm
  quyền, danh sách action dùng `AppFeatureSection`, empty state dùng
  `AppStatePanel`, route visibility dùng chung
  `AppNavModel.visibleTaskDestinations(user)` với Home/sidebar và log
  visible/hidden counts qua `AppLogger`. Các frame
  `Desktop v2 / Tasks Workspace` (`482:2`),
  `Tablet v2 / Tasks Workspace` (`482:75`) và
  `Mobile v2 / Tasks Workspace` (`482:145`) trong Figma đã được tạo theo
  runtime: desktop/tablet mô tả full super-admin, mobile mô tả staff chỉ có
  `Cài đặt`.
- Navigation ẩn destination không có quyền và log visible/hidden counts qua
  `AppLogger`.
- Theme có thêm token Figma cho primary hover/pressed/surface, status
  surfaces, sidebar light/dark, contextual surface/text/border helpers, và
  breakpoint desktop `1200`.
- Home được chuyển thành nội dung command center để global support,
  notification, account menu và app navigation nằm ở shell. Figma hiện đã có
  lại các frame runtime `Desktop v2 / Home Workspace` (`485:2`),
  `Tablet v2 / Home Workspace` (`485:86`) và
  `Mobile v2 / Home Workspace` (`485:160`): desktop/tablet mô tả Home nhiều
  quyền với 9 action, mobile mô tả staff có 5 action và bottom nav
  `Trang chủ`/`Tác vụ`/`Tài khoản`. Khi tài khoản không có workspace khả dụng,
  Home dùng shared `AppStatePanel.empty` trong surface `home-empty-state`; ba
  frame Figma tương ứng là desktop `487:2`, tablet `487:91` và mobile `487:170`.
- VietQR `/vietqr` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header hiển thị SR đang chọn, trạng
  thái QR và số lịch sử; chọn SR, quét mã đơn, tạo QR, kiểm tra MAP, realtime
  match, mở lại QR còn hạn, hết hạn 15 phút và tải ảnh QR vẫn giữ runtime
  contract hiện có. Các frame `Desktop v2 / VietQR Workspace` (`398:14`),
  `Tablet v2 / VietQR Workspace` (`135:558`) và
  `Mobile v2 / VietQR Workspace` (`135:142`) trong Figma đã bỏ các control giả
  không có runtime contract như copy/in QR, duyệt thông báo, lịch sử loa và
  search/filter cũ.
- Admin Feature Management đã được expose trong Admin workspace qua route
  `/admin/features`, guard bằng `ADMIN_FEATURES`, và hiển thị menu
  `Quản lý tính năng` khi người dùng có quyền tương ứng.
- Admin Feature Management đã được migrate khỏi `GradientHeader` riêng sang
  content-only screen trong `AppShell`: card mô tả + action row ở đầu màn,
  tab surface dùng shared token, và các danh sách data-heavy giữ nguyên runtime
  contract hiện có.
- Admin Menu `/admin` đã được migrate khỏi `GradientHeader` riêng sang
  content-only hub trong `AppShell`: header card hiển thị số chức năng khả dụng,
  danh sách action dùng `AppFeatureSection`/`AppFeatureGrid`, empty state dùng
  shared state panel, và các route vẫn bám feature access hiện có
  (`ADMIN_USERS`, `ADMIN_ROLES`, `ADMIN_ORG_TREE`, `ADMIN_POLICIES`,
  `ADMIN_FEATURES`) cộng thêm `Danh sách góp ý` cho Super Admin. Các frame
  `Desktop v2 / Admin Workspace` (`102:2`), `Tablet v2 / Admin Workspace`
  (`135:714`) và `Mobile v2 / Admin Workspace` (`135:258`) trong Figma đã bỏ
  metric/table/permission-matrix/audit/add-user/sales-report mock không có
  runtime contract, thay bằng hub action đúng màn đang chạy.
- Sales Report hub `/sales-reports` đã được migrate khỏi `GradientHeader`
  riêng sang content-only cockpit trong `AppShell`: card mô tả ở đầu màn, bộ
  lọc/action và 2 cột đơn hàng giữ nguyên runtime contract hiện có.
- Sales Report form/admin polish đã đồng bộ với Figma V2: form mua/chưa mua
  bỏ `GradientHeader` riêng và dùng header card nội dung, admin list dùng
  dropdown `Loại` thay checkbox dọc, hub/admin gom `Xuất HVTC`, `Xuất Doanh số`
  và `Xuất Trả góp` vào một menu `Xuất file`. Figma file
  `OpsHub Redesign System - 2026-06-30` đã cập nhật các frame hub/admin/form
  trên desktop, tablet và mobile để thể hiện compact toolbar/export menu, gồm
  desktop `152:3577`/`152:2179`, tablet `152:938`/`152:470`, và mobile
  `151:698`/`151:350` cho hub/admin.
- Admin Users `/admin/users` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header/action card chỉ hiện
  import/thêm mới cho Super Admin, search và 5 bộ lọc dùng shared controls,
  danh sách tài khoản responsive giữ nguyên reset/sửa/xóa theo quyền. Hai frame
  `Desktop v2 / Admin Users` và `Mobile v2 / Admin Users` trong Figma đã bỏ
  panel chi tiết/`Xuất file` không có runtime contract, thay bằng đúng
  header/filter/list/action đang chạy trong app.
- Admin Roles `/admin/roles` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card mô tả trạng thái chỉ
  đọc, action tải lại, trạng thái loading/empty/error dùng shared state panel,
  danh sách vai trò giữ contract read-only từ `/admin/roles` và không còn lộ mã
  role kỹ thuật ở UI. Hai frame `Desktop v2 / Admin Roles` và
  `Mobile v2 / Admin Roles` trong Figma đã bỏ search/filter/export/detail giả
  không có runtime contract, thay bằng header/read-only role cards đúng màn
  đang chạy.
- Organization Tree `/admin/organization` đã được migrate khỏi
  `GradientHeader` riêng sang content-only workspace trong `AppShell`: header
  card có trạng thái quyền, refresh/thêm node theo quyền, tree/detail được bọc
  bằng shared surface, trạng thái lỗi có thể retry, tree panel có thanh tìm
  nhanh theo mã nghiệp vụ, viết tắt hoặc tên node, và các thao tác
  tạo/sửa/xóa/gán tính năng node vẫn giữ repository/runtime contract hiện có.
  Các frame `Desktop v2 / Organization Tree` (`152:1741`),
  `Tablet v2 / Organization Tree` (`152:314`) và
  `Mobile v2 / Organization Tree` (`151:234`) trong Figma đã bỏ
  filter/export/tab giả không có runtime contract, thay bằng header + search
  trong tree panel + detail panel theo màn đang chạy.
- Policy Management `/admin/policies` đã được migrate khỏi `GradientHeader`
  riêng sang content-only workspace trong `AppShell`: header card có chip đếm
  chính sách/quy tắc/cấu hình, icon action tải lại/thêm mới, tab
  `Chính sách`/`Quy tắc`/`Cấu hình`, list cards và error state có thể retry
  vẫn giữ repository/runtime contract hiện có. Các frame `Desktop v2 / Policy
  Management`, `Tablet v2 / Policy Management` và `Mobile v2 / Policy
  Management` trong Figma đã bỏ search/filter/export giả và mã policy kỹ thuật,
  thay bằng header/tabs/cards theo màn đang chạy.
- Admin Feedback List `/admin/feedback` đã được migrate khỏi `GradientHeader`
  riêng sang content-only workspace trong `AppShell`: header card có metric
  tổng góp ý/góp ý có ảnh/số ảnh, icon action tải lại, trạng thái
  loading/empty/error có thể retry, và danh sách card hiển thị người gửi, nội
  dung, module, điểm đánh giá, thời gian, email và ảnh đính kèm vẫn giữ API
  `/feedback/admin` hiện có. Các frame `Desktop v2 / Admin Feedback List`,
  `Tablet v2 / Admin Feedback List` và `Mobile v2 / Admin Feedback List` trong
  Figma đã bỏ search/filter/export/thêm mới/status giả không có runtime
  contract, thay bằng header, metric chips, refresh action và feedback cards
  theo màn đang chạy.
- Staff Feedback form `/feedback` đã được migrate khỏi `GradientHeader` riêng
  sang content-only form trong `AppShell`: header card thể hiện trạng thái gửi
  và số ảnh `0/20`, form card giữ validation `Chức năng liên quan`/`Nội dung
  góp ý`, card ảnh minh họa giữ giới hạn 20 ảnh, submit multipart vẫn dùng
  endpoint `/feedback`, và các log mở màn/thêm ảnh/gửi thành công/thất bại
  hiện có vẫn được giữ. Các frame `Desktop v2 / Feedback Workspace`
  (`106:30`), `Tablet v2 / Feedback Workspace` (`135:831`) và
  `Mobile v2 / Feedback Workspace` (`135:345`) trong Figma đã được sync về
  staff form runtime, bỏ inbox/detail/ticket admin mock không thuộc route
  `/feedback`.
- Settings `/settings` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card hiển thị trạng thái giao
  diện/Windows startup, selector giao diện vẫn đổi `ThemeProvider`, toggle
  khởi động cùng Windows vẫn dùng `StartupSettingsService`, và log mở màn,
  load, toggle thành công/thất bại qua `AppLogger`. Các frame `Desktop v2 /
  Settings Workspace` (`106:105`), `Tablet v2 / Settings Workspace`
  (`135:870`) và `Mobile v2 / Settings Workspace` (`135:374`) trong Figma đã
  bỏ search/save, ERP endpoint, bank webhook, SSO, audit/security mock không có
  runtime contract, thay bằng đúng theme segmented control và Windows startup
  card.
- Profile `/profile` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card hiển thị avatar/tên/email
  và chip vai trò/cây tổ chức; card `Phiên đăng nhập` ngay dưới header đặt nút
  `Đăng xuất` dễ thấy trước nhóm form chỉnh sửa/thông tin. Card chỉnh sửa giữ
  luồng đổi mật khẩu/lưu tên, card thông tin tài khoản giữ email, vai trò, cây
  tổ chức và SR được gán. Nút `Đăng xuất` dùng `AuthProvider.logout()` rồi điều
  hướng về `/login`. Các log mở màn, lưu profile, đổi mật khẩu và đăng xuất
  thành công/thất bại được ghi qua `AppLogger`. Các frame `Desktop v2 /
  Profile` (`481:2`), `Tablet v2 / Profile` (`481:52`) và
  `Mobile v2 / Profile` (`481:99`) trong Figma đã bỏ mock `Họ tên`, `Phạm vi`,
  `Toàn hệ thống`, `Lưu thay đổi` và thay bằng header/edit/info cards đúng
  runtime contract, gồm cả card đăng xuất `490:2`, `490:8`, `490:14` theo code
  03/07/2026.
- Auth pre-shell `/login`, `/register`, `/forgot-password` và
  `/assignment-pending` đã bỏ nền `GradientHeader.getGradient` cũ, chuyển sang
  `AuthScreenShell` dùng surface token của redesign V2: desktop có brand panel,
  tablet/mobile có brand header + auth card gọn. Runtime contract vẫn giữ đăng
  nhập, tự chuyển register khi tài khoản chưa tồn tại/chưa có mật khẩu, đăng ký
  bằng mã xác thực email, quên mật khẩu 3 bước email/mã/mật khẩu mới, và màn
  chờ gán tổ chức có `Tải lại trạng thái`/`Đăng xuất`. Figma đã sync các frame
  Login `106:2`/`135:316`/`135:792`, Register
  `152:1161`/`151:31`/`152:41`, Forgot Password
  `152:1189`/`151:60`/`152:80`, Assignment Pending
  `152:1217`/`151:89`/`152:119`, bỏ mock SSO/2FA, `Họ và tên`,
  `Tạo tài khoản mới` và `Gửi mã xác minh` không khớp runtime.
- Inventory Import `/fifo/inventory-import` đã được migrate khỏi
  `GradientHeader` riêng sang content-only workspace trong `AppShell`: header
  card thể hiện trạng thái file import, panel chọn file/cập nhật dùng shared
  buttons, error state có thể retry, result card hiển thị tổng dòng/dòng hợp
  lệ/dòng bỏ qua/dòng ngừng active và SR trong file, trong khi endpoint
  `/fifo/inventory/import`, guard `FIFO_IMPORT`, và alias
  `/admin/inventory-import` vẫn giữ runtime contract hiện có. Các frame
  `Desktop v2 / Inventory Import`, `Tablet v2 / Inventory Import` và
  `Mobile v2 / Inventory Import` trong Figma đã bỏ lịch sử/search/filter/export
  và thêm mới giả không có runtime contract, thay bằng header/upload/result
  state theo màn đang chạy.
- FIFO hub `/fifo-menu` đã được migrate thành content-only workspace trong
  `AppShell`: header card hiển thị số tác vụ khả dụng/số tác vụ cần thêm
  quyền, danh sách action dùng `AppFeatureSection`, empty state dùng
  `AppStatePanel`, và click từng action log qua `AppLogger` trước khi mở
  `/fifo-check`, `/sort`, `/fifo/inventory-import` hoặc `/fifo-history`.
  Figma đã bổ sung các frame runtime `Desktop v2 / FIFO Menu` (`476:2`),
  `Tablet v2 / FIFO Menu` (`476:48`) và `Mobile v2 / FIFO Menu` (`476:92`)
  theo đúng action/copy đang chạy.
- Sort FIFO `/sort` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card có chips nhóm/vị trí/đã
  kiểm, command card nhập hoặc quét SKU/BIN, trạng thái loading/empty/error và
  danh sách kết quả dùng shared surfaces, trong khi `SortProvider`,
  `SortRepository`, scanner route, completion report và route guard FIFO vẫn
  giữ runtime contract hiện có. Các frame `Desktop v2 / Sort Workspace`,
  `Tablet v2 / Sort Workspace` và `Mobile v2 / Sort Workspace` trong Figma đã
  bỏ empty mock không còn đúng trạng thái mẫu, thay bằng header/input/result
  card theo dữ liệu SKU/BIN runtime và vẫn đặt active nav dưới FIFO.
- FIFO Check `/fifo-check` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card có chips chế độ/số sản
  phẩm/trạng thái, command card nhập hoặc quét SKU/serial, toggle
  `Hiển thị đã xuất kho`, trạng thái loading/empty/error và kết quả serial/SKU
  dùng shared surfaces, trong khi `FifoProvider`, `FifoRepository`, scanner
  route, đánh dấu/bỏ đánh dấu xuất kho và route guard `FIFO` vẫn giữ runtime
  contract hiện có. Các frame `Desktop v2 / FIFO Check`,
  `Tablet v2 / FIFO Check` và `Mobile v2 / FIFO Check` trong Figma đã bỏ mock
  SKU/BIN/copy không còn đúng contract, thay bằng header/input/toggle/result
  card theo dữ liệu serial runtime và vẫn đặt active nav dưới FIFO.
- FIFO History `/fifo-history` đã được migrate khỏi `GradientHeader` riêng
  sang content-only workspace trong `AppShell`: header card có tổng kiểm
  tra/sắp xếp và refresh, filter truy vấn/người dùng dùng shared surface, tab
  `Kiểm tra FIFO`/`Sắp xếp FIFO`, trạng thái loading/empty/error/retry và
  danh sách log vẫn giữ runtime contract `FifoLogRepository.getAdminLogs` với
  `FIFO_CHECK`/`FIFO_SORT`, phân trang, search, user filter và expand item.
  Các frame `Desktop v2 / FIFO History` (`152:2601`),
  `Tablet v2 / FIFO History` (`152:587`) và
  `Mobile v2 / FIFO History` (`151:437`) trong Figma đã bỏ nút thêm mới/mock
  SKU cũ không có runtime contract, thay bằng header/filter/tabs/cards theo
  dữ liệu log runtime và active nav nằm dưới FIFO.
- Sao kê `/bank-statement` đã được migrate khỏi `GradientHeader` riêng sang
  content-only workspace trong `AppShell`: header card có chips scope/số giao
  dịch/đã chọn/yêu cầu chờ Kế toán/trạng thái filter, bộ lọc tìm kiếm,
  toolbar chọn giao dịch, phân trang, danh sách giao dịch, chỉnh đơn hàng,
  lịch sử và review chuyển đơn vẫn giữ `BankStatementProvider`,
  `BankStatementRepository`, scoped/global lookup, default date, export và
  notification contract hiện có. Các frame `Desktop v2 / Statement Workspace`,
  `Tablet v2 / Statement Workspace` và `Mobile v2 / Statement Workspace` trong
  Figma đã được sync theo runtime: desktop được bổ sung mới, tablet/mobile bỏ
  layout tràn/chồng chữ, filter desktop/tablet gọn trong card và mobile dùng
  filter collapsed đúng không gian scroll.
- Payment Monitor `/payment-monitor` đã được migrate khỏi `GradientHeader`
  riêng sang content-only workspace trong `AppShell`: header card có chips
  scope SR/trạng thái đồng bộ/trạng thái loa/tổng giao dịch, panel loa hoặc
  list-only, chọn SR thủ công, lỗi loa, filter ngày/SR/số dòng, phân trang,
  transaction rows, sửa đơn hàng, yêu cầu/chấp thuận/từ chối chuyển đơn và
  history vẫn giữ `PaymentMonitorProvider`, `PaymentMonitorRepository`,
  realtime/audio/list contract hiện có. Các frame `Desktop v2 / Payment
  Monitor`, `Tablet v2 / Payment Monitor` và `Mobile v2 / Payment Monitor`
  trong Figma đã được sync theo runtime: bỏ metric/timeline/action giả, filter
  gom gọn trong card, active nav/rail là `Tiền vào`, và không đưa các control
  không có runtime contract như gắn đơn/lịch sử phát loa.
- Payment Monitor unsupported fallback `/payment-monitor` đã được migrate khỏi
  `GradientHeader` riêng sang content-only fallback trong `AppShell`: màn giữ
  log cảnh báo platform/isWeb, action quay về `/home`, copy hướng dẫn thiết bị
  chưa hỗ trợ và trạng thái `Chưa hỗ trợ loa`; không còn `Scaffold`/app bar
  riêng chen vào shell. Các frame Figma `Desktop v2 / Payment Monitor
  Unsupported` (`152:3479`), `Tablet v2 / Payment Monitor Unsupported`
  (`152:899`) và `Mobile v2 / Payment Monitor Unsupported` (`151:669`) đã được
  sync theo runtime fallback, bỏ các action/mock không có contract như xem tiền
  vào, lịch sử phát loa, kiểm tra thiết bị và gắn đơn thủ công.
- Offset Adjustment `/offset-adjustments` đã được migrate khỏi
  `GradientHeader` riêng sang content-only workspace trong `AppShell`: header
  card có chips scope/số hồ sơ/chờ Kế toán/trạng thái, nhóm nút tạo cấn trừ,
  filter responsive, toolbar phân trang, danh sách hồ sơ, dialog tạo/sửa/xem
  chi tiết và export menu vẫn giữ `OffsetAdjustmentProvider`,
  `OffsetAdjustmentRepository`, realtime notification và route guard
  `OFFSET_ADJUSTMENTS` hiện có. Các frame `Desktop v2 / Offset Workspace`
  (`107:100`), `Tablet v2 / Offset Workspace` (`135:948`) và
  `Mobile v2 / Offset Workspace` (`135:432`) trong Figma đã bỏ kanban/drawer,
  CTA/search/empty mock cũ không có runtime contract, thay bằng header/action,
  filter, toolbar và result card theo dữ liệu runtime.
- BH/SC hub `/warranty-main` và form upload `/warranty` đã được migrate khỏi
  `GradientHeader` riêng sang content-only screens trong `AppShell`: hub dùng
  header card và `AppFeatureSection` cho hai tác vụ `Lưu hình ảnh`/`Xem lại
  hình ảnh`; form upload dùng header card có chip số biên nhận + số ảnh,
  form card nhập hoặc quét số biên nhận, thêm tối đa 20 ảnh và nút lưu, trong
  khi `WarrantyProvider`, `WarrantyRepository`, scanner route, image picker,
  upload API và route guard `WARRANTY` vẫn giữ runtime contract hiện có. Các
  frame Figma đã được sync cho hub `Desktop v2 / BH-SC Workspace` (`101:2`),
  `Tablet v2 / BH-SC Workspace` (`135:675`), `Mobile v2 / BH-SC Workspace`
  (`135:229`) và form upload `Desktop v2 / Warranty Intake` (`152:2943`),
  `Tablet v2 / Warranty Intake` (`152:704`), `Mobile v2 / Warranty Intake`
  (`151:524`), bỏ gallery/detail/search/upload mock cũ không thuộc slice này.
- BH/SC lookup `/check-warranty`, detail biên nhận và image viewer đã được
  migrate khỏi `GradientHeader`: lookup là content-only dưới `AppShell` với
  header/action card, search card có scanner action và danh sách biên nhận;
  detail dùng page surface tokenized với header/back action, info card, gallery
  `Hình ảnh (2)` và viewer ảnh nền tối vẫn giữ zoom/pan/download contract.
  `WarrantyProvider.showAllWarranty`, `searchWarranty`, barcode scanner,
  route guard `WARRANTY`, chi tiết ảnh base64/remote URL và download ảnh vẫn
  giữ runtime contract hiện có. Figma đã sync các frame lookup/detail
  desktop/tablet/mobile: `Desktop v2 / Warranty Lookup` (`152:3051`),
  `Tablet v2 / Warranty Lookup` (`152:743`),
  `Mobile v2 / Warranty Lookup` (`151:553`),
  `Desktop v2 / Warranty Detail` (`152:3159`),
  `Tablet v2 / Warranty Detail` (`152:782`) và
  `Mobile v2 / Warranty Detail` (`151:582`).

## Route/frame gap được ghi nợ kỹ thuật

Các frame sau có trong Figma nhưng chưa implement hoặc chưa expose route trong
Batch 1. Không thêm route tạm nếu chưa có runtime contract rõ.

Audit 02/07/2026: các route nằm trong `AppShell` hiện không còn dùng
`GradientHeader` riêng. Guard `design_system_migration_guard_test.dart` khóa
việc tái dùng `GradientHeader` trong feature screens, chỉ cho phép hai ngoại lệ
đã ghi nợ là `PersonnelCatalogAdminScreen` legacy-hidden và
`FifoCheckConversationScreen` chưa expose route/menu; test cũng xác nhận hai
class này không xuất hiện trong `app_router.dart`.

| Figma frame | Trạng thái code hiện tại | Hướng xử lý |
| --- | --- | --- |
| Data Workspace | Chưa có route/runtime screen tương ứng | Tạo story/contract trước khi implement |
| Generic Report Workspace | Repo đang dùng Sales Report hub/form/admin; hub `/sales-reports` đã migrate content-only | Quyết định có cần report hub generic riêng hay Figma frame sẽ nhập vào Sales Report |
| Personnel Catalog Admin | Có screen code nhưng `ADMIN_PERSONNEL` đang là legacy hidden theo tree-first contract | Chỉ expose nếu product mở lại contract nhân sự ngoài cây tổ chức |
| FIFO Conversation Check | Có screen code nhưng chưa expose route/menu | Xác nhận flow còn dùng hay retire trước khi expose |
| Dialog/loading/empty/error state inventory | Nhiều dialog/state vẫn feature-local | Migrate theo batch sau qua shared shell/dialog/state pattern |

## Proof còn thiếu trước khi gọi là visual parity

- Đã có AppShell widget screenshot smoke light + dark cho desktop/tablet/mobile
  trong `.screenshot/figma_merge` (ignored, không commit ảnh).
- Android production debug APK đã build/install/mở được trên thiết bị
  `21081111RG`; proof runtime login light nằm trong `.screenshot/figma_merge`.
- Android dark authenticated smoke trước khi cài lại APK phát hiện clipping ở
  mobile app bar và Home command panel; đã sửa bằng bố cục mobile header gồm
  metrics bên trái, title giữa, support + notification bên phải.
- Android authenticated smoke sau khi đăng nhập phát hiện mobile Home bị nhân
  đôi avatar ở app bar và command panel; đã sửa bằng cách bỏ account/avatar
  button khỏi mobile app bar, giữ entry `Tài khoản` ở bottom nav. Home card chỉ
  giữ avatar nhận diện, title, tên người dùng và chi nhánh.
- Figma Home restore 03/07/2026 đã tạo lại desktop/tablet/mobile Home frames
  (`485:2`, `485:86`, `485:160`) theo runtime contract hiện có: command card,
  shell topbar/mobile app bar, action grid không có `Sắp xếp` độc lập, feedback
  nằm cuối và mobile giữ bottom nav. QA bằng Figma tool xác nhận required text
  missing `[]`, zero-size text `0`, missing font `0`, out-of-parent `[]`, và
  screenshot desktop/tablet/mobile không còn account text overlap sau lượt fix
  topbar.
- Home empty-state follow-up 03/07/2026 đã thay copy cục bộ bằng shared
  `AppStatePanel.empty`, giữ nguyên nhánh phân quyền và thêm widget proof cho
  tài khoản không có action khả dụng. Figma đã có đủ desktop/tablet/mobile
  empty-state frames (`487:2`, `487:91`, `487:170`); QA xác nhận required text
  missing `[]`, zero-size text `0`, missing font `0`, out-of-parent `[]`, và
  screenshot mobile sau fix line-height không còn text collapse.
- Web Chrome fullscreen smoke với seeded local session đã kiểm Home, FIFO menu,
  và route `/sort`; proof ảnh nằm trong `output/playwright/`.
- Windows debug build đã pass ở `build/windows/x64/runner/Debug`.
- Windows debug runtime smoke với live saved session đã refresh qua
  `/auth/get-user`, kiểm Home, FIFO menu và màn `Sắp xếp FIFO`; optional update
  dialog được đóng bằng `Để sau`.
- Windows debug runtime smoke với `APP_ENV=smoke` đã mở Admin >
  `Quản lý tính năng`, xác nhận screen `/admin/features` render trong
  `AppShell`, không còn `GradientHeader` riêng, action row/tab surface hiển thị,
  skeleton thoát và danh sách feature load từ API. Log runtime có
  `Feature management load started/succeeded`.
- Sales Report focused widget/provider proof đã pass sau khi migrate hub
  `/sales-reports`: cockpit 2 cột, filter ngày/SR/user, dialog báo cáo mua
  hàng, action admin và form/admin-list regression vẫn giữ contract.
- Windows debug runtime smoke với `APP_ENV=smoke` đã mở Home > `Báo cáo`,
  xác nhận `/sales-reports` render trong `AppShell`, không còn
  `GradientHeader` riêng, header card/filter/action hiển thị và cockpit 2 cột
  load đơn từ API. Log runtime có `Sales report order cockpit load
  started/succeeded`.
- Sales Report focused proof sau polish compact toolbar/export menu đã pass:
  `flutter test --no-pub --reporter expanded test\sales_report_hub_test.dart`
  và full `flutter test --no-pub --reporter expanded` (240 tests).
  `flutter analyze --no-pub`, design-system guard và Windows debug build
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub` đều
  pass. Figma screenshots được kiểm trong tool sau khi cập nhật desktop/mobile
  Sales Report Hub/Admin frames.
- VietQR focused widget proof xác nhận màn `/vietqr` content-only không còn
  `Scaffold`/`GradientHeader` riêng và vẫn giữ các state SR/QR/history theo
  runtime contract. Figma desktop/tablet/mobile screenshots đã được kiểm sau
  khi đồng bộ ba frame `398:14`, `135:558`, `135:142`.
- Admin Users focused widget proof đã pass ở desktop và viewport `390x844`, xác
  nhận content-only header/filter surfaces, action theo quyền, 5 shared filter
  dropdowns, user rows và không có layout exception. Figma desktop/mobile
  screenshots đã được kiểm lại sau khi sửa text sizing, filter controls và
  list-row widths; hai frame không còn placeholder hay text width/height bằng
  `0`. Design-system guard (2 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (242 tests) và Windows debug
  build với `APP_ENV=smoke` đều pass.
- Admin Roles focused widget proof đã pass, xác nhận màn `/admin/roles`
  content-only không còn `Scaffold`/`GradientHeader`, action refresh gọi lại
  repository, error state có thể retry và UI không hiển thị `SUPER_ADMIN`.
  Design-system guard pass cùng lượt focused. `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (246 tests) và Windows debug
  build với `APP_ENV=smoke` đều pass. Figma desktop/mobile screenshots đã được
  kiểm lại sau khi cập nhật; hai frame không còn placeholder, text width/height
  bằng `0`, hoặc copy không có runtime contract như `Tìm vai trò`, `Bộ lọc`,
  `Xuất file`, `Thêm mới`.
- Organization Tree focused widget proof đã pass, xác nhận màn
  `/admin/organization` content-only không còn `Scaffold`/`GradientHeader`,
  refresh gọi lại repository, detail panel hiển thị dữ liệu node, add action
  theo Super Admin, error state có thể retry, và search lọc đúng theo mã
  nghiệp vụ/viết tắt/tên node không dấu. Design-system guard pass cùng lượt
  focused. `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (246 tests) và Windows debug
  build với `APP_ENV=smoke` đều pass ở lượt migrate ban đầu. Lượt follow-up
  search và retry state đã pass focused
  `flutter test --no-pub --reporter expanded test\organization_tree_admin_redesign_test.dart test\admin_user_tree_scope_test.dart`
  (15 tests), sau đó `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (249 tests), Windows debug build
  với `APP_ENV=smoke`, và `git diff --check` đều pass (chỉ còn cảnh báo CRLF
  trên Windows). Figma desktop/tablet/mobile screenshots đã được kiểm lại sau
  khi thêm search runtime thật; ba frame không còn placeholder, text
  width/height bằng `0`, hoặc copy không có runtime contract như `Bộ lọc`,
  `Xuất file`, `Thêm mới`.
- Policy Management focused widget proof đã pass, xác nhận màn
  `/admin/policies` content-only không còn `Scaffold`/`GradientHeader`, load
  error có thể retry và UI không lộ mã quyền thô. Figma desktop/tablet/mobile
  screenshots đã được kiểm lại sau khi sync Policy Management; ba frame không
  còn search/filter/export giả hoặc raw code như `ADMIN_USERS`,
  `BANK_STATEMENT`, `SALES_REPORT`.
- Admin Feedback focused widget proof đã pass, xác nhận màn `/admin/feedback`
  content-only không còn `Scaffold`/`GradientHeader`, danh sách runtime render
  đúng người gửi/nội dung/module/điểm/email, và error state có thể retry.
  Figma desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Admin
  Feedback List; ba frame không còn search/filter/export/thêm mới/status giả,
  text mô tả không còn bị chip metadata chồng lên, và copy visible dùng
  `Danh sách góp ý` theo contract. Validation sau batch Admin Feedback đã pass
  `dart format`, `flutter test --no-pub
  test\feedback_admin_redesign_test.dart --reporter expanded` (2 tests),
  `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (251 tests), và Windows debug
  build `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- Staff Feedback focused widget proof đã pass, xác nhận màn `/feedback`
  content-only không còn `Scaffold`/`GradientHeader`, header card và form card
  render đúng copy `Góp ý`, `Sẵn sàng gửi`, `0/20 ảnh`, validation rỗng vẫn
  trả `Vui lòng nhập chức năng liên quan` và `Vui lòng nhập nội dung góp ý`.
  Figma desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Staff
  Feedback form; ba frame không còn inbox/detail/ticket admin mock, không lộ mã
  `FEEDBACK`, và đủ các text runtime `Không bắt buộc, tối đa 20 ảnh`,
  `Thêm ảnh`, `Gửi góp ý`.
- Admin Menu focused widget proof đã pass, xác nhận màn `/admin` content-only
  không còn `Scaffold`/`GradientHeader`, header card render đúng `Quản trị`,
  số chức năng khả dụng, section `Chức năng quản trị`, action theo feature
  access và empty state khi tài khoản chưa có quyền quản trị. Figma
  desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Admin
  Workspace; ba frame không còn metric/table/permission-matrix/audit/add-user
  mock hoặc action `Báo cáo sale` không có trong runtime menu Admin. Validation
  sau batch Admin Menu đã pass `dart format`, focused Admin Menu + guard +
  router/nav `flutter test --no-pub --reporter expanded
  test\admin_menu_screen_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (9 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (272 tests), và `flutter build web --no-pub`.
- Settings focused widget proof đã pass, xác nhận màn `/settings` content-only
  không còn `Scaffold`/`GradientHeader`, header/theme/startup cards render đúng
  runtime copy, theme segmented control cập nhật trạng thái `ThemeProvider`,
  và startup flow dùng injection trong test để không đụng registry thật. Figma
  desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Settings;
  ba frame không còn search/save, ERP endpoint, webhook, SSO, security/audit
  mock, và zero-size text bằng `0`. Validation sau batch Settings đã pass
  `dart format`, focused Settings + guard + router/nav
  `flutter test --no-pub --reporter expanded
  test\settings_screen_redesign_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (9 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (274 tests), và `flutter build web --no-pub`.
- Profile focused widget proof đã pass, xác nhận màn `/profile` content-only
  không còn `Scaffold`/`GradientHeader`, header/session/edit/info cards render
  đúng cây tổ chức, SR được gán và nút `Đăng xuất`; các field nhân sự legacy vẫn
  không hiển thị. Figma text/structure QA sau khi sync lại Profile desktop/
  tablet/mobile (`481:2`, `481:52`, `481:99`) xác nhận đủ text runtime chung
  `Nguyễn Hoàng`, `hoang.nv1@phongvu-mna.vn`, `Thông tin hiển thị`,
  `Phiên đăng nhập`, `Đăng xuất khỏi tài khoản trên thiết bị này.`,
  `Thông tin tài khoản`, `Tên`, `Họ`, `Đổi mật khẩu`, `Lưu`, `Email`,
  `Vai trò`, `Cây tổ chức`, `SR được gán`, `Đăng xuất`; không còn `Họ tên`,
  `Phạm vi`, `Toàn hệ thống`, `Lưu thay đổi`, zero-size text bằng `0`,
  missing font bằng `0`, và screenshot mobile xác nhận nút đăng xuất nằm ngay
  dưới header, không bị collapse/overlap.
  Validation sau batch Profile đã pass `dart format`, focused Profile + guard +
  router/nav `flutter test --no-pub --reporter expanded
  test\profile_screen_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (8 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (274 tests), và `flutter build web --no-pub`.
  Follow-up 03/07/2026 cho card `Phiên đăng nhập` đã pass focused Profile +
  guard/router/nav `flutter test --no-pub --reporter expanded
  test\profile_screen_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (9 tests),
  `flutter analyze --no-pub`, và `git diff --check`.
- Tasks focused widget proof đã pass, xác nhận màn `/tasks` content-only không
  còn `Scaffold`/`GradientHeader`, header key `tasks-header` render đúng
  `Tác vụ của bạn`, staff user chỉ thấy `1 tác vụ khả dụng` và `9 tác vụ cần
  thêm quyền`, còn Super Admin thấy `10 tác vụ khả dụng` và đủ workspace
  action. Figma desktop/tablet/mobile frames `482:2`, `482:75`, `482:145` đã
  được tạo theo runtime contract; QA xác nhận required text missing `[]`,
  zero-size text `0`, missing font `0`, và screenshot mobile cuối không còn
  chip bị tràn khỏi header. Validation sau batch Tasks đã pass
  `dart format`, focused Tasks
  `flutter test --no-pub --reporter expanded test\tasks_screen_redesign_test.dart`
  (2 tests), focused Tasks + migration guard/router/nav
  `flutter test --no-pub --reporter expanded
  test\tasks_screen_redesign_test.dart test\design_system_migration_guard_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (10 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (280 tests), `flutter build web --no-pub`, và `git diff --check`.
- Auth pre-shell focused proof đã pass, xác nhận `/login`, `/register`,
  `/forgot-password` và `/assignment-pending` đều dùng `AuthScreenShell`, không
  còn `GradientHeader`, vẫn render CTA runtime `Đăng nhập`, `Gửi mã xác thực
  email`, `Gửi mã đổi mật khẩu`, `Tải lại trạng thái` và `Đăng xuất`. Figma
  text/structure QA sau khi sync 12 frame auth xác nhận required missing bằng
  `[]`, không còn mock `Đăng nhập bằng SSO`, `Bảo mật: hỗ trợ 2FA`, `Họ và tên`,
  `Tạo tài khoản mới`, `Gửi mã xác minh`, và zero-size text bằng `0`.
  Validation sau batch Auth pre-shell đã pass `dart format`, focused Auth +
  widget/forgot-password + guard `flutter test --no-pub --reporter expanded
  test\auth_pre_shell_redesign_test.dart test\widget_test.dart
  test\forgot_password_screen_test.dart test\design_system_migration_guard_test.dart`
  (6 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (275 tests), và
  `flutter build web --no-pub`.
- Inventory Import focused widget proof đã pass, xác nhận màn
  `/fifo/inventory-import` content-only không còn `Scaffold`/`GradientHeader`,
  chọn file giả render đúng tên/định dạng, upload thành công render result
  metrics/SR chips, và lỗi upload có thể retry. Figma desktop/tablet/mobile
  screenshots đã được kiểm lại sau khi sync Inventory Import; ba frame không
  còn lịch sử/search/filter/export/thêm mới giả, không còn text width/height
  bằng `0`, và nav desktop/tablet active đúng FIFO workspace. Validation sau
  batch Inventory Import đã pass `dart format`,
  `flutter test --no-pub test\inventory_import_redesign_test.dart --reporter
  expanded` (2 tests), focused Inventory Import + Admin Feedback (4 tests),
  `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter expanded` (253 tests), và Windows debug
  build `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- FIFO Menu focused widget proof đã pass, xác nhận hub `/fifo-menu`
  content-only không còn `Scaffold`/`GradientHeader`, render header key
  `fifo-menu-header`, đủ action `Kiểm tra FIFO`, `Sắp xếp FIFO`,
  `Cập nhật tồn kho`, `Lịch sử FIFO`, và empty state
  `Chưa có tính năng FIFO` khi tài khoản chưa có quyền. Figma desktop/tablet/
  mobile frames `476:2`, `476:48`, `476:92` đã được tạo mới theo runtime menu;
  QA xác nhận required text missing `[]`, zero-size text `0`, và screenshot
  mobile cuối không còn card/header collapse hoặc chip chồng copy. Validation
  đã pass `flutter test --no-pub --reporter expanded
  test\fifo_menu_redesign_test.dart` (2 tests), focused FIFO Menu + migration
  guard/router/nav batch (10 tests), `flutter analyze --no-pub`, full
  `flutter test --no-pub --reporter compact` (278 tests), và
  `flutter build web --no-pub`.
- Sort FIFO focused widget proof đã pass trong focused batch, xác nhận màn
  `/sort` content-only không còn `Scaffold`/`GradientHeader`, empty state có
  input + scan/send actions, submit SKU render group result đúng serial/BIN và
  route vẫn thuộc FIFO workspace. Figma desktop/tablet/mobile screenshots đã
  được kiểm trực tiếp trong tool sau khi sync Sort Workspace; ba frame không
  còn empty mock, search/filter/export/thêm mới giả, không còn text
  width/height bằng `0`, và metadata đủ các text runtime `250403171`,
  `SN001`, `LK.04-A-03-a`. Validation sau batch Sort FIFO đã pass
  `dart format --output=none --set-exit-if-changed`, `flutter analyze
  --no-pub`, focused Sort FIFO + Inventory Import + Admin Feedback
  `flutter test --no-pub test\sort_screen_redesign_test.dart
  test\inventory_import_redesign_test.dart test\feedback_admin_redesign_test.dart
  --reporter expanded` (6 tests), full
  `flutter test --no-pub --reporter expanded` (255 tests), và Windows debug
  build `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`.
- FIFO Check focused widget proof đã pass trong focused batch, xác nhận màn
  `/fifo-check` content-only không còn `Scaffold`/`GradientHeader`, empty state
  có header/input/toggle/result surfaces, submit serial `SN001` gọi repository
  với `includeExported = true`, render thông điệp đúng FIFO, product card,
  SKU/serial/BIN/zone/import date và action `Đánh dấu xuất kho`. Figma
  desktop/tablet/mobile screenshots đã được kiểm trực tiếp trong tool sau khi
  sync FIFO Check; ba frame không còn copy cũ như `SKU hoặc BIN` hoặc
  `Hiển thị đề xuất kho`, không còn text width/height bằng `0`, và metadata đủ
  các text runtime `SN001`, `250403171`, `LK.04-A-03-a`, `A1`,
  `2026-07-01`, `Đúng FIFO. Lấy sản phẩm này.`. Focused validation đã pass
  `flutter test --no-pub test\fifo_check_redesign_test.dart --reporter
  expanded` (2 tests). Validation sau batch FIFO Check đã pass
  `dart format --output=none --set-exit-if-changed`, `flutter analyze
  --no-pub`, focused FIFO Check + Sort FIFO + Inventory Import + Admin
  Feedback `flutter test --no-pub test\fifo_check_redesign_test.dart
  test\sort_screen_redesign_test.dart test\inventory_import_redesign_test.dart
  test\feedback_admin_redesign_test.dart --reporter expanded` (8 tests), full
  `flutter test --no-pub --reporter expanded` (257 tests), Windows debug build
  `flutter build windows --debug --dart-define=APP_ENV=smoke --no-pub`, và
  `git diff --check` pass với cảnh báo CRLF trên Windows.
- FIFO History focused widget proof đã pass, xác nhận màn `/fifo-history`
  content-only không còn `GradientHeader`, render header/filter/tabs đúng
  runtime, chuyển tab gọi `FIFO_SORT`, mobile loaded/error/retry không phát
  sinh layout exception, và `AppLogger` có log start/success/failure cho flow
  tải lịch sử. Figma desktop/tablet/mobile screenshots đã được kiểm lại sau
  khi sync FIFO History; ba frame không còn placeholder, text rỗng, copy cũ
  như `Thêm mới`, `SKU check`, `Quét SKU`, `Query`, `items`, không còn overflow
  trong clipped frames, và đều dùng text style/font `Inter` của design system.
  Lưu ý parity: runtime Flutter vẫn dùng `SF Pro Display`, còn file Figma V2
  đang chuẩn hóa theo `Inter` để tránh lỗi render chữ trắng trong screenshot
  tool. Focused validation đã pass `flutter test --no-pub --reporter expanded
  test\fifo_history_redesign_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (8 tests). Validation sau batch FIFO History
  đã pass `dart format --output=none --set-exit-if-changed`, `flutter analyze
  --no-pub`, full `flutter test --no-pub --reporter compact` (265 tests), và
  web build `flutter build web --no-pub`.
- Sao kê focused widget proof đã pass, xác nhận màn `/bank-statement`
  content-only không còn `Scaffold`/`GradientHeader`, vẫn render header/toolbar,
  pending transfer bell trong `AppShell`, dialog thông báo Kế toán và history
  title theo runtime contract hiện có. Figma desktop/tablet/mobile screenshots
  đã được kiểm lại sau khi sync Statement Workspace; ba frame không còn title
  cũ `Sắp xếp FIFO`, filter tràn khỏi khung, hoặc transaction metadata bị
  chồng chữ. Focused validation đã pass `flutter test --no-pub
  test\bank_statement_screen_test.dart --reporter expanded` (3 tests).
  Validation sau batch Sao kê đã pass `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, focused
  Sao kê screen/provider/detail `flutter test --no-pub
  test\bank_statement_screen_test.dart test\bank_statement_provider_test.dart
  test\bank_statement_transaction_details_test.dart --reporter expanded` (27
  tests), full `flutter test --no-pub --reporter expanded` (258 tests), và
  Windows debug build `flutter build windows --debug --dart-define=APP_ENV=smoke
  --no-pub`.
- Payment Monitor focused widget proof đã pass, xác nhận màn
  `/payment-monitor` content-only không còn `Scaffold`/`GradientHeader`, render
  header `Theo dõi tiền vào`, chip scope SR, list-only/speaker status, filter,
  transaction row và giữ selected store runtime qua repository. Figma
  desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Payment
  Monitor; ba frame không còn metric/timeline/action giả, không còn text chồng
  lên nhau, và desktop/tablet active đúng `Tiền vào`. Focused validation đã
  pass `flutter test --no-pub
  test\payment_monitor_screen_redesign_test.dart --reporter expanded` (1
  test). Validation sau batch Payment Monitor đã pass `dart format
  --output=none --set-exit-if-changed`, `flutter analyze --no-pub`, focused
  route + Payment Monitor regression `flutter test --no-pub
  test\app_router_test.dart test\payment_monitor_screen_redesign_test.dart
  test\payment_monitor_provider_test.dart test\payment_transaction_tile_test.dart
  test\payment_monitor_unsupported_screen_test.dart --reporter expanded` (34
  tests), full `flutter test --no-pub --reporter expanded` (259 tests), và
  Windows debug build `flutter build windows --debug --dart-define=APP_ENV=smoke
  --no-pub`.
- Payment Monitor unsupported fallback proof đã pass, xác nhận màn fallback
  content-only không còn `Scaffold`/`GradientHeader`, render header/card keys
  `payment-monitor-unsupported-header` và
  `payment-monitor-unsupported-card`, có copy `Theo dõi tiền vào`,
  `Chưa hỗ trợ trên web`, `Chưa hỗ trợ loa` và action `Về trang chủ`. Figma
  visual/structure QA cho frames `152:3479`, `152:899` và `151:669` có
  required text missing `[]`, forbidden old mock/action text `[]` và
  zero-size text count `0`. Validation sau slice unsupported đã pass focused
  `flutter test --no-pub --reporter expanded
  test\payment_monitor_unsupported_screen_test.dart
  test\design_system_migration_guard_test.dart` (3 tests), focused route +
  Payment Monitor regression `flutter test --no-pub --reporter expanded
  test\app_router_test.dart test\payment_monitor_screen_redesign_test.dart
  test\payment_monitor_provider_test.dart test\payment_transaction_tile_test.dart
  test\payment_monitor_unsupported_screen_test.dart` (34 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (275 tests), và `flutter build web --no-pub`.
- Offset Adjustment focused widget proof đã pass, xác nhận màn
  `/offset-adjustments` content-only không còn `Scaffold`/`GradientHeader`,
  render header/filter/toolbar/result card, mobile dùng filter collapsed không
  phát sinh overflow và vẫn giữ all-store reviewer query qua repository. Figma
  desktop/tablet/mobile screenshots đã được kiểm lại sau khi sync Offset
  Workspace; ba frame không còn kanban/drawer/CTA/search/empty mock, text
  zero-size, stale copy kiểu `OFF-*` hoặc node tràn khỏi frame. Focused
  validation đã pass `flutter test --no-pub --reporter expanded
  test\offset_adjustment_screen_redesign_test.dart` (2 tests). Validation sau
  batch Offset đã pass `dart format --output=none --set-exit-if-changed`,
  `flutter analyze --no-pub`, focused Offset/route/nav regression
  `flutter test --no-pub --reporter expanded
  test\offset_adjustment_screen_redesign_test.dart
  test\offset_adjustment_provider_test.dart test\app_router_test.dart
  test\app_nav_model_test.dart` (13 tests), full `flutter test --no-pub
  --reporter compact` (267 tests), `flutter build web --no-pub`, và
  `git diff --check` pass với cảnh báo CRLF trên Windows.
- BH/SC focused widget proof đã pass, xác nhận hub `/warranty-main` và form
  upload `/warranty` content-only không còn `Scaffold`/`GradientHeader`, mobile
  upload render header/form/chip số ảnh compact và validation rỗng vẫn trả
  `Vui lòng nhập số biên nhận`. Figma desktop/tablet/mobile screenshots đã
  được kiểm lại sau khi sync 6 frame hub/intake; các frame không còn copy cũ
  kiểu `BH/SC Workspace`, `Upload ảnh`, `Gallery biên nhận gần đây`, text
  zero-size hoặc chip bị wrap. Focused validation đã pass
  `flutter test --no-pub --reporter expanded test\warranty_redesign_test.dart`
  (2 tests), regression BH/SC + route/nav/upload contract (20 tests), full
  `flutter test --no-pub --reporter compact` (269 tests), và
  `flutter build web --no-pub`.
- BH/SC lookup/detail focused widget proof đã pass, xác nhận
  `/check-warranty` content-only không còn `Scaffold`/`GradientHeader`, search
  + scanner action + receipt list giữ provider contract, detail render header
  `Chi tiết biên nhận`, `Thông tin biên nhận`, `Hình ảnh (2)` và mở image
  viewer không còn `GradientHeader`. Figma desktop/tablet/mobile screenshots
  đã được kiểm lại sau khi sync 6 frame lookup/detail; các frame không còn
  master-detail mock, `26 kết quả`, `CP75`, `4 ảnh`, `Tải thêm hình ảnh`,
  text bị chồng hoặc content auto-stack sai cột. Focused validation đã pass
  `flutter test --no-pub --reporter expanded test\warranty_redesign_test.dart`
  (4 tests). Validation sau slice lookup/detail đã pass `dart format
  --output=none --set-exit-if-changed`,
  `flutter analyze --no-pub`, focused BH/SC + route/nav/upload regression
  `flutter test --no-pub --reporter expanded test\warranty_redesign_test.dart
  test\warranty_upload_contract_test.dart test\validators_test.dart
  test\app_router_test.dart test\app_nav_model_test.dart` (22 tests), full
  `flutter test --no-pub --reporter compact` (271 tests), và
  `flutter build web --no-pub`.
- Route migration guard proof đã pass, xác nhận toàn bộ feature screens đang
  expose không dùng lại `GradientHeader` shell cũ. Guard chỉ cho phép hai file
  đã ghi nợ kỹ thuật `personnel_catalog_admin_screen.dart` và
  `fifo_check_conversation_screen.dart`, đồng thời xác nhận
  `PersonnelCatalogAdminScreen` và `FifoCheckConversationScreen` không nằm
  trong `app_router.dart`. Validation sau slice guard đã pass `dart format`,
  focused `flutter test --no-pub --reporter expanded
  test\design_system_migration_guard_test.dart` (3 tests),
  `flutter analyze --no-pub`, full `flutter test --no-pub --reporter compact`
  (276 tests), và `flutter build web --no-pub`.
- Lượt hợp nhất Batch 1-4 trên `staging` đã pass format cho 42 Dart files,
  `flutter analyze --no-pub`, 69 focused tests trên 18 test files, full
  `flutter test --no-pub --reporter compact` (262 tests), và
  `flutter build web --no-pub` kèm wasm dry-run.
- Chưa có Web smoke đăng nhập/API thật do localhost Web bị production CORS nếu
  chưa deploy hoặc proxy.
- Audit route 02/07/2026 không còn phát hiện hub/form/data-heavy runtime route
  nào dùng `GradientHeader` riêng. Phần còn lại của plan nằm ở nhóm
  route/frame gap phía trên: Data Workspace và Generic Report cần quyết định
  contract trước, Personnel Catalog đang legacy-hidden, FIFO Conversation chưa
  expose route/menu, còn dialog/loading/empty/error state sẽ migrate dần theo
  shared shell/dialog/state pattern.
