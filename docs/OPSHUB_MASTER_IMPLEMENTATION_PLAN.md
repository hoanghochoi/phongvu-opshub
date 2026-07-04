# OpsHub Master Implementation Plan

Ngày cập nhật: 2026-07-04
Trạng thái: Sẵn sàng triển khai, đã đối chiếu với repo/runtime hiện tại

## 1. Mục Tiêu

Plan này gom 6 nhánh việc đang giao cắt nhau vào một rollout có thứ tự rõ ràng:

1. Mobile nav 4 mục và route `/operations`.
2. Home chuyển từ command center sang dashboard tổng quan theo scope.
3. Sales Report lưu bền vững trạng thái order đã hủy để loại khỏi các flow sau.
4. Help chuyển từ static content sang runtime content có editor cho Super Admin.
5. Public `/help` trở thành route trong Flutter app/web.
6. Dọn các intro/top card còn dư sau đợt redesign shell.

Plan này thay cho việc tiếp tục nhồi yêu cầu mới vào `docs/UI_UX_AUDIT_PLAN.md`.

## 2. Checkpoint Và Mức Rủi Ro

Checkpoint hiện tại trước khi code:

- Branch: `staging`
- HEAD: `b5689b2e9885246fc4853f64dad05a587882b19e`
- Worktree tracked: sạch
- Local untracked artifact đang tồn tại và không thuộc scope batch này:
  - `assets/image/`
  - `docs/UI_UX_AUDIT_PLAN_CODEX.md`

Lane triển khai: `rủi ro cao`

Lý do:

- Chạm `authorization` và visibility theo role/scope.
- Chạm public contract của `/help`.
- Chạm data model và migration cho Sales Report/Help.
- Chạm external behavior với ERP order status.
- Chạm UI shell, router, deploy contract, và behavior đang dùng hằng ngày.

Nguyên tắc rollout:

- Làm theo batch nhỏ, mỗi batch có rollback point riêng.
- Không revert thay đổi ngoài scope.
- Không push `staging` trước final verification.
- Mọi flow mới hoặc flow bị sửa phải có log hữu ích qua `AppLogger` ở Flutter và logger backend tương ứng.
- Docs product và `docs/TEST_MATRIX.md` phải cập nhật cùng batch code.

## 3. Hiện Trạng Repo Phải Tôn Trọng

Đây là baseline thật của repo ở thời điểm lập plan; các batch phía dưới phải đi từ trạng thái này, không giả định lại từ đầu:

### 3.1 Navigation Và Home

- Mobile bottom nav runtime hiện có `Trang chủ`, `Thông báo`, `Tài khoản`.
- `Thông báo` hiện là shell-owned panel; bấm tab sẽ mở shared notifications flow, không đi vào inbox route riêng.
- Chưa có route `/operations`.
- Home hiện vẫn là command center dùng
  `AppNavModel.visibleWorkspaceDestinations(user)` để render lưới tác vụ theo quyền.
- Shared pattern đã có sẵn và nên reuse:
  - `AppFeatureSection`
  - `AppFeatureGrid`
  - `AppResponsiveScrollView`
  - `AppStatePanel`

### 3.2 Help

- `/help` hiện là static public page.
- Nội dung hiện tại lấy từ:
  - `docs/help/navigation.json`
  - `docs/help/content/*`
  - `docs/help/assets/*`
- Build static bằng `scripts/build-help-site.mjs`.
- Deploy hiện tại phục vụ `/help` riêng qua Caddy, không đi qua Flutter SPA.
- App hiện mở help bằng external browser, chưa navigate nội bộ.
- Entry `Hướng dẫn` hiện nằm trong side menu `Cấu hình` trên desktop/tablet; mobile hiện mới có support action, chưa có help screen in-app.
- Production content hiện còn dính contract `help-content` branch và static-only deploy.

### 3.3 Sales Report Và Order Hủy

