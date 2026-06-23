# Góp ý Contract

## Intent

Nhân viên gửi góp ý, báo điểm chưa thuận tiện hoặc lỗi vận hành để đội phát
triển cải thiện OpsHub.

## Current Shape

- Home hiển thị ô `Góp ý` khi user có feature `FEEDBACK`. Ô này luôn được append
  cuối danh sách chức năng Home và không còn nằm trong drawer.
- Flutter submission UI lives under `lib/features/feedback/`.
- Flutter administration UI hiển thị `Danh sách góp ý`, lives under
  `lib/features/admin/`, and is
  visible only to `SUPER_ADMIN`.
- NestJS feedback API lives under `backend-nest/src/feedback/`.
- Tên API, database model, route `/feedback`, feature code `FEEDBACK`, và
  `ADMIN_FEEDBACK` giữ nguyên để tương thích runtime/dữ liệu cũ.

## Contract Notes

- Form yêu cầu `Chức năng liên quan` tối đa 120 ký tự và `Nội dung góp ý` tối đa
  5000 ký tự. User có thể đính kèm tối đa 20 ảnh, khớp giới hạn hiện tại của
  backend `FilesInterceptor`.
- Submitting suggestions requires the `FEEDBACK` feature. Listing all entries uses
  `/feedback/admin`, requires `ADMIN_FEEDBACK`, and the service still enforces
  `SUPER_ADMIN` even if a non-super user gets that feature by mistake.
- The admin suggestion list should render uploaded image URLs as inline
  thumbnails while keeping non-displayable image text visible as fallback.
- If suggestions become user-identifying or sensitive, update auth and privacy
  expectations before implementation.

## Expected Proof

- NestJS feedback service/controller tests.
- Flutter Home ordering and suggestion form validation/UI tests.
- Flutter admin feedback parser tests when display parsing changes.
- Manual smoke for successful and failed submissions when API behavior changes.
