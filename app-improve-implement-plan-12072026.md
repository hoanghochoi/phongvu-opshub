# Kế hoạch triển khai cải thiện OpsHub

> Ngày lập: 12/07/2026
> Nguồn phát hiện: app-audit-21072026.md
> Trạng thái xác minh 14/07/2026: hardening và audit proof đã commit/push, deploy
> staging đến SHA `6fe62997eb76efc473c60f7998e9219fe7e69b20`; Cloudflare HTTPS/CSP/HSTS,
> staging container/ACL và TrueNAS backup đã có proof. Production chưa promote;
> private-media cutover, credential rotation, MFA và realtime destructive smoke
> vẫn là gate riêng.
> Mục tiêu: đóng rủi ro Critical/High trước, sau đó giảm bề mặt runtime và nợ bảo trì mà không làm gãy nghiệp vụ

## 1. Mục tiêu và nguyên tắc

### 1.1 Mục tiêu

1. Chặn các đường lộ token, media riêng tư và quyền quản trị.
2. Ép mọi truy cập web qua HTTPS và áp security header ở đúng lớp edge/static.
3. Đưa authorization realtime về phía server và chống slow-client/connection DoS.
4. Vá dependency, upload, CSV, rate limit, backup, container và logging theo defense-in-depth.
5. Tạo runtime artifact tối thiểu; loại mã/tài nguyên không phục vụ runtime theo bằng chứng.
6. Tách module lớn từng bước phía sau characterization test, không rewrite toàn hệ thống.

### 1.2 Nguyên tắc bắt buộc

- Chỉ làm trên staging hoặc main; không tự tạo branch khác.
- Mỗi đợt phải ghi checkpoint: branch, HEAD, upstream, dirty worktree và image/release digest đang live.
- Bảo vệ thay đổi Sales Report hiện có; không trộn security hotfix với thay đổi nghiệp vụ chưa ổn định.
- Mỗi migration phải có đường rollback thực tế, không chỉ “git revert”.
- Không log token, secret, raw payload, email đầy đủ hoặc URL media riêng tư.
- UI/backend error hiển thị cho người dùng phải bằng tiếng Việt, có hành động tiếp theo và không lộ code nội bộ.
- Feature/code mới phải có AppLogger theo quy tắc dự án, nhưng dùng redaction/sampling và metric để tránh log quá mức.
- Mọi thay đổi liên quan auth, upload, realtime, external integration, public contract và migration được coi là high-risk lane.
- Triển khai staging trước, chứng minh cùng SHA/image digest, rồi mới promote production.

## 2. Checkpoint trước khi bắt đầu implementation

Checkpoint tại thời điểm audit:

- Branch: main.
- HEAD/live production: 4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b.
- Worktree có thay đổi local từ trước ở Sales Report, migration và docs.
- Flutter test pass; Nest build pass. Baseline audit từng có 2/536 test Sales Report đỏ; gate này đã được đóng ngày 13/07/2026 bằng fixture đúng strict showroom contract. Go test/vet pass.

Trước nhịp implementation phải:

1. Quyết định xử lý snapshot dirty hiện tại: commit riêng, stash an toàn hoặc hoàn tất/loại thay đổi theo chỉ đạo của Đại Ca.
2. Chụp git status, git diff --stat và SHA production/staging.
3. Xuất manifest image digest, migration status, số lượng phiên đang active và cấu hình edge cần thay.
4. Chốt owner cho API, Flutter, Go, Infra và dữ liệu.
5. Ghi intake/story/proof/decision theo docs/FEATURE_INTAKE.md và harness nếu harness DB có sẵn.

Không bắt đầu P0 trên một worktree mà baseline test chưa được hiểu rõ.

## 3. Sơ đồ phụ thuộc triển khai

| Nhánh công việc | Phụ thuộc trước | Điều kiện đóng |
| --- | --- | --- |
| HTTPS/static headers | Quyền Cloudflare + test CSP Flutter | HTTP trả redirect; HTTPS không gãy app/help/download |
| WebSocket ticket | Nest + Redis + Go hỗ trợ dual mode | Client mới dùng ticket; query JWT về 0; session revoke có hiệu lực |
| Private media | Metadata/backfill + endpoint auth + client dual-read | URL công khai bị đóng; record scope test pass; cache purge |
| Break-glass | Có ít nhất hai admin thay thế + runbook | Startup không tái tạo; tài khoản cũ disabled; MFA/audit hoạt động |
| Staging hardening | Credential rotation + Access policy | Không còn shared secret trong repo; staging không public trực tiếp |
| Dependency patch | Golden/characterization test | Audit không còn High được gọi; import/export/upload tương thích |
| Artifact tối thiểu | Image/migration manifest + rollback theo digest | Server không còn full repo; rollback vẫn thực hiện được |
| Dead-code cleanup | Reachability + telemetry + support matrix | Không giảm coverage hoặc phá platform còn hỗ trợ |

