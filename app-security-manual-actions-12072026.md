# Việc bảo mật Đại Ca cần tự thực hiện

> Code local đã chuẩn bị nhưng Culi **không** tự đổi Cloudflare, secret, dữ liệu hay runtime. Không dán password/token/PFX/age private key vào Git, chat, ticket, ảnh chụp hoặc command history. Thực hiện staging trước, ghi ticket/người duyệt/thời gian/SHA cho từng bước.

## 0. Checkpoint và stop condition

Trên **đúng production host**, trước mọi thay đổi, tự tìm release/env đang dùng.
Không giả định `/srv/opshub/current`: workflow production đặt symlink chuẩn tại
`/home/ubuntu/phongvu-opshub/current`, còn `/srv/opshub` là vùng dữ liệu.

Chạy block chỉ-đọc sau. Block chạy trong subshell nên lỗi kiểm tra **không đóng
phiên SSH hiện tại**. Nó không in nội dung env; nếu không xác định duy nhất được
release hoặc env thì chỉ subshell dừng, không chạy Compose:

```bash
(
set -euo pipefail

mapfile -t release_candidates < <(
  {
    printf '%s\n' "/home/$(id -un)/phongvu-opshub/current"
    printf '%s\n' /home/ubuntu/phongvu-opshub/current
    docker ps --format '{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null || true
    find /home -maxdepth 4 -type l -path '*/phongvu-opshub*/current' -print 2>/dev/null || true
  } | awk 'NF && !seen[$0]++'
)

CURRENT_DIR=''
for candidate in "${release_candidates[@]}"; do
  if [ -f "$candidate/deploy/home-server/docker-compose.home.yml" ]; then
    CURRENT_DIR="$candidate"
    break
  fi
done

if [ -z "$CURRENT_DIR" ]; then
  echo 'STOP: chưa tìm thấy release chứa docker-compose.home.yml.' >&2
  echo 'Các Compose project/container hiện có:' >&2
  docker compose ls 2>/dev/null || true
  docker ps --format 'table {{.Names}}\t{{.Label "com.docker.compose.project.working_dir"}}\t{{.Label "com.docker.compose.project.config_files"}}' 2>/dev/null || true
  exit 1
fi

mapfile -t env_candidates < <(
  find /srv /home -maxdepth 5 -type f -name env -path '*opshub*' -print 2>/dev/null |
    awk 'NF && !seen[$0]++'
)
OPSHUB_ENV_FILE=''
if [ -f /srv/opshub/env ]; then
  OPSHUB_ENV_FILE=/srv/opshub/env
elif [ "${#env_candidates[@]}" -eq 1 ]; then
  OPSHUB_ENV_FILE="${env_candidates[0]}"
else
  echo 'STOP: không xác định duy nhất được production env file.' >&2
  printf 'Env candidate: %s\n' "${env_candidates[@]:-<không có>}" >&2
  exit 1
fi

export CURRENT_DIR OPSHUB_ENV_FILE
cd "$CURRENT_DIR"
printf 'Current release: %s\n' "$(readlink -f "$CURRENT_DIR")"
if [ -f release-manifest.json ]; then
  sed -n 's/.*"sourceCommit": "\([^"]*\)".*/Source commit: \1/p' release-manifest.json
else
  printf 'Source commit: legacy release, lấy từ tên thư mục release ở dòng trên\n'
fi
printf 'Env file: %s (mode %s)\n' \
  "$OPSHUB_ENV_FILE" "$(stat -c '%a' "$OPSHUB_ENV_FILE")"
docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml images --format json
docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml ps
)
```

Nếu block dừng, **không tự tạo env mới và không chọn đại staging env**. Gửi lại
chỉ phần path/container được in ra; không gửi nội dung file env.

- [x] Đã lưu checkpoint runtime ngày 13/07/2026: release
  `4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b`; API image
  `sha256:fe5daac14144ba56b95676fd86dbb66a69e2f1eb1ec67d50b14522f06d209025`;
  realtime image
  `sha256:3b3cdf217045a9603a9efb3548f4f38a0b950f28c651ffe619b05aef18aa068d`.
- [x] Có backup mã hóa + checksum + restore drill đã biết khỏe; TrueNAS off-host và
  scheduler hằng ngày đã chạy thử thành công. Vẫn còn gate riêng cho script legacy,
  backup plaintext cũ và retention/snapshot.
- [x] Hai test Sales Report baseline đã được đóng bằng fixture đúng contract; không cần waiver cho gate này.
- [ ] Dừng ngay nếu anonymous đọc được private media, ticket replay pass, API chạy root, backup không mã hóa hoặc runtime SHA lệch artifact.

### 0.1 Hai test Sales Report: ưu tiên sửa fixture, không waive mù

Lệnh xác nhận focused hiện tại:

```powershell
Set-Location backend-nest
npm test -- --runInBand `
  src/sales-reports/sales-report-erp.service.spec.ts `
  src/sales-reports/sales-reports.service.spec.ts
```

