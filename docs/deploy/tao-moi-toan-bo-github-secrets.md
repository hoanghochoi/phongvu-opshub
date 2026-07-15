# Tạo mới toàn bộ GitHub Environment Secrets

Tài liệu này áp dụng khi không thể lấy lại bất kỳ giá trị secret cũ nào của
`hoanghochoi/phongvu-opshub` và phải tạo lại toàn bộ từ đầu.

Không lưu secret, file khóa hoặc mật khẩu trong repo. Tất cả lệnh tạo khóa phải
được chạy ngoài thư mục dự án.

## Quyết định đã chốt cho OpsHub

- Giữ nguyên application ID `com.example.phongvu_opshub`.
- Tạo Android production keystore mới hoàn toàn.
- Không hỗ trợ cập nhật đè từ APK production cũ.
- Hơn 10 người dùng Android hiện tại sẽ gỡ bản cũ và cài lại bản mới.
- Triển khai theo nhóm nhỏ: 1-2 máy thử nghiệm trước, sau đó mới triển khai cho
  những người còn lại.
- Không cần đổi application ID và không cần cho hai bản chạy song song.

## Cảnh báo bắt buộc trước khi bắt đầu

### Android production sẽ không cập nhật đè được bản cũ

Ứng dụng production hiện dùng application ID:

```text
com.example.phongvu_opshub
```

APK production mới được ký bằng keystore mới sẽ không thể cài đè lên APK đang
cài nếu APK cũ được ký bằng khóa khác. Android sẽ báo lỗi tương tự:

```text
INSTALL_FAILED_UPDATE_INCOMPATIBLE
```

Quy trình đã chọn:

1. Người dùng ghi nhớ tài khoản đang đăng nhập.
2. Gỡ bản OpsHub cũ.
3. Tải APK mới từ trang `/download`.
4. Cài lại ứng dụng.
5. Đăng nhập và smoke các chức năng chính.

Dữ liệu nghiệp vụ trên backend không bị xóa. Token đăng nhập, cache và dữ liệu
chỉ lưu cục bộ có thể mất khi gỡ ứng dụng.

Workflow production hiện đặt `APP_FORCE_UPDATE=true` và đặt minimum supported
build bằng build mới. Nếu phát hành ngay, app cũ sẽ yêu cầu cập nhật nhưng không
thể cài đè APK ký bằng khóa mới. Vì vậy phải chuẩn bị thông báo gỡ/cài lại trước
production cutover.

### Windows sẽ có danh tính ký mới

Certificate Windows mới không làm hỏng dữ liệu ứng dụng, nhưng Windows hoặc
SmartScreen có thể cảnh báo lại vì publisher certificate đã thay đổi. Máy người
dùng cần tin cậy public certificate mới.

## Mục tiêu

Sau khi hoàn tất:

- `staging` có bộ Android, Windows, SSH và Tailscale secrets riêng;
- `production` có bộ Android, Windows, SSH và Tailscale secrets riêng;
- production và staging không dùng chung private signing key;
- GitHub Actions chỉ lấy secret sau khi environment protection được thông qua;
- repository secrets cũ được xóa sau khi cả hai environment đã chạy thành công;
- các file khóa mới có ít nhất hai bản sao lưu được mã hóa.

## Thứ tự thực hiện

1. Giữ workflows production và staging ở trạng thái disabled.
2. Chuẩn bị thư mục khóa ngoài repo và password manager.
3. Tạo toàn bộ staging secrets.
4. Nhập staging environment secrets.
5. Enable và smoke test staging.
6. Tạo toàn bộ production secrets.
7. Nhập production environment secrets.
8. Kiểm tra production SSH/Tailscale bằng static-only deploy.
9. Kiểm tra APK production mới trên máy thử nghiệm.
10. Thông báo kế hoạch gỡ/cài lại cho người dùng.
11. Chạy full production deploy.
12. Xóa repository secrets cũ và thu hồi credential cũ.

## 1. Chuẩn bị nơi lưu khóa

### Tạo thư mục ngoài repo

Mở PowerShell:

```powershell
$SecretDir = Join-Path $env:USERPROFILE 'OpsHub-Secrets-2026'
New-Item -ItemType Directory -Force $SecretDir | Out-Null
Set-Location $SecretDir
```

Không tạo thư mục này bên trong:

```text
C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub
```

### Chuẩn bị password manager

Tạo một mục riêng tên:

```text
OpsHub GitHub Actions Secrets 2026
```

Mỗi secret phải được lưu bằng đúng tên GitHub. Không lưu mật khẩu trong file
`.txt`, `.ps1`, ghi chú không mã hóa hoặc ảnh chụp màn hình.

### Hàm tạo mật khẩu ngẫu nhiên

Chạy trong PowerShell:

```powershell
function New-OpsHubPassword {
  $bytes = [byte[]]::new(32)
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  [Convert]::ToBase64String($bytes).
    TrimEnd('=').
    Replace('+', '-').
    Replace('/', '_')
}
```

Mỗi lần cần mật khẩu mới:

```powershell
New-OpsHubPassword
```

Lưu ngay kết quả vào password manager. Mỗi keystore/PFX nên có mật khẩu riêng.

## 2. Tìm công cụ Android

Tìm `keytool.exe`:

```powershell
$KeyTool = @(
  (Get-Command keytool.exe -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue);
  (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe');
  $(if ($env:JAVA_HOME) {
      Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    });
) | Where-Object {
  $_ -and (Test-Path -LiteralPath $_)
} | Select-Object -First 1

if (-not $KeyTool) {
  throw 'Không tìm thấy keytool.exe. Cần cài Android Studio hoặc JDK.'
}

& $KeyTool -help | Select-Object -First 2
```

Tìm `apksigner.bat`:

```powershell
$SdkRoot = @(
  $env:ANDROID_HOME;
  $env:ANDROID_SDK_ROOT;
  (Join-Path $env:LOCALAPPDATA 'Android\Sdk');
) | Where-Object {
  $_ -and (Test-Path -LiteralPath $_)
} | Select-Object -First 1

if (-not $SdkRoot) {
  throw 'Không tìm thấy Android SDK.'
}

$ApkSigner = Get-ChildItem "$SdkRoot\build-tools" `
  -Filter apksigner.bat `
  -Recurse |
  Sort-Object FullName -Descending |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $ApkSigner) {
  throw 'Không tìm thấy apksigner.bat trong Android SDK build-tools.'
}
```

## 3. Tạo Android staging keystore

Tạo hai mật khẩu khác nhau và lưu trong password manager:

- `ANDROID_STAGING_KEYSTORE_PASSWORD`
- `ANDROID_STAGING_KEY_PASSWORD`

Tạo keystore:

```powershell
Set-Location $SecretDir

& $KeyTool -genkeypair -v `
  -keystore .\opshub-staging-2026.jks `
  -storetype JKS `
  -alias opshub-staging-2026 `
  -keyalg RSA `
  -keysize 4096 `
  -sigalg SHA256withRSA `
  -validity 10000 `
  -dname 'CN=PhongVu OpsHub Staging, OU=Internal Apps, O=Phong Vu, C=VN'
```

Khi `keytool` hỏi:

1. Nhập `ANDROID_STAGING_KEYSTORE_PASSWORD`.
2. Nhập `ANDROID_STAGING_KEY_PASSWORD` cho alias.
3. Không dùng mật khẩu production.

Kiểm tra:

```powershell
& $KeyTool -list -v `
  -keystore .\opshub-staging-2026.jks `
  -alias opshub-staging-2026
```

Tạo base64:

```powershell
$StagingJksBase64 = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes(
    (Join-Path $SecretDir 'opshub-staging-2026.jks')
  )
)

$StagingJksBase64.Length
```

Nhập vào staging environment:

| Secret | Giá trị |
| --- | --- |
| `ANDROID_STAGING_KEYSTORE_BASE64` | `$StagingJksBase64` |
| `ANDROID_STAGING_KEYSTORE_PASSWORD` | Mật khẩu keystore staging |
| `ANDROID_STAGING_KEY_ALIAS` | `opshub-staging-2026` |
| `ANDROID_STAGING_KEY_PASSWORD` | Mật khẩu private key staging |