- Sales Report hiện đã chặn order hủy ở bước lookup/re-check ERP và trả copy `Đơn đã bị hủy.`.
- `SalesReportErpOrderCache` hiện có `confirmationStatus` và `fulfillmentStatus`, nhưng chưa có flag loại order khỏi các flow về sau.
- Chưa có bằng chứng repo cho thấy order hủy được persist thành exclusion bền vững để:
  - biến mất khỏi candidate list ở lần sau,
  - bị loại khỏi dashboard,
  - có dấu vết DB rõ ràng.

### 3.4 Scope/Permission

- Sales Report đã có scope runtime cần reuse, không được phát minh scope engine mới:
  - user thường xem theo email/personnel identity của chính mình,
  - manager/admin xem theo showroom/node được gán,
  - Super Admin xem toàn bộ.
- Home dashboard và canceled-order exclusion phải reuse logic scope này.

### 3.5 UI Cleanup

- Nhiều cleanup lớn đã làm xong trong đợt AppShell/UI audit gần đây.
- Không được giả định tất cả `VietQR`, `Quản trị`, `Báo cáo`, `Sales Report` vẫn còn top card lỗi.
- Batch cleanup cuối phải đi theo hướng `verify-first`, chỉ sửa màn nào còn dư thật.

## 4. Gate Quyết Định Trước Khi Cắt Code

Các điểm dưới đây cần được đóng rõ trong quá trình triển khai; plan mặc định đã chọn hướng an toàn hơn để tránh blocker:

### 4.1 KPI `conversionRate`

Yêu cầu thô hiện tại đang nói:

```text
conversionRate = totalOrders / totalReports * 100
```

Vấn đề:

- Công thức này có thể > `100%`.
- Tên `tỉ lệ chuyển đổi` dễ bị hiểu là coverage hoặc conversion thật.

Hướng mặc định của plan:

- Không hard-code công thức này vào UI/API trước khi xác nhận nhãn nghiệp vụ.
- Nếu business thực sự muốn công thức trên, cần đổi label hiển thị cho đỡ gây hiểu nhầm.
- Nếu KPI muốn thể hiện mức độ báo cáo phủ lên đơn, công thức an toàn hơn là:

```text
reportedOrders / totalOrders * 100
```

### 4.2 `/operations` Có Hiện Ở Desktop Hay Chỉ Mobile

Hướng mặc định:

- Route `/operations` tồn tại cross-platform để routing và deep-link nhất quán.
- Mobile bottom nav có `Vận hành`.
- Desktop vẫn giữ sidebar nhóm `Trang chủ` + các workspace như hiện tại trong v1, không ép thêm root destination mới nếu chưa cần.

### 4.3 Help Cutover Strategy

Do `/help` hiện đang bị Caddy bắt riêng cho static site, việc chuyển sang Flutter route không nên làm kiểu “đập một phát”.

Hướng mặc định:

- Build runtime content service và editor trước.
- Làm Flutter `HelpScreen` đạt parity trước.
- Chỉ cutover path `/help` sang Flutter sau khi đã có proof và rollback path rõ ràng.

### 4.4 Order Hủy Có Được “Mở Lại” Không

Copy yêu cầu hiện tại nghiêng về:

- đã xác định hủy thì loại khỏi flow về sau.

Hướng mặc định:

- Persist exclusion bền vững.
- Không tự mở lại chỉ vì lần sync sau không trả trạng thái rõ.
- Nếu sau này cần override thủ công, coi là việc tiếp theo riêng và ghi backlog.

## 5. Target State Sau Khi Hoàn Tất

### 5.1 Mobile IA

Mobile bottom nav mục tiêu:

1. `Trang chủ`
2. `Vận hành`
3. `Thông báo`
4. `Tài khoản`

Ý nghĩa:

- `Trang chủ`: dashboard tổng quan theo scope.
- `Vận hành`: lưới shortcut nghiệp vụ theo quyền.
- `Thông báo`: tiếp tục dùng shared notifications flow của shell.
- `Tài khoản`: profile, settings, help, support, logout.

