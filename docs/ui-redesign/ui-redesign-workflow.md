# OpsHub UI/UX Redesign Workflow

## 1. Mục tiêu

Redesign UI/UX OpsHub theo một visual foundation mới, task-first, responsive,
accessible và phù hợp thao tác vận hành nội bộ trên Android và Windows; web là
surface bổ sung phải tiếp tục hoạt động đúng contract.

Đợt redesign được phép thay visual hierarchy, typography, spacing, radius,
elevation, layout, navigation presentation, component appearance, interaction
presentation và motion. Nó không được tự ý thay:

- business logic, API/persistence contract hoặc permission;
- nội dung nghiệp vụ và Vietnamese-first copy rules;
- platform capability, shared runtime behavior hoặc security controls;
- accepted user flow, trừ khi có product decision riêng được ghi nhận;
- shared DateRangePicker, command-input layout, modal consistency và các
  contract UI cụ thể trong `AGENTS.md`/`docs/product/ui-ux.md`.

## 2. Figma gate

> **No approved Figma frame → No visual redesign implementation.**

Gate áp dụng khi task tạo hoặc thay đổi visual/interaction target thuộc đợt
redesign. Không bắt buộc tạo frame mới cho:

- review, test hoặc documentation không đổi UI;
- restorative bug fix đưa UI trở về approved behavior hiện có;
- refactor presentation không tạo khác biệt quan sát được và có regression
  proof phù hợp.

Nếu một bug fix hoặc refactor làm thay intended design, gate áp dụng lại.

## 3. Authority theo loại quyết định

| Loại quyết định | Authority |
| --- | --- |
| Safety, Git/release, privacy, security | `AGENTS.md` và runbook hiện hành |
| Business, API, permission, platform | Accepted product/runtime contracts |
| Scope, acceptance, proof | Linear issue và repository verification rules |
| Visual/interaction target | Approved Figma frame của đúng revision |
| Foundation/component target | `design-system-redesign.md` |
| Unmigrated behavior | Current product docs, code và tests |

Không dùng Figma để phát minh dữ liệu, quyền, route hoặc backend behavior. Không
dùng code legacy để phủ quyết target visual đã được duyệt.

Với mọi surface đã migrate, UI cũ phải được bỏ hoàn toàn. Code/test cũ chỉ là
authority bảo vệ behavior; không được tái dùng layout, spacing, typography,
icon, copy hoặc component appearance cũ làm fallback hay vì "gần giống". Thiếu
node cho một phần tử nhìn thấy là blocker Figma, không phải quyền suy diễn từ
runtime hiện tại.

## 4. Quy trình

### A — Intake và audit

1. Xác định Linear issue, scope, risk flags và affected consumers.
2. Đọc `docs/product/ui-ux.md`, product doc của feature, previous redesign audit,
   gap map, relevant Figma frames, code và tests.
3. Ghi rõ behavior phải giữ, visual được thay, platform và state cần proof.
4. Audit shared theme/tokens/components trước feature-local widgets.
5. Không refactor hoặc sửa runtime trong bước audit.
6. Lập node map theo từng viewport: exact Figma node/revision → Flutter shared
   component → token (màu/type/spacing/radius/elevation) → geometry/copy/icon
   → behavior phải giữ. Không có node map thì không bắt đầu UI mutation.

Audit phải thừa nhận baseline hiện tại; không giả định repo là greenfield.

### B — Foundations

Foundation issue xác định và duyệt:

- brand/color mapping và semantic colors;
- Be Vietnam Pro assets, weights, fallback và rendering proof;
- typography, spacing, radius, elevation, icon/component sizes;
- breakpoint/content width theo `AppLayoutTokens`;
- motion, focus, semantics và reduced-motion rules;
- migration/compatibility strategy cho màn hình chưa chuyển đổi.

Foundation chưa duyệt thì screen design không được tự đặt token riêng.

### C — Figma design

1. Thiết kế đúng scope/behavior đã audit.
2. Bao gồm breakpoint và state có ý nghĩa; ghi lý do nếu không áp dụng.
3. Ghi interaction, responsive, accessibility và technical notes.
4. Link exact frame/node/revision vào Linear.
5. Đưa vào Review và dừng chờ approval rõ ràng.

Khi sửa hoặc thêm component foundation, Figma review phải có proof cho:

- icon semantic đúng family Phosphor theo luồng catalog `Icon Exploration —
  Phosphor`; retry/loading, scan/search/submit và pagination/row action không
  dùng glyph generic hoặc icon khác nghĩa;
- action/container auto-layout không overlap; input đủ bốn cạnh ở mọi state;
- textarea/search có helper/error và character counter dùng hai lane riêng,
  với case validation dài đã render để chứng minh không overlap;
- focus control nằm đúng control, không bị clipping; navigation dark surface
  có contrast đủ cho icon/label và quick action;