## 4. Tạo Android production keystore mới

Tạo hai mật khẩu mới, khác staging:

- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

Tạo keystore:

```powershell
Set-Location $SecretDir

& $KeyTool -genkeypair -v `
  -keystore .\opshub-production-2026.jks `
  -storetype JKS `
  -alias opshub-production-2026 `
  -keyalg RSA `
  -keysize 4096 `
  -sigalg SHA256withRSA `
  -validity 10000 `
  -dname 'CN=PhongVu OpsHub Production, OU=Internal Apps, O=Phong Vu, C=VN'
```

Kiểm tra:

```powershell
& $KeyTool -list -v `
  -keystore .\opshub-production-2026.jks `
  -alias opshub-production-2026
```

Ghi lại `SHA256` certificate fingerprint trong password manager. Đây là danh
tính ký Android production mới và phải được giữ ổn định cho mọi bản sau.

Tạo base64:

```powershell
$ProductionJksBase64 = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes(
    (Join-Path $SecretDir 'opshub-production-2026.jks')
  )
)

$ProductionJksBase64.Length
```

Nhập vào production environment:

| Secret | Giá trị |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `$ProductionJksBase64` |
| `ANDROID_KEYSTORE_PASSWORD` | Mật khẩu keystore production |
| `ANDROID_KEY_ALIAS` | `opshub-production-2026` |
| `ANDROID_KEY_PASSWORD` | Mật khẩu private key production |

Không xóa file production JKS sau khi nhập GitHub. Đây là khóa bắt buộc cho mọi
bản cập nhật Android trong tương lai.

## 5. Tạo SSH deploy keys mới

Workflow hiện tại ghi private key trực tiếp ra file và không mở khóa bằng
passphrase. Vì vậy SSH deploy key phải không có passphrase, nhưng phải:

- dùng riêng cho GitHub Actions;
- production và staging dùng hai key khác nhau;
- chỉ cấp cho đúng deploy user;
- chỉ cho phép truy cập VPS qua Tailscale/firewall.

Tạo key:

```powershell
Set-Location $SecretDir

ssh-keygen -t ed25519 `
  -C 'github-actions-opshub-production-2026' `
  -f .\opshub-production-deploy-2026 `
  -N ''

ssh-keygen -t ed25519 `
  -C 'github-actions-opshub-staging-2026' `
  -f .\opshub-staging-deploy-2026 `
  -N ''
```

### Cấp production public key

Xác định production Tailscale IP:

```bash
tailscale ip -4
```

Trên máy ASUS:

```powershell
$ProductionHost = 'THAY_BANG_PRODUCTION_TAILSCALE_IP'
$ProductionPublicKey = (
  Get-Content .\opshub-production-deploy-2026.pub -Raw
).Trim()

$ProductionPublicKey |
  ssh "ubuntu@$ProductionHost" `
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'
```

Kiểm tra:

```powershell
ssh `
  -o IdentitiesOnly=yes `
  -i .\opshub-production-deploy-2026 `
  "ubuntu@$ProductionHost" `
  'id && hostname'
```

Nếu không còn bất kỳ quyền SSH nào vào VPS, phải dùng console của nhà cung cấp,
Tailscale SSH hoặc quyền truy cập vật lý để thêm public key. Không có cách tạo
GitHub secret nào tự cấp quyền vào VPS nếu public key chưa được authorize.

### Cấp staging public key

Xác minh lại staging Tailscale IP thay vì tin cố định IP cũ:

```powershell
$StagingHost = 'THAY_BANG_STAGING_TAILSCALE_IP'
$StagingPublicKey = (
  Get-Content .\opshub-staging-deploy-2026.pub -Raw
).Trim()

$StagingPublicKey |
  ssh "hhh@$StagingHost" `
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'
```

Kiểm tra:

```powershell
ssh `
  -o IdentitiesOnly=yes `
  -i .\opshub-staging-deploy-2026 `
  "hhh@$StagingHost" `
  'id && hostname'
```

### Nhập private keys vào GitHub

