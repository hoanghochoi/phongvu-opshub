# Tao Lai GitHub Environment Secrets

> Nếu không còn bất kỳ secret/khóa cũ nào và chấp nhận tạo mới hoàn toàn, dùng
> tài liệu tiếng Việt:
> [`tao-moi-toan-bo-github-secrets.md`](tao-moi-toan-bo-github-secrets.md).

Tai lieu nay dung cho `hoanghochoi/phongvu-opshub` sau khi repo duoc chuyen
sang public. Khong xoa repository secrets cu cho den khi staging va production
da chay thanh cong bang environment secrets.

## Nguyen tac bat buoc

1. Tao hai GitHub Environments:
   - `production`: chi cho branch `main` deploy.
   - `staging`: chi cho branch `staging` deploy.
2. Moi truong `production` nen co required reviewer. Chi bat
   `Prevent self-review` khi co mot nguoi khac co the approve.
3. Khong dat file `.jks`, `.pfx`, private SSH key, password hoac file base64
   trong thu muc repo.
4. Luu ban goc trong password manager va it nhat mot ban backup offline duoc ma
   hoa.
5. Environment secret trung ten se duoc uu tien hon repository secret. Vi vay
   co the nhap secret moi va smoke test truoc khi xoa secret cu.

## Chuan bi PowerShell

Mo PowerShell, tao thu muc secret ngoai repo va tim `keytool.exe`:

```powershell
$SecretDir = Join-Path $env:USERPROFILE 'OpsHub-Secrets'
New-Item -ItemType Directory -Force $SecretDir | Out-Null

$KeyTool = @(
  (Get-Command keytool.exe -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue);
  (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe');
  $(if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' });
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
  Select-Object -First 1

if (-not $KeyTool) {
  throw 'Khong tim thay keytool.exe. Cai Android Studio hoac JDK truoc.'
}
```

## Danh sach secret

### Production

| Secret | Bat buoc | Nguon |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Co | Base64 cua keystore production hien tai |
| `ANDROID_KEYSTORE_PASSWORD` | Co | Mat khau keystore production hien tai |
| `ANDROID_KEY_ALIAS` | Co | Alias trong keystore production hien tai |
| `ANDROID_KEY_PASSWORD` | Co | Mat khau private key production hien tai |
| `OPSHUB_VPS_HOST` | Co | Tailscale IP hoac DNS cua production VPS |
| `OPSHUB_VPS_PORT` | Nen co | Cong SSH, thuong la `22` |
| `OPSHUB_VPS_USER` | Nen co | User deploy, hien workflow mac dinh `ubuntu` |
| `OPSHUB_VPS_SSH_KEY` | Co | Dedicated private SSH deploy key |
| `TS_OAUTH_CLIENT_ID` | Co | Tailscale OAuth client |
| `TS_OAUTH_SECRET` | Co | Tailscale OAuth client secret |
| `WINDOWS_SIGNING_PFX_BASE64` | Tuy chon | Base64 cua PFX code-signing |
| `WINDOWS_SIGNING_PFX_PASSWORD` | Co neu co PFX | Mat khau PFX |

### Staging

| Secret | Bat buoc | Nguon |
| --- | --- | --- |
| `ANDROID_STAGING_KEYSTORE_BASE64` | Co | Base64 cua staging keystore |
| `ANDROID_STAGING_KEYSTORE_PASSWORD` | Co | Mat khau staging keystore |
| `ANDROID_STAGING_KEY_ALIAS` | Co | Alias staging key |
| `ANDROID_STAGING_KEY_PASSWORD` | Co | Mat khau staging private key |
| `OPSHUB_STAGING_VPS_HOST` | Co | Hien tai la Tailscale IP cua staging VPS |
| `OPSHUB_STAGING_VPS_PORT` | Nen co | Cong SSH, thuong la `22` |
| `OPSHUB_STAGING_VPS_USER` | Nen co | Hien tai workflow mac dinh `hhh` |
| `OPSHUB_STAGING_SSH_KEY` | Co | Dedicated private SSH deploy key |
| `TS_OAUTH_CLIENT_ID` | Co | Cung OAuth client hoac client rieng cho staging |
| `TS_OAUTH_SECRET` | Co | Client secret tuong ung |
| `WINDOWS_STAGING_SIGNING_PFX_BASE64` | Tuy chon | Base64 cua staging PFX |
| `WINDOWS_STAGING_SIGNING_PFX_PASSWORD` | Co neu co PFX | Mat khau staging PFX |

## 1. Tao GitHub Environments

Tren GitHub:

1. Vao `Settings > Environments`.
2. Tao `staging`.
3. Chon `Selected branches and tags`, them branch `staging`.
4. Tao `production`.
5. Chon `Selected branches and tags`, them branch `main`.
6. Them required reviewer cho `production`.
7. Trong tung environment, chon `Add secret` de nhap cac secret dung bang tren.

Khong xoa repository secrets o giai doan nay.

## 2. Android production: khong tao key moi

