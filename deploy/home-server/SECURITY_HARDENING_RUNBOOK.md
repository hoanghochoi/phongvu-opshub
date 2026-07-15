# Runbook hoàn tất hardening infra/platform OpsHub

Tài liệu này dành cho các bước cần quyền Cloudflare, quyền host, secret hoặc
thiết bị ký Android. Code/config local đã chuẩn bị nhưng **không tự thay đổi
Cloudflare, runtime, credential hay dữ liệu production/staging**.

## 1. Checklist trước khi triển khai

- [ ] Chốt checkpoint: branch, HEAD, `git status --short`, SHA đang chạy ở
  production/staging và image digest hiện tại.
- [ ] Không gộp triển khai khi Sales Report còn baseline test đỏ chưa có waiver.
- [ ] Export/sao lưu cấu hình Cloudflare Tunnel, Access, Redirect Rules và cache
  rules hiện tại.
- [ ] Chụp `docker compose ... config --quiet`; không in bản config đã resolve ra
  log vì nó chứa secret.
- [ ] Xác nhận thư mục `uploads`, `payment-audio`, PostgreSQL, Redis, Caddy data
  có owner/mode phù hợp với UID/GID của image mới.
- [ ] Chuẩn bị image/SHA rollback trước; không rollback bằng cách mở lại HTTP,
  dùng debug signing hoặc bỏ Redis password.

## 2. Cloudflare: việc Đại Ca/infra phải làm

### 2.1 Ép HTTPS

- [ ] Bật **Always Use HTTPS** cho zone chứa production và staging, hoặc tạo
  Redirect Rule tương đương cho đúng hai hostname.
- [ ] Giữ Cloudflare Tunnel chuyển tiếp tới origin HTTP loopback. Caddy chỉ
  redirect khi Cloudflare gửi `X-Forwarded-Proto: http`; không đổi site block
  thành HTTPS origin nếu Tunnel chưa được thiết kế lại.
- [ ] Caddy chỉ trust hop private/local của Cloudflare Tunnel, lấy IP gốc từ
  `CF-Connecting-IP`, rồi chuẩn hóa `X-Forwarded-For` và `X-Real-IP` về đúng
  `{client_ip}` trước khi chuyển vào API/realtime. Nest tiếp tục trust đúng một
  hop Caddy; không tăng rate limit để che lỗi nhận sai IP.
- [ ] Sau reload Caddy, xác minh bucket global duy nhất là `principal`. Cùng
  user+cùng trusted IP phải chung bucket; cùng user+khác IP và hai user chung
  NAT phải tách bucket. 429 phải có `Retry-After`; không được có header/bucket
  `Ip` riêng hoặc raw IP trong storage/log. Theo dõi 429, p95, CPU/RAM, DB và
  container restart ít nhất 5 phút trước khi bỏ backup rollback.
- [ ] Kiểm tra ít nhất các đường dẫn `/`, `/help`, `/download`, `/api/health`:

  ```bash
  curl -sS -o /dev/null -D - http://opshub.hoanghochoi.com/
  curl -sS -o /dev/null -D - http://opshub-staging.hoanghochoi.com/
  ```

  Kỳ vọng `301` hoặc `308`, `Location` là đúng hostname HTTPS, không có redirect
  loop. HTTPS phải có `X-Content-Type-Options`, `Referrer-Policy`,
  `X-Frame-Options`, `Permissions-Policy` và enforced
  `Content-Security-Policy`.
- [ ] Kiểm tra path normalization trực tiếp tại origin, tách khỏi Cloudflare
  Access. Với đúng `Host` header, `/download/` phải trả 308 và
  `Location: /download`; `/help/` phải trả 308 và `Location: /help`; hai URL
  canonical phải trả nội dung 200, không loop.

### 2.2 Staging Access

- [ ] Đặt hostname staging sau Cloudflare Access/VPN/IP allowlist.
- [ ] Tạo policy người dùng theo nhóm được duyệt; CI dùng service token riêng,
  không dùng session người thật.
- [ ] Kiểm tra anonymous bị chặn trước khi request tới app.
- [ ] Rotate `STAGING_TEST_PASSWORD`, JWT/Redis secret staging và thu hồi session
  test cũ. Secret chỉ nằm trong `/srv/opshub-staging/env` mode `0640` hoặc secret
  manager; không truyền qua CLI/shell history.
- [ ] Deploy staging phải ghi lại symlink `current` trước khi migrate/recreate.
  Lỗi migration, recreate hoặc health check phải tự khôi phục symlink và
  recreate service cũ; workflow vẫn kết luận fail. Batch 2026-07-15 không có
  migration DB nên runtime rollback không lệch schema.
- [ ] Xác minh staging ép
  `ERP_ORDER_CACHE_SYNC_ENABLED=false`,
  `ERP_ORDER_STATUS_SYNC_ENABLED=false`,
  `VIETQR_AUTO_RECONCILE_ENABLED=false`,
  `MAP_VIETIN_GLOBAL_SYNC_ENABLED=false`,
  `HOME_SUMMARY_ERP_BACKFILL_ENABLED=false` và xóa mọi `SMTP_*` trước load.