Kết quả đóng gate ngày 13/07/2026: focused batch pass 71/71 và full Nest pass
59/59 suite, 586/586 test. Hai fixture đã được bổ sung
`createdFromSiteDisplayName` cho CP01/CP62 theo product contract tại
`docs/product/sales-report.md`; runtime strict showroom source không thay đổi.
Không cần phát hành waiver cho baseline này.

Chỉ dùng waiver tạm nếu chưa kịp sửa test và **không** coi waiver là test pass.
Waiver phải ghi đủ: SHA release, hai tên test/line, expected-vs-actual, product
contract được duyệt, xác nhận không phải security regression, người duyệt, ngày
hết hạn tối đa 7 ngày, ticket sửa fixture và stop condition. Nếu batch deploy có
thay đổi runtime Sales Report nhưng chưa có product owner duyệt strict mapping,
không được waive: phải tách batch hoặc dừng deploy.

## 1. GitHub Environment: Windows signing

### 1.1 Trạng thái đã kiểm tra ngày 13/07/2026

- Secret source nằm tại `D:\OpsHub-Secrets-2026`; không đọc/in nội dung PFX,
  password, JKS, SSH private key hoặc hai JSON lên terminal/chat.
- Kiểm tra ngày 13/07/2026 cho thấy `D:` là USB FAT32 và `icacls` báo private file
  không có permission. USB chỉ cắm khi cần làm giảm mạnh exposure, nhưng FAT32
  không cung cấp ACL; chỉ coi đây là offline key vault khi toàn volume đã bật
  BitLocker To Go/mã hóa tương đương và USB được kiểm soát vật lý. Nếu chưa mã
  hóa, phải mã hóa hoặc chuyển private artifact sang NTFS/encrypted secret store
  trước khi tiếp tục. Không tin nội dung README cũ về ACL trên chính ổ `D:`.
- Hai vault JSON đều có đủ 12 entry, không có entry rỗng.
- GitHub Environment `production` và `staging` đã tồn tại; bốn Windows PFX/password
  secret đã có từ 22/06/2026. Không upload lại chỉ để "cho chắc".
- Hai Environment variable signer pin đã được Đại Ca cấu hình và Culi đọc lại
  từ GitHub lúc 11:51 ngày 13/07/2026; giá trị khớp public certificate tương ứng.
- Public certificate production/staging có hạn đến 22/06/2029. Fingerprint:
  - production: `505BFCE24E474483D4956102AC4EEF842D3E643C663A1A200B4705E7490BCF16`
  - staging: `1BE124CCBD3CB609F1CD0F9DADE5F53ECAAD2B3978914F4E295E4AF9CEE43BF7`
- `checksums-sha256.csv` hiện stale ở `finalize-opshub-secret-permissions.ps1`
  và hai `*-secrets.generated.json` do các file này được cập nhật sau lúc tạo
  manifest. PFX/CER/JKS/deploy key cốt lõi vẫn khớp checksum đã ghi. Không xóa
  hoặc refresh JSON cho tới khi đã lưu password manager và Đại Ca duyệt cleanup.

### 1.2 Mapping chính xác

Production Environment:

- Variable: `WINDOWS_UPDATE_SIGNER_SHA256`
- Secret: `WINDOWS_SIGNING_PFX_BASE64`
- Secret: `WINDOWS_SIGNING_PFX_PASSWORD`

Staging Environment:

- Variable: `WINDOWS_STAGING_UPDATE_SIGNER_SHA256`
- Secret: `WINDOWS_STAGING_SIGNING_PFX_BASE64`
- Secret: `WINDOWS_STAGING_SIGNING_PFX_PASSWORD`

### 1.3 Kiểm lại public certificate, không cần password

```powershell
$SecretDir = 'D:\OpsHub-Secrets-2026'
$Expected = @{
  'opshub-production-signing-2026.cer' = '505BFCE24E474483D4956102AC4EEF842D3E643C663A1A200B4705E7490BCF16'
  'opshub-staging-signing-2026.cer' = '1BE124CCBD3CB609F1CD0F9DADE5F53ECAAD2B3978914F4E295E4AF9CEE43BF7'
}

foreach ($Name in $Expected.Keys) {
  $Cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    (Join-Path $SecretDir $Name)
  )
  try {
    $Pin = $Cert.GetCertHashString(
      [Security.Cryptography.HashAlgorithmName]::SHA256
    ).ToUpperInvariant()
    if ($Pin -ne $Expected[$Name]) { throw "Fingerprint mismatch: $Name" }
    [pscustomobject]@{ File = $Name; NotAfter = $Cert.NotAfter; SHA256 = $Pin }
  } finally {
    $Cert.Dispose()
  }
}
```

Hai dòng phải ra đúng fingerprint ở 1.1 và `NotAfter` còn hiệu lực. Không dùng
Android `.cer`; phải dùng đúng `*-signing-2026.cer` của Windows.

