# SALES-REPORT-001: Báo cáo sale

## Story

Sale cần gửi báo cáo mua hàng/chưa mua hàng trong OpsHub để dữ liệu không còn
nằm rời ở Google Form và có thể dùng cho dashboard sau này.

## Acceptance

- Home hiện `Báo cáo` khi user có `SALES_REPORT`.
- Form `Mua hàng` yêu cầu nhập hoặc quét QR/barcode mã đơn và check ERP trước
  khi nhập/gửi báo cáo; sau khi check có thể bấm `Kiểm tra đơn khác` để đổi đơn.
- Nếu ERP trả `confirmationStatus` hoặc `fulfillmentStatus` là `cancelled`
  không phân biệt hoa/thường, app báo `Đơn đã bị hủy.` và không load thông tin
  đơn hàng vào form.
- ERP/Listing trả được ngành hàng/nhu cầu thì app tự fill; ngành hàng ưu tiên
  map bằng `productGroup.code` khớp `Cat group ID` trong `data/categories.csv`.
  Một báo cáo có thể chọn nhiều ngành hàng; nếu không map được ngành hàng về
  nhóm ngành OpsHub thì bắt buộc sale chọn tay trước khi gửi.
- Nhu cầu khách hàng và các câu hỏi hành vi sale là bắt buộc; hành vi tư vấn,
  trải nghiệm, quét Zalo và tải App PV mặc định là `Chọn`, không tự chọn `Có`.
- Backend re-check ERP khi submit và chặn duplicate `orderCode`.
- Form `Chưa mua hàng` không gọi ERP, bắt buộc ngành hàng và lý do chưa mua.
- Cả 2 form có tick `Trả góp`; mua hàng ghi nhận trả góp thành công, chưa mua
  ghi nhận trả góp thất bại và bắt buộc nhập lý do. Khi tick trả góp, sale phải
  chọn một hoặc nhiều đối tác trong list: `VNPAY - POS`, `PAYOO - POS`,
  `HomeCredit - CTTC`, `Shinhan - CTTC`, `HDSaison - CTTC`,
  `AEON Finance - CTTC`.
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
