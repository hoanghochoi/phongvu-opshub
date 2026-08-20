# Execution Plan: OPS-209 Contract Appendix ERP Row Total and Multi-Order

## Status

In progress — R2 Figma revision was approved by Đại Ca on 2026-08-20. R3 is a
follow-up proposal pending explicit approval; visual completion remains gated.

## Outcome

Contract Appendix must use the shipment `rowTotal` as the VAT-inclusive line
total so the preview, saved snapshot, and Word clipboard reconcile exactly with
ERP. A user may collect up to ten orders before one atomic lookup, with
compatible lines grouped while retaining source provenance.

## Checkpoint

- Linear: `OPS-209`.
- Task branch: `codex/ops-209-word-clipboard-ui-fix` (follow-up from live `origin/staging`).
- Base: `7439862a7327b14dc562e925243341bb0f1f2732` (live `origin/staging`).
- Canonical worktree was clean before task start.

## Decisions

- Shipment `finalSellPrice` remains gross unit price; shipment `rowTotal` is
  `lineAfterVat`. Missing, ambiguous, negative, fractional, or unsafe shipment
  values fail closed with no fallback.
- `lineBeforeVat` is derived from gross unit/VAT; `lineVatAmount` is the
  residual `lineAfterVat - lineBeforeVat`, and negative residuals are invalid.
- Request accepts `orderCodes[]` (1–10, max 200 source lines) and the legacy
  singleton `orderCode`; lookup failure is atomic.
- Group only same SKU, gross unit, effective tax semantics, and ERP unit;
  quantity and ERP row totals are summed, first occurrence controls position.
- No customer-identity hard block and no PII persistence. Word is a
  six-column table without SKU/order-code columns; SKU remains internal
  provenance only.
- Follow-up product decision (2026-08-20): the Word preview must include the
  same line table and footer rows as the clipboard payload. ERP product name and
  unit are read-only in the editor; product names wrap naturally instead of
  truncating with an ellipsis.

## Scope and recovery

- Update product/story/test authority, Nest ERP/calculator/service/DTO/schema,
  additive Prisma migration, Flutter domain/repository/provider and focused
  proof.
- Preserve Sales Report capture-price behavior, old snapshots, old API fields,
  permissions, retention, tax lookup, and clipboard formatting.
- Application rollback remains readable because legacy parent/order/item fields
  stay populated. Migration rollback is scratch-only and must not be used as a
  production data rollback after new multi-order snapshots exist.

## Verification

- Focused ERP, calculator, multi-order service/controller, migration and
  Flutter core/provider tests.
- Prisma format/validate/generate, Nest build/full tests, Flutter analyze/full
  tests, platform builds, `verify-task.mjs`, and `git diff --check`.
- Staging must prove a real `rowTotal != finalSellPrice * quantity` order, two
  orders, save/refetch/history and Word Windows/Web paste. UI completion additionally
  requires approved Figma nodes, geometry proof and authenticated Chrome audit.

## Progress

- [x] Create/link `OPS-209`, record kickoff, and start guarded task worktree.
- [x] Update product/story/test authority.
- [x] Implement backend rowTotal and multi-order contract.
- [x] Implement Flutter non-visual plural state/data contract.
- [x] Implement approved Figma-driven UI interaction against R2.
- [x] Run focused/full local verification and record proof; inspect final diff
  and Linear note.
- [ ] Approve Figma R3 proposal `2445:23936` and record the new node map.
- [ ] Verify six-column Word preview, web ClipboardItem paste, locked ERP text,
  and wrapped product names on staging.

## Current evidence — 2026-08-20

- Prisma format/validate/generate and the OPS-209 static migration/rollback
  contract pass. Docker Desktop/PostgreSQL is unavailable in this session, so
  fresh/upgrade/rollback execution remains unverified.
- Focused Nest Contract Appendix proof passes 2 suites / 18 tests after the
  final row-total adjustment; full Nest passes 124 suites / 1,327 tests with 6
  skips (1,333 total), including the Sales Report capture-price regression.
  Nest build passes.
- Focused Flutter Contract Appendix proof, design-system guard, and bank
  statement affected-consumer proof pass. The final full Flutter run passes
  887 tests with 3 skips; Flutter analyze passes.