## 4. Wave 0 — Giảm phơi nhiễm khẩn cấp trong 0–24 giờ

### P0-01 — Ép HTTPS và bổ sung static security headers

**Phạm vi**

- Cloudflare production/staging.
- deploy/home-server/Caddyfile.
- Trang Flutter Web, Help, Download và static upload/public asset còn lại.

**Thực hiện**

1. Kiểm kê subdomain và xác nhận HTTPS hợp lệ.
2. Bật Always Use HTTPS tại edge cho production/staging.
3. Thêm nosniff, Referrer-Policy, frame-ancestors/X-Frame-Options phù hợp và Permissions-Policy.
4. Xây CSP ở report-only trước; ghi nhận resource bị chặn của Flutter Web/Help/Download.
5. Chuyển CSP sang enforce khi report sạch; chỉ sau đó cân nhắc HSTS includeSubDomains/preload.
6. Sửa CORS reject để không tạo 500; tắt credentials nếu xác nhận không dùng cookie auth.

**Bằng chứng nghiệm thu**

- curl HTTP mọi route chính trả 301/308 sang đúng HTTPS.
- HTTPS root/help/download/API không mixed content.
- Header test tự động cho production/staging.
- Flutter Web login/navigation, Help asset và Download manifest smoke pass.
- Không tăng lỗi CSP/CORS trong log.

**Rollback**

- Giữ cấu hình edge/Caddy trước thay đổi.
- Có thể chuyển CSP về report-only hoặc bỏ directive gây lỗi; không rollback HTTPS trừ khi có sự cố chứng chỉ được xác nhận.

### P0-02 — Ngừng ghi JWT WebSocket vào log

**Phạm vi**

- backend-go/main.go và log middleware.
- Reverse proxy/access log nếu có.

**Thực hiện**

1. Thay gin.Default bằng logger/recovery riêng; log path đã loại query hoặc redaction toàn bộ token/ticket.
2. Thêm regression test: URL chứa access_token/ticket không xuất hiện trong log.
3. Cấu hình Docker log max-size/max-file ngay trong Compose.
4. Đo query token count sau deploy.

**Bằng chứng nghiệm thu**

- Kết nối realtime vẫn thành công.
- Không có access_token, Authorization hoặc raw ticket trong log mới.
- Log rotation hoạt động và disk alert có ngưỡng.

**Rollback**

- Giữ recovery middleware độc lập; nếu structured logger lỗi, fallback logger vẫn phải bỏ RawQuery.

### P0-03 — Khoanh vùng public upload trước khi migration đầy đủ

Không tắt route public đột ngột khi client cũ còn phụ thuộc.

**Thực hiện**

1. Inventory loại media: Help public, avatar, feedback, bảo hành và orphan.
2. Dừng tạo URL đoán được cho upload mới; cấp opaque object id.
3. Thêm endpoint authenticated đọc media mới, kiểm feature + record scope.
4. Với upload mới, trả private URL/identifier; không cache public.
5. Thêm audit access và cảnh báo nếu route static cũ tiếp tục bị gọi.
6. Chuẩn bị backfill metadata cho file cũ; chưa xóa file.

**Bằng chứng nghiệm thu**

- User ngoài scope nhận 403/404 nhất quán.
- URL mới không tải được khi thiếu/expired JWT.
- Help public vẫn tải bình thường.
- Upload mới không xuất hiện qua Caddy public path.

**Rollback**

- Feature flag dual-read theo loại media; giữ mapping old path → object record.
- Không tái mở toàn bộ thư mục; rollback chỉ theo object đã xác định.

### P0-04 — Khóa cơ chế break-glass tự tái kích hoạt

**Điều kiện tiên quyết**

- Xác nhận ít nhất hai tài khoản admin bình thường có thể đăng nhập và khôi phục quyền.
- Chốt người giữ quyền phê duyệt sự cố.

**Thực hiện**

