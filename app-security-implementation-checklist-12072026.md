# Checklist triển khai bảo mật OpsHub

> Story: `SECURITY-001`
> Nguồn: `app-improve-implement-plan-12072026.md`
> Checkpoint audit ban đầu: `main` tại `4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b`
> Checkpoint trước re-audit 14/07/2026: `staging` tại `300dcd22...`, sạch và
> trùng `origin/staging`. Proof runtime cuối của re-audit: `6fe62997...`.
> Quy ước: `[x]` đã có bằng chứng local; `[ ]` chưa đóng; `[M]` cần quyền/secret/runtime của Đại Ca; `[D]` tách follow-up có lý do; `[W]` đã đóng bằng waiver tạm thời có owner, control bù và ngày rà soát.

## A. Checkpoint và phạm vi

- [x] Ghi branch, HEAD, upstream và dirty-worktree trước khi sửa.
- [x] Ghi Harness intake `54`, lane high-risk, story `SECURITY-001`.
- [x] Bảo vệ batch Sales Report/migration/docs có trước; không sửa contract showroom của batch đó.
- [x] Nhịp audit ban đầu không tạo branch, commit, push hoặc deploy; các nhịp
  remediation sau đó đã commit/push/deploy `staging` theo từng checkpoint.
- [x] Mỗi workstream có test/contract và đường rollback tương ứng.
- [x] Exact diff audit cuối cùng và `git diff --check` sau khi mọi tài liệu đã chốt.

## B. Edge, auth và secret

- [x] Caddy có redirect dựa trên `X-Forwarded-Proto`, `nosniff`, Referrer/Frame/Permissions Policy và CSP report-only.
- [x] CORS production fail sạch, không dùng credential cookie, trust-proxy được giới hạn.
- [x] Cloudflare có redirect HTTP -> HTTPS `308` chỉ cho hai hostname OpsHub;
  staging vẫn nằm sau Cloudflare Access.
- [x] CSP đã chuyển sang enforce sau smoke Home/Help/Download/WebSocket; HSTS
  `max-age=31536000; includeSubDomains` có trên staging, production và cả
  response Cloudflare Access.
- [x] Xóa startup break-glass hard-code; restart không tự tạo/mở khóa/nâng quyền admin.
- [x] CLI reset admin khẩn cấp dùng token 256-bit, lưu hash, TTL tối đa 15 phút và audit; CLI disable khóa account + revoke session.
- [M] Xác nhận hai admin cá nhân thay thế, disable account dùng chung cũ và kích hoạt MFA khi provider được chốt.
- [x] OTP dùng crypto RNG, attempt/cooldown/one-time; response public chống account enumeration.
- [x] Compound throttling dùng IP/principal đã chuẩn hóa, không tin caller ID làm khóa duy nhất.
- [x] Staging refresh không đưa password vào command line; example chỉ còn placeholder.
- [M] Rotate JWT/Redis/staging/shared credentials ở maintenance window.

## C. Realtime

- [x] Nest cấp ticket một lần, hash trong Redis, TTL 45 giây, gắn session/scope/feature.
- [x] Go consume ticket nguyên tử bằng `GETDEL`; legacy JWT mặc định tắt và dùng secret rollback riêng.
- [x] Flutter 7 consumer dùng ticket; không còn `access_token` trong WebSocket URL.
- [x] Session revoke publish fail-closed và Go đóng connection tương ứng.
- [x] Audience được tính phía server cho event nhạy cảm; client không tự khai quyền.
- [x] Queue bounded, deadline, ping/pong, idle/read limit, handshake/connection cap.
- [x] `/ready` phụ thuộc Redis; log query được redaction.
- [x] Go `test`, `vet`, race/slow-client/audience tests và `govulncheck` bằng toolchain `go1.25.12` pass.
- [x] Staging client thật kết nối WebSocket thành công; runtime xác nhận
  `WS_ALLOW_LEGACY_JWT=false`, `WS_MAX_CONNECTIONS_PER_USER=12`, realtime
  healthy và log 8 giờ không có `access_token=`/`ticket=`.
- [M] Ticket replay, close-session và authenticated load smoke vẫn cần một
  phiên test có credential riêng; unit/race/slow-client test không thay thế
  hoàn toàn proof live này.

## D. Private media và upload

