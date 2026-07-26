## Linear

- Issue: OPS-<id>
- Tracking phrase: `Part of OPS-<id>` while awaiting staging QA

## Approved Figma

- File/page:
- Exact frame/node/revision:
- Approval reference:

## Product authority and protected behavior

- Product docs and decision:
- Business/API/permission/platform behavior preserved:
- Affected consumers:

## Scope

Mô tả user-visible changes, shared foundation/components và changed screens.

## Responsive and states

- Compact `<600`:
- Medium `600–899`:
- Expanded `900–1199`:
- Wide `>=1200`:
- Loading/empty/error/validation/permission/domain states:

## Accessibility, logging and copy

- Keyboard/focus/semantics/contrast/touch/text scaling/reduced motion proof:
- `AppLogger` start/success/failure/key branches:
- Vietnamese-first copy review:

## Verification

- [ ] Focused tests:
- [ ] Affected-consumer proof:
- [ ] `dart format --output=none --set-exit-if-changed ...`
- [ ] `git diff --check`
- [ ] `flutter analyze --no-pub`
- [ ] `flutter test --no-pub --reporter expanded`
- [ ] Android proof when affected
- [ ] Windows proof when affected
- [ ] Web/additional platform regression proof when affected
- [ ] Figma comparison completed with viewport/platform/build SHA

## Screenshots or observable evidence

Thêm ảnh/link Figma và Flutter cho các viewport/state liên quan.

## Known differences, unverified surfaces and residual risk

Ghi rõ khác biệt đã duyệt, proof chưa chạy và next staging/manual action.

## Delivery checklist

- [ ] PR title `[OPS-123] Description`
- [ ] Base branch `staging`
- [ ] Exact Linear/Figma links present
- [ ] No unrelated files
- [ ] No protected direct push/release action in this PR