Lấy toàn bộ nội dung private key:

```powershell
$ProductionSshPrivateKey = Get-Content `
  .\opshub-production-deploy-2026 -Raw

$StagingSshPrivateKey = Get-Content `
  .\opshub-staging-deploy-2026 -Raw
```

Giá trị phải gồm đủ:

```text
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
```

Nhập:

| Environment | Secret | Giá trị |
| --- | --- | --- |
| production | `OPSHUB_VPS_SSH_KEY` | `$ProductionSshPrivateKey` |
| staging | `OPSHUB_STAGING_SSH_KEY` | `$StagingSshPrivateKey` |

## 6. Xác định VPS host, port và user

Các giá trị này không phải private key, nhưng workflow hiện đọc qua
`secrets.*`, nên vẫn nhập dưới dạng environment secret.

Production:

| Secret | Giá trị |
| --- | --- |
| `OPSHUB_VPS_HOST` | Production Tailscale IPv4 hoặc MagicDNS name |
| `OPSHUB_VPS_PORT` | `22`, trừ khi SSH đã đổi cổng |
| `OPSHUB_VPS_USER` | `ubuntu`, nếu vẫn là deploy user hiện tại |

Staging:

| Secret | Giá trị |
| --- | --- |
| `OPSHUB_STAGING_VPS_HOST` | Staging Tailscale IPv4 hoặc MagicDNS name |
| `OPSHUB_STAGING_VPS_PORT` | `22`, trừ khi SSH đã đổi cổng |
| `OPSHUB_STAGING_VPS_USER` | `hhh`, nếu vẫn là deploy user hiện tại |

Kiểm tra trên từng VPS:

```bash
whoami
tailscale ip -4
sudo ss -lntp | grep ':22'
```

## 7. Tạo Tailscale OAuth clients mới

Workflow hiện dùng:

```yaml
oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
tags: tag:ci
```

Nên tạo hai OAuth clients riêng để có thể thu hồi độc lập.

### Trên Tailscale Admin Console

1. Mở trang quản trị tailnet.
2. Xác nhận `tag:ci` đã tồn tại trong policy.
3. Xác nhận policy chỉ cho `tag:ci` kết nối tới đúng VPS và cổng cần thiết.
4. Vào `Trust credentials`.
5. Tạo OAuth client cho production.
6. Cấp scope `auth_keys`.
7. Giới hạn credential vào `tag:ci`.
8. Copy Client ID và Client secret ngay khi được hiển thị.
9. Lưu hai giá trị trong password manager.
10. Lặp lại để tạo OAuth client riêng cho staging.

Nhập:

| Environment | Secret |
| --- | --- |
| production | `TS_OAUTH_CLIENT_ID` |
| production | `TS_OAUTH_SECRET` |
| staging | `TS_OAUTH_CLIENT_ID` |
| staging | `TS_OAUTH_SECRET` |

Tên secret giống nhau nhưng giá trị production và staging có thể khác nhau vì
chúng nằm trong hai environments độc lập.

## 8. Tạo Windows signing certificates mới

Tạo certificate riêng cho production và staging. Không dùng cùng private key.

### Production certificate

Tạo một mật khẩu mới trong password manager:

```text
WINDOWS_SIGNING_PFX_PASSWORD
```

Chạy:

```powershell
Set-Location $SecretDir

$ProductionWindowsCert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject 'CN=PhongVu OpsHub Production 2026' `
  -FriendlyName 'PhongVu OpsHub Production 2026' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(3)

$ProductionPfxPassword = Read-Host `
  'Nhập WINDOWS_SIGNING_PFX_PASSWORD' `
  -AsSecureString

$ProductionPfxPath = Join-Path `
  $SecretDir 'opshub-production-signing-2026.pfx'

$ProductionCerPath = Join-Path `
  $SecretDir 'opshub-production-signing-2026.cer'

Export-PfxCertificate `
  -Cert $ProductionWindowsCert `
  -FilePath $ProductionPfxPath `
  -Password $ProductionPfxPassword

Export-Certificate `
  -Cert $ProductionWindowsCert `
  -FilePath $ProductionCerPath

$ProductionWindowsCert |
  Format-List Subject, Thumbprint, NotAfter, EnhancedKeyUsageList
```

