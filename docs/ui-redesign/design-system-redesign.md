# OpsHub Redesign Design System

## 1. Trạng thái và phạm vi

Tài liệu này mô tả **target foundation** cho đợt redesign mới. Foundation chỉ
trở thành implementation authority sau khi issue foundation và Figma variables
được Đại Ca duyệt. Runtime hiện tại tiếp tục là compatibility baseline cho các
screen chưa migrate.

Không tạo theme hoặc token tree song song trong feature. Target phải được map
vào shared layer hiện có: `AppColors`, `AppTextStyles`, `AppRadius`,
`AppLayoutTokens`, `AppTheme` và shared widgets.

## 2. Brand và colors

- Giữ official logo/assets và brand palette hiện có.
- Mọi color runtime đi qua `AppColors`; không hardcode `Color(0x...)` hoặc
  `Colors.*` trong feature UI.
- Có thể tạo tonal/semantic variants nhưng phải giữ nhận diện và đạt contrast.
- Semantic groups tối thiểu: brand, primary, secondary, background, surface,
  text, border/divider, success, warning, error, information, overlay, focus,
  selected và disabled.
- Không dùng màu làm tín hiệu duy nhất.

## 3. Typography target

Font target: **Be Vietnam Pro**, weights 400, 500, 600 và 700.

Foundation implementation phải:

1. Xác minh nguồn/license và commit font assets được phép phân phối offline.
2. Khai báo font tập trung trong `pubspec.yaml` và shared theme.
3. Có fallback phù hợp cho ký tự/biểu tượng không được font bao phủ.
4. Proof Android, Windows và web same-origin/offline rendering.
5. Kiểm tra Vietnamese diacritics, long content, numeric/table alignment và
   text scaling.

Không đổi font từng widget. Screen chưa migrate có thể tiếp tục dùng SF Pro
Display cho tới phase cutover đã duyệt; tránh một screen trộn hai font ngoài
compatibility boundary có chủ đích.

Typography roles tối thiểu: display, heading, title, body, label, caption,
button, numeric và table. Feature dùng `AppTextStyles` hoặc theme text styles;
không hardcode family/size/weight/height/letter spacing.

## 4. Responsive foundation

Dùng available width và token hiện tại của repo:

| Class | Width |
| --- | --- |
| Compact | `< 600` |
| Medium | `600–899` |
| Expanded | `900–1199` |
| Wide desktop | `>= 1200` |

- Compact: touch-first, một cột, primary command dùng một tay.
- Medium: rail hoặc hai cột khi content/flow yêu cầu.
- Expanded: sidebar, master-detail hoặc multi-column có bounded width.
- Wide desktop: tiếp tục giới hạn `contentMaxWidth`; không kéo giãn dữ liệu.
- Auth breakpoint riêng tiếp tục dùng shared token cho tới khi foundation issue
  thay đổi có proof.

Figma và Flutter phải dùng cùng tên/giá trị; không đưa breakpoint `840` vào
feature-local code.

## 5. Spacing, radius, elevation và sizing

- Xác định primitive → semantic → component token và map vào shared classes.
- Dùng spacing scale nhất quán; magic number chỉ khi có lý do/proof rõ.
- Radius semantic: small, medium, large và full; tránh mỗi screen một radius.
- Elevation giải thích hierarchy/state, không chỉ trang trí.
- Ưu tiên spacing, surface và typography thay cho card lồng card.
- Touch target, control height và content width phải dùng shared metrics.

## 6. Component strategy

Thứ tự migration:

1. Foundation tokens.
2. Primitives: button, input, icon, text, divider, surface.
3. Form controls và validation.
4. Navigation/shell.
5. Feedback/data states.
6. Composite components và screen templates.
7. Feature screens.

Không mặc định giữ visual cũ, nhưng phải reuse/evolve shared component hiện có
nếu behavior, accessibility và API của nó còn đúng. Không thay component chỉ
để đổi tên hoặc tạo abstraction song song.

Core target gồm buttons, text/search/textarea, `AppCombobox`, checkbox/radio/
switch, chip/badge/tooltip, list/table, dialog/bottom sheet, toast/banner,
skeleton/loading/empty/error/unsupported và pagination.

Mỗi component hỗ trợ các state phù hợp: default, hover, focus, pressed,
selected, disabled, loading, error, success, read-only, long content và large
text scale.

## 7. OpsHub contracts phải giữ

- Date filter mở qua canonical shared DateRangePicker; desktop anchored
  popover, mobile bottom sheet.
- Scan/search/submit command bar giữ input và primary actions cùng hàng.
- Related editor/report flows dùng presentation model nhất quán; long modal
  giữ context header cố định và chỉ scroll body.
- UI copy Vietnamese-first, action-oriented, không lộ role/policy/backend code.
- Shared shell/navigation, global notifications, selection/input context menu,
  dialog dismissal và platform-specific behavior tiếp tục theo
  `docs/product/ui-ux.md` cho tới khi có product decision riêng.

## 8. Accessibility

Bắt buộc: WCAG-appropriate contrast, visible focus, logical focus order,
keyboard navigation, screen reader semantics, touch targets, text scaling,
reduced motion, error announcement, safe area và long Vietnamese content.

Accessibility behavior đang đúng là protected behavior, kể cả khi visual được
redesign.

## 9. Forms, data states và motion

- Label rõ; placeholder không thay label; validation gần field.
- Không mất draft khi lỗi; chống duplicate submit; có loading/disabled state.
- Destructive action tách khỏi primary action và có confirmation khi cần.
- Data screen xét initial loading, refreshing, loaded, empty, filtered empty,
  error/retry, offline, partial, permission denied, session expired và
  pagination states.
- Motion chỉ giải thích state, continuity, confirmation hoặc attention; tôn
  trọng reduced motion và không làm chậm tác vụ.

## 10. Foundation completion gate

Foundation chỉ được coi là sẵn sàng khi có:

- approved Figma variables/components và revision links;
- token mapping vào shared Flutter layer;
- typography asset/license/platform proof;
- responsive/accessibility component proof;
- compatibility strategy và rollback cho unmigrated screens;
- Linear tracking note với exact validation và residual risk.