- [ ] Load proof chỉ dùng CLI/runbook staging đã hard-gate tại
  `deploy/staging/load-proof-runbook.md`; mọi kết quả đều phải revoke/delete đủ
  60 user và xóa token/k6 tạm. Cleanup không chứng minh được thì chưa sẵn sàng.

### 2.3 CSP enforced

- [ ] Trong staging, mở DevTools Console và chạy login, navigation, scanner,
  Help, Download, tải font/icon, WebSocket và self-update manifest. CSP hiện
  enforced nên bất kỳ violation làm hỏng luồng nào cũng chặn release.
- [ ] Ghi từng CSP violation theo directive/resource; không nới policy chỉ để
  làm smoke xanh khi chưa xác định đúng dependency bị chặn.
- [ ] Không thêm collector bên thứ ba khi chưa được duyệt vì report có thể chứa
  URL/path nội bộ. Nếu cần collector, dùng endpoint nội bộ có retention/redaction.
- [ ] Giữ `Content-Security-Policy` enforced. HSTS `includeSubDomains`/preload
  cần review toàn zone riêng, không bật tự động.

## 3. Redis password: triển khai phối hợp, không bật nửa vời

Compose mới bắt buộc `REDIS_PASSWORD`; Nest và Go phải nhận cùng secret. Thay đổi
này làm client cũ mất kết nối, vì vậy phải triển khai trong một maintenance
window.

- [ ] Sinh secret ngẫu nhiên tối thiểu 32 byte trong secret manager; không ghi
  secret vào tài liệu hoặc command output.
- [ ] Cập nhật `REDIS_PASSWORD` đồng thời trong env production/staging; chỉ đặt
  `REDIS_USERNAME` khi đã cấu hình ACL user tương ứng.
- [ ] Recreate theo thứ tự `redis` -> `api` -> `realtime`; kiểm `/api/health`,
  realtime `/ready`, publish/subscribe và reconnect client.
- [ ] Xác nhận healthcheck Redis dùng `REDISCLI_AUTH`, log không chứa secret.
- [ ] Nếu lỗi, rollback image/config đồng bộ nhưng giữ Redis authentication;
  không đưa Redis về trạng thái không mật khẩu trên network dùng chung.

## 4. Non-root, read-only rootfs và log rotation

- [ ] Build hai target Nest: `runtime` cho API và `ops` cho migration/job thủ
  công. Xác nhận API image không có `prisma` CLI, Jest, ESLint, TypeScript hay
  thư mục `scripts`.
- [ ] Xác nhận UID API khác `0`:

  ```bash
  docker compose --env-file /srv/opshub/env \
    -f deploy/home-server/docker-compose.home.yml run --rm \
    --no-deps --entrypoint id api
  ```

- [ ] Trước recreate, kiểm UID/GID trên host có quyền đọc/ghi đúng hai volume
  `uploads`, `private-media` và `payment-audio`. `private-media` phải mode `0770`
  hoặc hẹp hơn và tuyệt đối không mount vào Caddy. Không `chmod 777`; dùng
  owner/group hoặc ACL hẹp.
- [ ] Sau deploy, kiểm `ReadonlyRootfs=true`, `CapDrop=[ALL]`,
  `no-new-privileges` cho API/realtime/Caddy và chỉ volume/tmpfs được ghi.
- [ ] Kiểm Docker log driver có `max-size`/`max-file`; quan sát ít nhất một vòng
  rotation và dung lượng disk. Không đưa token/query/raw payload vào log.

PostgreSQL/Redis không bị drop toàn bộ capability trong wave này vì official
entrypoint còn phải hạ quyền/chỉnh volume khi khởi tạo. Việc siết thêm cần test
trên volume clone trước, không áp trực tiếp production.

## 5. Backup mã hóa và restore drill

`backup.sh` mặc định fail-closed nếu thiếu `BACKUP_AGE_RECIPIENT`. Repo không tạo
hoặc giữ private identity.

- [ ] Trên máy quản trị an toàn/offline, tạo age identity và lưu vào secret
  manager/kho offline; chỉ chuyển **public recipient** sang host chạy backup.
- [ ] Cài binary `age` từ nguồn package chính thức trên host.
- [ ] Đặt `BACKUP_AGE_RECIPIENT` trong runtime env; giữ
  `BACKUP_ALLOW_UNENCRYPTED=false`.
- [ ] Chạy backup và xác nhận thư mục mode `0700`, file mode `0600`, artifact có
  hậu tố `.age`, gồm PostgreSQL, uploads và private-media khi tồn tại;
  `sha256sum -c SHA256SUMS` pass.
- [ ] Copy một bản sang môi trường cô lập, giải mã bằng identity ngoài host,
  restore PostgreSQL và upload archive, rồi smoke test dữ liệu/số file.
- [ ] Ghi thời gian restore, checksum, owner và người phê duyệt. Không coi backup
  thành công nếu chưa có restore drill.
