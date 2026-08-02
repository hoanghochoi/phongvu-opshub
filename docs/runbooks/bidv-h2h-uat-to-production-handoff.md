# BIDV H2H - Handoff từ UAT đến production

Ngày cập nhật: 02/08/2026
Đối tượng: Đại Ca, vận hành OpsHub và đầu mối kỹ thuật BIDV
Hợp đồng tích hợp: OAuth 2.0 `client_credentials` và OpenPGP.

## 0. Quy tắc làm việc

- UAT và production là hai môi trường tách biệt: client, secret, OpenPGP key,
  KEK và access token không dùng chung.
- Không gửi client secret, token, KEK, private key hoặc payload giao dịch qua
  email thường/ticket/chat nhóm.
- Chỉ bật **ingest** trước. Chỉ bật **projection** sau khi có biên bản đối soát.
- Bất kỳ lỗi TLS, decrypt, auth hoặc persistence nào: dừng UAT, tắt ingest và
  giữ lại evidence; không xóa receipt/canonical/audit record.

## 1. Trạng thái sẵn sàng hiện tại

| Hạng mục | UAT | Production |
| --- | --- | --- |
| Hostname | `https://bankapis-staging.hoanghochoi.com` | Chưa public; chỉ tạo trong release production |
| Route smoke | Đã pass | Chưa thực hiện |
| Source code | Đã ở `staging` | Chưa promote từ `staging` sang `main` |
| Ingest/projection | Giữ tắt đến khi chuẩn bị UAT | Giữ tắt |

UAT public smoke đã xác nhận:

```text
GET  /health              -> 200, body ok
GET  /                    -> 404
GET  /api/health          -> 404
POST /oauth2/token        -> 401 khi chưa có auth
POST /v1/balance-changes  -> 401 khi chưa có auth
```

## 2. Chuẩn bị UAT trên OpsHub

### 2.1 Kiểm tra protected env staging

Kết nối máy staging:

```bash
ssh mementoamoris
sudo -i
sudoedit /srv/opshub-staging/env
```

Xác nhận có các giá trị sau. Không in file env ra terminal.

```dotenv
BIDV_H2H_DOMAIN=bankapis-staging.hoanghochoi.com
BIDV_H2H_PUBLIC_BASE_URL=https://bankapis-staging.hoanghochoi.com
BIDV_H2H_ENVIRONMENT=staging
BIDV_H2H_KEK_BASE64=<Base64-cua-32-byte-KEK-UAT>
BIDV_H2H_INGEST_ENABLED=false
BIDV_H2H_PROJECTION_ENABLED=false
BIDV_H2H_TOKEN_TTL_SECONDS=300
BIDV_H2H_MAX_ENCODED_BODY_BYTES=1048576
BIDV_H2H_MAX_TRANSACTIONS_PER_BATCH=100
BIDV_H2H_PROCESSING_TIMEOUT_MS=10000
```

Nếu chưa có KEK UAT, tạo **trên protected host** rồi dán trực tiếp vào `env`:

```bash
umask 077
openssl rand -base64 32
```

Kiểm tra quyền file, rồi thoát:

```bash
sudo chown root:"$(id -gn hhh)" /srv/opshub-staging/env
sudo chmod 0640 /srv/opshub-staging/env
sudo stat -c '%a %U %G %n' /srv/opshub-staging/env
exit
exit
```

Kỳ vọng: quyền `640`, owner `root`, group vận hành staging.

### 2.2 Chỉ đổi biến backend: recreate API trên VPS

Nếu chỉ sửa các biến runtime của NestJS như `BIDV_H2H_KEK_BASE64`,
`BIDV_H2H_INGEST_ENABLED`, `BIDV_H2H_PROJECTION_ENABLED`, TTL, limit hoặc
timeout thì **không cần build lại APK/Windows/web** và không cần chạy workflow
deploy đầy đủ.

Trên VPS staging chạy:

```bash
ssh mementoamoris
cd /home/hhh/phongvu-opshub-staging
export OPSHUB_ENV_FILE=/srv/opshub-staging/env
export OPSHUB_SSD_ROOT=/srv/opshub-staging
export COMPOSE_PROJECT_NAME=opshub_staging

docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml \
  up -d --no-deps --force-recreate api

docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml ps api
```

`docker compose restart api` chỉ khởi động lại container với environment cũ;
không đủ để nạp giá trị mới trong `env_file`. Vì vậy dùng `up -d
--no-deps --force-recreate api`. Lệnh này không build image và không chạy
migration.