- Windows release build and Web build pass. Android production debug build
  passes; Android release is blocked only by the repository's required signing
  secrets, which are intentionally absent from this worktree.
- The baseline OPS-209 implementation recorded `verify-task.mjs
  --base origin/staging --full` and `git diff --check` as passing before this
  UI follow-up. Staging ERP/Word/Chrome smoke, scratch DB migration execution,
  and release signing remain external gates.

### Follow-up UI verification — 2026-08-20

- Contract Appendix focused Flutter proof passes 16 tests, including six-column
  Word payload wrapping, locked ERP name/unit semantics, and four approved
  viewport geometry checks. Flutter analyze and `flutter build web --no-pub`
  pass; the Web build required clearing the generated `lib/l10n` ReadOnly
  attribute in the task worktree only.
- The full Flutter suite currently reports two failures outside this feature
  (`test/widget_test.dart` session-dialog timing and
  `test/sales_report_hub_test.dart` realtime coalescing); no Contract Appendix
  test fails. The full `verify-task` run reports one existing Windows Nest
  helper harness failure (`tests/toolchain/run-with-toolchain.test.mjs`), so
  release proof is not green yet.

## Figma approved revision R2 — 2026-08-20

R2 is approved by Đại Ca. It uses the approved OpsHub foundation tokens and
Phosphor icon components. The mobile command row keeps the order input and
`Thêm đơn` side-by-side; the ERP fetch CTA is the next full-width action row.

File: [OpsHub Design System](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll)

| Viewport | Candidate section | State frames | Responsive contract |
| --- | --- | --- | --- |
| Compact 390×844 | [Mobile R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23891) | [Selected](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23922), [Validation](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23958), [Loading](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23994), [Error](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24028), [Loaded/locked](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24059), [Reset](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24107), [History](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24165) | App bar; 16px content inset; input + `Thêm đơn` same row; fetch CTA below; order chips wrap; mobile preview uses item cards. |
| Medium 768×1024 | [Tablet 768 R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2434-27703) | Empty/selected/validation/loading/error/loaded/reset/history in section grid | R2 baseline; R3 loaded/locked proposal is `2445:23985`. |
| Expanded 1024×900 | [Tablet 1024 R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2434-28192) | Empty/selected/validation/loading/error/loaded/reset/history in section grid | R2 baseline; R3 loaded/locked proposal is `2445:24088`. |
| Wide 1440×900 | [Desktop R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2436-68736) | [Loaded/locked](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2436-69045), plus empty/selected/validation/loading/error/reset/history | R2 baseline; R3 loaded/locked proposal is `2445:24191`. |

### R2 node map

Every frame above contains the following visible contract elements: (1) app
shell context with page title and platform navigation; (2) order command card
with ERP eyebrow, title, helper, order-code input, search icon, `Thêm đơn`,
fetch CTA, selected-count and removable/locked order chips; (3) state-specific
feedback for validation, bounded loading, atomic error, locked snapshot and
reset confirmation; (4) preview surface with either mobile item cards or the
  six Word columns `STT / Tên hàng / ĐVT / SL / Đơn giá / Thành tiền`,
plus ERP total and amount-in-words footer; and (5) history search, multi-order
provenance text and view actions. Vietnamese-first copy, focusable 48px
  controls, no PII, and no SKU/order-code column in the Word table are protected
behavior. The Chrome audit matrix is exactly 390×844, 768×1024, 1024×900 and
1440×900 for every implemented state.

### Figma R3 follow-up proposal (pending approval)

- File: [OpsHub Design System](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll).
- Wrapper: `2445:23936`.
- Loaded/locked nodes: compact `2445:23939`, medium `2445:23985`, expanded
  `2445:24088`, wide `2445:24191`.
- Node map contract: Word columns `STT / Tên hàng hóa / ĐVT / SL / Đơn giá /
  Thành tiền`; no SKU/Mã hàng; product name wraps; Tên hàng/ĐVT read-only;
  footer rows `Tổng cộng`, `Thuế GTGT`, `Tổng giá trị hợp đồng (đã bao gồm thuế
  GTGT)`, `Bằng chữ`.