### 5.2 Home

- Không còn là lưới workspace chính.
- Hiển thị metrics trong ngày theo scope.
- Giữ layout gọn, task-first, không quay lại hero/top card lớn.

### 5.3 Operations Workspace

- Là nơi mới chứa các action grid nghiệp vụ.
- Reuse permission logic và shared grid/card hiện có.
- Không copy-paste lưới Home thành logic riêng.

### 5.4 Help

- Public `/help` đọc được khi chưa đăng nhập.
- Help content lấy từ DB/API runtime.
- Super Admin có editor trong app/web.
- Save xong public view thấy ngay, không cần redeploy app.

### 5.5 Sales Report

- Order đã hủy được persist thành trạng thái bị loại.
- Candidate list không hiển thị lại order đã hủy.
- Dashboard và các report summary không tính order bị loại.

### 5.6 UI Cleanup

- Màn nghiệp vụ không lặp lại tên screen bằng top card lớn.
- Shell top bar là nơi sở hữu destination title.
- Feature content chỉ giữ heading/helper text thật sự phục vụ thao tác.

## 6. Kiến Trúc Và Contract Đề Xuất

### 6.1 Navigation/Home Source Of Truth

Điểm cần giữ:

- Root/workspace/account destinations tiếp tục nằm trong `AppNavModel`.
- Visibility vẫn phải đi qua feature/scope check đang có.

Thay đổi đề xuất:

- Thêm destination `operations`.
- Tách helper build workspace actions để Home cũ và `/operations` không tự nhân đôi logic.
- Home dashboard chỉ hiển thị metrics + action phụ theo ngữ cảnh nếu cần, không giữ full grid.

### 6.2 Home Summary API

Endpoint đề xuất:

```http
GET /api/home/summary?date=YYYY-MM-DD
```

Response shape đề xuất:

```json
{
  "date": "2026-07-04",
  "scope": {
    "type": "own|store|managed|all",
    "label": "Phạm vi đang xem"
  },
  "salesRevenue": 125000000,
  "totalOrders": 42,
  "totalReports": 38,
  "reportedOrders": 35,
  "unreportedOrders": 7,
  "conversionRate": 83.33,
  "updatedAt": "2026-07-04T10:30:00.000Z"
}
```

Quy ước:

- Scope resolve ở server, không tin client gửi scope.
- `totalOrders` loại order đã hủy/bị exclude.
- `reportedOrders` là số order hợp lệ đã có báo cáo.
- `unreportedOrders = max(totalOrders - reportedOrders, 0)`.
- `totalReports` là tổng report hợp lệ trong ngày theo scope.
- `conversionRate` chờ gate ở mục 4.1 trước khi chốt formula cuối.

### 6.3 Help Runtime Content

Public API đề xuất:

```http
GET /api/help-content/public
```

Admin API đề xuất:

```http
GET    /api/admin/help-content/pages
POST   /api/admin/help-content/pages
PATCH  /api/admin/help-content/pages/:id
POST   /api/admin/help-content/assets
```

Model ưu tiên:

- `HelpPage`
  - `id`
  - `navKey`
  - `slug`
  - `title`
  - `summary`
  - `parentId`
  - `navOrder`
  - `contentMarkdown`
  - `isPublished`
  - `createdAt`
  - `updatedAt`
  - `updatedByUserId`
- `HelpPageRevision`
  - `id`
  - `pageId`
  - `title`
  - `summary`
  - `contentMarkdown`
  - `navOrder`
  - `isPublished`
  - `createdAt`
  - `createdByUserId`
- `HelpAsset`
  - optional trong v1 nếu upload ảnh được làm cùng batch

Lý do không dùng model phẳng tối giản:

- Current static help đang có menu cha/con trong `navigation.json`.
- Runtime CMS cần giữ được hierarchy đó, không chỉ một danh sách page phẳng.

Seed/migration:

- Seed ban đầu từ `docs/help/navigation.json` + `docs/help/content/*`.
- Trong giai đoạn chuyển tiếp, `docs/help/*` vẫn là rollback/reference source.
- Khi cutover hoàn tất, DB/API mới là source of truth runtime.

### 6.4 Canceled Order Persistence

Ưu tiên mở rộng bảng hiện có thay vì tạo bảng rời ngay từ đầu:

- Mở rộng `SalesReportErpOrderCache` với các field như:
  - `isCanceled`
  - `canceledAt`
  - `excludedFromReportsAt`
  - `excludedReason`
  - `lastCancellationCheckAt`

Lý do:

- Cache order hiện đã là nguồn cockpit và đã giữ status ERP.
- Dashboard tương lai cũng cần loại ngay từ nguồn này.
- Ít join hơn, ít rủi ro sai lệch hơn so với một bảng exclusion rời không gắn chặt cache row.

Nếu sau này cần audit trail chi tiết hơn, thêm event table riêng ở bước tiếp theo, không chặn v1.

### 6.5 Scope Reuse

Home dashboard và canceled-order rollout phải reuse các khối hiện có của Sales Report:

- managed scope check
- allowed store resolution
- identity match theo email/personnel code
- org-tree/store assignment hiện tại

Không làm:

- scope param client tự chọn rồi backend tin theo
- scope engine mới chỉ dành cho dashboard

## 7. Kế Hoạch Batch

## Batch 1 - Mobile Nav 4 Mục Và `/operations`

Mục tiêu:

- Thêm root destination `Vận hành`.
- Tạo route `/operations`.
- Chuyển lưới workspace chính từ Home sang `/operations`.
- Mobile bottom nav thành `Trang chủ`, `Vận hành`, `Thông báo`, `Tài khoản`.

Repo baseline phải giữ:

- Home hiện đang dùng `AppNavModel.visibleWorkspaceDestinations(user)`.
- Shared grid pattern đã có, phải reuse.

Files/modules dự kiến:

- `lib/app/navigation/app_nav_model.dart`
- `lib/app/navigation/app_router.dart`
- `lib/app/navigation/app_shell.dart`
- `lib/features/home/*`
- `lib/features/operations/*` mới
- `lib/app/widgets/app_feature_grid.dart` nếu cần chỉ để extract/reuse

Logging:

- log navigation resolved counts như hiện tại
- thêm log open `/operations` nếu cần
- không log raw feature codes ra UI

