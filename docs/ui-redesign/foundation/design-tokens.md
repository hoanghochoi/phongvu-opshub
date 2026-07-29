# OpsHub Redesign Design Tokens

Status: **Approved for Figma foundation — not runtime authority**
Revision: `OPS-25-2026-07-26`
Machine-readable source: `design-tokens.json`

## 1. Architecture và naming

Ba lớp bắt buộc:

```text
primitive → semantic light/dark → component
```

- Primitive chỉ mang giá trị thô: `color/primitive/brand/500`, `space/4`.
- Semantic mang ý nghĩa: `color/semantic/light/text/primary`.
- Component chỉ alias semantic/metric: `buttonPrimary/background`.
- Screen không tạo token theo tên feature nếu giá trị có thể thuộc shared
  foundation/component.
- Figma dùng `/`; Flutter map sang named members nhưng giữ cùng nghĩa.

## 2. Color primitives

### Brand blue — giữ official palette hiện có

| Token | Value |
| --- | --- |
| `brand/50` | `#EEF0FB` |
| `brand/100` | `#CCD3F4` |
| `brand/200` | `#99A7E9` |
| `brand/300` | `#667BDE` |
| `brand/400` | `#334FD3` |
| `brand/500` | `#1435C3` |
| `brand/600` | `#102A9C` |
| `brand/700` | `#0D1F75` |
| `brand/800` | `#091550` |
| `brand/900` | `#050A28` |

Quyết định proposal: `brand/500 #1435C3` là semantic primary light. Runtime
hiện dùng `AppColors.primary #0A66C2`; implementation sau này phải giữ legacy
alias có chủ đích trong migration phase, không đổi âm thầm từ docs này.

### Neutral

| Token | Value | Use |
| --- | --- | --- |
| `neutral/0` | `#FFFFFF` | white/surface |
| `neutral/25` | `#F7F8FB` | light canvas |
| `neutral/50` | `#F5F7FB` | sunken surface |
| `neutral/75` | `#E6EAF0` | subtle divider |
| `neutral/100` | `#E5E7EB` | disabled background |
| `neutral/150` | `#D8DEE8` | default border |
| `neutral/200` | `#D1D5DB` | strong divider |
| `neutral/300` | `#B6BCC5` | inactive decoration |
| `neutral/400` | `#9CA3AF` | disabled/inactive |
| `neutral/500` | `#6B7280` | disabled content |
| `neutral/550` | `#5F6B7A` | muted readable text |
| `neutral/575` | `#667085` | accessible control boundary |
| `neutral/600` | `#4B5563` | secondary text |
| `neutral/700` | `#374151` | strong secondary |
| `neutral/800` | `#1F2937` | inverse surface |
| `neutral/900` | `#111827` | primary text |
| `neutral/1000` | `#000000` | pure black/QR only |

### Supporting/status

| Family | Surface | Strong | Content/on-surface |
| --- | --- | --- | --- |
| Teal/secondary | `#F0FDFA` | `#0F766E` | `#115E59` when needed |
| Violet/accent | `#F5F3FF` | `#7C3AED` | `#5B21B6` when needed |
| Information | `#DBEAFE` | `#1D4ED8` | `#1D4ED8` |
| Success | `#DCFCE7` | `#12805C` | `#0F7954` |
| Warning | `#FEF3C7` | `#8A5A08` | `#8A5A08` |
| Error | `#FEE4E2` | `#B42318` | `#B42318` |

Error đổi từ runtime orange `#C2410C` sang red `#B42318` trong proposal để tách
rõ warning/error. Đây là design decision chờ duyệt, chưa phải code change.

## 3. Semantic color modes

### Light