`EnhancedKeyUsageList` phải chứa `Code Signing`.

Tạo base64:

```powershell
$ProductionPfxBase64 = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes($ProductionPfxPath)
)

$ProductionPfxBase64.Length
```

Nhập vào production:

| Secret | Giá trị |
| --- | --- |
| `WINDOWS_SIGNING_PFX_BASE64` | `$ProductionPfxBase64` |
| `WINDOWS_SIGNING_PFX_PASSWORD` | Mật khẩu PFX production |

Tính SHA-256 certificate fingerprint và nhập nó dưới dạng GitHub Environment
**variable** `WINDOWS_UPDATE_SIGNER_SHA256` (không phải secret):

```powershell
$ProductionWindowsCert.GetCertHashString(
  [System.Security.Cryptography.HashAlgorithmName]::SHA256
).ToLowerInvariant()
```

### Staging certificate

Tạo mật khẩu riêng:

```text
WINDOWS_STAGING_SIGNING_PFX_PASSWORD
```

Chạy:

```powershell
$StagingWindowsCert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject 'CN=PhongVu OpsHub Staging 2026' `
  -FriendlyName 'PhongVu OpsHub Staging 2026' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(3)

$StagingPfxPassword = Read-Host `
  'Nhập WINDOWS_STAGING_SIGNING_PFX_PASSWORD' `
  -AsSecureString

$StagingPfxPath = Join-Path `
  $SecretDir 'opshub-staging-signing-2026.pfx'

$StagingCerPath = Join-Path `
  $SecretDir 'opshub-staging-signing-2026.cer'

Export-PfxCertificate `
  -Cert $StagingWindowsCert `
  -FilePath $StagingPfxPath `
  -Password $StagingPfxPassword

Export-Certificate `
  -Cert $StagingWindowsCert `
  -FilePath $StagingCerPath

$StagingWindowsCert |
  Format-List Subject, Thumbprint, NotAfter, EnhancedKeyUsageList
```

Tạo base64:

```powershell
$StagingPfxBase64 = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes($StagingPfxPath)
)

$StagingPfxBase64.Length
```

Nhập vào staging:

| Secret | Giá trị |
| --- | --- |
| `WINDOWS_STAGING_SIGNING_PFX_BASE64` | `$StagingPfxBase64` |
| `WINDOWS_STAGING_SIGNING_PFX_PASSWORD` | Mật khẩu PFX staging |

Tính fingerprint tương ứng và nhập GitHub Environment **variable**
`WINDOWS_STAGING_UPDATE_SIGNER_SHA256`:

```powershell
$StagingWindowsCert.GetCertHashString(
  [System.Security.Cryptography.HashAlgorithmName]::SHA256
).ToLowerInvariant()
```

### Cài public certificate trên máy Windows thử nghiệm

Mở PowerShell bằng quyền Administrator:

```powershell
certutil.exe -addstore -f Root `
  "$env:USERPROFILE\OpsHub-Secrets-2026\opshub-production-signing-2026.cer"

certutil.exe -addstore -f TrustedPublisher `
  "$env:USERPROFILE\OpsHub-Secrets-2026\opshub-production-signing-2026.cer"
```

Chỉ phân phối file `.cer`. Không gửi file `.pfx` hoặc mật khẩu PFX cho máy
người dùng.

## 9. Tạo và cấu hình GitHub Environments

### Staging

1. Vào repo GitHub.
2. Chọn `Settings`.
3. Chọn `Environments`.
4. Chọn hoặc tạo `staging`.
5. Trong `Deployment branches and tags`, chỉ cho branch `staging`.
6. Trong `Environment secrets`, thêm đủ:

```text
ANDROID_STAGING_KEYSTORE_BASE64
ANDROID_STAGING_KEYSTORE_PASSWORD
ANDROID_STAGING_KEY_ALIAS
ANDROID_STAGING_KEY_PASSWORD
OPSHUB_STAGING_VPS_HOST
OPSHUB_STAGING_VPS_PORT
OPSHUB_STAGING_VPS_USER
OPSHUB_STAGING_SSH_KEY
TS_OAUTH_CLIENT_ID
TS_OAUTH_SECRET
WINDOWS_STAGING_SIGNING_PFX_BASE64
WINDOWS_STAGING_SIGNING_PFX_PASSWORD
```

7. Thêm Environment variable bắt buộc
   `WINDOWS_STAGING_UPDATE_SIGNER_SHA256` bằng fingerprint SHA-256 ở bước 8.

### Production

1. Chọn hoặc tạo `production`.
2. Chỉ cho branch `main`.
3. Thêm required reviewer.
4. Chỉ bật `Prevent self-review` khi có reviewer thứ hai.
5. Thêm đủ:

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
OPSHUB_VPS_HOST
OPSHUB_VPS_PORT
OPSHUB_VPS_USER
OPSHUB_VPS_SSH_KEY
TS_OAUTH_CLIENT_ID
TS_OAUTH_SECRET
WINDOWS_SIGNING_PFX_BASE64
WINDOWS_SIGNING_PFX_PASSWORD
```

6. Thêm Environment variable bắt buộc `WINDOWS_UPDATE_SIGNER_SHA256` bằng
   fingerprint SHA-256 ở bước 8.

Không xóa repository secrets cũ tại bước này. Environment secrets cùng tên sẽ
được dùng bởi các jobs đã khai báo `environment: production` hoặc
`environment: staging`.

## 10. Kiểm tra danh sách secret

Nếu GitHub CLI đã đăng nhập:

```powershell
gh secret list `
  --env staging `
  --repo hoanghochoi/phongvu-opshub

gh secret list `
  --env production `
  --repo hoanghochoi/phongvu-opshub
```

GitHub chỉ hiện tên và thời gian cập nhật, không hiện giá trị.

Đối chiếu phải có đúng 12 secret cho staging và 12 secret cho production.

## 11. Smoke test staging

1. Enable riêng workflow `Deploy OpsHub Staging`.
2. Giữ production workflow disabled.
3. Chạy staging bằng `workflow_dispatch`.
4. Approve staging environment nếu đã cấu hình reviewer.
5. Chờ toàn bộ Android, Windows và deploy jobs thành công.

Kiểm tra:

```powershell
curl.exe -fsS `
  https://opshub-staging.hoanghochoi.com/health

curl.exe -fsS `
  https://opshub-staging.hoanghochoi.com/api/health

curl.exe -fsS `
  'https://opshub-staging.hoanghochoi.com/api/app-version?platform=android'

curl.exe -fsS `
  'https://opshub-staging.hoanghochoi.com/api/app-version?platform=windows'

curl.exe -fsS `
  https://opshub-staging.hoanghochoi.com/downloads/latest.json
```

Tải staging APK và kiểm tra signer:

```powershell
$StagingManifest = Invoke-RestMethod `
  'https://opshub-staging.hoanghochoi.com/downloads/latest.json'

$StagingApkPath = Join-Path $SecretDir 'staging-built-by-actions.apk'

Invoke-WebRequest `
  -Uri $StagingManifest.files.apk.url `
  -OutFile $StagingApkPath

& $ApkSigner verify --print-certs $StagingApkPath
```

Certificate SHA-256 phải trùng với staging keystore mới.

## 12. Kiểm tra production trước khi phát hành

### Kiểm tra kết nối không đổi app-version

Enable production workflow và chạy thủ công:

```text
skip_client_build=true
```

Đường chạy này kiểm tra Tailscale, SSH, quyền ghi static download và Caddy nhưng
không kiểm tra Android/Windows signing secrets.

Sau khi chạy:

```powershell
curl.exe -fsS https://opshub.hoanghochoi.com/download
curl.exe -fsS https://opshub.hoanghochoi.com/downloads/latest.json

curl.exe -fsS `
  'https://opshub.hoanghochoi.com/api/app-version?platform=android'

curl.exe -fsS `
  'https://opshub.hoanghochoi.com/api/app-version?platform=windows'