### 1.4 Thiết lập/kiểm lại hai GitHub Environment variable

```powershell
$Repo = 'hoanghochoi/phongvu-opshub'
$ProdPin = '505BFCE24E474483D4956102AC4EEF842D3E643C663A1A200B4705E7490BCF16'
$StagingPin = '1BE124CCBD3CB609F1CD0F9DADE5F53ECAAD2B3978914F4E295E4AF9CEE43BF7'

gh auth status
gh variable set WINDOWS_UPDATE_SIGNER_SHA256 `
  --env production --repo $Repo --body $ProdPin
gh variable set WINDOWS_STAGING_UPDATE_SIGNER_SHA256 `
  --env staging --repo $Repo --body $StagingPin

gh variable list --env production --repo $Repo
gh variable list --env staging --repo $Repo
gh secret list --env production --repo $Repo
gh secret list --env staging --repo $Repo
```

List chỉ hiển thị tên/metadata, không lộ secret value. Kết quả cần có đúng hai
variable mới và bốn Windows secret tương ứng. Không chạy
`Publish-OpsHubSecretsToGitHub.ps1` lúc này vì secret đã tồn tại; script đó upload
lại cả 12 secret mỗi môi trường.

### 1.5 Proof bắt buộc trên staging trước production

1. Chỉ sau khi security batch đã commit/push lên `staging`, để workflow
   `Deploy OpsHub Staging` chạy đúng SHA đó. Không dispatch workflow từ local
   dirty worktree vì GitHub chưa có code mới.
2. Job Windows phải qua các bước: validate pin, load PFX bằng ephemeral key,
   sign app EXE, sign installer, Defender scan và upload artifact.
3. Tải installer staging về máy kiểm thử và chạy:

```powershell
$Installer = 'C:\duong-dan\phongvu-opshub-staging-windows-setup-....exe'
$Signature = Get-AuthenticodeSignature -FilePath $Installer
$Signature | Select-Object Status, StatusMessage, SignerCertificate
if ($Signature.Status -ne 'Valid') { throw 'Staging signature is not Valid.' }
$ActualPin = $Signature.SignerCertificate.GetCertHashString(
  [Security.Cryptography.HashAlgorithmName]::SHA256
).ToUpperInvariant()
if ($ActualPin -ne '1BE124CCBD3CB609F1CD0F9DADE5F53ECAAD2B3978914F4E295E4AF9CEE43BF7') {
  throw 'Staging installer signer pin mismatch.'
}
```

4. Chỉ khi staging pass mới giữ production pin đã cấu hình và cho phép workflow
   production ký. Không dispatch production chỉ để thử PFX vì workflow này có
   deploy thật.

Rotation về sau: thêm **old + new pin** -> deploy client tin cả hai -> đổi PFX
sang cert mới -> xác nhận artifact mới -> release bắt buộc -> hết support client
cũ mới bỏ old pin. Workflow phải fail khi thiếu PFX/password/pin, signature không
`Valid`, timestamp lỗi hoặc cert không khớp pin.

## 2. Cloudflare HTTPS, Access, CSP và HSTS

1. SSL/TLS mode phải là Full (strict) hoặc contract Tunnel đã duyệt, không dùng Flexible.
2. Bật **Always Use HTTPS** hoặc Redirect Rule chỉ cho production/staging hostname.
3. Đặt staging sau Zero Trust Access/VPN; CI dùng service token riêng, không dùng account người thật.
4. Deploy Caddy report-only, smoke `/`, `/login`, `/help`, `/download`, scanner, font/icon, API và WebSocket.
5. Thu CSP violation tối thiểu một cửa sổ traffic đại diện; không đưa URL nội bộ sang collector bên thứ ba chưa duyệt.
6. Chỉ chuyển CSP enforce/HSTS sau review toàn subdomain; chưa bật preload nếu chưa có quyết định zone.

```bash
curl -sS -o /dev/null -D - http://opshub.hoanghochoi.com/
curl -sS -o /dev/null -D - https://opshub.hoanghochoi.com/
curl -sS -o /dev/null -D - http://opshub-staging.hoanghochoi.com/
```

Kỳ vọng HTTP là 301/308 đúng host, HTTPS có `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`, `Permissions-Policy`, CSP report-only và không redirect loop.

## 3. Secret, Redis và tài khoản break-glass

1. Xác nhận tối thiểu hai `SUPER_ADMIN` cá nhân đăng nhập được.
2. Rotate Redis/JWT/staging credential trong secret manager; cập nhật Nest + Go đồng thời.
3. Recreate theo thứ tự Redis -> API -> realtime; không rollback bằng Redis không password.
4. Dùng CLI dưới đây từ one-shot maintenance container hoặc `backend-nest/` có `DATABASE_URL`.

Disable account dùng chung cũ:

```powershell
npm run security:disable-account-access -- `
  --email "tai-khoan-can-vo-hieu@example.com" `
  --ticket "INC-YYYY-NNN" `
  --approved-by "ma-nguoi-duyet" `
  --confirm DISABLE_ACCOUNT_AND_REVOKE_SESSIONS
```

Phát hành reset token khẩn cấp tối đa 15 phút:

```powershell
npm run security:issue-emergency-admin-reset -- `
  --email "admin-da-duyet@example.com" `
  --ticket "INC-YYYY-NNN" `
  --approved-by "ma-nguoi-duyet" `
  --ttl-minutes 10 `
  --confirm ISSUE_ONE_TIME_RESET
```

Gửi token qua kênh bí mật; kiểm `AppLog.source=SecurityEmergencyAccess`, login mới pass và session cũ fail. Chi tiết: `docs/runbooks/emergency-admin-access.md`.

## 4. Private media: dry-run, backfill, cutover, rollback

Giữ nguyên shell đã chạy thành công ở Bước 0, hoặc thiết lập lại bằng đúng hai
path đã xác minh tại Bước 0 (không dùng path ví dụ nếu host khác):

```bash
export CURRENT_DIR=/home/ubuntu/phongvu-opshub/current
export OPSHUB_ENV_FILE=/srv/opshub/env
test -f "$CURRENT_DIR/deploy/home-server/docker-compose.home.yml"
test -f "$OPSHUB_ENV_FILE"
cd "$CURRENT_DIR"
compose=(docker compose --env-file "$OPSHUB_ENV_FILE" \
  -f deploy/home-server/docker-compose.home.yml)
```

### 4.1 Audit và dry-run

```bash
"${compose[@]}" --profile maintenance run --rm maintenance \
  npm run security:audit-private-media -- --strict

"${compose[@]}" --profile maintenance run --rm maintenance \
  npm run security:migrate-private-media -- --strict --limit 100
```

Lưu JSON report vào kho nội bộ an toàn. So sánh số avatar/warranty/feedback, missing file/owner, orphan và dung lượng. Dry-run không sửa reference.

### 4.2 Apply theo batch

Chạy backup mã hóa trước, sau đó:

```bash
"${compose[@]}" --profile maintenance run --rm maintenance \
  npm run security:migrate-private-media -- \
  --apply --strict --limit 100 \
  --ticket SEC-YYYY-NNN \
  --approved-by MA-NGUOI-DUYET \
  --confirm MIGRATE_PRIVATE_MEDIA_V1