| Semantic token | Value/alias |
| --- | --- |
| `background/canvas` | `#F7F8FB` |
| `surface/default` | `#FFFFFF` |
| `surface/sunken` | `#F5F7FB` |
| `surface/raised` | `#FFFFFF` + elevation khi cần |
| `text/primary` | `#111827` |
| `text/secondary` | `#4B5563` |
| `text/muted` | `#5F6B7A` |
| `text/link` | `#1435C3` |
| `border/default` | `#D8DEE8` |
| `border/subtle` | `#E6EAF0` |
| `border/control` | `#667085` |
| `action/primary/default` | `#1435C3` |
| `action/primary/hover` | `#102A9C` |
| `action/primary/pressed` | `#0D1F75` |
| `action/primary/content` | `#FFFFFF` |
| `action/secondary/default` | `#0F766E` |
| `focus/ring` | `#2563EB` |
| `selected/background` | `#EEF0FB` |
| `selected/content` | `#1435C3` |
| `overlay/scrim` | `#0000007A` (48%) |

### Dark

| Semantic token | Value |
| --- | --- |
| `background/canvas` | `#0B1220` |
| `surface/sunken` | `#070D19` |
| `surface/default` | `#111827` |
| `surface/raised` | `#172033` |
| `text/primary` | `#F8FAFC` |
| `text/secondary` | `#CBD5E1` |
| `text/muted` | `#94A3B8` |
| `border/default` | `#475569` |
| `border/subtle` | `#334155` |
| `border/control` | `#64748B` |
| `action/primary/default` | `#8EA0FF` |
| `action/primary/hover` | `#AAB6FF` |
| `action/primary/pressed` | `#6F83F7` |
| `action/primary/content` | `#050A28` |
| `action/secondary/default` | `#5EEAD4` |
| `action/secondary/hover` | `#99F6E4` |
| `focus/ring` | `#93C5FD` |
| `selected/background` | `#17324D` |
| `selected/content` | `#DBEAFE` |
| `overlay/scrim` | `#000000A3` (64%) |

Dark primary là accessible tonal extension của brand, không phải thay logo/
official asset color. Logo asset giữ nguyên và đặt trên approved surface.

## 4. Contrast evidence

Phương pháp: WCAG relative luminance `(L1 + 0.05) / (L2 + 0.05)`. Target là
`>=4.5:1` cho normal text và `>=3:1` cho large text/non-text boundaries. Disabled
controls không được dùng để truyền tải nội dung bắt buộc.

| Pair | Foreground | Background | Ratio | Result |
| --- | --- | --- | ---: | --- |
| Light primary text / surface | `#111827` | `#FFFFFF` | 17.74 | AA pass |
| Light secondary text / surface | `#4B5563` | `#FFFFFF` | 7.56 | AA pass |
| Light muted text / canvas | `#5F6B7A` | `#F7F8FB` | 5.11 | AA pass |
| Light primary button | `#FFFFFF` | `#1435C3` | 9.02 | AA pass |
| Light primary hover | `#FFFFFF` | `#102A9C` | 11.45 | AA pass |
| Light primary pressed | `#FFFFFF` | `#0D1F75` | 14.29 | AA pass |
| Light secondary button | `#FFFFFF` | `#0F766E` | 5.47 | AA pass |
| Information strong | `#FFFFFF` | `#1D4ED8` | 6.70 | AA pass |
| Success strong | `#FFFFFF` | `#12805C` | 4.92 | AA pass |
| Success content / surface | `#0F7954` | `#DCFCE7` | 4.92 | AA pass |
| Warning content / surface | `#8A5A08` | `#FEF3C7` | 5.32 | AA pass |
| Error content / surface | `#B42318` | `#FEE4E2` | 5.45 | AA pass |
| Light control border / surface | `#667085` | `#FFFFFF` | 4.97 | Non-text pass |
| Dark primary text / surface | `#F8FAFC` | `#111827` | 16.96 | AA pass |
| Dark secondary text / surface | `#CBD5E1` | `#111827` | 11.95 | AA pass |
| Dark muted text / canvas | `#94A3B8` | `#0B1220` | 7.30 | AA pass |
| Dark primary button | `#050A28` | `#8EA0FF` | 7.98 | AA pass |
| Dark primary pressed | `#050A28` | `#6F83F7` | 5.80 | AA pass |
| Dark secondary button | `#052E22` | `#5EEAD4` | 9.99 | AA pass |
| Dark information | `#84ADFF` | `#061D3A` | 7.55 | AA pass |
| Dark success | `#6CE9A6` | `#052E22` | 9.75 | AA pass |
| Dark warning | `#FEC84B` | `#3A2604` | 9.31 | AA pass |
| Dark error | `#FDA29B` | `#3B0A03` | 8.79 | AA pass |
| Dark control border / surface | `#64748B` | `#111827` | 3.73 | Non-text pass |