1. Thêm test chứng minh startup không tạo/nâng quyền bất kỳ user nào.
2. Loại constant hash/email và onModuleInit bootstrap khỏi đường runtime.
3. Tạo CLI/job một lần, cần secret ngoài Git, approval, TTL, MFA enrollment và reason/ticket id.
4. Deploy code trước ở staging, restart nhiều lần và chứng minh không tái tạo.
5. Production: disable tài khoản cũ, rotate credential, tăng tokenVersion và thu hồi phiên.
6. Ghi audit event cảnh báo cao cho mọi lần tạo/dùng break-glass.

**Bằng chứng nghiệm thu**

- Restart API không tạo hoặc sửa user.
- DB không còn tài khoản hard-coded active.
- Break-glass mới hết hạn tự động, có MFA và audit trail.
- Runbook khôi phục đã diễn tập.

**Rollback**

- Rollback không được khôi phục constant credential.
- Nếu mất admin access, dùng job one-time đã ký/phê duyệt, không bật lại startup bootstrap.

### P0-05 — Rotate và cô lập staging

**Thực hiện**

1. Rotate toàn bộ shared staging credential và token phiên.
2. Xóa literal khỏi README/cây hiện tại; tạo secret qua secret manager.
3. Đánh giá dọn Git history; khi rewrite phải thông báo và có kế hoạch cho mọi clone.
4. Đặt staging sau Cloudflare Access/VPN/IP allowlist.
5. Tạo account theo cá nhân, TTL/quyền tối thiểu; tắt outbound integration khi dùng sanitized DB.

**Bằng chứng nghiệm thu**

- Không thể truy cập staging nếu chưa qua Access.
- Secret scan cây Git hiện tại sạch; shared credential cũ không đăng nhập được.
- Refresh sanitized DB không tạo SUPER_ADMIN dùng chung lâu dài.

## 5. Wave 1 — Đóng Critical/High trong 1–3 ngày

### P1-01 — WebSocket ticket dùng một lần và session-aware

**Thiết kế**

- NestJS endpoint authenticated cấp ticket ngẫu nhiên 256-bit, TTL 30–60 giây.
- Redis lưu hash ticket với userId, sessionId, tokenVersion, clientId/platform, audience/scope và consumed=false.
- Go consume nguyên tử bằng Lua/GETDEL, kiểm audience/expiry/session snapshot; ticket không được reuse.
- Kết nối sống phải đóng khi nhận event revoke hoặc khi session version thay đổi.

**Rollout tương thích**

1. Go/Nest hỗ trợ song song ticket và JWT cũ, log metric không chứa giá trị.
2. Flutter Android/Windows/Web chuyển sang xin ticket trước khi connect.
3. Theo dõi tỷ lệ ticket/JWT theo app version.
4. Bắt buộc update hoặc hết cửa sổ tương thích rồi tắt access_token.
5. Rotate JWT secret/thu hồi phiên và xử lý log cũ.

**Test bắt buộc**

- Ticket hết hạn, reuse, sai client/audience, user disabled, session replaced, password reset.
- Browser reconnect, mobile background/resume, Redis restart.
- Không token/ticket trong URL log, exception, metric label.

### P1-02 — Authorization và backpressure cho realtime

**Thực hiện**

1. Định nghĩa event envelope versioned: type, eventId, occurredAt, audience, payload.
2. Mỗi publisher bắt buộc gửi audience; compiler/test fail nếu event nhạy cảm thiếu audience.
3. Go filter theo server-side claims/scope; client filter chỉ còn tối ưu UI.
4. Per-client bounded queue, writer goroutine, write deadline, ping/pong, idle timeout.
5. Chính sách queue full: drop event coalescible hoặc disconnect; metric rõ.
6. Rate limit handshake và cap connection theo IP/user; bảo vệ /ws/app-updates.
7. Readiness fail nếu Redis/subscription không sẵn sàng.

**Nghiệm thu**

- Matrix role/store/client chứng minh warranty/Sales Report không cross-scope.
- Slow-client load test không chặn client khác.
- Connection flood test đạt ngưỡng đã chốt và không làm API/realtime kiệt tài nguyên.

### P1-03 — Private media migration đầy đủ

**Mô hình đề xuất**

