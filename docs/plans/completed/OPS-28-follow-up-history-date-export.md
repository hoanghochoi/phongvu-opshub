# OPS-28 — Lọc ngày và tải lịch sử chăm sóc

## Checkpoint

- Base: `origin/staging` tại `3fe2e5cd9a7b14813399e68f522e266bd0c958f5`.
- Branch: `codex/ops-28-follow-up-history-date-export`.
- Worktree được tạo qua `scripts/task-lifecycle.mjs start --execute`.
- Lane: high-risk vì authorization, PII export, public API, timezone và existing behavior.

## Implementation

1. Backend nhận khoảng ngày cho danh sách, dùng `lastFollowUpAt` hoặc fallback
   `submittedAt`, mặc định 30 ngày và tối đa 90 ngày theo giờ Việt Nam.
2. Endpoint XLSX chỉ cho managed scope, lọc `contactedAt`, keyword/showroom và
   chặn file rỗng hoặc vượt 10.000 lượt.
3. Flutter dùng `AppDateRangeDropdown`, giữ khoảng ngày qua ba tab và chỉ hiện
   nút tải khi response xác nhận `managedScope`.
4. AppLogger/backend log bao phủ start/success/failure mà không ghi PII.

## Affected runtime

- Protected consumers: list/search/showroom, ba tab, pagination, realtime,
  Nhập Excel, modal chi tiết và canonical DateRangePicker.
- Focused proof:
  - `npm test -- --runInBand sales-report-follow-ups.service.spec.ts sales-report-follow-ups.controller.spec.ts`
    trong `backend-nest/`.
  - `flutter test --no-pub test/not_purchased_customers_test.dart test/app_date_range_dropdown_test.dart`.
- Broad proof: Nest build/full tests, Flutter analyze/full tests và
  `git diff --check` trên final changeset.

## Recovery

- Chưa có schema/migration; rollback là revert patch của branch trước publish.
- Không push trực tiếp `staging`/`main`; feature đi qua PR vào `staging`.
- Dừng nếu live `origin/staging`, scope, issue acceptance criteria hoặc protected
  consumer plan thay đổi trước final proof.

## Status

- Implementation và local proof hoàn tất tại commit `8321b440`; PR #37 đã mở
  vào `staging`. Phần CI, staging deploy và QA tiếp tục được theo dõi trên
  GitHub/Linear theo release workflow.

## Validation

- `npx prisma validate`: PASS.
- Focused Nest follow-up service/controller: 2 suites, 16 tests PASS.
- Full Nest: 90 suites, 894 tests PASS; `npm run build`: PASS.
- Focused Flutter protected consumers: `not_purchased_customers_test.dart` và
  `app_date_range_dropdown_test.dart`: PASS.
- Full Flutter: 616 tests PASS, 3 skipped; `flutter analyze --no-pub`: PASS.
- `git diff --check`: PASS; changed runtime files không có dấu hiệu mojibake.
- Exact diff/staged scope audit: PASS; branch đã push và PR #37 đã mở.
- Residual risk trước release: CI, staging deploy và staging QA bằng tài khoản
  managed scope với file XLSX thực chưa hoàn tất tại thời điểm đóng execution
  plan cục bộ.