Validation tối thiểu:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/app_nav_model_test.dart test/app_shell_route_viewport_test.dart test/home_feedback_action_test.dart test/design_system_migration_guard_test.dart
git diff --check
```

Nếu cần, thêm test mới `test/operations_screen_test.dart`.

Điều kiện xong batch:

- Mobile nav đúng 4 mục.
- `/operations` render grid theo quyền.
- `Thông báo` vẫn đi qua shared shell panel, không tự mở thêm inbox route mới nếu chưa có accepted contract riêng.
- Desktop sidebar không bị vỡ IA hiện tại.
- Home không còn là full workspace catalog.

Commit đề xuất:

```text
feat(nav): add operations hub and four-tab mobile shell
```

## Batch 2 - Persist Durable Canceled Order Exclusions

Mục tiêu:

- Khi ERP xác nhận order hủy, trạng thái bị loại được lưu bền vững vào DB.
- Candidate list và submit flow fail closed cho order đã hủy.
- Batch này đi backend trước; client UX bám theo contract mới.

Files/modules dự kiến:

- `backend-nest/prisma/schema.prisma`
- Prisma migration mới
- `backend-nest/src/sales-reports/*`
- `lib/features/sales_report/*` nếu client cần auto-close hoặc copy mới

Behavior mong muốn:

- check-order/re-check ERP gặp order hủy:
  - persist exclusion,
  - trả copy tiếng Việt rõ,
  - không cho tạo report,
  - candidate list lần sau không hiển thị lại.

Logging:

- lookup start/success/failure
- branch `order canceled`
- persist exclusion success/failure
- client form auto-close nếu có

Validation tối thiểu:

```powershell
cd backend-nest
npx prisma validate
npm run build
npm test -- --runInBand src/sales-reports/sales-report-erp.service.spec.ts src/sales-reports/sales-reports.service.spec.ts
cd ..
flutter analyze --no-pub
git diff --check
```

Nếu client có behavior auto-close, mở rộng thêm `test/sales_report_hub_test.dart` hoặc test mới cùng batch.

Điều kiện xong batch:

- DB có dấu vết exclusion bền vững.
- API list/cockpit không trả lại order đã bị loại.
- Submit report bị chặn fail closed cho order đã hủy.

Commit đề xuất:

```text
feat(sales-report): persist canceled order exclusions
```

## Batch 3 - Home Dashboard Theo Scope

Phụ thuộc:

- Batch 2 phải xong trước để dashboard không đếm order hủy sai.

Mục tiêu:

- Home chuyển sang dashboard tổng quan trong ngày.
- Metrics theo đúng scope hiện có của Sales Report.
- Action grid chính đã nằm ở `/operations`.

Metrics scope:

- doanh số trong ngày
- tổng số đơn hợp lệ
- tổng số báo cáo hợp lệ
- số đơn đã báo cáo
- số đơn chưa báo cáo
- KPI `conversionRate` theo gate ở mục 4.1

Files/modules dự kiến:

- `backend-nest/src/home-summary/*` mới hoặc module tương đương
- `backend-nest/src/sales-reports/*` helper reuse
- `lib/features/home/*`
- provider/repository mới nếu cần

UI behavior:

- dashboard cards nhỏ gọn
- hiển thị label scope hiện hành
- loading/error/empty dùng shared state components
- không dùng top hero card lớn

Validation tối thiểu:

```powershell
cd backend-nest
npm run build
npm test -- --runInBand src/home-summary/home-summary.service.spec.ts src/home-summary/home-summary.controller.spec.ts
cd ..
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/home_feedback_action_test.dart test/home_avatar_test.dart test/app_nav_model_test.dart
git diff --check
```

Thêm mới `test/home_dashboard_test.dart` nếu batch này introduces dedicated dashboard states.

Điều kiện xong batch:

- Home là dashboard, không còn full catalog.
- Scope user/store/manager/admin đúng.
- Order hủy không bị tính.
- KPI label/formula đã chốt rõ.

Commit đề xuất:

```text
feat(home): add scoped operating summary dashboard
```

## Batch 4 - Runtime Help Content Service Và Super Admin Editor

Mục tiêu:

- Có DB/API runtime cho help content.
- Có editor cho Super Admin trong app/web.
- Public source chưa cần cut sang Flutter ngay trong batch này nếu path `/help` còn collision với static site.

Files/modules dự kiến:

- `backend-nest/prisma/schema.prisma`
- Prisma migration mới
- `backend-nest/src/help-content/*` mới
- guard/feature access hiện có
- `lib/features/help/*`
- `lib/features/admin/*` hoặc workspace phù hợp

Behavior:

- Super Admin thấy menu `Quản lý hướng dẫn` hoặc tương đương.
- Non-Super Admin không thấy entry và backend cũng chặn.
- Save xong dữ liệu runtime được cập nhật ngay ở API public.
- Nếu asset upload chưa sẵn sàng trong cùng batch, editor markdown vẫn phải dùng được và phần còn lại phải được ghi backlog.

Logging:

- backend: load/save/upload/forbidden/validation error
- Flutter: open editor, load page, save start/success/failure
- không log raw markdown dài hoặc payload nhạy cảm

Validation tối thiểu:

```powershell
cd backend-nest
npx prisma validate
npm run build
npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts
cd ..
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/admin_menu_screen_test.dart
git diff --check
```

Điều kiện xong batch:

- Runtime content service chạy được.
- Super Admin sửa được, non-Super Admin bị chặn ở UI và API.
- Seed/migration từ `docs/help/*` có rollback path rõ.

Commit đề xuất:

```text
feat(help): add runtime help content service
```

## Batch 5 - Cutover Public `/help` Sang Flutter Route

Phụ thuộc:

- Batch 4 có public API/runtime content stable.

Mục tiêu:

- `/help` trở thành public route trong Flutter web/app.
- App không còn phụ thuộc external browser cho primary help experience.
- Deploy/Caddy/help-content branch contract được cập nhật đồng bộ.

Điểm khó phải xử lý rõ:

- Caddy hiện bắt `/help` cho static site trước SPA fallback.
- Nếu cutover thiếu đồng bộ, route sẽ vỡ ngay dù Flutter screen đã xong.

Files/modules dự kiến:

- `lib/app/navigation/app_router.dart`
- `lib/features/help/presentation/help_screen.dart`
- `lib/app/navigation/app_shell.dart`
- `deploy/home-server/Caddyfile`
- workflow/deploy script liên quan đến static help nếu có
- `docs/product/help.md`
- `docs/product/backend-platform.md`
- `docs/help/README.md`
- `docs/stories/HELP-001-static-help-page.md`

Behavior:

- Khách chưa đăng nhập vào `/help` đọc được.
- Logged-in user mở help trong app.
- Có thể giữ secondary action `Mở ngoài trình duyệt` nếu còn hữu ích, nhưng không còn là luồng chính.
- Khi cutover hoàn tất, `help-content` branch/static-only deploy phải được đánh giá lại:
  - retire hẳn, hoặc
  - giữ như rollback path ngắn hạn với quy trình rõ.

Validation tối thiểu:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/app_shell_route_viewport_test.dart
flutter build web --debug --no-pub
git diff --check
```

Smoke bắt buộc:

- mở `/help` khi logged out
- mở `/help` khi logged in
- account/help entry đi đúng route mới
- refresh browser tại `/help` không bị redirect login hoặc 404

Điều kiện xong batch:

- `/help` là route Flutter thật trên web/app.
- Public content đọc từ runtime source.
- Deploy contract mới đã được doc lại, không để repo nói một đằng runtime chạy một nẻo.

Commit đề xuất:

```text
feat(help): serve public help inside app
```

## Batch 6 - Verify-First Cleanup Các Intro Card Còn Dư

Mục tiêu:

- Scan các route còn lặp shell title bằng intro/top card không cần thiết.
- Chỉ sửa các màn còn dư thật sau khi đối chiếu code + `docs/TEST_MATRIX.md`.

Cách làm:

- Verify-first, không assume `VietQR`, `Admin`, `Reports` còn lỗi nếu repo đã cleanup.
- Ưu tiên các route còn khả năng sót như:
  - `Feedback`
  - report sub-screens còn intro card
  - finance/report/admin child screens còn lặp shell title
- Nếu một compact header card vẫn đang mang task-specific context hữu ích, không ép xóa chỉ vì “trông giống top card”.

Files/modules dự kiến:

- các screen Flutter còn issue thật
- `test/design_system_migration_guard_test.dart`
- các widget test route tương ứng

Validation tối thiểu:

```powershell
flutter analyze --no-pub
flutter test --no-pub --reporter expanded test/feedback_screen_test.dart test/report_workspace_screen_test.dart test/sales_report_hub_test.dart test/admin_menu_screen_test.dart test/vietqr_screen_test.dart test/design_system_migration_guard_test.dart
git diff --check
```

Điều kiện xong batch:

- Không còn top card dư ở các route target còn active.
- Không mất action chính của màn.
- Copy/title không trùng shell destination label một cách vô nghĩa.
- Các compact task/status strips còn giá trị ngữ cảnh được phép giữ lại.

Commit đề xuất:

```text
feat(ui): remove remaining redundant intro cards
```

## Batch 7 - Final Verification Và Push `staging`

Mục tiêu:

- Xác minh full rollout không phá runtime.
- Chỉ push `staging` khi toàn bộ proof pass hoặc phần chưa pass đã được Đại Ca chấp nhận rõ.

Validation bắt buộc:

```powershell
flutter analyze
flutter test
cd backend-nest
npm run build
npm test -- --runInBand
cd ..
cd backend-go
go test ./...
cd ..
git diff --check
git status --short
```

Smoke checklist:

- Mobile nav có 4 mục và route active đúng.
- Home là dashboard theo scope.
- `/operations` mở đúng grid theo quyền.
- `Thông báo` và `Tài khoản` không regress.
- `/help` mở được khi chưa đăng nhập và đã đăng nhập.
- Super Admin sửa help được; non-Super Admin bị chặn.
- Order đã hủy bị loại khỏi Sales Report và dashboard.
- Các route cleanup không còn top card dư.

Điều kiện push:

- validation pass
- smoke pass
- diff sạch
- local artifact ngoài scope không bị stage nhầm

Push command:

```powershell
git push origin staging
```

Commit cuối nếu chỉ còn wire-up nhỏ:

```text
chore(release): verify master implementation rollout
```

## 8. Gợi Ý Chia Subagent Song Song

Nếu muốn tăng tốc, nên chia ownership theo write-set tách nhau:

- Agent A: Flutter nav/home/operations
  - `lib/app/navigation/*`
  - `lib/features/home/*`
  - `lib/features/operations/*`
- Agent B: backend sales-report/home-summary
  - `backend-nest/src/sales-reports/*`
  - `backend-nest/src/home-summary/*`
  - Prisma migration liên quan đến order exclusion
- Agent C: help runtime + editor + deploy/doc contract
  - `backend-nest/src/help-content/*`
  - `lib/features/help/*`
  - `deploy/home-server/*`
  - docs help/backend-platform
- Agent D: verify-first UI cleanup + test matrix/docs
  - route screens còn intro card
  - `docs/TEST_MATRIX.md`
  - product doc sync

Không nên để nhiều agent cùng sửa:

- `lib/app/navigation/app_router.dart`
- `lib/app/navigation/app_shell.dart`
- `backend-nest/prisma/schema.prisma`

trong cùng một nhịp nếu chưa chia batch rõ, vì rất dễ conflict.

## 9. Tài Liệu Phải Cập Nhật Kèm Code

Batch nào đụng behavior thật thì cập nhật docs cùng lúc:

- `docs/product/help.md`
- `docs/product/backend-platform.md`
- `docs/product/sales-report.md`
- `docs/product/ui-ux.md`
- `docs/product/overview.md` nếu entry-level behavior đổi rõ
- `docs/TEST_MATRIX.md`
- `docs/stories/HELP-001-static-help-page.md`

Nếu một batch buộc phải defer asset uploader, override order hủy, hoặc KPI formula decision, phải ghi backlog qua harness trong cùng turn ship.

## 10. Ngoài Scope

- Redesign lại toàn bộ design system từ đầu.
- Mở quyền sửa help cho non-Super Admin.
- Cho phép raw HTML tùy ý lên public help mà không có sanitizer policy rõ.
- Viết scope engine mới chỉ để phục vụ dashboard.
- Push `staging` trước khi final verification xong.

## 11. Definition Of Done

Plan này chỉ được coi là hoàn tất khi:

- Các batch được triển khai theo đúng dependency, có rollback point riêng.
- Home là dashboard theo scope và `/operations` là workspace catalog mới.
- Sales Report persist và loại được order đã hủy khỏi flow sau này.
- Help runtime content và editor cho Super Admin chạy được.
- `/help` là public route trong Flutter app/web, không còn lệch giữa docs và deploy runtime.
- Cleanup cuối chỉ sửa các màn còn issue thật, không reopen các route đã sạch.
- Product docs và `docs/TEST_MATRIX.md` phản ánh đúng behavior thật sau rollout.
- `staging` chỉ được push sau khi full verification pass.
