# QUICK-ACTIONS-001 — Thao tác nhanh v1

Lane: high-risk.

Risk flags: authorization, data model, public contracts, cross-platform,
existing behavior, multi-domain.

Contract: [quick-actions.md](../product/quick-actions.md)

## Acceptance

- Mobile compact giữ đúng bốn destination và có launcher tia sét ở chính giữa;
  menu lưới tự xuống hàng, không cuộn ngang và tự đóng khi bấm lại, chạm ngoài,
  back, đổi route hoặc đổi kích thước.
- Windows native chỉ có launcher tại Home, padding 24px, menu dọc có keyboard,
  Escape và trả focus.
- Đủ bảy action đúng thứ tự; ba action nghiệp vụ kiểm tra cả child + quyền gốc.
- Bốn QR theo showroom, không fallback; multi-store chọn showroom trước; vùng
  mã luôn trắng thuần với nét đen trong light mode và dark mode.
- Store Manager trở lên + feature + scope mới sửa được bốn link; lưu/xóa atomic,
  chỉ URL http/https tối đa 2.048 ký tự.
- Feature tree/backfill cho phép tắt từng child ở từng level và không tự bật lại
  khi sửa link.
- Client lưu QR bền vững theo user + showroom, không gọi API mỗi lần mở launcher;
  cache quyền/scope cũ không được dùng khi scope hoặc tập quyền thay đổi.
- Lưu link phát sự kiện v2 theo showroom; client đúng scope xóa cache scope/QR
  và tải lại một lần, còn Windows ngoài Home hoãn tải tới khi launcher hoạt động.
- Có log đã sanitize, unit/widget proof và tài liệu/test matrix đồng bộ.

## Proof plan

- Nest: Prisma validation, service tests về role/scope/URL/transaction, build và
  full Jest.
- Flutter: launcher/menu order, route guard, shell/navigation regression,
  analyze và full test.
- Manual: Windows focus/USB scanner/viewport; điện thoại thật camera, horizontal
  scroll và quét QR bằng máy khách.
