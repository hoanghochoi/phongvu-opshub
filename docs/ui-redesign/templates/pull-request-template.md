## Linear

- Issue: OPS-<id>
- Tracking phrase: `Part of OPS-<id>` while awaiting staging QA

## Approved Figma

- File/page:
- Exact frame/node/revision:
- Approval reference:

## Visual delivery evidence

| Viewport/state | Exact Figma node/revision | Geometry test/golden | Deployed SHA | Authenticated Chrome comparison | Verdict |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

All visible elements must be covered by the approved node map. Legacy code and
old runtime screenshots are behavior-only references and must not supply any
visual decision or fallback.

**Hard-gate attestation:** node map was recorded before the first production UI
edit; the table includes every affected viewport/state; this migrated surface
has no feature flag, conditional legacy widget/style or responsive fallback
that can render old UI. An unapproved visual drift blocks merge/status/QA pass.

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
- [ ] `node scripts/run-with-toolchain.mjs --profile flutter -- flutter analyze`
- [ ] `node scripts/run-with-toolchain.mjs --profile flutter -- flutter test --reporter expanded`
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