Contrast pass không thay proof cho focus visibility, color blindness, state
differentiation hoặc real rendered font weight.

## 5. Typography

Target family:

```text
Be Vietnam Pro → Roboto → Segoe UI → Arial → sans-serif
```

Weights: 400 Regular, 500 Medium, 600 Semibold, 700 Bold. Không synthesize
weight 800. Numeric/table dùng tabular figures khi platform/font hỗ trợ.

| Role | Size / line | Weight | Use |
| --- | --- | ---: | --- |
| `displayLarge` | 32 / 40 | 700 | Rare workspace/page statement |
| `displayMedium` | 28 / 36 | 700 | Primary page title |
| `headingLarge` | 24 / 32 | 700 | Major section |
| `headingMedium` | 20 / 28 | 700 | Card/modal section |
| `headingSmall` | 18 / 26 | 600 | Subsection |
| `titleMedium` | 16 / 24 | 600 | Row/card title |
| `bodyLarge` | 16 / 24 | 400 | Primary readable copy/form content |
| `bodyMedium` | 14 / 20 | 400 | Operational secondary copy |
| `bodySmall` | 13 / 18 | 400 | Dense supportive copy, not primary instructions |
| `labelLarge` | 16 / 20 | 600 | Large primary action |
| `labelMedium` | 14 / 20 | 600 | Default controls |
| `labelSmall` | 12 / 16 | 600 | Chip/table header |
| `caption` | 11 / 16 | 500 | Non-critical metadata only |
| `numeric` | 14 / 20 | 600 | Money/count with `tnum` |
| `table` | 13 / 20 | 500 | Dense table cell |

Không áp `0.92` automatic text scale trên compact trong redesign target. Giữ
font size và thay composition/density; user text scaling vẫn được tôn trọng.

License đã xác minh là SIL OFL 1.1 tại Google Fonts. Trước runtime migration còn
phải có local `.ttf`, OFL/copyright, upstream version/commit, SHA-256, fallback,
Vietnamese diacritic fixture và Android/Windows/web offline proof.

## 6. Spacing và layout

Primitive scale:

| Token | px | Token | px |
| --- | ---: | --- | ---: |
| `space/0` | 0 | `space/0_5` | 2 |
| `space/1` | 4 | `space/2` | 8 |
| `space/3` | 12 | `space/4` | 16 |
| `space/5` | 20 | `space/6` | 24 |
| `space/8` | 32 | `space/10` | 40 |
| `space/12` | 48 | `space/16` | 64 |

Semantic aliases:

| Token | Value |
| --- | ---: |
| `layout/pagePadding/compact` | 16 |
| `layout/pagePadding/medium` | 24 |
| `layout/pagePadding/expanded` | 32 |
| `layout/gap/inline` | 8 |
| `layout/gap/control` | 12 |
| `layout/gap/stack` | 16 |
| `layout/gap/section` | 24 |
| `layout/gap/pageSection` | 32 |

## 7. Radius, elevation và sizing

Radius primitives: `0, 4, 8, 12, 16, 20, 24, full(9999)`.

| Component semantic | Radius |
| --- | ---: |
| Compact chip/indicator | 8 |
| Button/input/card | 12 |
| Large panel | 16 |
| Auth hero/container | 20 |
| Dialog/bottom sheet | 24 |
| Pill/avatar/status | 9999 |