- [ ] Chỉ dùng `BACKUP_ALLOW_UNENCRYPTED=true` trong tình huống khẩn cấp được phê
  duyệt bằng văn bản; di chuyển/mã hóa artifact ngay và rotate dữ liệu liên quan.

## 6. Android và Windows signing

- [ ] Thu hẹp ACL `key.properties`/keystore về đúng tài khoản build; không gửi
  file hoặc secret qua chat/issue.
- [ ] Chạy release build khi bỏ từng signing secret và xác nhận Gradle fail; không
  được tạo APK ký debug.
- [ ] Chạy release build đầy đủ và xác minh certificate fingerprint trùng bản
  production trước.
- [ ] Test backup/device-transfer: SharedPreferences/database/token OpsHub không
  được restore sang thiết bị khác.
- [ ] Self-update production chỉ tải URL HTTPS trên
  `opshub.hoanghochoi.com/downloads/`; staging chỉ tải URL chuẩn trên
  `opshub-staging.hoanghochoi.com/downloads/`. Redirect, cross-host và đường dẫn
  legacy phải bị từ chối; type/size và checksum runtime phải pass. Chữ ký
  Authenticode, timestamp, signer pin và Defender scan vẫn là release gate bắt
  buộc của CI, không còn là client runtime gate.
- [ ] Cấu hình GitHub Environment production với variable
  `WINDOWS_UPDATE_SIGNER_SHA256`, secrets `WINDOWS_SIGNING_PFX_BASE64` và
  `WINDOWS_SIGNING_PFX_PASSWORD`.
- [ ] Cấu hình staging tương ứng bằng prefix `WINDOWS_STAGING_`; workflow thiếu
  PFX/password/pin hoặc signature/timestamp/pin sai phải fail.
- [ ] Rotation signer dùng giai đoạn hai pin, release client tin cert mới trước
  khi đổi PFX; xem lệnh chi tiết trong
  `app-security-manual-actions-12072026.md`.

## 7. Dependency và static pages

- [ ] `npm audit --omit=dev` phải bằng 0. `xlsx` đã chuyển sang official SheetJS
  CE `0.20.3`; giữ parser/export corpus và không hạ lại npm registry `0.18.5`.
- [ ] Smoke Help với navigation hợp lệ, file Markdown, link/ảnh relative; URL
  protocol-relative, HTTP, cross-origin và path `..` phải bị từ chối.
- [ ] Smoke Download với manifest production/staging; chỉ URL HTTPS same-origin
  dưới prefix tương ứng tạo được nút tải.
- [ ] Chạy `node scripts/verify-platform-security.mjs` trong CI/release gate.

### 7.1 Telemetry tối thiểu cho `/uploads` legacy

- [ ] Chỉ bật named access logger `legacy_uploads`; `no_hostname` bảo đảm request
  khác không bị ghi. Không bật site-wide access log vì reset/auth URL có thể
  chứa query nhạy cảm.
- [ ] Entry phải xóa URI, IP, headers, response headers và user id; chỉ giữ path
  hash, thời gian, method/status/duration/size. Docker log tiếp tục giới hạn
  `10m x 5`.
- [ ] Sau deploy, tạo đúng một probe `/uploads/*?token=...`; chạy
  `security:audit-legacy-upload-access -- --strict` và xác nhận một hit, một
  hash, không có raw path/query/IP.
- [ ] Dùng cửa sổ tối thiểu 7 ngày trước media cutover. `--fail-on-hits` phải
  trả 0; nếu exit `3` thì dừng cutover, không xóa route/file/cache.

### 7.2 GitHub repository security

- [ ] Secret scanning và push protection ở trạng thái enabled; query alert chỉ
  lấy count/metadata, tuyệt đối không in trường `secret`.
- [ ] Dependabot alerts/security updates enabled; không auto-merge PR bảo mật,
  vẫn phải chạy regression và staging gate.
- [ ] CodeQL advanced workflow scan `javascript-typescript` và `go`, dùng
  `security-extended`, action pin SHA và quyền tối thiểu
  `contents: read`/`security-events: write`.
- [ ] Chỉ đóng control sau khi hai CodeQL matrix job success và open alert count
  đã review; không dismiss alert chỉ để làm xanh workflow.

## 8. Stop conditions

Dừng promotion nếu có một trong các điều kiện:

- HTTP vẫn trả nội dung `200`, redirect loop hoặc thiếu static security headers.
- API/realtime không kết nối Redis bằng credential mới.
- API chạy UID `0`, rootfs/capability khác contract hoặc volume không ghi được.
- Backup chưa mã hóa, checksum lỗi hoặc chưa restore được trong môi trường cô lập.
- APK release có thể fallback debug signing; updater chấp nhận HTTP/cross-host.
- CSP violation làm hỏng login/scanner/Help/Download hoặc static allowlist chặn
  artifact hợp lệ.

Rollback phải dùng image/config đã chốt và giữ nguyên các invariant bảo mật:
HTTPS, Redis auth, non-debug signing, backup encryption và không log secret.