Nếu đổi `BIDV_H2H_DOMAIN` hoặc `BIDV_H2H_PUBLIC_BASE_URL`, Caddy cũng phải nhận
env mới:

```bash
docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml \
  up -d --no-deps --force-recreate api caddy
```

Sau recreate, chạy smoke public ngay:

```bash
curl -fsS https://bankapis-staging.hoanghochoi.com/health
curl -sS -o /dev/null -w 'root=%{http_code}\n' \
  https://bankapis-staging.hoanghochoi.com/
curl -sS -o /dev/null -w 'api=%{http_code}\n' \
  https://bankapis-staging.hoanghochoi.com/api/health
```

Kỳ vọng: `health` trả `ok`, `root=404`, `api=404`. Nếu API health hoặc route smoke fail,
kiểm tra log đã lọc secret:

```bash
docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml logs --tail=120 api
```

Không dùng `docker compose down` cho env-only change vì sẽ dừng cả Postgres,
Redis và các consumer không cần thiết.

### 2.3 Đổi source code/image hoặc cần migration: dùng workflow deploy

Nếu thay source code, Docker image, compose, migration, Caddy image hoặc static
artifact thì phải dùng workflow deploy đầy đủ. Từ PowerShell tại máy có GitHub CLI:

```powershell
cd C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub
gh workflow run deploy-opshub-staging.yml --ref staging -f failure_injection=none
gh run list --workflow deploy-opshub-staging.yml --branch staging --limit 3
gh run watch <RUN_ID> --exit-status
```

Chỉ sang bước tiếp theo khi run `success`.

### 2.4 Tạo UAT client và OpenPGP key trên UI

1. Mở `https://opshub-staging.hoanghochoi.com` và đăng nhập Super Admin.
2. Vào **Quản trị > Quản lý kết nối API**.
3. Xác nhận **Tiếp nhận dữ liệu BIDV** và **Đối soát tự động** đều tắt.
4. Tạo client UAT. Lưu `client_id` và `client_secret` ngay khi UI hiển thị;
   secret không xem lại được.
5. Chọn **Tạo khóa OpenPGP**. Nếu báo thiếu KEK, quay lại bước 2.1 rồi redeploy.
6. Xuất public key `.asc`, ghi fingerprint và key version.
7. Ghi vào sổ bàn giao: môi trường, client ID, key version, fingerprint,
   người bàn giao/nhận và thời điểm. Không ghi secret/KEK/private key.

## 3. Gửi package UAT cho BIDV

Gửi bằng các kênh bảo mật đã thống nhất:

| Thông tin | Kênh gửi |
| --- | --- |
| Base URL | `https://bankapis-staging.hoanghochoi.com` |
| Token endpoint | `POST /oauth2/token` |
| Push endpoint | `POST /v1/balance-changes` |
| `client_id` | Kênh 1 |
| `client_secret` | Kênh 2, tách khỏi kênh 1 |
| Public key `.asc` | Kênh 1 |
| Fingerprint public key | Kênh 2 để đọc lại xác nhận |
| Playbook | PDF `BIDV-H2H-OpsHub-Connection-Playbook` |

Yêu cầu BIDV phản hồi xác nhận đã nhận đủ thông tin, fingerprint khớp và cung
cấp fixture UAT gồm plaintext, ciphertext mã hóa bằng public key UAT và response
mong đợi. Fixture chỉ dùng dữ liệu đã được phê duyệt cho UAT.

## 4. Bật UAT theo hai lớp control

Chỉ làm sau khi BIDV đã xác nhận package UAT và fixture sẵn sàng.

### 4.1 Bật master ingest trên env

Trên `mementoamoris`, sửa đúng một biến:

```bash
ssh mementoamoris
sudoedit /srv/opshub-staging/env
```

```dotenv
BIDV_H2H_INGEST_ENABLED=true
BIDV_H2H_PROJECTION_ENABLED=false
```

Redeploy bằng các lệnh ở bước 2.2 và chờ `success`.

### 4.2 Bật request ingest trên UI

1. Vào lại **Quản trị > Quản lý kết nối API** trên staging.
2. Bật **Tiếp nhận dữ liệu BIDV** và lưu.
3. Không bật **Đối soát tự động**.

Nếu cần dừng UAT, làm ngược lại: tắt ingest trên UI, đặt master ingest về
`false`, redeploy staging.

