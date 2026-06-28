# SALES-REPORT-001: Báo cáo sale

## Story

Sale cần gửi báo cáo mua hàng/chưa mua hàng trong OpsHub để dữ liệu không còn
nằm rời ở Google Form và có thể dùng cho dashboard sau này.

## Acceptance

- Home hiện `Báo cáo` khi user có `SALES_REPORT`.
- Form `Mua hàng` yêu cầu nhập mã đơn và check ERP trước khi nhập/gửi báo cáo.
- ERP/Listing trả được ngành hàng/nhu cầu thì app tự fill; ngành hàng ưu tiên
  map bằng `productGroup.code` khớp `Cat group ID` trong `data/categories.csv`.
  Nếu không map được ngành hàng về nhóm ngành OpsHub thì bắt buộc sale chọn tay
  trước khi gửi.
- Nhu cầu khách hàng và các câu hỏi hành vi sale là bắt buộc; hành vi tư vấn,
  trải nghiệm, quét Zalo và tải App PV mặc định là `Chọn`, không tự chọn `Có`.
- Backend re-check ERP khi submit và chặn duplicate `orderCode`.
- Form `Chưa mua hàng` không gọi ERP, bắt buộc ngành hàng và lý do chưa mua.
- Admin có `ADMIN_SALES_REPORTS` theo node tổ chức xem/query/export báo cáo
  trong phạm vi được gán; Super Admin thấy toàn app.
- Ngành hàng lấy từ `data/categories.csv`, hiển thị tiếng Việt và lưu snapshot
  song song code/tên gốc/tên Việt.
- Không có payload nhập tay `MSNV`.

## Proof Target

- Backend: Prisma validate/generate, Nest build, focused sales-report Jest khi
  bổ sung test suite.
- Flutter: `flutter analyze`, focused widget/provider tests khi bổ sung test
  suite.
- Repo: `git diff --check`.

## Notes

- Dashboard UI chưa thuộc story này; DB/API/export phải đủ để dashboard nối vào
  sau.
- ERP credential nhập qua env trên server, không commit vào repo.