| Elevation | Shadow | Use |
| --- | --- | --- |
| `0` | none | Default cards/data surfaces |
| `1` | `0 1 2 #10182814` | Hover/floating compact control |
| `2` | `0 4 12 -2 #1018281A` | Popover/dropdown |
| `3` | `0 12 28 -6 #10182824` | Dialog/critical overlay |

Sizing giữ các contract đã có:

- touch target 48; controls 40/48/52; list row minimum 56;
- icon 16/20/24;
- content max 1180, form max 720, action bar max 560, auth max 460;
- sidebar 250, rail 88, top bar 72, bottom navigation 76.

## 8. Responsive tokens

| Class | Range |
| --- | --- |
| Compact | `<600` |
| Medium | `600–899` |
| Expanded | `900–1199` |
| Wide desktop | `>=1200` |

Auth keeps `1024` as its explicit shared composition breakpoint until a later
approved issue removes it. Feature-local `960` hoặc raw `600/900` không trở
thành token mới; implementation phải map về shared classes/metrics.

## 9. Motion

| Token | Value | Use |
| --- | ---: | --- |
| `instant` | 0ms | Reduced motion / direct state swap |
| `fast` | 120ms | Hover/press/focus feedback |
| `standard` | 200ms | Small enter/exit |
| `emphasized` | 300ms | Panel/sheet continuity |
| `slow` | 400ms | Rare large transition, never task-blocking |

Easing: standard `[0.2,0,0,1]`, enter `[0,0,0.2,1]`, exit `[0.4,0,1,1]`,
emphasized `[0.2,0.8,0.2,1]`. Reduced motion maps decorative/continuity motion
to `instant`; loading/progress meaning remains available without animation-only
communication.

## 10. Component tokens

| Component | Exact shared metrics | Color/state owner |
| --- | --- | --- |
| Primary button | h48, large52, px20, gap8, r12, focus2 | semantic primary default/hover/pressed/content/focus |
| Input/combobox | h48, px12, gap8, r12, focus2 | surface/text/muted/border/focus/error |
| Card | padding16, gap12, r12, elevation0 default | surface/border/text |
| Table | header44, row min56, cell x12/y10 | surface/text/border/selected/status |
| Dialog | padding24, gap16, r24, elevation3 | raised/scrim/text/action |
| State panel | icon40, gap12, max width480 | semantic status surface/content/strong |
| Navigation | sidebar250, rail88, top72, bottom76 | navigation mode tokens + selected/focus |

Mọi interactive component phải thiết kế state áp dụng được: default, hover,
focus-visible, pressed, selected, disabled, loading, error, success, read-only,
long content và large text. Không dùng opacity-only để mô tả disabled text nếu
nội dung vẫn cần đọc.

## 11. Figma handoff

Sau khi pack được duyệt, tạo ba collections:

1. `OpsHub Primitives` — không có modes.
2. `OpsHub Semantics` — modes `Light` và `Dark`.
3. `OpsHub Components` — alias semantics; geometry aliases shared metrics.

Rules:

- Variable names giữ path trong JSON; không đổi `primary` thành tên feature.
- Không detach alias để “chỉnh cho giống mắt”.
- Typography styles map đúng role table và test Vietnamese diacritics.
- Core component set phải được duyệt trước screens.
- Record exact file/node/revision trong OPS-25 follow-up hoặc Figma foundation
  issue; pack này không chứa link giả.

## 12. Flutter migration seam

Future implementation issue sẽ:

- map primitives/semantics vào `AppColors` hoặc `ThemeExtension`;
- map typography vào `AppTextStyles`/`TextTheme` sau khi font assets pass;
- map spacing/radius/sizing vào `AppLayoutTokens`/`AppRadius`;
- giữ compatibility aliases cho unmigrated screens;
- migrate shared components trước feature screens;
- thêm tests cho alias, modes, contrast-sensitive widgets và platform fonts.

Không thực hiện bất kỳ bước runtime nào trong OPS-25.
