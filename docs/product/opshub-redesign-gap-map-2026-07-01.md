# OpsHub Redesign System Gap Map

Ngày cập nhật: 02/07/2026

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

## Route/frame gap được ghi nợ kỹ thuật

Các frame sau có trong Figma nhưng chưa implement hoặc chưa expose route trong
Batch 1. Không thêm route tạm nếu chưa có runtime contract rõ.

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
- Lượt hợp nhất Batch 1-4 trên `staging` đã pass format cho 42 Dart files,
  `flutter analyze --no-pub`, 69 focused tests trên 18 test files, full
  `flutter test --no-pub --reporter compact` (262 tests), và
  `flutter build web --no-pub` kèm wasm dry-run.
- Chưa có Web smoke đăng nhập/API thật do localhost Web bị production CORS nếu
  chưa deploy hoặc proxy.
- Các hub/form/data-heavy screens còn lại vẫn cần migrate theo batch sau; Batch
  1 khóa nền shell, route `/tasks`, token, permission model và screen
  `/admin/features` plus `/sales-reports` đã có runtime contract.
