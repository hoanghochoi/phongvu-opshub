# OpsHub UI/UX Redesign

Bộ tài liệu này điều phối **đợt redesign mới** của OpsHub. Đây là design target
và delivery workflow, không phải mô tả runtime hiện tại và không tự động thay
thế product contract đã được chấp nhận.

## Bối cảnh repository

OpsHub đã có một đợt Redesign V2 trong năm 2026, cùng `AppShell`, design tokens,
shared components, Figma inventory và regression guards. Vì vậy đợt mới phải:

- audit và kế thừa **hành vi đúng**, nhưng với migrated surface phải bỏ hoàn
  toàn visual UI cũ; code cũ không được dùng làm visual fallback;
- migrate theo feature/screen, không rewrite toàn bộ app trong một PR;
- giữ business logic, API contract, permission, platform contract và dữ liệu;
- giữ màn hình chưa migrate hoạt động theo contract hiện hành;
- chỉ coi visual target là có hiệu lực sau khi Figma frame cụ thể được duyệt.

## Nguồn chuẩn

Các nguồn có phạm vi authority khác nhau:

1. `AGENTS.md`, `docs/WORKFLOW.md`, product docs, security/release rules và
   runtime contracts kiểm soát safety, business behavior, API, permission,
   platform và verification.
2. Xác nhận hiện tại của Đại Ca quyết định product/design direction trong phạm
   vi không làm yếu các guard bắt buộc ở trên.
3. Approved Figma frame kiểm soát visual và interaction target của đúng scope.
4. `design-system-redesign.md` kiểm soát foundation/component target chung.
5. Linear acceptance criteria kiểm soát scope và proof của từng work item.
6. Code hiện tại là baseline cho phần chưa migrate và bằng chứng cho behavior
   cần bảo vệ; nó tuyệt đối không là visual target hay fallback của surface đã
   migrate.

Nếu Figma đưa ra control, dữ liệu hoặc hành vi chưa có product authority, dừng
và tạo quyết định/acceptance criteria trước khi implement.

## Quyết định nền tảng đã chốt

- Giữ brand palette và official brand assets hiện có.
- Be Vietnam Pro là typography target của redesign, chỉ được đưa vào runtime
  qua một foundation issue đã duyệt, có font assets/license/proof đầy đủ.
- Dùng breakpoint token hiện tại: compact `<600`, medium `600–899`, expanded
  `900–1199`, wide desktop `>=1200`.
- Ưu tiên nâng cấp shared tokens/components hiện có; không tạo một design system
  song song trong feature.
- No approved Figma frame means no **visual redesign implementation**.

## Delivery gate bắt buộc cho mọi UI mutation

Mỗi thay đổi visual/interaction phải đi đúng thứ tự dưới đây. Đây là điều kiện
để tiếp tục, không phải checklist có thể bù sau:

1. Retrieve exact approved Figma node/revision cho mọi viewport và state bị ảnh hưởng.
2. Ghi node map: Figma node → shared Flutter widget → token → geometry →
   typography/copy/icon → responsive constraint → behavior cần giữ.
3. Implement chỉ từ node map; thêm widget/golden geometry proof bám map đó.
4. Build source SHA đã test, deploy `staging`.
5. Mở app đã authenticated trong Chrome, chụp và so trực tiếp từng viewport với
   đúng node/revision; sửa mọi drift chưa được duyệt rồi lặp lại từ proof bị ảnh hưởng.

Không được dùng UI/code/screenshot cũ để điền khoảng trống visual ở bất kỳ bước
nào. Code cũ chỉ dùng để bảo vệ behavior; thiếu node, state hoặc viewport là
blocker phải cập nhật Figma + Linear và chờ approval.

## Tài liệu

| Tài liệu | Mục đích |
| --- | --- |
| `ui-redesign-workflow.md` | Quy trình audit → design → approval → code → QA |
| `design-system-redesign.md` | Target tokens, typography, responsive và components |
| `figma-workflow.md` | Cấu trúc frame, review, approval và revision |
| `linear-workflow.md` | Issue/dependency/status/proof theo workflow OpsHub |
| `flutter-implementation-rules.md` | Quy tắc migration Flutter trong repo hiện tại |
| `qa-checklist.md` | Visual, behavior, accessibility và platform proof |
| `templates/` | Mẫu issue và PR cho redesign |
| `AGENTS-snippet.md` | Section đã hiệu chỉnh để ghép vào root `AGENTS.md` |

## Cách bắt đầu một scope redesign

1. Có Linear issue và xác định behavior/product docs cần bảo vệ.
2. Audit code, Figma/history hiện có và affected consumers.
3. Thiết kế/revise frame, đưa vào review và chờ xác nhận rõ ràng.
4. Tạo implementation worktree bằng `scripts/task-lifecycle.mjs start` từ live
   `origin/staging`.
5. Implement incremental, chạy focused proof và full gates theo risk.
6. PR vào `staging`, staging QA rồi mới đủ điều kiện xét production promotion.

Bug fix chỉ khôi phục behavior/visual đã được duyệt có thể dùng source hiện có
thay vì tạo Figma mới. Nếu fix thay đổi intended design, Figma gate áp dụng.