## 5. BIDV chạy UAT

### 5.1 Lấy token

```text
POST https://bankapis-staging.hoanghochoi.com/oauth2/token
Authorization: Basic base64(client_id:client_secret)
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
```

Kỳ vọng: HTTP `200`, scope `balance-changes:write`, token TTL 300 giây.

### 5.2 Push biến động

```text
POST https://bankapis-staging.hoanghochoi.com/v1/balance-changes
Authorization: Bearer <access_token>
REQUESTID: <ma-duy-nhat-cho-noi-dung-request>
Content-Type: application/json
```

`data` là OpenPGP ASCII armor được Base64 theo playbook. Khi retry, BIDV giữ
nguyên cả `REQUESTID` và body.

Giới hạn UAT:

| Endpoint | Giới hạn |
| --- | --- |
| Token | 60 request/phút/IP |
| Balance changes | 600 request/phút/IP |
| Payload mã hóa | Tối đa 1 MiB/request |
| Batch | Tối đa 100 giao dịch |
| Timeout xử lý | 10 giây |

Khi nhận HTTP `429`, chờ đúng `Retry-After` rồi gửi lại; không bắn dồn request.
Tải 2 request/giây của BIDV nằm trong ngưỡng balance-change 600 request/phút.

### 5.3 Checklist UAT cần ký xác nhận

- [ ] Token hợp lệ; client/secret sai trả `401`.
- [ ] Một Credit/VND, batch hợp lệ và batch 100 giao dịch.
- [ ] Retry cùng `REQUESTID`/body không tạo side effect trùng.
- [ ] `REQUESTID` cũ với body khác bị từ chối.
- [ ] Key/armor/Base64 sai; batch có dòng sai; conflict transaction.
- [ ] Debit, ngoại tệ, số lẻ VND và showroom không map chỉ được audit.
- [ ] 2 request/giây trong thời lượng thống nhất không có `429` hoặc duplicate.
- [ ] Đối soát tổng giao dịch, tổng tiền, ngày `ddMMyy`, giờ `HHmmss` và múi
  giờ `Asia/Ho_Chi_Minh`.
- [ ] Biên bản UAT có chữ ký/xác nhận của hai bên.

## 6. Bật projection staging sau UAT

Chỉ làm khi biên bản UAT và đối soát ở bước 5.3 đã được duyệt.

1. Trên staging env đặt:

   ```dotenv
   BIDV_H2H_PROJECTION_ENABLED=true
   ```

2. Redeploy staging và chờ workflow xanh.
3. Trên UI bật **Đối soát tự động**.
4. Kiểm tra mỗi giao dịch chỉ có một side effect tại Tiền vào, Sao kê, VietQR,
   speaker, realtime, Home và BigQuery.

Nếu có sai lệch downstream: tắt control projection trên UI trước, sau đó đặt
master projection về `false` và redeploy. Không xóa evidence ingress.

## 7. Điều kiện vào production

Đại Ca xác nhận đủ tất cả điều kiện trước khi promote:

- [ ] UAT acceptance được ký/xác nhận.
- [ ] Staging deploy của SHA cần phát hành thành công.
- [ ] QA staging đạt; không có merge mới trong release window.
- [ ] Production KEK, client và OpenPGP key riêng đã sẵn sàng.
- [ ] Backup/restore, rollback owner và đầu mối xử lý sự cố đã rõ.

Chỉ khi đủ các điều kiện trên và Đại Ca ra lệnh chính xác
`Promote origin/staging vào main ngay bây giờ.` mới được promotion.

## 8. Promote source và deploy production

Từ PowerShell ở canonical repository:

```powershell
cd C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub
git fetch origin main staging
$stagingSha = (git rev-parse origin/staging).Trim()

node scripts/promote-production.mjs `
  --expected-sha $stagingSha `
  --ci-confirmed `
  --qa-confirmed `
  --release-window-locked

gh workflow run promote-production.yml --ref main `
  -f staging_sha=$stagingSha `
  -f qa_confirmation=QA-APPROVED `
  -f "release_confirmation=PROMOTE ORIGIN/STAGING TO MAIN"