OpsHub phat APK truc tiep, khong dua qua Google Play App Signing. Android chi
cho phep cai ban cap nhat khi APK moi dung cung signing key voi ban dang cai.

Vi vay bon production secrets phai duoc khoi phuc tu keystore cu:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

GitHub khong cho doc nguoc secret. Can tim file keystore goc trong backup an
toan, password manager, may build cu hoac noi da luu khi tao key lan dau.

Kiem tra keystore ung vien:

```powershell
& $KeyTool -list -v -keystore "$SecretDir\opshub-production.jks"
```

Kiem tra certificate cua APK production dang phat hanh:

```powershell
$Manifest = Invoke-RestMethod `
  'https://opshub.hoanghochoi.com/downloads/latest.json'

Invoke-WebRequest `
  -Uri $Manifest.files.apk.url `
  -OutFile "$SecretDir\current-production.apk"

$SdkRoot = @(
  $env:ANDROID_HOME;
  $env:ANDROID_SDK_ROOT;
  (Join-Path $env:LOCALAPPDATA 'Android\Sdk');
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
  Select-Object -First 1

if (-not $SdkRoot) {
  throw 'Khong tim thay Android SDK.'
}

$ApkSigner = Get-ChildItem "$SdkRoot\build-tools" `
  -Filter apksigner.bat -Recurse |
  Sort-Object FullName -Descending |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $ApkSigner) {
  throw 'Khong tim thay apksigner.bat trong Android SDK build-tools.'
}

& $ApkSigner verify --print-certs "$SecretDir\current-production.apk"
```

SHA-256 certificate digest cua APK va keystore phai trung nhau. Neu khong tim
duoc private key cu, dung cutover; tao key production moi se lam may da cai app
bao `INSTALL_FAILED_UPDATE_INCOMPATIBLE` va phai go app cu.

Khi da xac minh dung keystore:

```powershell
$Jks = Join-Path $env:USERPROFILE 'OpsHub-Secrets\opshub-production.jks'
$JksBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Jks))
$JksBase64.Length
```

Nhap `$JksBase64` vao `ANDROID_KEYSTORE_BASE64`. Gia tri phai nho hon gioi han
48 KB cua GitHub secret.

## 3. Android staging: co the tao lai

Staging dung application id rieng nen co the tao key moi. Chay ngoai thu muc
repo:

```powershell
$SecretDir = Join-Path $env:USERPROFILE 'OpsHub-Secrets'
New-Item -ItemType Directory -Force $SecretDir | Out-Null
Set-Location $SecretDir

& $KeyTool -genkeypair -v `
  -keystore opshub-staging.jks `
  -storetype JKS `
  -alias opshub-staging `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000
```

Nhap mat khau manh tu password manager khi `keytool` hoi. Sau do:

```powershell
$Jks = Join-Path $env:USERPROFILE 'OpsHub-Secrets\opshub-staging.jks'
$JksBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Jks))
```

Nhap:

- `ANDROID_STAGING_KEYSTORE_BASE64` = `$JksBase64`
- `ANDROID_STAGING_KEYSTORE_PASSWORD` = mat khau keystore
- `ANDROID_STAGING_KEY_ALIAS` = `opshub-staging`
- `ANDROID_STAGING_KEY_PASSWORD` = mat khau private key

## 4. Tao va rotate SSH deploy keys

Tao key rieng cho tung environment. Workflow hien tai khong xu ly passphrase,
nen deploy key phai khong co passphrase; bu lai, key chi duoc cap cho dung user
deploy va chi di qua Tailscale.

```powershell
$SecretDir = Join-Path $env:USERPROFILE 'OpsHub-Secrets'
Set-Location $SecretDir

ssh-keygen -t ed25519 `
  -C "github-actions-opshub-production-2026" `
  -f .\opshub-production-deploy `
  -N ''

ssh-keygen -t ed25519 `
  -C "github-actions-opshub-staging-2026" `
  -f .\opshub-staging-deploy `
  -N ''
```

Them public key moi vao VPS trong khi van giu key cu:

```powershell
Get-Content .\opshub-production-deploy.pub |
  ssh ubuntu@PRODUCTION_TAILSCALE_IP `
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'

Get-Content .\opshub-staging-deploy.pub |
  ssh hhh@100.127.127.89 `
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys'
```

Kiem tra key moi truoc khi dua vao GitHub:

```powershell
ssh -i .\opshub-production-deploy ubuntu@PRODUCTION_TAILSCALE_IP 'id && hostname'
ssh -i .\opshub-staging-deploy hhh@100.127.127.89 'id && hostname'
```

Nhap full noi dung, gom ca dong `BEGIN/END OPENSSH PRIVATE KEY`:

```powershell
Get-Content .\opshub-production-deploy -Raw
Get-Content .\opshub-staging-deploy -Raw
```

Gan vao:

- production: `OPSHUB_VPS_SSH_KEY`
- staging: `OPSHUB_STAGING_SSH_KEY`

Chi xoa public key cu khoi `authorized_keys` sau khi workflow moi da deploy
thanh cong. Truoc khi xoa, backup file:

```bash
cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.before-opshub-rotation
```

## 5. Tao lai Tailscale OAuth client

Workflow dung `tag:ci`. Trong Tailscale Admin Console:

1. Xac nhan `tag:ci` ton tai va ACL chi cho phep truy cap dung production va
   staging VPS tren cong can thiet.
2. Vao `Trust credentials`, chon `Credential`, sau do chon `OAuth`.
3. Cap scope `auth_keys` va chi chon tag `tag:ci`.
4. Chon `Generate credential`.
5. Copy Client ID va Client secret ngay khi Tailscale hien thi.
6. Nhap cung cap gia tri vao ca `production` va `staging`:
   - `TS_OAUTH_CLIENT_ID`
   - `TS_OAUTH_SECRET`

Sau khi ca hai workflow thanh cong, revoke OAuth client cu.

## 6. VPS host, port va user

Lay Tailscale IPv4 tren tung may:

```bash
tailscale ip -4
```

Production:

- `OPSHUB_VPS_HOST` = production Tailscale IPv4 hoac MagicDNS name
- `OPSHUB_VPS_PORT` = `22`, neu SSH khong doi cong
- `OPSHUB_VPS_USER` = `ubuntu`, neu server van dung user hien tai

Staging:

- `OPSHUB_STAGING_VPS_HOST` = staging Tailscale IPv4
- `OPSHUB_STAGING_VPS_PORT` = `22`, neu SSH khong doi cong
- `OPSHUB_STAGING_VPS_USER` = `hhh`, neu server van dung user hien tai

Host, port va username khong phai private key, nhung workflow hien tai doc chung
qua `secrets`, nen giu dung ten de khong phai sua workflow trong dot cutover.

## 7. Windows code-signing PFX

### Production

Neu may nhan vien da tin certificate production hien tai, nen khoi phuc PFX cu.
Tao certificate moi se doi publisher identity va co the lam Windows/SmartScreen
canh bao lai. Neu bat buoc rotate, phan phoi public certificate moi den may
nhan vien truoc khi phat hanh ban ky bang key moi.

### Staging hoac production noi bo moi

Tao self-signed code-signing certificate ngoai thu muc repo:

```powershell
$Cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject 'CN=PhongVu OpsHub Internal Signing' `
  -FriendlyName 'PhongVu OpsHub Internal Signing' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -KeyExportPolicy Exportable `
  -NotAfter (Get-Date).AddYears(3)

$PfxPassword = Read-Host 'Nhap mat khau PFX da luu trong password manager' -AsSecureString
$PfxPath = Join-Path $env:USERPROFILE 'OpsHub-Secrets\opshub-internal-signing.pfx'

Export-PfxCertificate `
  -Cert $Cert `
  -FilePath $PfxPath `
  -Password $PfxPassword

Export-Certificate `
  -Cert $Cert `
  -FilePath (Join-Path $env:USERPROFILE 'OpsHub-Secrets\opshub-internal-signing.cer')
```

Kiem tra certificate co Code Signing EKU:

```powershell
$Cert | Format-List Subject, Thumbprint, NotAfter, EnhancedKeyUsageList
```

Tao base64:

```powershell
$PfxBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($PfxPath))
$PfxBase64.Length
```

Production:

- `WINDOWS_SIGNING_PFX_BASE64` = `$PfxBase64`
- `WINDOWS_SIGNING_PFX_PASSWORD` = mat khau PFX

Staging:

- `WINDOWS_STAGING_SIGNING_PFX_BASE64` = `$PfxBase64`
- `WINDOWS_STAGING_SIGNING_PFX_PASSWORD` = mat khau PFX

Nen dung certificate khac nhau cho production va staging. Hai secret Windows co
the bo trong; workflow se tao artifact unsigned va ghi ro signing bi tat.

## 8. Thu tu cutover an toan

1. Tao va nhap toan bo staging environment secrets.
2. Enable chi workflow staging.
3. Chay full staging deploy va kiem tra health, app-version va download files.
4. Tao va nhap production environment secrets.
5. Chay production `workflow_dispatch` voi `skip_client_build=true`.
6. Xac nhan app-version production khong doi.
7. Chay full production deploy bang dung Android production keystore cu.
8. Kiem tra APK moi co cung signing certificate voi APK dang phat hanh.
9. Cai update APK tren it nhat mot may dang dung ban production cu.
10. Sau khi ca hai environment xanh, xoa repository secrets trung ten.
11. Revoke Tailscale OAuth client cu va xoa SSH public key cu.

## 9. Kiem tra sau cung

```powershell
gh secret list --env staging --repo hoanghochoi/phongvu-opshub
gh secret list --env production --repo hoanghochoi/phongvu-opshub
```

Lenh tren chi hien ten secret, khong hien gia tri. Khong paste secret vao issue,
commit, workflow log, chat, hoac terminal command co the duoc luu history.