- [x] Media mới lưu private bằng UUID opaque + metadata owner/scope/checksum/size.
- [x] `GET /media/:id` bắt JWT, kiểm feature/record/showroom/owner; deny trả 404 chung, `no-store`, `nosniff`.
- [x] Private path containment, file size và SHA-256 được kiểm trước stream.
- [x] Upload dùng temp-disk bounded, aggregate cap, magic/decode/pixel check, Sharp rotate/re-encode/strip metadata và atomic mode `0600`.
- [x] Warranty/avatar/feedback rollback orphan nếu DB update lỗi và dọn media cũ khi thay thế thành công.
- [x] Flutter chỉ gắn bearer cho đúng API origin + `/media/`; từ chối external, userinfo và `/uploads` legacy.
- [x] Có audit, dry-run/apply migration và rollback-reference scripts; apply bắt ticket/approver/confirmation.
- [x] Backup gồm `private-media`; Caddy không mount thư mục private.
- [D] Staging dry-run không có dữ liệu nên không chứng minh được migration.
  Theo quyết định của Đại Ca, access-log `/uploads/*`, backfill, retention,
  purge cache và orphan cleanup được ghi nợ để chạy khi promote production;
  không dùng staging rỗng làm proof giả.

## E. Input, log và outbound integration

- [x] CSV export dùng helper chung chống formula injection và có regression test.
- [x] App log upload có source allowlist, quota, byte/depth/key limits và context policy.
- [x] Flutter log redaction che secret, email, phone, customer name, URL query; local Windows log vẫn giữ contract.
- [x] Nest log dùng user ID/fingerprint, safe error và không ghi email/query/raw input trực tiếp.
- [x] MAP/eFAST, ERP và TTS dùng redirect `manual`; MAP/TTS có timeout + bounded streamed response.
- [x] Production external URL validation bắt HTTPS/exact host, cấm embedded credential.
- [x] VietQR external key chỉ nhận header, so sánh constant-time và có rotation contract.
- [x] Help/Download URL policy same-origin HTTPS, chặn protocol-relative/cross-origin/path traversal.

## F. Dependency, container, backup và updater

- [x] `@nestjs/platform-express`, Nodemailer, Hono, qs và quic-go đã nâng; production `npm audit --omit=dev` = 0 finding.
- [x] `xlsx` chuyển sang official SheetJS CE `0.20.3` tarball; parser/export focused tests pass.
- [x] Node/Go/Alpine/Postgres/Redis/Caddy image đã pin digest; Go build pin `1.25.12`.
- [x] API runtime prune dev deps, non-root, read-only rootfs, drop capabilities; Prisma CLI/scripts chỉ ở one-shot `ops` target.
- [x] Redis bắt password; database/cache local chỉ bind loopback; Docker log rotation có giới hạn.
- [x] Backup fail-closed khi thiếu age recipient, `umask 077`, lock, partial-dir atomic, checksum và safe retention.
- [x] Android release không fallback debug signing, backup/device-transfer tắt.
- [x] Updater bắt HTTPS/exact host/path, không follow redirect, có size/time/checksum và Windows Authenticode signer pin.
- [x] Windows workflow bắt PFX + password + signer SHA-256; timestamp/signature/pin mismatch đều fail.
- [x] GitHub Environment production/staging đã có Windows signing secret; hai signer
  SHA-256 variable đã được cấu hình và đọc lại khớp public certificate.
- [x] Installer staging của SHA `af32413074c6fd71cc4afe7b15f647877ce2c5b4`
  khớp checksum công khai, Authenticode `Valid`, signer pin staging khớp và Defender pass.
- [W] Tạm dùng certificate tự quản lý do chưa có ngân sách public CA code-signing;
  waiver `SEC-WIN-SELF-SIGNED-20260713`, owner Đại Ca, rà soát lại 13/10/2026.
- [x] Age identity nằm offline trong VeraCrypt; encrypted backup, checksum và restore
  drill cô lập đã pass.
- [x] TrueNAS off-host đã mount qua Tailscale/NFSv4.2; job app-aware hằng ngày đã chạy
  thử thành công, publish nguyên tử và không còn staging/`.incoming`.
- [x] Staging runtime đã kiểm trực tiếp: API `1000:1000`, realtime `app`, Caddy
  `1000:1000`; cả ba `ReadonlyRootfs=true`, `CapDrop=ALL`,
  `no-new-privileges`; `private-media` mode `0770`; Docker log `10m x 5`.
