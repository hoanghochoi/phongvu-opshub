# Checklist triển khai bảo mật OpsHub

> Story: `SECURITY-001`
> Nguồn: `app-improve-implement-plan-12072026.md`
> Checkpoint: `main` tại `4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b`
> Quy ước: `[x]` đã có bằng chứng local; `[ ]` chưa đóng; `[M]` cần quyền/secret/runtime của Đại Ca; `[D]` tách follow-up có lý do.

## A. Checkpoint và phạm vi

- [x] Ghi branch, HEAD, upstream và dirty-worktree trước khi sửa.
- [x] Ghi Harness intake `54`, lane high-risk, story `SECURITY-001`.
- [x] Bảo vệ batch Sales Report/migration/docs có trước; không sửa contract showroom của batch đó.
- [x] Không tạo branch, commit, push hoặc deploy.
- [x] Mỗi workstream có test/contract và đường rollback tương ứng.
- [x] Exact diff audit cuối cùng và `git diff --check` sau khi mọi tài liệu đã chốt.

## B. Edge, auth và secret

- [x] Caddy có redirect dựa trên `X-Forwarded-Proto`, `nosniff`, Referrer/Frame/Permissions Policy và CSP report-only.
- [x] CORS production fail sạch, không dùng credential cookie, trust-proxy được giới hạn.
- [M] Bật Cloudflare Always Use HTTPS và đặt staging sau Access/VPN.
- [M] Chỉ chuyển CSP/HSTS sang enforce sau live smoke và quan sát report.
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
- [M] Staging replay/close-session/load smoke với Redis và client thật.

## D. Private media và upload

- [x] Media mới lưu private bằng UUID opaque + metadata owner/scope/checksum/size.
- [x] `GET /media/:id` bắt JWT, kiểm feature/record/showroom/owner; deny trả 404 chung, `no-store`, `nosniff`.
- [x] Private path containment, file size và SHA-256 được kiểm trước stream.
- [x] Upload dùng temp-disk bounded, aggregate cap, magic/decode/pixel check, Sharp rotate/re-encode/strip metadata và atomic mode `0600`.
- [x] Warranty/avatar/feedback rollback orphan nếu DB update lỗi và dọn media cũ khi thay thế thành công.
- [x] Flutter chỉ gắn bearer cho đúng API origin + `/media/`; từ chối external, userinfo và `/uploads` legacy.
- [x] Có audit, dry-run/apply migration và rollback-reference scripts; apply bắt ticket/approver/confirmation.
- [x] Backup gồm `private-media`; Caddy không mount thư mục private.
- [M] Chạy dry-run/backfill live, theo dõi legacy hit, đóng `/uploads`, purge cache và orphan cleanup sau retention.

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
- [x] Age identity nằm offline trong VeraCrypt; encrypted backup, checksum và restore
  drill cô lập đã pass.
- [x] TrueNAS off-host đã mount qua Tailscale/NFSv4.2; job app-aware hằng ngày đã chạy
  thử thành công, publish nguyên tử và không còn staging/`.incoming`.
- [M] Sau deploy vẫn phải kiểm UID/GID/ACL thật, proof installer staging đã ký, xử lý
  backup plaintext cũ và phê duyệt retention/ZFS snapshot trước khi đóng SEC-12.

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
- [x] Web release, Android staging debug và Windows debug compile pass; signed release vẫn là manual CI gate.
- [x] Prisma format/generate và Nest build pass.
- [x] Nest focused security: 171/171; outbound: 124/124; log/scope: 215/215.
- [x] Full Nest: 59/59 suite, 586/586 test. Hai fixture Sales Report đã được bổ sung `createdFromSiteDisplayName` theo strict showroom contract; không khôi phục runtime fallback.
- [x] Go test/vet/govulncheck, npm production audit, platform contract, YAML, shell, PowerShell và Compose config pass.
- [x] `git diff --check` và invariant grep (JWT query/RawQuery/break-glass/full-repo rsync/raw email log) pass.
- [x] Exact changed-file review cuối: 112 file tracked thay đổi + 44 mục untracked, đều nằm trong phạm vi bảo mật/tài liệu hoặc baseline Sales Report đã ghi nhận; không có build artifact/secret/signing key lọt vào worktree.
- [M] Build container thật, deploy staging cùng SHA/digest, migration/backfill và live smoke.
- [M] Promote production chỉ sau khi mọi stop condition manual đã đóng.
- [x] Hướng dẫn manual được ghi trong `app-security-manual-actions-12072026.md` và runbook liên quan.
