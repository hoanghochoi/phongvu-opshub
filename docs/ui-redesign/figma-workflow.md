# Figma Workflow For The New Redesign

## 1. Scope

Figma là visual/interaction target của đợt redesign, không phải authority để
thêm route, dữ liệu, permission hoặc business behavior. Mọi frame phải trace
được về product contract và Linear scope.

Các frame Redesign V2 năm 2026 hiện có là baseline/history. Đợt mới phải dùng
page/file/revision được phân biệt rõ; không sửa đè approved historical frame.

## 2. Suggested structure

```text
00 — Cover & Status
01 — Foundations
02 — Components
03 — Compact Screens
04 — Medium Screens
05 — Expanded & Wide Screens
06 — Flows & Prototypes
07 — Review
08 — Approved
99 — Archive
```

Tên file/page chính thức do foundation issue chốt và phải được ghi trong
Linear. Không dùng vị trí frame làm approval; dùng exact URL/node/revision.

## 3. Naming

```text
<Feature> / <Screen> / <Width class> / <State> / <Revision>
```

Ví dụ:

```text
Authentication / Login / Compact / Default / R1
Authentication / Login / Compact / Validation Error / R1
Authentication / Login / Expanded / Default / R1
```

## 4. Design intake

Trước khi vẽ, issue phải nêu:

- mục tiêu, user và main task;
- current behavior/protected behavior;
- primary/secondary actions và information hierarchy;
- data/API/permission/platform constraints;
- error/empty/loading and domain-specific states;
- breakpoint behavior và content density;
- accessibility requirements và reusable components;
- out-of-scope behavior.

Không vẽ control giả chưa có product contract. Nếu cần behavior mới, dừng và
xin product decision trước.

## 5. Deliverables

Tùy scope, package gồm compact, medium, expanded/wide; relevant data/form/
permission/session states; dialog/bottom-sheet/menu/confirmation; interaction,
responsive, keyboard/focus/semantics và motion notes. State không áp dụng phải
ghi lý do.

Foundation/component work cần variables, variants, properties, state matrix và
mapping note sang shared Flutter tokens/components.

## 6. Review

1. Chuyển candidate frames vào `07 — Review`.
2. Cập nhật Linear `In Review` khi đã có tracking comment theo repo policy.
3. Comment exact Figma links, revision, frame/state inventory, decisions,
   differences from current UI, trade-offs, open questions và proof plan.
4. Dừng và chờ feedback; không hiểu im lặng là approval.

## 7. Approval

Approval hợp lệ phải xác định rõ frame/revision. Sau đó:

1. Snapshot/lock revision và đưa vào `08 — Approved`.
2. Ghi owner approval cùng exact links trong Linear.
3. Link approved frame vào implementation issue và bỏ dependency blocker.
4. Implementation chỉ bắt đầu sau khi acceptance criteria cũng đã rõ.
5. Áp dụng lifecycle trong `linear-workflow.md`: issue gộp quay lại
   `In Progress` khi bắt đầu code; Design issue tách riêng giữ `In Review` tới
   production và Implementation issue chuyển `Todo` → `In Progress`.

Status hoặc việc frame nằm trong page `Approved` không thay thế xác nhận của
Đại Ca.

## 8. Revision và design drift

Nếu target đổi sau approval:

1. Tạo revision mới và change log; không sửa silent approved revision.
2. Chuyển revision mới về Review.
3. Dừng phần implementation bị ảnh hưởng.
4. Cập nhật Linear scope/proof và chờ re-approval.

Flutter screenshot khác Figma chỉ được chấp nhận khi difference đã ghi rõ,
được duyệt và phản ánh lại vào source of truth phù hợp.