```

Approve environment `production` trong GitHub, theo dõi workflow tới khi
production deploy thành công. Sau deploy, fetch lại để xác nhận
`origin/main` và `origin/staging` cùng SHA.

## 9. Cấu hình production hostname sau production deploy

Không cấu hình public hostname này trước bước 8. Làm trên `hoang-n8n` ngay sau
production deploy thành công:

```bash
ssh hoang-n8n
sudo cp -a /etc/cloudflared/config.yml \
  /etc/cloudflared/config.yml.bak-bankapis-<YYYYMMDD-HHMMSS>
sudoedit /etc/cloudflared/config.yml
```

Thêm entry này **ngay trước** entry `http_status:404`:

```yaml
  - hostname: bankapis.hoanghochoi.com
    service: http://localhost:8090
```

Validate và restart tunnel:

```bash
sudo cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate
sudo systemctl restart cloudflared.service
sudo systemctl is-active --quiet cloudflared.service
```

Tạo DNS route bằng credential Cloudflare quản lý `hoanghochoi.com`:

```bash
cloudflared --origincert /home/ubuntu/.cloudflared/cert.pem tunnel route dns \
  --overwrite-dns ffb3f4df-428e-47d2-bd36-064eebc4a94c \
  bankapis.hoanghochoi.com
```

Nếu bất kỳ lệnh validate/smoke nào fail, restore backup config, restart service
và xóa DNS route vừa tạo; không tiếp tục activation.

## 10. Chuẩn bị runtime và client production

Trên production protected env `/srv/opshub/env`, thêm giá trị riêng:

```dotenv
BIDV_H2H_DOMAIN=bankapis.hoanghochoi.com
BIDV_H2H_PUBLIC_BASE_URL=https://bankapis.hoanghochoi.com
BIDV_H2H_ENVIRONMENT=production
BIDV_H2H_KEK_BASE64=<Base64-cua-32-byte-KEK-production>
BIDV_H2H_INGEST_ENABLED=false
BIDV_H2H_PROJECTION_ENABLED=false
```

Sau deploy/hostname smoke, tạo client và OpenPGP key **trên UI production**;
gửi package production cho BIDV theo cùng quy tắc hai kênh ở bước 3.

## 11. Smoke production trước activation

Từ máy có Internet:

```powershell
$base = 'https://bankapis.hoanghochoi.com'
curl.exe -fsS -D - "$base/health"
curl.exe -sS -o NUL -w "%{http_code}`n" "$base/"
curl.exe -sS -o NUL -w "%{http_code}`n" "$base/api/health"
curl.exe -sS -o NUL -w "%{http_code}`n" -X POST `
  -H 'Content-Type: application/x-www-form-urlencoded' `
  --data 'grant_type=client_credentials' "$base/oauth2/token"
```

Kỳ vọng: `health=200`, root/API health `404`, token không auth `401`. Nếu root
hoặc API health trả `200`, rollback tunnel/DNS ngay; hostname đang trỏ vào app
thông thường thay vì boundary BIDV.

## 12. Production activation và hoàn tất

1. BIDV xác nhận đã nhận production package và có fixture production được duyệt.
2. Đặt `BIDV_H2H_INGEST_ENABLED=true`, redeploy production, sau đó bật ingest
   trên UI production.
3. Chạy happy path, retry, auth failure và reconciliation smoke với fixture.
4. Theo dõi receipt count, decrypt/auth errors, 429, retry/dead-letter và
   aggregate số giao dịch/số tiền.
5. Sau xác nhận đối soát production, đặt
   `BIDV_H2H_PROJECTION_ENABLED=true`, redeploy rồi bật projection trên UI.
6. Xác minh Tiền vào, Sao kê, VietQR, speaker, realtime, Home và BigQuery chỉ
   nhận một side effect/giao dịch đủ điều kiện.
7. Ghi SHA deploy, URL workflow, kết quả smoke, người QA, biên bản đối soát và
   residual risk vào OPS-39 trước khi chuyển issue `Done`.

## 13. Rollback nhanh

| Sự cố | Thao tác ngay |
| --- | --- |
| Sai TLS/route public | Xóa DNS route mới hoặc restore tunnel config backup rồi restart tunnel |
| Lỗi auth/decrypt/persistence | Tắt ingest UI, đặt master ingest `false`, redeploy |
| Sai downstream/duplicate | Tắt projection UI, đặt master projection `false`, redeploy |
| Cần quay về release cũ | Theo release playbook; không rewrite `main` |

Sau rollback, giữ nguyên receipt/canonical/audit evidence và mở sự cố với thời
điểm, REQUESTID đã băm, environment và SHA release.