```

App-version không được thay đổi.

### Build thử APK production bằng key mới

Trong PowerShell, không ghi mật khẩu vào file:

```powershell
Set-Location C:\Users\ASUS1\Documents\flutter_projects\phongvu-opshub

$env:ANDROID_KEYSTORE_PATH = (
  Join-Path $SecretDir 'opshub-production-2026.jks'
)
$env:ANDROID_KEYSTORE_PASSWORD = Read-Host `
  'Nhập ANDROID_KEYSTORE_PASSWORD'
$env:ANDROID_KEY_ALIAS = 'opshub-production-2026'
$env:ANDROID_KEY_PASSWORD = Read-Host `
  'Nhập ANDROID_KEY_PASSWORD'

flutter pub get
flutter build apk `
  --release `
  --flavor production `
  --dart-define `
  'API_BASE_URL=https://opshub.hoanghochoi.com/api'
```

Kiểm tra APK:

```powershell
$ProductionApkPath = Join-Path `
  (Get-Location) `
  'build\app\outputs\flutter-apk\app-production-release.apk'

& $ApkSigner verify --print-certs $ProductionApkPath
```

Certificate SHA-256 phải trùng production keystore mới.

Xóa biến mật khẩu khỏi PowerShell sau khi build:

```powershell
Remove-Item Env:ANDROID_KEYSTORE_PATH
Remove-Item Env:ANDROID_KEYSTORE_PASSWORD
Remove-Item Env:ANDROID_KEY_ALIAS
Remove-Item Env:ANDROID_KEY_PASSWORD
```

### Kiểm tra hành vi trên thiết bị

Trên một máy đang cài bản production cũ:

1. Thử cài đè APK mới để xác nhận Android từ chối vì khác signer.
2. Ghi nhận tài khoản đang dùng.
3. Gỡ bản cũ.
4. Cài APK mới.
5. Đăng nhập lại.
6. Kiểm tra update, realtime, tải ảnh và các luồng nghiệp vụ chính.

Đây là smoke bắt buộc trước khi thông báo toàn bộ người dùng.

## 13. Full production cutover

Trước khi chạy:

- staging đã xanh;
- production static-only đã xanh;
- APK production local đã ký đúng khóa mới;
- một thiết bị đã gỡ/cài lại thành công;
- người dùng đã được thông báo về downtime và việc đăng nhập lại;
- có đường dẫn tải APK mới bên ngoài app cũ.

Sau đó:

1. Lập danh sách hơn 10 người dùng và thiết bị cần cài lại.
2. Chọn 1-2 máy thử nghiệm thuộc nhóm dễ hỗ trợ trực tiếp.
3. Gửi trước hướng dẫn: ghi nhớ tài khoản, chưa tự cập nhật đè APK.
4. Merge đúng commit đã kiểm tra vào `main`.
5. Production workflow tự chạy full deploy.
6. Approve `production` environment.
7. Theo dõi Android build, Windows build và deploy.
8. Kiểm tra `/health`, `/api/health`, app-version và download manifest.
9. Tải APK production từ server và kiểm tra signer lần cuối.
10. Trên 1-2 máy thử nghiệm: gỡ bản cũ, cài APK mới, đăng nhập và smoke.
11. Nếu nhóm thử nghiệm đạt, triển khai lần lượt cho những người còn lại.
12. Ghi nhận người đã hoàn tất để không bỏ sót thiết bị.

Đường dẫn gửi cho người dùng sau khi production deploy thành công:

```text
https://opshub.hoanghochoi.com/download
```

Không gửi trực tiếp file APK qua chat nếu có thể dùng trang tải chính thức; trang
tải giúp mọi người luôn nhận đúng bản mới nhất.

### Mẫu thông báo cho người dùng Android

```text
OpsHub có bản cài đặt mới và cần cài lại một lần do thay đổi khóa bảo mật.

1. Ghi nhớ email/tài khoản đang sử dụng.
2. Gỡ ứng dụng PhongVu OpsHub cũ.
3. Mở https://opshub.hoanghochoi.com/download
4. Tải và cài APK Android mới.
5. Đăng nhập lại và báo quản trị nếu không vào được.

