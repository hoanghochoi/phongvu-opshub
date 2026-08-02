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

### Quy tắc component bắt buộc

- Icon dùng trong Figma và runtime thuộc một family thống nhất: **Phosphor**.
  Luồng bắt buộc là tìm theo ngữ nghĩa nghiệp vụ trong
  [`phosphor-icons/core`](https://github.com/phosphor-icons/core) → đưa SVG
  official vào section `FOUNDATION / Icons — Phosphor` trên page `Foundation`
  → mới reuse ở component/screen.
  Dùng Regular mặc định; Fill chỉ dành cho trạng thái active/filled được chỉ
  định rõ. Không vẽ lại icon bằng primitive hoặc thay một icon generic cho
  action có ngữ nghĩa khác.
- Status Banner dùng `arrow-counter-clockwise` cho retry và spinner Phosphor
  cho busy. Action phải là auto-layout, có khoảng cách icon/label rõ ràng và
  không được đè lên nội dung banner.
- Focus của checkbox/radio/switch chỉ viền quanh control thực, không viền cả
  hit-area 48 px, không clip và không tách rời control. Giữ outline 2 px có
  contrast, thứ tự focus logic và hit target tối thiểu 48 dp trên Android,
  44 pt trên iOS/iPadOS.
- Mobile Button có thể dùng visual surface cao 40 px trong toolbar/dialog chật,
  nhưng interaction, focus và semantics hit box bên ngoài vẫn phải tối thiểu
  48 dp trên Android và 44 pt trên iOS/iPadOS. Không được map trực tiếp visual
  40 px thành hit target 40 px; action độc lập tiếp tục ưu tiên control cao
  48 px.
- Input, combobox và command input phải giữ đủ bốn cạnh ở default, focused,
  error, disabled và read-only; stroke nằm trong bounds để không bị cắt. Focus
  dùng semantic focus border, không thay bằng shadow rời hoặc mất cạnh; field
  không clip chính stroke của mình.
- Với textarea/search có helper hoặc lỗi kèm character counter, helper/error và
  counter là hai lane auto-layout riêng: helper được wrap trong phần còn lại,
  counter có bề rộng cố định và căn đáy. Component phải đủ chiều cao cho hai
  dòng helper để không overlap hoặc làm mất counter.
- Navigation trên nền tối dùng foreground đủ contrast: icon/label mặc định là
  light neutral, selected theo semantic selected; quick action nổi bật dùng
  icon trắng. Không dùng neutral xám tối cho foreground trên dark surface.
- Navigation Destination ở **mọi state** luôn dùng slot icon Phosphor 24 px:
  Sidebar/Rail căn giữa theo cả hai trục của ô icon, Bottom Navigation căn giữa
  trong vùng icon phía trên label. Ở state selected, icon dùng đúng semantic foreground của
  label selected, không giữ màu default/dark-surface. Sau khi sửa component
  nguồn, phải audit tất cả instance/override ở các Shell mẫu và màn hình; một
  override cũ không được phép giữ màu hoặc hình học khác component nguồn.
- Reusable source (component, component set, icon master, screen pattern và
  specimen) chỉ nằm trên page `Foundation`, trong section theo family. Toàn bộ
  documentation cũng nằm ở `FOUNDATION / Documentation`; không tạo page riêng
  theo component. Screen page chỉ dùng frame/instance; icon master chỉ nằm ở
  `FOUNDATION / Icons — Phosphor`. Sau mỗi lần di chuyển hoặc tạo mới phải audit
  source ngoài Foundation, overflow và overlap của section trước khi review.
- Screen inventory tách đúng platform: `Screens — Desktop · Windows`,
  `Screens — Mobile · Android` và `Screens — Tablet · Android`. Không trộn
  breakpoint/platform trong cùng page, không đặt main component trong page
  Screens và yêu cầu top-level overlap bằng `0`. Page cũ chỉ xóa sau khi đã
  chuyển hết nội dung và xác minh `childCount = 0`.
- Với icon Navigation, audit phải đối chiếu `vectorPaths` của từng master với
  SVG `regular` cùng tên từ `phosphor-icons/core`; không chỉ kiểm tra tên layer
  hoặc kích thước. Nếu icon không tồn tại trong core hay sai ngữ nghĩa runtime,
  thay toàn bộ consumer bằng icon Phosphor chính thức phù hợp, rồi loại master
  cũ không còn consumer. Không duy trì page Navigation Shell riêng sau khi icon
  master, component, specimen và documentation đã chuyển về Foundation.
- Brand block của Navigation Shell dùng đúng `AppBrand.logoAsset`,
  `AppBrand.title` và `AppBrand.slogan`; không thay bằng placeholder, logo tự
  vẽ hoặc slogan tự đặt. Sidebar/drawer xếp logo, title và slogan bằng
  auto-layout; slogan desktop là hai dòng theo câu “Kết nối nguồn lực.” và
  “Đồng bộ vận hành.”, còn drawer hẹp truncate một dòng theo runtime.
- Loading indicator là shared `Phosphor / SpinnerGap / Regular` ở mọi
  breakpoint/state; không thay bằng vector spinner vẽ riêng theo từng screen
  hoặc component.
- Mobile ưu tiên content/task. Helper không thiết yếu được ẩn khỏi layout và
  mở theo ngữ cảnh bằng nút `?` qua bubble/dialog; không ẩn validation, error,
  permission hoặc hướng dẫn an toàn cần quyết định ngay.
- Trên compact mobile, tên chức năng hiển thị ở header/app bar thay vì lặp lại
  trong page header. Helper có action, link hoặc thao tác phải tách action đó
  ra khu vực thao tác chính; bubble chỉ giữ hướng dẫn ngắn, không tương tác.
- Figma không có global setting cấm frame overlap. Mọi App Shell audit frame
  phải nằm trên canvas grid theo breakpoint, có gutter rõ ràng; trước review
  chạy collision audit bounding-box cho top-level screen frame và yêu cầu kết
  quả bằng `0`. Component bên trong ưu tiên auto-layout; metadata (timestamp,
  chip, counter) phải có lane/y riêng, không dùng cùng toạ độ tuyệt đối.

## 7. OpsHub contracts phải giữ

- Date filter mở qua canonical shared DateRangePicker; desktop anchored
  popover, mobile bottom sheet. Quick ranges có tối thiểu `Hôm nay`, `Hôm qua`,
  `7 ngày qua`, `30 ngày qua` và `Tùy chọn`; không tạo date picker cục bộ.
  Một shortcut chỉ xuất hiện một lần trong cùng popover/dialog/modal: desktop
  đặt ở cột `Khoảng nhanh`, không lặp trong các ô `Từ ngày`/`Đến ngày`.
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
