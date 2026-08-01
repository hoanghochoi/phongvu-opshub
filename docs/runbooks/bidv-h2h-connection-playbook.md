# HƯỚNG DẪN KẾT NỐI BIDV H2H - OPSHUB

Phiên bản: 1.0 - 30/07/2026
Phạm vi: Thông báo biến động số dư BIDV H2H - OAuth 2.0 và OpenPGP

## 1. Đầu mối và môi trường

| Môi trường | Base URL | Trạng thái |
| --- | --- | --- |
| UAT | `https://bidv-staging.opshub.hoanghochoi.com` | Kích hoạt sau khi thống nhất IP allowlist |
| Production | `https://bidv.opshub.hoanghochoi.com` | Kích hoạt sau nghiệm thu UAT |

## 2. Thông tin OpsHub bàn giao cho BIDV

OpsHub bàn giao qua kênh bảo mật đã thống nhất:

- `client_id`;
- `client_secret` một lần, không gửi trong cùng kênh xác nhận;
- public key OpenPGP dạng ASCII armor (`.asc`);
- fingerprint OpenPGP được xác nhận qua kênh thứ hai;
- hai endpoint trong mục 3.

## 3. Lấy access token

`POST {baseUrl}/oauth2/token`
Content-Type: `application/x-www-form-urlencoded`
Authorization: `Basic base64(client_id:client_secret)`

Body:

```text
grant_type=client_credentials
```

Phản hồi thành công:

```json
{
  "access_token": "<opaque-access-token>",
  "token_type": "Bearer",
  "expires_in": 300,
  "scope": "balance-changes:write"
}
```

Không ghi log hoặc gửi lại giá trị `Authorization`/`access_token`. OpsHub trả
`Cache-Control: no-store`. Khi token hết hạn, BIDV lấy token mới bằng client
đang hoạt động.

## 4. Mã hóa OpenPGP

1. BIDV đối chiếu fingerprint public key với OpsHub qua kênh thứ hai.
2. Nội dung plaintext là mảng JSON giao dịch theo đặc tả BIDV revision 1.3.
3. BIDV mã hóa plaintext bằng public key OpsHub (encryption subkey X25519).
4. BIDV lấy thông điệp OpenPGP ASCII armor và Base64 toàn bộ armor; kết quả là
   giá trị trường `data`.

Không ký payload trong revision này. Nếu BIDV yêu cầu chữ ký hoặc thay đổi
thuật toán, hai bên phải thống nhất phiên bản hợp đồng mới trước khi gửi UAT.

## 5. Gửi biến động số dư

`POST {baseUrl}/v1/balance-changes`
Content-Type: `application/json`
Authorization: `Bearer <access_token>`
REQUESTID: `<mã duy nhất cho nội dung request>`

```json
{
  "bankCode": "BIDV",
  "data": "<base64-openpgp-message>"
}
```

Phản hồi thành công, bao gồm request lặp hợp lệ:

```json
{
  "errorCode": "000",
  "errorDesc": "Success"
}
```

Giới hạn mặc định cần xác nhận trong UAT: request mã hóa tối đa 1 MiB, tối đa
100 giao dịch/mẻ và thời gian xử lý 10 giây. Ngày dùng `ddMMyy`, giờ dùng
`HHmmss`, múi giờ nghiệp vụ `Asia/Ho_Chi_Minh`.

## 6. Idempotency và retry

- BIDV giữ nguyên `REQUESTID` và body khi retry cùng một request.
- Cùng `REQUESTID` và nội dung đã nhận trả HTTP 200 cùng response thành công.
- Không tái sử dụng `REQUESTID` cho nội dung khác.
- Theo đặc tả BIDV, response khác HTTP 200 được retry tối đa 3 lần, cách nhau
  15 giây.
- Hai bên đối soát identity mặc định
  `bankCode + accountNo + refNo + seq + businessDate` trước khi bật production.

## 7. Checklist mạng và bảo mật

- [ ] BIDV cung cấp IP nguồn UAT và production.
- [ ] Hai bên chốt IP allowlist cho UAT và production; kết nối **không dùng mTLS**.
- [ ] TLS public hợp lệ; BIDV không bỏ kiểm tra chứng thư.
- [ ] Firewall/Cloudflare chỉ cho phép chính sách đã thống nhất.
- [ ] Không truyền credential qua email thường hoặc đưa vào ticket/chat nhóm.
- [ ] Fingerprint OpenPGP được đọc lại qua kênh thứ hai.
- [ ] Đồng hồ hai bên đồng bộ NTP.

## 8. Ma trận UAT tối thiểu

| Ca kiểm thử | Kỳ vọng |
| --- | --- |
| Token hợp lệ | HTTP 200, token 5 phút, scope đúng |
| Sai client/secret | HTTP 401, không lộ nguyên nhân nhạy cảm |
| Một giao dịch Credit/VND | HTTP 200, đối soát đúng identity/số tiền/ngày giờ |
| Nhiều giao dịch | Toàn mẻ hợp lệ mới được ghi nhận |
| Gửi lặp cùng REQUESTID/body | HTTP 200, không tạo bản ghi/side effect trùng |
| REQUESTID cũ/body khác | Không chấp nhận; hai bên điều tra log bằng mã đã băm |
| Sai key/armor/Base64 | Không chấp nhận, không ghi một phần |
| Một dòng sai trong mẻ | Không ghi bất kỳ dòng nào của mẻ |
| Debit/ngoại tệ/số lẻ/không map showroom | Tiếp nhận audit, không tạo thông báo thanh toán |
| Identity trùng nhưng payload khác | Cách ly conflict, không tạo side effect |
| Xoay client/key | Hai phiên bản chạy trong cửa sổ 24 giờ, sau đó thu hồi cũ |
| Retry 3 lần, cách 15 giây | Không tạo dữ liệu hoặc thông báo trùng |

BIDV cung cấp cho OpsHub ít nhất một bộ plaintext, ciphertext mã hóa bằng public
key UAT và response mong đợi. Không sử dụng dữ liệu tài khoản thật nếu chưa có
chấp thuận bảo mật phù hợp.

## 9. Kích hoạt production

Chỉ kích hoạt sau khi hai bên ký xác nhận UAT, chốt identity/batch/timezone,
IP allowlist, đối soát tổng số giao dịch và tổng số tiền, cửa sổ
rotation và kế hoạch rollback. Production dùng client/key riêng, không tái sử
dụng UAT.

## 10. Xử lý sự cố

| Hiện tượng | BIDV kiểm tra | Phối hợp OpsHub |
| --- | --- | --- |
| HTTP 401 token | Basic header, client đang hoạt động | Xác nhận phiên bản client; rotation nếu mất secret |
| HTTP 401 push | Token hết hạn/scope | Lấy token mới, không tái sử dụng token cũ |
| HTTP 400/409 | REQUESTID, Base64/armor, schema | Cung cấp REQUESTID và thời điểm; không gửi secret/payload qua kênh thường |
| HTTP 429 | Tần suất và `Retry-After` | Giảm tốc theo phản hồi |
| HTTP 503/timeout | Giữ nguyên REQUESTID/body khi retry | OpsHub kiểm tra kill switch/khóa/persistence |
| Không thấy thanh toán downstream | Kiểm tra response HTTP 200 | OpsHub đối soát canonical; tiếp nhận có thể vẫn an toàn khi projection tắt |