- DateRangePicker có `Hôm qua` trên desktop popover lẫn mobile bottom sheet;
- cùng một surface không lặp shortcut/copy/action cùng nghĩa; với desktop
  DateRangePicker, preset chỉ ở cột `Khoảng nhanh`, không lặp trong date field;
- compact mobile không để helper không thiết yếu chiếm chỗ; `?` phải mở
  bubble/dialog ngữ cảnh, còn error/validation/permission thiết yếu vẫn hiện
  trực tiếp.
- trên compact mobile, chức năng nằm ở app bar; action/link trong helper được
  đưa ra command/action area trước khi ẩn helper.
- trước review, chạy collision audit top-level App Shell frame theo bounding
  box; sắp frame vào grid Desktop/Mobile/Tablet với gutter và chỉ pass khi
  overlap = 0.
- file hiện giữ tám page canonical: `Cover`, `Foundation` và sáu page screen
  `Screens — Desktop · Windows`, `Screens — Mobile · Android`,
  `Screens — Tablet · Android`, `Screens — Mobile · iOS`,
  `Screens — Tablet · iPadOS` và `Screens — Web · Responsive`; source và
  documentation ở Foundation, screen page không chứa main component.

Im lặng, emoji hoặc task chuyển status không tự động là design approval.

### D — Approval

Approval phải nêu rõ frame/revision được duyệt. Sau approval:

1. Đóng băng approved revision hoặc tạo version snapshot.
2. Ghi approval và frame links trong Linear.
3. Bỏ blocker cho implementation issue.
4. Mọi thay đổi visual tiếp theo phải đi qua revision/re-approval.

### E — Flutter implementation

1. Tạo Linear-linked task branch/worktree từ live `origin/staging` bằng
   `scripts/task-lifecycle.mjs start`.
2. Migrate shared token/primitive trước khi tạo feature-local variant.
3. Giữ business/state/provider/service behavior ngoài scope không đổi.
4. Implement đúng approved frame và required states.
5. Thêm sanitized `AppLogger` cho flow user-facing mới/thay đổi.
6. Nếu technical constraint buộc đổi design, dừng phần liên quan, cập nhật
   Linear/Figma và chờ re-approval.
7. Không dùng visual UI cũ làm fallback. Nếu Figma thiếu một visible state hoặc
   element, tạo/revise node và chờ approval; vẫn có thể tiếp tục các node đã đủ
   authority.

### F — Verification

Proof tối thiểu cho UI code:

- focused unit/widget/golden or visual regression proof;
- compact, medium, expanded và wide behavior khi layout đổi;
- loading, empty, error, long Vietnamese content và text scaling;
- keyboard, focus, semantics, safe area, overflow và performance;
- render/review các master component sau khi sửa để bắt overlap, border mất
  cạnh, focus clipping, icon sai ngữ nghĩa và foreground chìm trên nền tối;
- protected old-consumer proof theo risk lane;
- `dart format`, `git diff --check`, Flutter analyze/test theo repo contract.
- geometry/widget or golden proof bám exact node map ở mọi breakpoint thay đổi;
  test phải kiểm tra kích thước, vị trí, copy/icon và overflow khi áp dụng.
- build của source SHA; sau staging deploy, Chrome audit authenticated tại mọi
  viewport affected, so trực tiếp với exact Figma node/revision. Difference
  chưa được duyệt là fail và phải sửa/audit lại, không được gọi là complete.

Ảnh so sánh phải ghi viewport/platform, frame/node và build/SHA.

### G — Delivery

- PR title `[OPS-123] Description`, base `staging`.
- Body dùng `Part of OPS-123` khi chờ staging QA.
- PR link Linear issue, approved Figma revision, screenshots và exact proof.
- Feature PR squash-and-merge; merge staging chưa phải `Done`.
- Linear `Done` chỉ sau production deployment thành công.
- Production promotion tuân thủ exact authorization và release playbook.

## 5. Rollout

1. Foundations và compatibility strategy.
2. Core primitives/components và guard tests.
3. Ba screen đại diện: form, data-heavy, list/detail workflow.
4. Feature migration theo dependency và user impact.
5. Cleanup/deprecation chỉ khi không còn consumer và rollback path đã rõ.

Không migrate toàn bộ app trong một PR. Mỗi phase phải có rollback được và màn
hình chưa migrate vẫn chạy theo baseline hiện hành.

## 6. Stop conditions

Dừng trước mutation hoặc phần implementation liên quan khi:

- thiếu product authority hoặc approved Figma;
- Figma mâu thuẫn business/API/permission/platform contract;
- source revision, branch/SHA hoặc acceptance criteria đã stale;
- design đòi component song song thay vì shared migration chưa được duyệt;
- proof bắt buộc không thể chạy hoặc có nguy cơ bị làm yếu;
- technical constraint cần thay approved design.