- [x] Re-audit production ngày 14/07 phát hiện trước promotion rằng env live còn
  thiếu `OPSHUB_RUNTIME_UID/GID` và `REDIS_PASSWORD`; workflow đã được sửa để
  fail-closed, kiểm password tối thiểu 32 ký tự, chuẩn bị writable volume bằng
  UID/GID non-root, recreate Redis cùng API/realtime/Caddy và rollback cả Redis.
- [x] Preflight production đã chuẩn bị trực tiếp không lộ secret:
  `OPSHUB_RUNTIME_UID/GID=1000`, Redis password 64 ký tự; Compose + Caddy config
  của SHA `962257a9...` pass với env live. Encrypted backup on-demand
  `20260714-121022` publish xong, 6/6 checksum pass, không còn `.incoming` hay
  local staging directory và toàn bộ container production vẫn healthy.
- [M] Production vẫn dùng image legacy: API/Caddy chạy root, rootfs ghi được và
  chưa drop capabilities. Env/volume live phải qua preflight mới trước khi
  promote đúng SHA rồi kiểm lại UID/GID/ACL;
  đồng thời inventory/xử lý backup plaintext cũ và phê duyệt retention/ZFS
  snapshot trước khi đóng SEC-12 production.

## G. Runtime artifact và cleanup

- [x] Workflow dùng `scripts/build-runtime-release.mjs`, không rsync toàn repository.
- [x] Artifact CI chỉ lấy tracked allowlist và từ chối dirty runtime file; local reviewed-untracked preview sinh manifest SHA-256: 234 file, 11,093,245 byte, 0 test/env/xlsx/keystore.
- [x] Chỉ publish `docs/help/assets`; không publish lại HTML/content Help tĩnh như runtime song song.
- [x] Runtime artifact chỉ mang 3 font + 2 logo thật sự được backend dùng; không mang `data/user_temp.xlsx` hoặc import mẫu.
- [D] Xóa dead Dart subtree/asset khỏi app bundle: tách batch sau reachability + platform build proof để không trộn security hotfix.
- [D] Retire method/table legacy: cần telemetry 30 ngày, owner và migration/backup approval.

## H. Validation và release

- [x] `flutter analyze --no-pub` pass; focused security/payment tests pass.
- [x] Full Flutter pass: 515 test, 1 skipped, 0 error.
- [x] Web release, Android staging debug và Windows debug compile pass; signed Windows
  staging release đã qua CI, checksum/signer-pin/Defender và máy kiểm thử thực.
- [x] Prisma format/generate và Nest build pass.
- [x] Nest focused security: 171/171; outbound: 124/124; log/scope: 215/215.
- [x] Full Nest: 59/59 suite, 586/586 test. Hai fixture Sales Report đã được bổ sung `createdFromSiteDisplayName` theo strict showroom contract; không khôi phục runtime fallback.
- [x] Go test/vet/govulncheck, npm production audit, platform contract, YAML, shell, PowerShell và Compose config pass.
- [x] `git diff --check` và invariant grep (JWT query/RawQuery/break-glass/full-repo rsync/raw email log) pass.
- [x] Exact changed-file review cuối: 112 file tracked thay đổi + 44 mục untracked, đều nằm trong phạm vi bảo mật/tài liệu hoặc baseline Sales Report đã ghi nhận; không có build artifact/secret/signing key lọt vào worktree.
- [x] Deploy staging proof cuối đúng SHA
  `962257a96310e6d56b13bba4e25d0ad5ff0a8b17`; workflow
  `29307636667` pass. SSH proof xác nhận API/realtime/Caddy non-root,
  read-only, `CapDrop=ALL`, log `10m x 5`; origin health `200` và CSP/HSTS/static
  security headers enforce.
- [x] Live edge/CORS/anonymous smoke ngày 14/07/2026: HTTP `308`; CSP/HSTS
  enforce; origin lạ không có ACAO; origin staging được phép; anonymous
  `/api/media/:id` và `/api/admin/quick-action-links` trả `401`.
- [M] Proof runtime còn lại chỉ gồm ticket replay/session-revoke/authenticated
  load, hai-admin/MFA, credential rotation và các gate production đã ghi nợ.
- [M] Promote production chỉ sau khi mọi stop condition manual đã đóng.
- [x] Hướng dẫn manual được ghi trong `app-security-manual-actions-12072026.md` và runbook liên quan.
