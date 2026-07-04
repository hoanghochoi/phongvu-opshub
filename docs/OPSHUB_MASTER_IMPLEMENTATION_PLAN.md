# OpsHub Master Implementation Plan

Ngày lập: 2026-07-04

## 1. Bối Cảnh Và Checkpoint

Plan này gom các yêu cầu mới vào một kế hoạch triển khai duy nhất, thay vì nhồi thêm vào
`docs/UI_UX_AUDIT_PLAN.md`. Lý do: phạm vi hiện tại đã vượt UI/UX thuần túy, bao gồm
điều hướng mobile, màn hình tổng quan, Help CMS, quyền Super Admin, hành vi DB cho đơn đã
hủy và dọn lại các màn hình còn top card.

Checkpoint tại thời điểm lập plan:

- Branch: `staging`.
- HEAD: `9466ea33`.
- Tracked worktree: sạch.
- Artifact local chưa tracked, giữ nguyên và không đưa vào batch này nếu không có yêu cầu riêng:
  - `assets/image/`
  - `docs/UI_UX_AUDIT_PLAN_CODEX.md`

Nguyên tắc triển khai:

- Làm từng batch nhỏ, dễ rollback.
- Trước mỗi batch: kiểm tra diff hiện tại và xác nhận không kéo nhầm thay đổi ngoài scope.
- Sau mỗi batch: chạy test focused, kiểm tra diff, rồi commit local.
- Chỉ push `staging` sau khi toàn bộ batch qua final verification.
- Không revert hoặc chỉnh các thay đổi local không thuộc batch.
- Mọi UI copy hiển thị cho nhân viên phải tiếng Việt, dễ hiểu, không lộ mã quyền nội bộ.
- Flow mới hoặc flow bị sửa phải có log hữu ích qua `AppLogger` ở Flutter và logger backend tương ứng.

## 2. Scope Tổng Hợp

### 2.1 Mobile Nav 4 Mục

Mobile bottom navigation sẽ còn 4 mục:

1. Trang chủ
2. Vận hành
3. Thông báo
4. Tài khoản

Mục tiêu IA:

- `Trang chủ`: chuyển thành nơi hiển thị tổng quan vận hành.
- `Vận hành`: hiển thị các nút chọn chức năng nghiệp vụ.
- `Thông báo`: giữ luồng thông báo, tránh trùng vai trò với icon chuông ở header.
- `Tài khoản`: gom thông tin cá nhân, cài đặt, hỗ trợ và các action tài khoản.
- Desktop sidebar vẫn có `Trang chủ`.

### 2.2 Màn Hình `/operations`

Tạo destination vận hành dùng chung cho mobile và desktop khi cần:

- Là nơi chứa lưới shortcut nghiệp vụ.
- Tôn trọng phân quyền hiện có.
- Không copy/paste lưới chức năng từ Home cũ thành logic riêng.
- Dùng lại card/grid shared nếu repo đã có pattern như `AppFeatureSection` hoặc `AppFeatureGrid`.

### 2.3 `/help` Thành Màn Hình Trong App

`/help` phải là một route trong Flutter app/web:

- Người chưa đăng nhập vẫn đọc được hướng dẫn.
- Người đã đăng nhập có thể mở Help trong app shell hoặc từ khu vực tài khoản.
- Trang download tiếp tục link tới `/help`.
- Không còn phụ thuộc vào static HTML riêng cho trải nghiệm chính.
- Nội dung Help đọc từ backend runtime content để save là lên trang ngay, không cần redeploy.

### 2.4 Chức Năng Sửa Hướng Dẫn Cho Super Admin

Chỉ Super Admin được sửa trang hướng dẫn:

- Có màn hình quản trị nội dung hướng dẫn trong app/web.
- Có thể sửa nội dung, tiêu đề, thứ tự, trạng thái hiển thị.
- Có thể lưu và thấy ngay trên `/help`.
- Có thể upload hoặc gắn ảnh minh họa nếu cần.
- Người không phải Super Admin không thấy entry sửa hướng dẫn và backend cũng phải chặn.

### 2.5 Trang Chủ Tổng Quan Vận Hành

Home mới hiển thị số liệu tổng quan trong ngày theo phạm vi quyền:

- Doanh số bán trong ngày.
- Tổng số đơn hàng.
- Tổng số báo cáo.
- Đơn đã báo cáo.
- Đơn chưa báo cáo.
- Tỉ lệ chuyển đổi `% = tổng số đơn hàng / tổng số báo cáo * 100`, guard chia cho 0.

Phạm vi dữ liệu:

- User thường: chỉ xem dữ liệu của mình.
- Store Manager: xem dữ liệu cửa hàng mình.
- Area Manager: xem dữ liệu vùng mình.
- Các cấp quản lý cao hơn: xem theo cây tổ chức hoặc scope đã được hệ thống phân quyền.
- Super Admin/Admin phù hợp: xem theo phạm vi được phép, không bypass rules nếu UI đang ở scope hẹp.

### 2.6 Sales Report: Đơn Đã Hủy

Khi user báo cáo đơn hàng đã mua:

- App/backend lấy thông tin đơn hàng từ nguồn hiện tại.
- Nếu thấy đơn đã hủy:
  - tự đóng form báo cáo,
  - báo nhẹ cho user bằng copy tiếng Việt,
  - ẩn đơn đã hủy khỏi danh sách báo cáo,
  - lưu trạng thái đã hủy vào DB,
  - không dùng đơn đó cho báo cáo sau này nữa.
- Không tạo báo cáo sale cho đơn đã hủy.
- Không tính đơn đã hủy vào dashboard và các màn hình báo cáo vận hành.

### 2.7 Cleanup Top Card

Các màn hình còn top card giới thiệu lớn cần được dọn:

- `VietQR`
- `Quản trị`
- `Báo cáo`
- `Góp ý`
- Các màn hình tương tự nếu scan phát hiện cùng pattern

Nguyên tắc UI:

- Màn hình nghiệp vụ bắt đầu bằng nội dung thao tác chính.
- Không dùng top card lớn chỉ để lặp lại tên màn hình/mô tả.
- Nếu cần mô tả, chuyển thành heading nhỏ, helper text hoặc empty state đúng ngữ cảnh.

## 3. Contract API Và DB Dự Kiến

### 3.1 Home Summary API

Endpoint đề xuất:

```http
GET /api/home/summary?date=YYYY-MM-DD
```

Response đề xuất:

```json
{
  "date": "2026-07-04",
  "scope": {
    "type": "user|store|area|region|all",
    "label": "Phạm vi đang xem"
  },
  "salesRevenue": 125000000,
  "totalOrders": 42,
  "totalReports": 38,
  "reportedOrders": 35,
  "unreportedOrders": 7,
  "conversionRate": 110.53,
  "updatedAt": "2026-07-04T10:30:00.000Z"
}
```

Quy ước tính:

- `salesRevenue`: tổng giá trị đơn hợp lệ trong ngày, không tính đơn đã hủy.
- `totalOrders`: số đơn hợp lệ trong ngày theo scope.
- `totalReports`: số báo cáo hợp lệ trong ngày theo scope.
- `reportedOrders`: số đơn đã có báo cáo.
- `unreportedOrders`: `totalOrders - reportedOrders`, không âm.
- `conversionRate`: `totalOrders / totalReports * 100`, nếu `totalReports = 0` thì trả `0`.
- Scope phải reuse logic phân quyền Sales Report và cây tổ chức hiện có.

Điểm cần kiểm tra trước code:

- Repo đang lưu/cached đơn hàng ở bảng nào.
- `SalesReport` hiện liên kết order bằng field nào.
- Logic scope hiện dùng `organizationNodeId`, store assignment, hay helper riêng nào.
- Có cần cache ERP order trong DB để dashboard không gọi ERP quá nhiều hay không.

### 3.2 Help Content API

Public endpoint:

```http
GET /api/help-content
```

Response đề xuất:

```json
{
  "version": 12,
  "updatedAt": "2026-07-04T10:30:00.000Z",
  "pages": [
    {
      "id": "getting-started",
      "title": "Bắt đầu sử dụng",
      "slug": "bat-dau-su-dung",
      "order": 10,
      "contentMarkdown": "...",
      "isPublished": true
    }
  ]
}
```

Admin endpoints đề xuất:

```http
GET    /api/admin/help-content/pages
POST   /api/admin/help-content/pages
PATCH  /api/admin/help-content/pages/:id
POST   /api/admin/help-content/assets
```

DB models đề xuất:

- `HelpPage`
  - `id`
  - `slug`
  - `title`
  - `contentMarkdown`
  - `order`
  - `isPublished`
  - `createdAt`
  - `updatedAt`
  - `updatedByUserId`
- `HelpPageRevision`
  - `id`
  - `pageId`
  - `title`
  - `contentMarkdown`
  - `order`
  - `isPublished`
  - `createdAt`
  - `createdByUserId`
- `HelpAsset` nếu upload ảnh được tách riêng.

Authorization:

- Public `GET /api/help-content`: không cần đăng nhập, chỉ trả page published.
- Admin endpoints: yêu cầu đăng nhập và role Super Admin.
- Backend không chỉ dựa vào việc ẩn UI.

Seed/migration:

- Seed ban đầu từ `docs/help/navigation.json` và `docs/help/content/*` nếu bảng Help trống.
- Sau khi có dữ liệu DB, DB là source of truth cho `/help`.
- File docs giữ vai trò backup/reference, không còn là nội dung live.

### 3.3 Sales Report Canceled Order Persistence

Field/model đề xuất tùy schema hiện tại:

- Nếu đã có bảng cache order/report candidate: thêm trạng thái vào bảng đó.
- Nếu chưa có: tạo bảng nhẹ để lưu order bị loại khỏi report.

Fields cần có:

- `orderCode`
- `orderStatus`
- `isCanceled`
- `canceledAt`
- `excludedFromReportsAt`
- `excludedReason`
- `lastCheckedAt`
- `source`
- `createdByUserId` hoặc user đã trigger check
- scope/store/showroom nếu có

Contract:

- Một khi order được xác định đã hủy, các API danh sách report candidate phải loại order này.
- Khi user nhập lại order đã hủy, API trả trạng thái rõ ràng để app đóng form/không cho report.
- Dashboard không tính order đã hủy.
- Log phải ghi decision branch: order fetched, status canceled, persisted exclusion, form closed.

## 4. Kế Hoạch Batch

## Batch 1 - Mobile Nav 4 Mục Và `/operations`

Mục tiêu:

- Đổi mobile nav thành `Trang chủ`, `Vận hành`, `Thông báo`, `Tài khoản`.
- Home không còn là lưới chức năng chính.
- Tạo `/operations` để chứa shortcut nghiệp vụ.
- Desktop sidebar vẫn có `Trang chủ`.

Files/modules dự kiến chạm:

- `lib/app/router.dart` hoặc router tương đương.
- `lib/app/app_shell.dart` hoặc shell/navigation tương đương.
- `lib/features/home/*`.
- `lib/features/operations/*` mới hoặc module phù hợp.
- Shared feature card/grid component nếu đang có.
- Test widget/navigation liên quan.

API/DB contract:

- Không thêm DB.
- Không thêm API bắt buộc.
- Chỉ reuse feature entitlement/permission hiện tại.

UI behavior:

- Mobile bottom nav có đúng 4 item.
- Header không tạo cảm giác trùng thông báo với nav; nếu header vẫn có bell thì cần rõ vai trò hoặc bỏ khỏi mobile header nếu dư.
- `Vận hành` mở lưới chức năng theo quyền.
- Desktop vẫn vào `Trang chủ` từ sidebar.

Test focused:

```powershell
flutter test --no-pub --reporter expanded test/app_shell_navigation_test.dart
flutter analyze
```

Nếu test hiện tại tên khác, chọn test gần nhất cho shell/router và ghi rõ trong commit note.

Điều kiện commit local:

- Diff chỉ gồm navigation/operations và test liên quan.
- Mobile nav render đúng 4 mục.
- Không mất quyền truy cập chức năng đang có.
- Commit message đề xuất:

```text
feat(nav): add operations hub and four-tab mobile shell
```

## Batch 2 - `/help` Thành Màn Hình Flutter Public

Mục tiêu:

- `/help` mở được trong Flutter web/app.
- Người chưa đăng nhập đọc được Help.
- Link `Hướng dẫn sử dụng` từ download/login/account trỏ về `/help`.

Files/modules dự kiến chạm:

- `lib/app/router.dart`.
- `lib/features/help/presentation/help_screen.dart` mới.
- `lib/features/auth/presentation/*` nếu login có link Help.
- `deploy/*`, Caddy/nginx/static routing nếu đang route `/help` ra static site.
- `docs/help/*` chỉ cập nhật mô tả vai trò nếu cần.
- `docs/product/help.md` nếu chưa có thì tạo.

API/DB contract:

- Tạm thời có thể đọc từ bundled seed/static JSON nếu Batch 3 chưa làm API.
- Nhưng route `/help` phải được thiết kế để chuyển sang API runtime content.

UI behavior:

- `/help` có CTA `Đăng nhập` cho khách chưa đăng nhập.
- Không hiển thị nút sửa trên public Help.
- Layout mobile/web đọc dễ, không bị app shell redirect về login.

Test focused:

```powershell
flutter test --no-pub --reporter expanded test/help_screen_test.dart
flutter analyze
```

Smoke thủ công:

- Mở `/help` khi logged out.
- Mở `/help` khi logged in.
- Kiểm tra download page link tới `/help`.

Điều kiện commit local:

- `/help` là route Flutter public.
- Không phá `/download`.
- Commit message đề xuất:

```text
feat(help): render help as public app route
```

## Batch 3 - Help CMS Runtime Và Super Admin Editor

Mục tiêu:

- Nội dung hướng dẫn sửa được trong app/web.
- Save xong cập nhật public `/help` ngay, không cần redeploy.
- Chỉ Super Admin được sửa.

Files/modules dự kiến chạm:

- `backend-nest/prisma/schema.prisma`.
- Prisma migration mới.
- `backend-nest/src/help-content/*` mới.
- Auth/role guard hiện có.
- `lib/features/help/*`.
- `lib/features/admin/*` hoặc menu quản trị hiện có.
- `docs/product/help.md`.
- Test backend và Flutter liên quan.

API/DB contract:

- Thêm `HelpPage`, `HelpPageRevision`, có thể thêm `HelpAsset`.
- Public `GET /api/help-content`.
- Admin CRUD `/api/admin/help-content/pages`.
- Admin upload asset `/api/admin/help-content/assets` nếu làm upload trong batch này.
- Guard backend bắt buộc Super Admin.

UI behavior:

- Super Admin thấy entry `Sửa hướng dẫn` hoặc `Quản lý hướng dẫn`.
- Non-Super Admin không thấy entry.
- Nếu non-Super Admin gọi API trực tiếp, backend trả forbidden copy an toàn.
- Editor có state loading, saving, saved, error.
- Save xong public Help refresh hoặc đọc lại API và hiển thị nội dung mới.

Logging:

- Backend log: load, save, upload, forbidden attempt, validation error.
- Flutter `AppLogger`: open editor, save start/success/failure, public Help load start/success/failure.
- Không log raw content dài hoặc token.

Test focused:

```powershell
cd backend-nest
npm run build
npm test -- --runInBand src/help-content/help-content.service.spec.ts src/help-content/help-content.controller.spec.ts
cd ..
flutter test --no-pub --reporter expanded test/help_screen_test.dart test/admin_menu_screen_test.dart
flutter analyze
```

Điều kiện commit local:

- Migration chạy được.
- Public Help đọc từ API.
- Super Admin sửa được.
- Non-Super Admin bị chặn ở UI và API.
- Commit message đề xuất:

```text
feat(help): add runtime help editor
```

## Batch 4 - Trang Chủ Tổng Quan Vận Hành

Mục tiêu:

- Home hiển thị dashboard tổng quan trong ngày.
- Dữ liệu theo đúng phân quyền/scope.
- Không còn dùng Home làm lưới shortcut nghiệp vụ.

Files/modules dự kiến chạm:

- `backend-nest/src/home-summary/*` mới hoặc module phù hợp.
- Sales Report service/scope helpers hiện có.
- Prisma query/cached order source nếu có.
- `lib/features/home/*`.
- `lib/features/home/data/*` và provider/state tương ứng.
- `docs/product/home-dashboard.md` nếu cần tạo.

API/DB contract:

- `GET /api/home/summary?date=YYYY-MM-DD`.
- Response theo contract ở mục 3.1.
- Backend tự resolve scope từ user hiện tại, không tin scope client gửi lên.
- Nếu cần filter date theo timezone Việt Nam, thống nhất trong service và test.

UI behavior:

- Home có metric cards nhỏ gọn, không dùng hero/top card lớn.
- Có indicator phạm vi đang xem: cá nhân/cửa hàng/vùng.
- Loading skeleton gọn.
- Empty state tiếng Việt nếu chưa có dữ liệu.
- Error state có hành động thử lại.
- Các shortcut nghiệp vụ chuyển sang `/operations`.

Logging:

- Flutter log load dashboard start/success/failure, scope label, counts, duration.
- Backend log summary query start/success/failure, scope type, counts, duration.

Test focused:

```powershell
cd backend-nest
npm run build
npm test -- --runInBand src/home-summary/home-summary.service.spec.ts src/home-summary/home-summary.controller.spec.ts
cd ..
flutter test --no-pub --reporter expanded test/home_dashboard_test.dart
flutter analyze
```

Acceptance:

- User chỉ thấy số của mình.
- Store Manager thấy cửa hàng mình.
- Area Manager thấy vùng mình.
- Đơn đã hủy bị loại.
- `conversionRate` guard chia 0.

Điều kiện commit local:

- Contract backend + UI + test focused pass.
- Commit message đề xuất:

```text
feat(home): add scoped operating summary dashboard
```

## Batch 5 - Sales Report Durable Canceled Orders

Mục tiêu:

- Persist trạng thái order đã hủy vào DB.
- Tự đóng form báo cáo nếu order đã mua nhưng ERP/source trả trạng thái đã hủy.
- Ẩn order đã hủy khỏi các report flow sau này.

Files/modules dự kiến chạm:

- `backend-nest/prisma/schema.prisma`.
- Prisma migration mới.
- Sales Report service/controller hiện có.
- Order lookup/cache service hiện có.
- `lib/features/sales_report/*` hoặc module báo cáo tương ứng.
- Tests sales report backend và Flutter form/list.
- Product docs sales report.

API/DB contract:

- Thêm hoặc mở rộng bảng lưu exclusion/canceled state.
- API lookup order trả trạng thái `excluded/canceled` đủ rõ cho client.
- API list candidate loại order đã hủy.
- API create report fail closed nếu order đã bị đánh dấu hủy.

UI behavior:

- Khi nhập/chọn order đã hủy:
  - form báo cáo tự đóng hoặc quay về danh sách,
  - hiện snackbar/dialog ngắn: `Đơn hàng đã hủy nên không cần báo cáo.`,
  - không giữ draft report cho order đó.
- Danh sách sau refresh không còn order đã hủy.
- Không làm mất dữ liệu báo cáo hợp lệ khác.

Logging:

- Lookup order start/success/failure.
- Branch `order canceled`.
- Persist exclusion success/failure.
- Client form closed due to canceled order.

Test focused:

```powershell
cd backend-nest
npm run build
npm test -- --runInBand src/sales-report/sales-report.service.spec.ts src/sales-report/sales-report.controller.spec.ts
cd ..
flutter test --no-pub --reporter expanded test/sales_report_canceled_order_test.dart
flutter analyze
```

Acceptance:

- Đơn đã hủy được lưu DB.
- Không tạo `SalesReport` cho đơn đã hủy.
- Lần sau order không hiện trong candidate list.
- Dashboard không tính order đã hủy.

Điều kiện commit local:

- Migration và tests pass.
- Commit message đề xuất:

```text
feat(sales-report): persist canceled order exclusions
```

## Batch 6 - Cleanup Top Card

Mục tiêu:

- Dọn các top card dư ở màn hình nghiệp vụ.
- Đảm bảo plan và thực thi khớp nhau trên desktop/mobile/web.

Files/modules dự kiến chạm:

- `lib/features/vietqr/*`.
- `lib/features/admin/*`.
- `lib/features/reports/*`.
- `lib/features/feedback/*`.
- Shared page/header/card component nếu top card đến từ component chung.
- Widget/golden tests nếu có.

API/DB contract:

- Không thay đổi API/DB.

UI behavior:

- `VietQR`, `Quản trị`, `Báo cáo`, `Góp ý` không còn top card lớn như screenshot.
- Nội dung chính nằm gần đầu màn hình hơn.
- Empty/permission states vẫn rõ.
- Không tạo card lồng card.
- Mobile và desktop không overlap text.

Test focused:

```powershell
flutter test --no-pub --reporter expanded test/ui_top_card_cleanup_test.dart
flutter analyze
```

Visual verification:

- Desktop: các route target.
- Mobile narrow viewport: các route target.
- Web build/smoke nếu route chỉ lỗi trên web.

Acceptance:

- Không còn top card dư ở các route target.
- Header/page title vẫn đủ ngữ cảnh.
- Không mất action chính của từng màn hình.

Điều kiện commit local:

- Diff chỉ gồm UI cleanup và tests liên quan.
- Commit message đề xuất:

```text
feat(ui): remove redundant top cards
```

## Batch 7 - Final Verification Và Push Staging

Mục tiêu:

- Xác nhận toàn bộ thay đổi không phá runtime.
- Chỉ push `staging` sau khi pass.

Commands bắt buộc:

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
```

Smoke staging/local cần kiểm:

- Mobile nav:
  - có 4 mục,
  - `Trang chủ` mở dashboard,
  - `Vận hành` mở shortcut nghiệp vụ,
  - `Thông báo` hoạt động,
  - `Tài khoản` có thông tin/cài đặt.
- Desktop:
  - sidebar vẫn có `Trang chủ`,
  - các route nghiệp vụ vẫn mở đúng theo quyền.
- Help:
  - `/help` mở khi chưa đăng nhập,
  - `/help` mở khi đã đăng nhập,
  - Super Admin sửa và save nội dung,
  - nội dung public cập nhật không redeploy,
  - non-Super Admin không sửa được.
- Home dashboard:
  - user/store manager/area manager nhìn đúng scope,
  - số liệu trong ngày đúng với dữ liệu test,
  - guard chia 0,
  - order đã hủy bị loại.
- Sales Report:
  - order đã hủy đóng form,
  - DB lưu trạng thái,
  - order đã hủy không hiện lại.
- Top card cleanup:
  - target screens không còn top card dư,
  - mobile/desktop không overlap.

Điều kiện push staging:

- `git diff --check` sạch.
- Tất cả validation bắt buộc pass hoặc blocker được nêu rõ và được Đại Ca chấp nhận.
- `git status --short` chỉ còn artifact local được chủ động loại khỏi commit nếu có.
- Push command:

```powershell
git push origin staging
```

Commit final nếu chỉ chỉnh wiring nhỏ sau verification:

```text
chore(release): verify opshub master implementation
```

## 5. Tài Liệu Cần Cập Nhật Khi Implement

Các batch code cần cập nhật docs tương ứng:

- `docs/product/home-dashboard.md`
  - scope, metric definitions, role visibility.
- `docs/product/help.md`
  - `/help` route, public read, Super Admin editor, runtime save.
- `docs/product/sales-report.md`
  - canceled order exclusion behavior.
- `docs/TEST_MATRIX.md`
  - thêm proof cho mobile nav, Help CMS, Home dashboard, canceled order, top-card cleanup.
- `docs/decisions/*` nếu có tradeoff đáng lưu như DB source of truth cho Help.

## 6. Ngoài Scope Của Plan Này

- Thiết kế lại toàn bộ design system.
- Tạo landing page marketing.
- Cho phép editor Help public hoặc non-Super Admin.
- Sửa raw HTML tự do cho Help content nếu chưa có sanitizer rõ ràng.
- Thay toàn bộ backend scope engine nếu helper hiện tại đủ dùng.
- Push staging khi chưa qua verification.

## 7. Definition Of Done

Plan được xem là hoàn tất khi:

- Mỗi batch được implement, test focused và commit local riêng.
- Final verification pass đủ Flutter, NestJS, Go và smoke.
- Docs product/test matrix được cập nhật theo behavior thật.
- Không còn top card dư ở các màn hình target.
- `/help` là màn hình app, nội dung sửa runtime, chỉ Super Admin được sửa.
- Home hiển thị dashboard đúng scope.
- Sales Report persist và loại đơn đã hủy khỏi các flow sau này.
- `staging` chỉ được push sau khi pass toàn bộ kiểm tra.