Không cài đè trực tiếp lên bản cũ vì Android sẽ từ chối do khóa ký đã thay đổi.
```

## 14. Xóa repository secrets cũ

Chỉ thực hiện sau khi staging và production đều thành công.

Vào:

```text
Settings > Secrets and variables > Actions > Repository secrets
```

Xóa các repository secrets trùng tên với environment secrets.

Sau khi xóa:

1. Chạy lại staging workflow.
2. Chạy production static-only.
3. Xác nhận workflows vẫn lấy được environment secrets.

Không xóa environment secrets.

## 15. Thu hồi credential cũ

### Tailscale

- Revoke các OAuth clients cũ không còn dùng.
- Giữ hai clients mới theo tên rõ ràng production/staging.
- Kiểm tra không còn ephemeral node bất thường.

### SSH

Trên từng VPS:

```bash
cp ~/.ssh/authorized_keys \
  ~/.ssh/authorized_keys.before-opshub-2026-cleanup

nl -ba ~/.ssh/authorized_keys
```

Chỉ xóa dòng public key cũ khi đã xác định chắc chắn comment/fingerprint. Không
xóa toàn bộ `authorized_keys`, vì có thể tự khóa quyền quản trị VPS.

Kiểm tra fingerprint public key mới trên máy ASUS:

```powershell
ssh-keygen -lf .\opshub-production-deploy-2026.pub
ssh-keygen -lf .\opshub-staging-deploy-2026.pub
```

## 16. Backup bắt buộc

Backup các file:

```text
opshub-production-2026.jks
opshub-staging-2026.jks
opshub-production-signing-2026.pfx
opshub-production-signing-2026.cer
opshub-staging-signing-2026.pfx
opshub-staging-signing-2026.cer
opshub-production-deploy-2026
opshub-production-deploy-2026.pub
opshub-staging-deploy-2026
opshub-staging-deploy-2026.pub
```

Tạo checksum:

```powershell
Get-ChildItem $SecretDir -File |
  Get-FileHash -Algorithm SHA256 |
  Select-Object Path, Hash |
  Export-Csv `
    (Join-Path $SecretDir 'checksums-sha256.csv') `
    -NoTypeInformation
```

Yêu cầu tối thiểu:

- một bản trong password manager hoặc vault có mã hóa;
- một bản offline trên USB/ổ đĩa có BitLocker;
- không đặt backup trong repo, Google Drive công khai hoặc thư mục chia sẻ chung;
- kiểm tra có thể mở backup trước khi xóa bản local.

## Checklist hoàn tất

- [ ] Đã chấp nhận Android production phải gỡ/cài lại.
- [ ] Đã tạo staging Android JKS.
- [ ] Đã tạo production Android JKS.
- [ ] Đã lưu SHA-256 fingerprint của cả hai JKS.
- [ ] Đã tạo hai SSH deploy keys.
- [ ] Đã authorize và test hai SSH keys.
- [ ] Đã tạo hai Tailscale OAuth clients.
- [ ] Đã tạo hai Windows PFX/certificate.
- [ ] Đã nhập đủ 12 staging environment secrets.
- [ ] Đã nhập đủ 12 production environment secrets.
- [ ] Staging full deploy thành công.
- [ ] Production static-only thành công và không đổi app-version.
- [ ] Production APK local ký đúng certificate mới.
- [ ] Một thiết bị production đã gỡ/cài lại và smoke thành công.
- [ ] Full production deploy thành công.
- [ ] Đã xóa repository secrets cũ.
- [ ] Đã revoke credential cũ sau khi xác minh.
- [ ] Đã tạo hai bản backup khóa được mã hóa.

## Tài liệu chính thức

- Android app signing:
  <https://developer.android.com/studio/publish/app-signing>
- GitHub deployment environments:
  <https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments>
- Tailscale GitHub Action:
  <https://tailscale.com/docs/integrations/github/github-action>
- Microsoft `New-SelfSignedCertificate`:
  <https://learn.microsoft.com/en-us/powershell/module/pki/new-selfsignedcertificate>
