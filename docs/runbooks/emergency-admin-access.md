# Khôi phục quyền truy cập quản trị khẩn cấp

Runbook này thay cho tài khoản break-glass hard-code. API **không** tự tạo,
tự mở khóa hoặc tự nâng quyền tài khoản khi khởi động.

## Điều kiện bắt buộc

- Có sự cố/ticket được phê duyệt và ghi rõ lý do.
- Người duyệt đã xác minh danh tính người nhận qua kênh thứ hai.
- Tài khoản đích đã tồn tại, đang hoạt động và đã có vai trò `SUPER_ADMIN`.
- Chạy lệnh trong môi trường có `DATABASE_URL`; không chép URL database, token
  hoặc kết quả lệnh vào chat, ticket hay shell history công khai.

CLI không tạo tài khoản và không nâng quyền. Nó chỉ phát hành một reset token
ngẫu nhiên 256-bit, lưu bản băm trong database, TTL tối đa 15 phút và vô hiệu
các reset token cũ của tài khoản. Sự kiện phát hành được ghi vào `AppLog` nhưng
không ghi token.

## Chuyển đổi tài khoản break-glass cũ

Sau khi deploy bản loại bỏ startup bootstrap, vô hiệu tài khoản dùng chung cũ
bằng CLI tham số hóa dưới đây. Không đưa email thật vào Git hoặc runbook:

```powershell
npm run security:disable-account-access -- `
  --email "tai-khoan-can-vo-hieu@example.com" `
  --ticket "INC-YYYY-NNN" `
  --approved-by "ma-nhan-su-nguoi-duyet" `
  --confirm DISABLE_ACCOUNT_AND_REVOKE_SESSIONS
```

Lệnh khóa tài khoản, tăng `tokenVersion`, thu hồi phiên, vô hiệu reset/OTP chưa
dùng và ghi audit event. Chạy lại vẫn giữ trạng thái khóa; lệnh không xóa dữ
liệu nghiệp vụ liên quan đến tài khoản.

## Phát hành token dùng một lần

Từ thư mục `backend-nest/`:

```powershell
npm run security:issue-emergency-admin-reset -- `
  --email "tai-khoan-admin-da-duyet@example.com" `
  --ticket "INC-YYYY-NNN" `
  --approved-by "ma-nhan-su-nguoi-duyet" `
  --ttl-minutes 10 `
  --confirm ISSUE_ONE_TIME_RESET
```

Gửi riêng trường `resetToken` cho đúng người nhận qua kênh bí mật đã duyệt.
Người nhận dùng token với luồng `POST /auth/reset-password` trước `expiresAt`.
Token hết hạn hoặc đã dùng sẽ bị từ chối; đổi mật khẩu thành công tăng
`tokenVersion` và thu hồi các phiên cũ.

## Sau khi khôi phục

1. Kiểm tra `AppLog.source=SecurityEmergencyAccess` khớp ticket/người duyệt.
2. Xác nhận người nhận đặt mật khẩu mới và đăng nhập được.
3. Xác nhận phiên cũ đã bị thu hồi; kiểm tra không còn reset token chưa dùng.
4. Kết thúc sự cố, rà lại quyền `SUPER_ADMIN`; hạ quyền nếu chỉ cấp tạm.
5. Ghi kết quả, thời gian và người chịu trách nhiệm vào ticket.

## Việc vận hành vẫn phải làm thủ công

- Kích hoạt MFA cho mọi `SUPER_ADMIN` ngay khi ứng dụng có cơ chế MFA.
- Luôn duy trì ít nhất hai quản trị viên cá nhân độc lập; không dùng tài khoản
  dùng chung lâu dài.
- Không phục hồi constant email/hash hoặc startup bootstrap khi rollback.