- Bảng MediaObject: id opaque, ownerFeature, ownerRecordId, uploaderId, contentTypeVerified, size, checksum, storageKey, visibility, createdAt, expiresAt/deletedAt.
- Endpoint đọc kiểm JWT, feature, record/store scope; có thể trả stream hoặc signed URL 30–60 giây.
- Help assets public ở namespace/bucket riêng.

**Migration**

1. Backfill metadata theo path hiện hữu, checksum và owner record; file không map được đưa vào quarantine list.
2. Client dual-read theo server response, không tự ghép path.
3. Đo static route hit theo app version.
4. Khi traffic cũ về 0 hoặc sau forced update, bỏ Caddy /uploads file_server.
5. Purge Cloudflare cache; kiểm anonymous download.
6. Sau retention window mới xóa orphan có manifest/checksum.

**Upload hardening kèm theo**

- Aggregate body cap, stream/quota, magic bytes/decode/pixel limit.
- Re-encode, strip EXIF, malware scan theo loại file.
- Cleanup partial/aborted upload.

### P1-04 — Rate limit, OTP và chống account enumeration

**Thực hiện**

- Compound bucket đồng thời theo IP, email/account hash, device đã xác minh, endpoint và global.
- Tracker không lấy trực tiếp clientId/deviceId tự khai làm khóa duy nhất.
- Login/reset/verify/VietQR/app-logs/upload có policy riêng.
- OTP dùng crypto.randomInt; hash at rest, one-time consume, attempt cap, cooldown và resend cap.
- Public auth response thống nhất; không tiết lộ email có tồn tại.
- MFA bắt buộc cho SUPER_ADMIN và break-glass.

**Nghiệm thu**

- Xoay header/query/body ID không né được rate limit.
- Timing/message giữa email tồn tại/không tồn tại nằm trong ngưỡng thống nhất.
- Không khóa nhầm luồng bình thường qua NAT; có dashboard false-positive.

### P1-05 — Chống CSV formula injection

**Thực hiện**

1. Tạo export-cell policy trung tâm.
2. Ưu tiên XLSX cell type string cho Map Vietin/Offset.
3. Nếu CSV: neutralize =, +, -, @, tab, CR, LF ở đầu cell sau canonicalization; quote RFC 4180.
4. Golden test bằng Excel/LibreOffice với malicious fixtures.

**Nghiệm thu**

- Không cell dữ liệu người dùng nào được Excel diễn giải thành formula.
- Unicode/Vietnamese, dấu phẩy, nháy kép và xuống dòng vẫn đúng.

### P1-06 — Dependency patch

**Thứ tự**

1. Multer/Nest platform và qs.
2. Nodemailer.
3. Go patch toolchain + quic-go tối thiểu 0.59.1 hoặc bản tương thích đã vá.
4. Thay xlsx bằng thư viện được duy trì.
5. Nâng Flutter direct dependency theo từng cụm, không đại nâng một lần.

**Guardrail cho xlsx replacement**

- Corpus file nhân sự/FIFO/report hợp lệ và độc hại.
- 5 MB limit hiện hữu, sheet/row/cell/formula cap.
- Parse trong worker/process bị giới hạn CPU/RAM/time.
- Golden output và Vietnamese number/date formatting.

**Nghiệm thu**

- npm audit --omit=dev không còn High trên dependency được gọi.
- govulncheck không còn called vulnerability đã biết.
- SBOM và image scan được lưu cùng release.

### P1-07 — Container, log và backup hardening

**Container**

- API runtime production deps only; non-root USER.
- read_only, tmpfs cho /tmp, cap_drop ALL, security_opt no-new-privileges.
- Migration/ops image riêng; không để script admin trong API chính.
- Pin image digest và lưu provenance/SBOM.

**Log**

- json-file max-size/max-file.
- Redaction library bắt buộc; hash email/user id, cấm token/query/raw payload.
- Sampling success log; metric cho count/duration/failure.
- Incident retention và quyền đọc log tối thiểu.

**Backup**

- umask 077, directory 700, file 600.
- Mã hóa trước khi upload/copy; key tách khỏi archive.
- Retention/immutable copy và restore drill.

**Nghiệm thu**

- API uid khác 0; rootfs write bị chặn ngoài tmpfs/volume cho phép.
- Disk/log growth test ổn định.
- Restore một backup vào môi trường cô lập, checksum và smoke pass.

**Trạng thái runtime ngày 13/07/2026**

- Đã có age identity offline trong VeraCrypt, bản container dự phòng, checksum và
  restore drill cô lập pass.
