# OPS-39 - Handoff hạ tầng Bank APIs

Ngày cập nhật: 01/08/2026

## Mục tiêu

Xuất bản hai hostname chuyên dụng cho BIDV H2H:

| Môi trường | Hostname | Origin |
| --- | --- | --- |
| UAT | `bankapis-staging.hoanghochoi.com` | `http://127.0.0.1:8090` trên `mementoamoris` |
| Production | `bankapis.hoanghochoi.com` | origin production tại cổng Caddy 8090 |

Hai hostname này chỉ phục vụ `/health`, `/oauth2/token` và
`/v1/balance-changes`. Các đường dẫn khác phải trả `404`.

## 1. Staging Cloudflare Tunnel và DNS

Trong Cloudflare Zero Trust, thêm Public Hostname vào tunnel `opshub-staging`:

| Trường | Giá trị |
| --- | --- |
| Subdomain | `bankapis-staging` |
| Domain | `hoanghochoi.com` |
| Service type | `HTTP` |
| URL | `http://127.0.0.1:8090` |
| HTTP Host Header | `bankapis-staging.hoanghochoi.com` |

Để Cloudflare tạo CNAME proxied và chờ Edge Certificate trạng thái `Active`.
Không gắn Cloudflare Access browser login vào hostname này.

## 2. Protected staging env

Trên `mementoamoris`, sửa `/srv/opshub-staging/env` bằng `sudoedit`:

```dotenv
BIDV_H2H_DOMAIN=bankapis-staging.hoanghochoi.com
BIDV_H2H_PUBLIC_BASE_URL=https://bankapis-staging.hoanghochoi.com
BIDV_H2H_ENVIRONMENT=staging
BIDV_H2H_KEK_BASE64=<Base64-32-byte-KEK>
BIDV_H2H_INGEST_ENABLED=false
BIDV_H2H_PROJECTION_ENABLED=false
```

KEK phải được tạo/lưu trong kênh bí mật đã phê duyệt. Không đặt vào Git, chat
hoặc ticket. Giữ file env ở quyền `0640` với owner `root` và group vận hành.

## 3. Redeploy và smoke test

Sau khi lưu env, chạy deployment staging từ PowerShell:

```powershell
cd C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub
gh workflow run deploy-opshub-staging.yml --ref staging -f failure_injection=none
gh run list --workflow deploy-opshub-staging.yml --branch staging --limit 3
gh run watch <RUN_ID> --exit-status
```

Chỉ tiếp tục khi run thành công. Sau đó kiểm tra từ Internet:

```powershell
$base = 'https://bankapis-staging.hoanghochoi.com'
curl.exe -fsS -D - "$base/health"
curl.exe -sS -o NUL -w "%{http_code}`n" "$base/"
curl.exe -sS -o NUL -w "%{http_code}`n" "$base/api/health"
curl.exe -sS -o NUL -w "%{http_code}`n" -X POST `
  -H 'Content-Type: application/x-www-form-urlencoded' `
  --data 'grant_type=client_credentials' "$base/oauth2/token"
curl.exe -sS -o NUL -w "%{http_code}`n" -X POST `
  -H 'Content-Type: application/json' `
  --data '{"bankCode":"BIDV","data":"x"}' "$base/v1/balance-changes"
```

Kỳ vọng: `/health` là `200` với `ok`; `/` và `/api/health` là `404`; hai POST
chưa có xác thực là `401` (không phải `404` hoặc lỗi TLS). Nếu sai, giữ hai
master switch `false` và kiểm tra lại tunnel host header/Caddy trước UAT.

## 4. Rate limit và kiểm tra tải UAT

OpsHub tự giới hạn theo địa chỉ IP mà Caddy đã tin cậy:

| Endpoint | Giới hạn | Khi vượt ngưỡng |
| --- | --- | --- |
| `POST /oauth2/token` | 60 request/phút/IP | HTTP `429`, header `Retry-After` |
| `POST /v1/balance-changes` | 600 request/phút/IP | HTTP `429`, header `Retry-After` |

Không đặt rate limit bằng Cloudflare rule trùng với các ngưỡng này. Khi nhận
`429`, BIDV chờ đúng số giây trong `Retry-After` rồi retry với `REQUESTID` và
body không đổi. Không retry token cũ khi token đã hết hạn; lấy token mới sau
thời gian chờ.

Trong UAT, kiểm tra lần lượt:

1. Gửi 2 request/giây tới `/v1/balance-changes` trong khoảng thời gian đã thống
   nhất; kỳ vọng không có `429` và không có dữ liệu trùng.
2. Gửi vượt 600 request/phút từ một IP test; kỳ vọng response `429` có
   `Retry-After`, không lộ credential và log chỉ chứa dữ liệu đã băm.
3. Chờ hết `Retry-After`, gửi lại một request hợp lệ; kỳ vọng hệ thống nhận lại
   bình thường.
4. Gửi 61 request token từ một IP test; kỳ vọng request vượt ngưỡng nhận `429`.

Không chạy bước 2 hoặc 4 với client production. Chỉ dùng client UAT và fixture
đã được phê duyệt.

## 5. UAT và production

Sau smoke staging, tạo/kiểm tra client và OpenPGP key trên **Quản trị > Quản lý
kết nối API**, bàn giao public key/fingerprint và client credentials qua kênh
được phê duyệt. Bật ingest trước, giữ projection tắt cho đến khi đối soát UAT
được chấp thuận bằng văn bản.

Production lặp lại cùng quy trình với `bankapis.hoanghochoi.com`, env/KEK/client
và key production riêng. Không tái sử dụng dữ liệu bảo mật giữa UAT và
production.
