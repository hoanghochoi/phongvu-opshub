# Linear Workflow For UI Redesign

## 1. Vai trò

Linear theo dõi scope, dependency, approval link, implementation và proof. Nó
không thay product docs, approved Figma, repository tests hoặc release gates.

Mọi task thuộc đợt redesign phải có một `OPS-*` issue trước khi tạo branch.
Không tạo issue trùng; tìm project/parent/related issue và previous design work
trước.

## 2. Issue shape

Với scope đủ lớn, dùng:

```text
Parent/initiative: UI/UX Redesign — OpsHub
[Design] <Feature or Screen>
[Implementation] <Feature or Screen>
[QA] <Feature or Screen>
```

Dependency:

```text
Design approval blocks Implementation
Implementation + build proof blocks QA
Staging QA blocks production release
```

Scope nhỏ có thể dùng một issue nếu description tách rõ design approval,
implementation và QA gates. Không tách issue chỉ để tạo nghi thức.

## 3. Status mapping hiện hành

| Event | Status |
| --- | --- |
| Issue sẵn sàng nhưng chưa bắt đầu | `Todo` |
| Agent bắt đầu approved scope | `In Progress` |
| Design hoặc PR chờ review | `In Review` |
| PR merge/deploy staging chờ QA | `Ready for QA` |
| Đang test staging | `Testing` |
| QA đạt và chờ release | `Ready for Release` |
| Đang production promotion | `Releasing` |
| Production deploy thành công | `Done` |

Không yêu cầu hoặc tự tạo status `Approved for Development`. Design approval
phải được ghi bằng comment có exact frame/revision; không tự sửa Linear
workflow. Sau approval:

- issue gộp Design + Implementation chuyển `In Review` → `In Progress` khi bắt
  đầu implementation;
- Design issue tách riêng giữ `In Review`, kèm approval comment và link tới
  implementation issue, cho tới khi scope đã deploy production; chỉ khi đó mới
  chuyển `Done`;
- Implementation issue tách riêng chuyển `Todo` → `In Progress` khi bắt đầu
  implementation.

Không chuyển implementation/feature issue sang `Done` vì design approved,
code xong, PR merge, staging deploy hoặc QA pass. `Done` cần production deploy.

## 4. Update and proof policy

Trước mỗi forward status transition, comment phải ghi:

- implementation/design outcome và user-visible behavior;
- changed scope/files hoặc frame/revision;
- branch, commit, PR và environment khi có;
- exact test, visual, affected-consumer, CI và QA results;
- residual risk và unverified surfaces;
- đúng một next-step recommendation.

Post comment trước, transition sau, rồi read issue back để xác minh cả hai.
Không ghi “Working on it” hoặc claim proof chưa chạy.

## 5. Approval and blocker policy

- Design issue vào review phải link exact Figma revision và open questions.
- Implementation issue giữ blocked/Todo cho tới khi approval rõ ràng.
- Technical constraint cần đổi visual phải đưa revision về review.
- QA chỉ bắt đầu khi có build/SHA, screenshots và proof package.
- Linear unavailable thì không claim issue/comment/status đã được cập nhật.

## 6. Git linkage

- Branch do lifecycle tạo: `codex/ops-123-short-slug`.
- PR title: `[OPS-123] Description`, base `staging`.
- Dùng `Part of OPS-123` khi còn chờ staging QA.
- Dùng `Fixes OPS-123` chỉ khi production release dự kiến đóng issue.
- Feature PR squash-and-merge; direct protected push cần explicit command và
  toàn bộ release gates.