- Đã cấu hình TrueNAS off-host qua Tailscale/NFSv4.2 và job app-aware hằng ngày lúc
  02:30 `Asia/Bangkok`. Manual run `20260713-152745` tạo 1,6 GB ciphertext, hai lượt
  checksum pass, publish nguyên tử và service trả `Result=success`.
- Chưa bật auto-retention/ZFS snapshot vì đây là thao tác xóa theo thời gian cần phê
  duyệt riêng. Backup lịch sử plaintext trên production và `backup.sh` legacy vẫn là
  residual gate; không xóa hoặc migrate mù.
- Job an toàn hiện được quản lý trên host. Trước release kế tiếp phải đồng bộ contract
  này với script/runbook tracked, xác minh UID/GID/ACL sau deploy và chạy lại restore
  drill từ recovery point do scheduler tạo.

## 6. Wave 2 — Defense-in-depth trong tuần 1–2

### P2-01 — Bảo vệ app-logs

- Limit serialized context khoảng 16 KB, depth/key count và string length.
- Allowlist source/level/schemaVersion; quota user/app version/ngày.
- Reject/drop debug ở production; metric rejected count.
- Retention theo loại log; không dùng database chính như log sink vô hạn.

### P2-02 — External integration và VietQR key

- Production exact HTTPS host allowlist cho ERP, Map Vietin, eFAST, TTS và public URLs.
- Chặn redirect khác host, DNS rebinding hợp lý, response size/time cap và egress network policy.
- VietQR chỉ nhận key qua header, constant-time comparison/HMAC, key id/rotation.
- Tách read/write scope và audit không ghi key.

### P2-03 — Android hardening

- Gradle production release fail nếu thiếu release signing; không fallback debug.
- Thu hẹp ACL local keystore, rotate credential khi cần, ưu tiên secret manager/hardware-backed flow.
- allowBackup=false hoặc dataExtractionRules chính xác; test restore/migration.
- Production updater chỉ chấp nhận HTTPS và exact host/download prefix.
- Giữ kiểm package/version/SHA-256/chữ ký và FileProvider not-exported.

### P2-04 — Local development stack

- PostgreSQL/Redis bind 127.0.0.1 hoặc không publish.
- Credential qua local env/secret; Redis auth.
- Compose profile rõ cho dev/test; docs cảnh báo không dùng production.

### P2-05 — Static Help/Download

- Same-origin HTTPS URL allowlist.
- Không cho protocol-relative URL.
- CSP/Trusted Types khi khả thi; sanitize regression tests.

## 7. Wave 3 — Loại mã/tài nguyên không phục vụ runtime trong tuần 2–3

Mỗi nhóm phải là PR/commit riêng, có build/test trước và sau; không gộp với security hotfix.

### CLEAN-01 — Flutter dead subtree

**Xóa đề xuất**

- Shell cũ main_navigation_screen.
- email_domain_policy và url_utils không dùng.
- 9 tệp FIFO model/repository/provider/widget cũ và model entry.
- Hai warranty request model/entity cũ.

**Giữ**

- Scanner FIFO hiện tại.
- Media plugins cần native registration dù không có import trực tiếp.

**Validation**

- Reachability scan về 0 cho nhóm đã quyết định.
- flutter analyze, flutter test, build web/apk/windows.
- Smoke FIFO scanner, warranty, auth/navigation.

### CLEAN-02 — Demo/test helper và l10n

- Chuyển DateRangePicker demo khỏi lib sang tool/example.
- Chuyển vietnamese_amount_words test-only sang test helper nếu còn cần.
- ADR quyết định i18n:
  - Hoàn tất AppLocalizations và thay visible copy; hoặc
  - Gỡ generated files/ARB/config nếu sản phẩm Vietnamese-only.

Không để half-migration tồn tại.

### CLEAN-03 — Asset/font/dependency

- Khai báo từng asset runtime, không bundle assets/icon/source và staging/source.
- Loại hai ảnh 9Router không reference khỏi app bundle.
- Giữ 4 font weight thực dùng; archive/xóa 14 tệp còn lại sau license check.
- Bỏ cupertino_icons sau build đa nền tảng.
- So sánh APK/Web asset manifest và kích thước trước/sau.

**Mục tiêu đo được**

- Giảm tối thiểu khoảng 30 MB font tracked/bundle không dùng.
- Không còn build-source icon trong Flutter asset manifest.

### CLEAN-04 — Nest method legacy

