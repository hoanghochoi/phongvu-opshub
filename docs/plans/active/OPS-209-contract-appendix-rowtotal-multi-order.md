# Execution Plan: OPS-209 Contract Appendix ERP Row Total and Multi-Order

## Status

In progress — R2 Figma revision approved by Đại Ca on 2026-08-20; Flutter
interaction visuals are now authorized against the exact node map below.

## Outcome

Contract Appendix must use the shipment `rowTotal` as the VAT-inclusive line
total so the preview, saved snapshot, and Word clipboard reconcile exactly with
ERP. A user may collect up to ten orders before one atomic lookup, with
compatible lines grouped while retaining source provenance.

## Checkpoint

- Linear: `OPS-209`.
- Task branch: `codex/ops-209-contract-appendix-rowtotal-multi-order`.
- Base: `c6b77c6e6d74c00fdc2d6eb755c01cdcb36f1740` (live `origin/staging`).
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
- No customer-identity hard block and no PII persistence. Word remains a
  seven-column table without order-code columns.

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
  orders, save/refetch/history and Word Windows paste. UI completion additionally
  requires approved Figma nodes, geometry proof and authenticated Chrome audit.

## Progress

- [x] Create/link `OPS-209`, record kickoff, and start guarded task worktree.
- [x] Update product/story/test authority.
- [x] Implement backend rowTotal and multi-order contract.
- [x] Implement Flutter non-visual plural state/data contract.
- [x] Implement approved Figma-driven UI interaction against R2.
- [x] Run focused/full local verification and record proof; inspect final diff
  and Linear note.

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
- `verify-task.mjs --base origin/staging --full` and `git diff --check` pass on
  the final worktree. Staging ERP/Word/Chrome smoke, scratch DB migration
  execution, and release signing remain external gates.

## Figma approved revision R2 — 2026-08-20

R2 is approved by Đại Ca. It uses the approved OpsHub foundation tokens and
Phosphor icon components. The mobile command row keeps the order input and
`Thêm đơn` side-by-side; the ERP fetch CTA is the next full-width action row.

File: [OpsHub Design System](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll)

| Viewport | Candidate section | State frames | Responsive contract |
| --- | --- | --- | --- |
| Compact 390×844 | [Mobile R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23891) | [Selected](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23922), [Validation](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23958), [Loading](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-23994), [Error](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24028), [Loaded/locked](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24059), [Reset](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24107), [History](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2432-24165) | App bar; 16px content inset; input + `Thêm đơn` same row; fetch CTA below; order chips wrap; mobile preview uses item cards. |
| Medium 768×1024 | [Tablet 768 R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2434-27703) | Empty/selected/validation/loading/error/loaded/reset/history in section grid | 88px rail; 24px content inset; input + add + fetch share one command row; preview is 7-column table. |
| Expanded 1024×900 | [Tablet 1024 R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2434-28192) | Empty/selected/validation/loading/error/loaded/reset/history in section grid | 88px rail; 24px content inset; command row remains single-line; table columns retain Word order. |
| Wide 1440×900 | [Desktop R2](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2436-68736) | [Loaded/locked](https://www.figma.com/design/mFzSmQzlapSe3RSmUhvzll?node-id=2436-69045), plus empty/selected/validation/loading/error/reset/history | 250px sidebar; 32px content inset; command + summary two-column; preview spans content width. |

### R2 node map

Every frame above contains the following visible contract elements: (1) app
shell context with page title and platform navigation; (2) order command card
with ERP eyebrow, title, helper, order-code input, search icon, `Thêm đơn`,
fetch CTA, selected-count and removable/locked order chips; (3) state-specific
feedback for validation, bounded loading, atomic error, locked snapshot and
reset confirmation; (4) preview surface with either mobile item cards or the
seven Word columns `STT / Tên hàng / Mã hàng / ĐVT / SL / Đơn giá / Thành tiền`,
plus ERP total and amount-in-words footer; and (5) history search, multi-order
provenance text and view actions. Vietnamese-first copy, focusable 48px
controls, no PII, and no order-code column in the Word table are protected
behavior. The Chrome audit matrix is exactly 390×844, 768×1024, 1024×900 and
1440×900 for every implemented state.
