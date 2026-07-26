# UI/UX Redesign QA Checklist

Checklist phải được thu gọn theo scope; item không áp dụng ghi `N/A` kèm lý do.

## Authority and traceability

- [ ] Linear issue/acceptance criteria khớp scope.
- [ ] Exact approved Figma frame/node/revision được link.
- [ ] Product/business/API/permission/platform behavior cần bảo vệ đã liệt kê.
- [ ] Build/commit/SHA và viewport/platform của evidence được ghi.
- [ ] Không có khác biệt visual chưa được duyệt.

## Design system

- [ ] Brand colors/assets dùng đúng shared tokens.
- [ ] Typography đúng approved migration phase; không trộn font ngoài boundary.
- [ ] Spacing, radius, elevation, icons và component metrics dùng shared tokens.
- [ ] Không có feature-local primitive/design system song song.
- [ ] Relevant component states khớp approved design.

## Responsive and platform

- [ ] Compact `<600`.
- [ ] Medium `600–899`.
- [ ] Expanded `900–1199`.
- [ ] Wide desktop `>=1200` khi áp dụng.
- [ ] Android mobile proof.
- [ ] Windows desktop proof.
- [ ] Web/additional platforms không regression khi thuộc affected scope.
- [ ] Resize/rotation, safe area, keyboard viewport và no overflow.
- [ ] Bounded content width, pointer/hover và two-axis scroll khi áp dụng.

## Data and interaction states

- [ ] Initial loading/skeleton và refreshing.
- [ ] Loaded, empty, filtered empty và no search result.
- [ ] Error/retry, cached/stale, offline và partial data.
- [ ] Permission denied và session expired.
- [ ] Disabled/loading/success/validation/duplicate-submit behavior.
- [ ] Pagination loading/error khi áp dụng.
- [ ] Back/Escape/outside dismissal và dirty-form guard đúng contract.

## Accessibility

- [ ] Contrast và không truyền đạt chỉ bằng màu.
- [ ] Keyboard navigation, visible focus và logical focus order.
- [ ] Screen reader semantics/labels/error announcement.
- [ ] Touch targets và icon tooltips/accessible names.
- [ ] Text scaling và long Vietnamese content.
- [ ] Reduced motion khi áp dụng.
- [ ] Global text selection/input context menu không regression.

## OpsHub-specific contracts

- [ ] UI copy Vietnamese-first, action-oriented, không lộ technical codes.
- [ ] Canonical DateRangePicker/AppCombobox/shared controls được reuse.
- [ ] Scan/search/submit command input và primary actions cùng hàng.
- [ ] Related flows dùng cùng presentation model.
- [ ] Long modal giữ fixed context header, chỉ form body scroll.
- [ ] Platform-specific controls hidden/unsupported behavior đúng contract.
- [ ] `AppLogger` có start/success/failure/key branches, không log sensitive data.

## Technical proof

- [ ] Focused widget/unit/golden or visual regression tests pass.
- [ ] Protected affected consumers pass.
- [ ] `dart format --output=none --set-exit-if-changed ...` pass.
- [ ] `git diff --check` pass.
- [ ] `flutter analyze --no-pub` pass.
- [ ] `flutter test --no-pub --reporter expanded` pass.
- [ ] Screenshot/smoke comparison ghi Figma revision, viewport và build SHA.
- [ ] Performance/frame behavior chấp nhận được cho affected flow.

## Delivery

- [ ] PR title `[OPS-123] Description`, base `staging`.
- [ ] PR body link Linear, Figma revision, screenshots và exact proof.
- [ ] Linear tracking comment đã post trước status transition và đọc lại.
- [ ] Known differences, unverified surfaces và residual risk được ghi.
- [ ] Staging QA/release gates không bị diễn giải thành production `Done`.