1. Instrument retired route/method counter trong 30 ngày.
2. Xác nhận controller/service call graph và external client inventory.
3. Xóa CRUD region/area/store không caller và test chỉ bảo vệ API đã retire.
4. Giữ 410 route thêm một release window rồi mới gỡ.
5. Giữ legacy catalog sync đang có traffic cho tới replacement.

### CLEAN-05 — Minimal deploy artifact

**Thay workflow rsync toàn repo**

- Build/push API image, realtime image theo SHA và digest.
- Package migration bundle có checksum.
- Package web/help/download artifact riêng.
- Deploy compose/Caddy manifest tối thiểu.
- current release chỉ lưu manifest/digest/version, không chứa source repo.

**Không đưa lên host**

- docs ngoài runbook cần thiết, tests, mockups, n8n legacy, platform source, .claude, .github, .vscode, tool và asset nguồn.

**Rollback**

- Giữ 5 manifest release + image digest; rollback symlink/manifest và chạy health proof.
- Diễn tập rollback trước khi xóa release full-repo cũ.

### CLEAN-06 — Ops scripts và dữ liệu orphan

- Tách backend-nest/scripts vào ops image/repo area; allowlist, owner và runbook cho từng script.
- Bảng SalesReportErpOrderCache_prune_20260706_035930:
  1. tìm owner/reference;
  2. export checksum;
  3. xác nhận retention/restore;
  4. drop qua migration phê duyệt;
  5. monitor query/error sau deploy.

Không chạy drop trong cleanup code thông thường.

## 8. Wave 4 — Tách module lớn và cải thiện kiến trúc trong tuần 3–6

### ARCH-01 — User domain

Tách user.service.ts theo bounded context:

- User lifecycle/auth profile.
- Admin import.
- Organization catalog/scope.
- Feature assignment.
- Email onboarding.
- Legacy adapter.

Controller gọi application service nhỏ; policy/authorization không nằm rải trong query helper.

### ARCH-02 — Sales Report

Tách:

- ERP client/normalizer.
- Cache mapping.
- Scheduler/status refresh.
- Query/cockpit.
- Report command.
- Export.
- Realtime publisher.

Trước khi tách phải giải quyết 2 baseline test đỏ về storeCode và khóa contract bằng characterization test.

### ARCH-03 — Map Vietin, Payment và Home Summary

- Tách query, reconciliation, export, notification/delivery và presentation aggregation.
- Dùng pagination/stream export, tránh giữ dataset lớn trong memory.
- Contract test cho quantity counter và unique-order counter.

### ARCH-04 — Observability và SLO

- SLO cho API latency/error, realtime connection/delivery, scheduler lag, upload failure và storage growth.
- Dashboard theo feature/source, không dùng email làm metric label.
- Alert disk/log/upload growth, Redis disconnect, auth anomaly và backup restore age.

## 9. Ma trận validation bắt buộc

| Lớp | Test tối thiểu | Proof trước production |
| --- | --- | --- |
| Flutter | analyze, full test, build web/apk/windows | Login, upload/view media, realtime reconnect, updater smoke |
| NestJS | build, full Jest, integration auth/upload/rate/CSV | 0 baseline test đỏ hoặc waiver được ký |
| Go | test, vet, govulncheck, race/load test | Audience matrix + slow-client/flood proof |
| Web edge | HTTP/HTTPS/header/CSP/CORS automation | Production/staging route matrix |
| Media | authz matrix, migration checksum, cache test | Anonymous URL fail; dual-read success; orphan report |
| Container | image scan, SBOM, uid/rootfs/cap test | Digest pin, health/readiness, rollback drill |
| Backup | create/encrypt/restore/checksum | Restore smoke ở môi trường cô lập |
| Dependency | npm audit, govulncheck, OSV/Pub scan | Advisory report đính kèm release |
| Data | Prisma status, migration dry-run/rollback | Row count/checksum và backup trước migration |

Không ghi “pass” nếu command chưa chạy. Partial phải nêu số test, lỗi và phần chưa xác minh.

## 10. Kế hoạch release và rollback

### 10.1 Release order

1. Chốt/đóng baseline Sales Report dirty.
2. Commit nhỏ theo workstream; security hotfix tách khỏi cleanup/refactor.
3. Deploy staging cùng SHA/image digest.
4. Chạy full automated validation + smoke runtime.
5. Quan sát ít nhất một cửa sổ traffic đại diện cho auth/realtime/upload.
6. Promote đúng SHA/digest sang main/production.
7. Verify public endpoint, container, log, DB, media và version thực tế.