```

Sau mỗi batch chạy audit, smoke đúng owner/showroom/admin và anonymous 404. Script re-encode ảnh, tạo metadata/checksum, đổi reference nhưng **không xóa file legacy**.

### 4.3 Cutover

1. Theo dõi access log `/uploads/*` theo app version cho đến khi client legacy về 0 hoặc đã force-update.
2. Xóa `handle_path /uploads/*` khỏi Caddy ở một change riêng, validate/reload, purge đúng cache prefix.
3. Kiểm anonymous `/uploads/...` và `/api/media/:id` đều không trả ảnh; đúng scope `/api/media/:id` vẫn pass.
4. Chỉ dọn orphan sau retention + backup + approval; không dùng lệnh xóa tay không manifest.

Rollback reference nếu phải quay client/API nhưng vẫn giữ file private:

```bash
"${compose[@]}" --profile maintenance run --rm maintenance \
  npm run security:rollback-private-media -- \
  --apply --ticket SEC-YYYY-NNN --approved-by MA-NGUOI-DUYET \
  --confirm ROLLBACK_PRIVATE_MEDIA_REFERENCES_V1
```

## 5. Backup encryption và restore drill

### 5.0 Trạng thái đã hoàn thành ngày 13/07/2026

- USB secret vault đã chuyển vào VeraCrypt; hai vòng remount/hash và bản container dự
  phòng đều pass. Plaintext trên USB đã được format theo xác nhận của Đại Ca.
- Backup age-encrypted ban đầu và restore drill cô lập đã pass; PostgreSQL khôi phục
  được 48 bảng public, 51 Prisma migration và 158 constraint; uploads archive không
  có path traversal.
- TrueNAS độc lập đã có dataset/export `/mnt/mainpool/opshub-backups`; `hoang-n8n`
  mount NFSv4.2 tại `/mnt/truenas/opshub-backups` qua Tailscale.
- Job `/usr/local/sbin/opshub-backup-to-truenas` mã hóa database, persistent data,
  `/srv/opshub/env` và deployed release; kiểm checksum hai đầu rồi publish nguyên tử.
  Manual run `20260713-152745` pass và timer đang chạy hằng ngày 02:30
  `Asia/Bangkok` với jitter tối đa 15 phút.

Gate còn mở, không tự động xử lý:

1. `/srv/opshub/backups` còn khoảng 1,4 GB backup lịch sử plaintext; chỉ xóa/migrate
   sau khi Đại Ca phê duyệt danh sách và recovery point thay thế.
2. Chưa bật retention/ZFS snapshot; cần duyệt policy dung lượng và thao tác expiry.
3. Share thử `/mnt/mainpool/backups/hoang-n8n` còn tồn tại; chỉ xóa sau phê duyệt.
4. Job an toàn hiện là host-managed; cần đưa contract tương ứng vào release chính thức
   và proof lại sau deploy.
5. TrueNAS UI hiện dùng HTTP. Không tạo/dùng API key cho tới khi có HTTPS hợp lệ;
   TrueNAS 25.04+ sẽ revoke API key được trình qua HTTP.

### 5.1 Tạo age identity ngoài production host

Cài `age` từ module chính thức trên một máy quản trị an toàn. Máy Windows hiện có
Go nhưng chưa có `age-keygen`; cài bản đã pin, không cần quyền admin:

```powershell
go install filippo.io/age/cmd/...@v1.3.0
$AgeBin = Join-Path (go env GOPATH) 'bin'
$AgeKeygen = Join-Path $AgeBin 'age-keygen.exe'
$Age = Join-Path $AgeBin 'age.exe'
if (-not (Test-Path $AgeKeygen) -or -not (Test-Path $Age)) {
  throw 'age installation did not produce age.exe and age-keygen.exe.'
}
& $Age --version
```

Sau đó tạo private identity. Lệnh sẽ in public recipient nhưng không được
chụp/gửi nội dung private key:

Nếu USB `D:` chưa mã hóa thì không dùng private identity vừa tạo trên đó. Có hai
lựa chọn: bật BitLocker To Go cho toàn USB rồi giữ key như offline master, hoặc
tạo working copy trong thư mục NTFS local, khóa inheritance như sau:

Quy trình BitLocker To Go an toàn cho USB đã có dữ liệu:

1. Tạo một bản sao đã kiểm checksum vào storage **đã mã hóa** khác; không format
   USB và không bắt đầu encryption khi chưa có bản sao phục hồi.
2. Trong File Explorer, right-click ổ `D:` -> **Turn on BitLocker**.
3. Chọn unlock bằng password mạnh, duy nhất; lưu password trong password manager.
4. Lưu Recovery Key ở một nơi khác USB `D:`; không gửi key vào chat/ticket/repo.
5. Vì USB đã từng chứa secret, chọn **Encrypt entire drive**, không chọn used-space
   only; chọn compatible/removable-drive mode nếu wizard hỏi.
6. Giữ USB cắm ổn định tới khi hoàn tất; không bật automatic unlock cho offline
   vault. Xác minh bằng PowerShell Administrator:

```powershell
manage-bde -status D:
```

Chỉ tiếp tục khi có `Fully Encrypted`, `100%`, `Protection On`. Nếu encryption
bị gián đoạn hoặc recovery key chưa được lưu ở nơi thứ hai thì dừng.

#### Windows Home: dùng VeraCrypt file container thay BitLocker

Máy quản trị hiện là Windows Home Single Language nên Microsoft không cung cấp
BitLocker Drive Encryption/BitLocker To Go UI. Không ép `manage-bde -on`. Dùng
VeraCrypt stable `1.26.29` theo quy trình sau:

1. Mở `https://veracrypt.io/en/Downloads.html`, tải **EXE Installer (x64 and
   ARM64)**. Không dùng mirror/quảng cáo tìm từ search engine.
2. Trước khi chạy installer, kiểm chữ ký:

```powershell
$Installer = Join-Path $env:USERPROFILE 'Downloads\VeraCrypt Setup 1.26.29.exe'
$Signature = Get-AuthenticodeSignature -FilePath $Installer
$Signature | Select-Object Status, StatusMessage,
  @{Name='Subject';Expression={$_.SignerCertificate.Subject}},
  @{Name='NotAfter';Expression={$_.SignerCertificate.NotAfter}}
if ($Signature.Status -ne 'Valid') { throw 'VeraCrypt installer signature is not Valid.' }
if ($Signature.SignerCertificate.Subject -notmatch 'IDRIX') {
  throw 'Unexpected VeraCrypt installer signer.'
}
```

3. Cài VeraCrypt, giữ các default driver/integration; không bật system encryption.
4. Mở VeraCrypt -> **Create Volume** -> **Create an encrypted file container** ->
   **Standard VeraCrypt volume**.
5. Chọn file mới `D:\opshub-offline-vault.hc`. Không chọn file/thư mục secret đang
   tồn tại vì wizard sẽ overwrite path được chọn.
6. Chọn AES, hash mặc định được VeraCrypt đề xuất, volume size `2 GB`, không chọn
   Dynamic. FAT32 host có giới hạn file và không hỗ trợ dynamic sparse container;
   2 GB đủ cho key vault nhưng không dùng chứa production database backup lớn.
7. Nhập password dài/duy nhất từ password manager; không đưa password vào command
   line, screenshot, clipboard history hay chat. PIM để `0` nếu không quản lý một
   giá trị PIM riêng; không dùng keyfile ở vòng đầu để tránh mất dependency.
8. Chọn filesystem `NTFS`, di chuyển chuột ngẫu nhiên trong wizard rồi Format.
9. Trong VeraCrypt, chọn drive letter `V:`, **Select File** container vừa tạo,
   **Mount**, nhập password. Không bật cache password/auto-mount.
10. Copy dữ liệu nhưng chưa xóa source:

```powershell
$Source = 'D:\OpsHub-Secrets-2026'
$Target = 'V:\OpsHub-Secrets-2026'
robocopy $Source $Target /E /COPY:DAT /DCOPY:DAT /R:1 /W:1
if ($LASTEXITCODE -ge 8) { throw "Robocopy failed: $LASTEXITCODE" }

$SourceFiles = Get-ChildItem $Source -Recurse -File
$Problems = foreach ($File in $SourceFiles) {
  $Relative = $File.FullName.Substring($Source.Length).TrimStart('\')
  $Copy = Join-Path $Target $Relative
  if (-not (Test-Path -LiteralPath $Copy)) {
    "missing: $Relative"
    continue
  }
  if ((Get-FileHash $File.FullName -Algorithm SHA256).Hash -ne
      (Get-FileHash $Copy -Algorithm SHA256).Hash) {
    "hash mismatch: $Relative"
  }
}
if ($Problems) { $Problems; throw 'Encrypted copy verification failed.' }
"Verified encrypted copy: $($SourceFiles.Count) files"
```

11. Dismount `V:`, rút/cắm lại USB, mount lại container và chạy lại hash check.
    Copy file `.hc` sang một storage thứ hai; container copy vẫn là ciphertext.
12. **Dừng tại đây.** Chỉ xóa plaintext `D:\OpsHub-Secrets-2026` sau khi hai lần
    mount, hash check và bản sao container thứ hai đều pass, và Đại Ca phê duyệt
    thao tác xóa. Với flash storage, không tuyên bố secure erase tuyệt đối; nếu USB
    từng thất lạc/chia sẻ thì rotate key thay vì chỉ xóa file.

```powershell
$AgeDir = Join-Path $env:USERPROFILE 'OpsHub-Private\backup-age'
New-Item -ItemType Directory -Force -Path $AgeDir | Out-Null
$Me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
icacls $AgeDir /inheritance:r | Out-Null
icacls $AgeDir /grant:r "${Me}:(OI)(CI)(F)" 'NT AUTHORITY\SYSTEM:(OI)(CI)(F)' | Out-Null

& $AgeKeygen -o (Join-Path $AgeDir 'opshub-backup-age-2026.key')
& $AgeKeygen -y (Join-Path $AgeDir 'opshub-backup-age-2026.key') |
  Set-Content -NoNewline (Join-Path $AgeDir 'opshub-backup-age-2026.recipient.txt')

icacls (Join-Path $AgeDir 'opshub-backup-age-2026.key')
```

Key đã tạo dưới `D:\OpsHub-Secrets-2026\backup-age` chưa dùng để mã hóa backup.
Nếu USB chưa mã hóa, chưa upload recipient này lên server; bật mã hóa toàn USB
hoặc tạo cặp mới trong NTFS trước. Nếu BitLocker To Go đã bật và USB được giữ
offline/kiểm soát vật lý thì có thể giữ cặp hiện tại làm offline identity.

Lưu private `.key` vào password manager/offline encrypted backup rồi hạn chế ACL.
Chỉ public recipient dạng `age1...` được chuyển sang server. Sau khi hoàn tất các
task Codex cần đọc thư mục này, chạy script finalize ACL theo phê duyệt của Đại Ca;
script sẽ loại quyền sandbox khỏi secret directory.

### 5.2 Chuẩn bị production host

Trên server, cài `age`, kiểm NAS/backup mount tồn tại và không dùng fallback local
ngoài ý muốn:

```bash
sudo apt-get update
sudo apt-get install -y age
age --version
findmnt -T /mnt/truenas/opshub-backups
test -d /mnt/truenas/opshub-backups
```

Nếu `findmnt` không chứng minh đúng storage dự kiến thì dừng. Mở env bằng
`sudoedit /srv/opshub/env`, thêm/cập nhật bằng public recipient đã tạo:

```dotenv
OPSHUB_BACKUP_ROOT=/mnt/truenas/opshub-backups
BACKUP_AGE_RECIPIENT=age1...public-recipient...
BACKUP_ALLOW_UNENCRYPTED=false
```

Không đưa private key lên server. Sau khi lưu:

```bash
sudo chmod 0640 /srv/opshub/env
sudo chown root:ubuntu /srv/opshub/env
```

Chỉ dùng group thực tế đang vận hành nếu không phải `ubuntu`; kiểm trước bằng
`stat -c '%U:%G %a %n' /srv/opshub/env`.

### 5.3 Tạo và kiểm backup mã hóa

Lệnh backup chỉ đọc PostgreSQL/uploads/private-media và ghi một thư mục backup
mới; không restore vào production:

```bash
CURRENT_DIR=/home/ubuntu/phongvu-opshub/releases/4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b
BACKUP_SCRIPT="$CURRENT_DIR/deploy/home-server/backup.sh"

test -f "$BACKUP_SCRIPT"
grep -q 'BACKUP_AGE_RECIPIENT' "$BACKUP_SCRIPT"
grep -q '^umask 077$' "$BACKUP_SCRIPT"
grep -q 'sha256sum' "$BACKUP_SCRIPT"

set -a
source /srv/opshub/env
set +a
BACKUP_ROOT="${OPSHUB_BACKUP_ROOT:?Missing OPSHUB_BACKUP_ROOT}"
BACKUP_MOUNT="$(findmnt -no TARGET -T "$BACKUP_ROOT")"
test -n "$BACKUP_MOUNT"
test "$BACKUP_MOUNT" != / # không cho scheduled backup rơi vào system disk

cd "$CURRENT_DIR"
start_epoch=$(date +%s)
bash "$BACKUP_SCRIPT" /srv/opshub/env
BACKUP_DIR="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 \
  -type d -name '20??????-??????' -printf '%T@ %p\n' | sort -nr | awk 'NR==1 {$1=""; sub(/^ /,""); print}')"
test -n "$BACKUP_DIR"
printf 'Backup directory: %s\n' "$BACKUP_DIR"
printf 'Backup duration seconds: %s\n' "$(( $(date +%s) - start_epoch ))"

test "$(stat -c '%a' "$BACKUP_DIR")" = 700
find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%m %s %f\n' | sort
grep -Fx 'encryption=age' "$BACKUP_DIR/manifest.txt"
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.age' -size +0c -print
(cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS)
```

Các `grep` trên là fail-closed gate, không phải kiểm tra trang trí. Production
release `4e1ced4...` ngày 13/07/2026 không pass gate vì là script legacy; không
được chạy lại cho tới khi release chứa script backup mới đã deploy và verify.
Đồng thời phải thay `/mnt/truenas/opshub-backups` bằng storage mount đã được
`findmnt` chứng minh; system disk `/srv/opshub/backups/encrypted` chỉ là staging
tạm cho snapshot manual, không phải đích scheduled/disaster-recovery cuối cùng.

Pass khi directory `0700`, file `0600`, artifact có `.age`, checksum đều `OK`,
có `postgres.sql.gz.age` và có archive uploads/private-media nếu thư mục nguồn
tồn tại. Lưu path, thời gian, SHA256SUMS và image/release SHA vào ticket nội bộ.

### 5.4 Restore drill trên máy cô lập, tuyệt đối không chạy ở production

Copy nguyên thư mục backup đã mã hóa sang máy test. Kiểm checksum **trước** giải
mã, sau đó stream SQL thẳng vào PostgreSQL 15 tạm để tránh lưu SQL rõ trên disk:

```bash
cd /secure/opshub-restore-drill/20YYYYMMDD-HHMMSS
sha256sum -c SHA256SUMS

AGE_IDENTITY=/secure/offline/opshub-backup-age-2026.key
test -f "$AGE_IDENTITY"
age --decrypt -i "$AGE_IDENTITY" postgres.sql.gz.age | gzip -t

RESTORE_NAME=opshub-restore-drill
read -r -p 'Original POSTGRES_USER (không gửi vào chat): ' RESTORE_DB_USER
read -r -s -p 'Temporary restore DB password: ' RESTORE_DB_PASSWORD; echo
docker run -d --name "$RESTORE_NAME" \
  -e POSTGRES_USER="$RESTORE_DB_USER" \
  -e POSTGRES_PASSWORD="$RESTORE_DB_PASSWORD" \
  -e POSTGRES_DB=opshub_restore postgres:15-alpine
until docker exec "$RESTORE_NAME" pg_isready -U "$RESTORE_DB_USER"; do sleep 2; done

age --decrypt -i "$AGE_IDENTITY" postgres.sql.gz.age | gzip -dc | \
  docker exec -i "$RESTORE_NAME" psql -X -v ON_ERROR_STOP=1 \
    -U "$RESTORE_DB_USER" -d opshub_restore
docker exec "$RESTORE_NAME" psql -X -v ON_ERROR_STOP=1 \
  -U "$RESTORE_DB_USER" -d opshub_restore -c '\\dt'
docker exec "$RESTORE_NAME" psql -X -At \
  -U "$RESTORE_DB_USER" -d opshub_restore \
  -c 'SELECT count(*) FROM "_prisma_migrations";'
```

Restore file archive vào directory test riêng:

```bash
mkdir -p restored-files
for encrypted in uploads.tar.gz.age private-media.tar.gz.age; do
  [ -f "$encrypted" ] || continue
  age --decrypt -i "$AGE_IDENTITY" "$encrypted" | tar -tzf - >/dev/null
  age --decrypt -i "$AGE_IDENTITY" "$encrypted" | tar -xzf - -C restored-files
done
find restored-files -type f | wc -l
```

### 5.5 Proof thực tế ngày 13/07/2026 và phần còn mở

- VeraCrypt vault: 23/23 file khớp SHA-256 sau copy và sau remount; bản container
  thứ hai mount/restore thành công. USB đã format và chỉ nhận lại container mã
  hóa cùng checksum.
- Production cài `age 1.1.1`; env giữ public recipient, cấm unencrypted fallback
  và có checkpoint `/srv/opshub/env.pre-age-20260713-071253` cùng checkpoint
  shell-quote riêng. Private identity không rời volume `V:`.
- Backup `/srv/opshub/backups/encrypted/20260713-071520` có directory `0700`,
  file `0600`, checksum pass trên server và bản off-host. Không còn `.sql`,
  `.sql.gz` hoặc `.tar.gz` rõ trong snapshot này.
- Restore PostgreSQL 15 cô lập pass với 48 bảng public, 51 migration, 158 PK/FK
  constraint và kích thước khoảng 406 MB. Upload tar stream pass 858 member/762
  file; container restore đã xóa và Docker Desktop đã trả về trạng thái dừng.
- Production release `4e1ced4...` có `backup.sh` legacy và lần chạy đầu đã sinh
  plaintext; plaintext của đúng snapshot này đã mã hóa rồi xóa. Không phát hiện
  cron/timer gọi script. **Không bật lịch backup** trước khi deploy script mới.
- `/srv/opshub/backups` vẫn còn backup lịch sử dạng rõ và không có NAS/network
  mount. Việc xóa/mã hóa lịch sử là destructive migration cần ticket, inventory,
  checksum và phê duyệt riêng; bản off-host hiện tại chưa phải immutable copy.

Smoke ít nhất: schema/tables hiện đủ, `_prisma_migrations` có row, các count nghiệp
vụ quan trọng hợp lý, file count > 0 nếu source có file và mở thử được một ảnh.
Ghi RPO (khoảng cách `created_at` đến lúc sự cố giả định), RTO từ bắt đầu restore
đến smoke pass, checksum, owner/người duyệt và ngày drill. Sau khi lưu proof, chỉ
xóa container test cô lập bằng `docker rm -f opshub-restore-drill`; không chạy
lệnh cleanup này trên production.

## 6. Host/container ACL và deploy staging

- [ ] Đặt `OPSHUB_RUNTIME_UID/GID` đúng owner ba volume; không `chmod 777`.
- [ ] `private-media` mode `0770` hoặc hẹp hơn và không mount Caddy.
- [ ] API/realtime/Caddy có `ReadonlyRootfs=true`, `CapDrop=ALL`, `no-new-privileges`; API UID khác 0.
- [ ] Docker log có `max-size/max-file`, disk không tăng vô hạn.
- [ ] Runtime release có `release-manifest.json`, SHA và image digest trùng CI.

```bash
docker inspect opshub-api-1 --format '{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{json .HostConfig.CapDrop}}'
docker inspect opshub-realtime-1 --format '{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{json .HostConfig.CapDrop}}'
curl -fsS https://opshub-staging.hoanghochoi.com/api/health
curl -fsS https://opshub-staging.hoanghochoi.com/health
```

Smoke bắt buộc: login đúng/sai/enumeration, reset OTP attempt, ticket replay, revoke session đóng WS, cross-store event không tới, slow client không làm nghẽn, media scope matrix, upload invalid/oversize, Help/Download, Windows/Android update.

## 7. Những việc chưa thể tự động

| Việc | Vì sao cần Đại Ca | Điều kiện đóng |
| --- | --- | --- |
| Cloudflare HTTPS/Access/CSP/HSTS | Cần quyền zone và quyết định policy | Header/live smoke + rollback export |
| Rotate JWT/Redis/staging credential | Culi không được biết hoặc phát tán secret | Session cũ fail, service khỏe, log sạch |
| Disable break-glass/MFA | Cần xác minh admin thay thế và provider | 2 admin cá nhân + audit + MFA |
| Media backfill/cutover | Sửa dữ liệu/cache/client live | Dry-run, backup, batch audit, legacy hit=0 |
| age key/restore drill | Hoàn tất manual ngày 13/07/2026; private key vẫn ngoài repo/host | Encrypted backup + off-host checksum + restore proof đã pass |
| Windows/Android signing | Cần PFX/keystore và quyền GitHub Environment | Signed artifact + fingerprint/pin proof |
| Container build/deploy | Docker daemon local hiện không dùng được; production write cần lệnh riêng | staging cùng SHA/digest + smoke |
| CSP/HSTS enforce | Có thể làm hỏng Flutter/subdomain | report window sạch + owner phê duyệt |
| MFA implementation | Chưa chốt provider/UX/recovery | product decision + threat-model riêng |

Runbook infra chi tiết bổ sung: `deploy/home-server/SECURITY_HARDENING_RUNBOOK.md`.