### 10.2 Rollback theo loại thay đổi

| Loại | Rollback |
| --- | --- |
| Edge/CSP | Cấu hình phiên bản trước; CSP chuyển report-only |
| WebSocket | Feature flag dual mode; không tái bật raw-query logging |
| Media | Dual-read theo object mapping; không mở lại toàn thư mục |
| Break-glass | One-time approved admin job; không khôi phục hard-code |
| Dependency/image | Image digest trước + schema tương thích |
| Migration DB | Backup/checksum + down/forward-fix đã diễn tập |
| Artifact deploy | Manifest/symlink release trước + health check |
| Dead code | Revert commit riêng; không trộn data migration |

### 10.3 Stop conditions

Dừng promotion nếu có một trong các điều kiện:

- HTTP vẫn trả 200, JWT/ticket còn xuất hiện trong log hoặc anonymous media còn tải được.
- Auth/realtime authorization test chưa pass.
- NestJS còn baseline test đỏ chưa được chấp thuận rõ.
- Migration checksum/backup/rollback chưa có proof.
- Runtime SHA/digest khác artifact đã kiểm tra.
- Error rate, latency, disconnect hoặc disk growth vượt ngưỡng đã chốt.

## 11. Ước lượng và thứ tự owner

| Cụm | Ước lượng tương đối | Owner chính | Mức rủi ro |
| --- | ---: | --- | --- |
| HTTPS/header/CORS | 0,5–1 ngày | Infra + Web | Cao |
| Log redaction/rotation | 0,5–1 ngày | Go + Infra | Cao |
| Break-glass/staging | 1–2 ngày | Backend + Infra/Security | Critical |
| WebSocket ticket/authz/backpressure | 3–5 ngày | Nest + Go + Flutter | Critical |
| Private media migration | 4–8 ngày | Backend + Flutter + Infra/Data | Critical |
| Rate limit/OTP/MFA | 2–4 ngày | Backend | Cao |
| CSV + dependency patch | 2–5 ngày | Backend + Go | Cao |
| Container/backup hardening | 2–4 ngày | Infra | Cao |
| Dead code/assets/artifact | 3–6 ngày | Flutter + Backend + Infra | Trung bình |
| Module split/observability | 2–4 tuần | Theo domain | Trung bình |

Ước lượng chưa gồm thời gian chờ update client cũ, phê duyệt MFA/Access, dọn cache và migration 1,51 GB media.

## 12. Deliverable của từng wave

Mỗi wave phải giao:

1. Intake/story/decision cập nhật.
2. Threat model hoặc abuse-case tương ứng.
3. Code + AppLogger đã redaction.
4. Unit/integration/e2e/load test theo ma trận.
5. Migration/rollback script và runbook.
6. SBOM/advisory report nếu đổi dependency/image.
7. Staging proof cùng SHA/digest.
8. Production verify và số liệu sau deploy.
9. TEST_MATRIX cập nhật.
10. Backlog cho follow-up/technical debt nếu còn Phase 1 tạm thời.

## 13. Definition of Done tổng

Kế hoạch chỉ được coi là hoàn tất khi:

- Không còn 4 phát hiện Critical.
- Không còn dependency High có đường gọi mà chưa có mitigation được chấp thuận.
- HTTP production/staging không phục vụ nội dung.
- JWT/ticket/secret không xuất hiện trong log mới.
- Media riêng tư không thể tải anonymous và có lifecycle.
- Startup không tự tạo/nâng quyền admin; break-glass có MFA/TTL/audit.
- Realtime authorization nằm ở server và chịu được slow client/connection flood theo ngưỡng.
- Full validation pass hoặc mọi waiver có owner, hạn xử lý và rủi ro rõ.
- Runtime artifact không còn là bản sao toàn repository.
- Dead code/tài nguyên chỉ bị xóa sau proof, không làm mất flow còn hoạt động.

## 14. Trạng thái hiện tại

- Wave 0/1/2 phía source và cấu hình local đã thực hiện theo story
  `docs/stories/SECURITY-001-opshub-hardening/`.
- Đã đóng local các cụm realtime ticket/audience/revocation/backpressure,
  private media/upload validation, break-glass, OTP/rate limit/enumeration,
  log redaction/quota, CSV, outbound redirect/size, dependency, image/container,
  backup, Android/Windows updater và minimal runtime artifact.
- Production dependency audit hiện có 0 finding; Go vulnerability scan bằng
  đúng toolchain release `go1.25.12` không có vulnerability được gọi.
- Nest build pass. Full Jest ngày 13/07/2026 pass 59/59 suite, 586/586 test sau
  khi hai fixture Sales Report được bổ sung `createdFromSiteDisplayName` theo
  strict showroom contract; runtime fallback không được khôi phục.
- Flutter analyze và các focused security/payment test pass; full test cuối và
  platform build proof được theo dõi trong
  `app-security-implementation-checklist-12072026.md`.
- Các bước cần quyền/secret/runtime và lệnh thực hiện nằm trong
  `app-security-manual-actions-12072026.md`. Không được xem các manual gate là
  đã hoàn tất chỉ vì code local đã có.
- Manual backup gate ngày 13/07/2026 đã có proof end-to-end cho **một snapshot**:
  age-encrypted artifact, server/off-host checksum, decrypt/gzip/tar validation
  và PostgreSQL 15 restore smoke đều pass. Proof DB gồm 48 bảng public, 51
  migration và 158 PK/FK constraint; container restore đã cleanup.
- Backup control vẫn ở trạng thái **partial**: production release dùng
  `backup.sh` legacy không hỗ trợ age, không có NAS/immutable target và backup cũ
  dạng rõ còn tồn tại. Trước khi bật lịch tự động phải deploy đúng script mới,
  smoke một scheduled run, xác minh chỉ có `.age`, rồi thiết lập retention và
  off-host/immutable storage. Không dùng `/srv/opshub/backups/encrypted` trên
  cùng system disk như đích disaster-recovery cuối cùng.
- Hai test Sales Report baseline đã được đóng, **không cần waiver**: focused
  batch pass 71/71 và full Nest pass 586/586. Thay đổi chỉ cập nhật fixture theo
  strict showroom contract, không thay đổi runtime Sales Report. Với regression
  tương lai, chỉ phát hành waiver tối đa 7 ngày khi có release cụ thể, owner phê
  duyệt, ticket xử lý và bằng chứng runtime không bị thay đổi.

## 15. Re-baseline ngày 14/07/2026

### Đã đóng bằng bằng chứng hiện tại

- Checkpoint trước re-audit sạch và trùng `origin/staging` tại `300dcd22...`;
  proof cuối deploy SHA `6fe62997...` qua workflow `29299619536` thành công.
- Edge live: HTTP -> HTTPS `308`; HSTS một năm có `includeSubDomains`; CSP
  enforce; staging Access response cũng có HSTS.
- API live: CORS chỉ trả ACAO cho origin staging; anonymous media/admin trả
  `401`; health trả `200`.
- Runtime staging: API/realtime/Caddy non-root, read-only rootfs, drop toàn bộ
  capability (Caddy chỉ add lại `CAP_NET_BIND_SERVICE`),
  `no-new-privileges`; private media `0770`; log rotation `10m x 5`.
- Realtime: legacy JWT tắt, 12 connection/user, container healthy, authenticated
  browser smoke pass và log tám giờ không có token/ticket query.
- Supply chain 14/07: `npm audit --omit=dev` có 0 finding; `govulncheck` có 0
  vulnerability được gọi; tracked tree không có private key thật (chuỗi PEM
  duy nhất là placeholder trong tài liệu).
- Validation HEAD: Nest build pass, 60/60 suite và 596/596 test; Go test/vet
  pass; platform security contract pass; Flutter analyze không có issue.
- Backup TrueNAS timer enabled/active; lần gần nhất `Result=success`, checksum
  các artifact mã hóa pass và publish hoàn tất.

### Gate còn mở, không được tự suy diễn là đã đóng

- Production vẫn chạy image legacy: API/Caddy root, rootfs ghi được, chưa drop
  capabilities. Cần promotion có maintenance window và rollback digest.
- Production private media/access-log/retention/backfill được ghi nợ theo quyết
  định của Đại Ca vì staging không có dữ liệu.
- Cần hai admin cá nhân + MFA/recovery, secret rotation và realtime
  replay/session-revoke/authenticated-load smoke bằng tài khoản test riêng.
- Backup plaintext lịch sử, retention và ZFS snapshot/immutability cần inventory
  cùng phê duyệt trước mọi cleanup phá huỷ.
