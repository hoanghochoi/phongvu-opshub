param(
  [string]$OutputDirectory = (Join-Path $env:TEMP 'OpsHub-Secrets-2026')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function New-RandomSecret {
  $bytes = [byte[]]::new(32)
  [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return [Convert]::ToBase64String($bytes).
    TrimEnd('=').
    Replace('+', '-').
    Replace('/', '_')
}

function Protect-SecretDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $intendedIdentity = "$env:USERDOMAIN\$env:USERNAME"
  $acl = [Security.AccessControl.DirectorySecurity]::new()
  $acl.SetAccessRuleProtection($true, $false)

  $identities = @(
    $currentIdentity,
    $intendedIdentity,
    'NT AUTHORITY\SYSTEM'
  ) | Select-Object -Unique
  foreach ($identity in $identities) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
      $identity,
      [Security.AccessControl.FileSystemRights]::FullControl,
      [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
      [Security.AccessControl.PropagationFlags]::None,
      [Security.AccessControl.AccessControlType]::Allow
    )
    $acl.AddAccessRule($rule)
  }

  Set-Acl -LiteralPath $Path -AclObject $acl
}

function Find-KeyTool {
  $candidates = @(
    (Get-Command keytool.exe -ErrorAction SilentlyContinue |
      Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue);
    (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe');
    $(if ($env:JAVA_HOME) {
        Join-Path $env:JAVA_HOME 'bin\keytool.exe'
      });
  ) | Where-Object {
    $_ -and (Test-Path -LiteralPath $_)
  }

  $keyTool = $candidates | Select-Object -First 1
  if (-not $keyTool) {
    throw 'keytool.exe was not found. Install Android Studio or a JDK.'
  }
  return $keyTool
}

function Invoke-KeyTool {
  param(
    [Parameter(Mandatory = $true)][string]$KeyTool,
    [Parameter(Mandatory = $true)][string[]]$Arguments
  )

  & $KeyTool @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE."
  }
}

function New-AndroidSigningBundle {
  param(
    [Parameter(Mandatory = $true)][string]$KeyTool,
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Prefix,
    [Parameter(Mandatory = $true)][string]$Alias,
    [Parameter(Mandatory = $true)][string]$DistinguishedName,
    [Parameter(Mandatory = $true)][string]$StorePassword,
    [Parameter(Mandatory = $true)][string]$KeyPassword
  )

  $keystorePath = Join-Path $Directory "$Prefix.jks"
  $certificatePath = Join-Path $Directory "$Prefix.cer"

  $env:OPSHUB_KEYSTORE_PASSWORD = $StorePassword
  $env:OPSHUB_KEY_PASSWORD = $KeyPassword
  try {
    Invoke-KeyTool -KeyTool $KeyTool -Arguments @(
      '-genkeypair',
      '-noprompt',
      '-v',
      '-keystore', $keystorePath,
      '-storetype', 'JKS',
      '-storepass:env', 'OPSHUB_KEYSTORE_PASSWORD',
      '-keypass:env', 'OPSHUB_KEY_PASSWORD',
      '-alias', $Alias,
      '-keyalg', 'RSA',
      '-keysize', '4096',
      '-sigalg', 'SHA256withRSA',
      '-validity', '10000',
      '-dname', $DistinguishedName
    )

    Invoke-KeyTool -KeyTool $KeyTool -Arguments @(
      '-exportcert',
      '-keystore', $keystorePath,
      '-storepass:env', 'OPSHUB_KEYSTORE_PASSWORD',
      '-alias', $Alias,
      '-file', $certificatePath
    )
  } finally {
    Remove-Item Env:OPSHUB_KEYSTORE_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:OPSHUB_KEY_PASSWORD -ErrorAction SilentlyContinue
  }

  $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $certificatePath
  )
  $fingerprint = $certificate.GetCertHashString(
    [Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $base64 = [Convert]::ToBase64String(
    [IO.File]::ReadAllBytes($keystorePath)
  )
  if ($base64.Length -ge 49152) {
    throw "$Prefix.jks exceeds GitHub's 48 KB secret limit after base64 encoding."
  }

  return [pscustomobject]@{
    Alias = $Alias
    Base64 = $base64
    CertificatePath = $certificatePath
    FingerprintSha256 = $fingerprint
    KeystorePath = $keystorePath
  }
}

function New-SshDeployKey {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string]$Comment
  )

  $privatePath = Join-Path $Directory $FileName
  & ssh-keygen.exe -q -t ed25519 -C $Comment -f $privatePath -N ''
  if ($LASTEXITCODE -ne 0) {
    throw "ssh-keygen failed for $FileName with exit code $LASTEXITCODE."
  }

  $intendedIdentity = "$env:USERDOMAIN\$env:USERNAME"
  & icacls.exe $privatePath /grant "${intendedIdentity}:(F)" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not grant $intendedIdentity access to $FileName."
  }

  $publicPath = "$privatePath.pub"
  $fingerprint = (& ssh-keygen.exe -lf $publicPath).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "ssh-keygen fingerprint failed for $FileName."
  }

  return [pscustomobject]@{
    Fingerprint = $fingerprint
    PrivateKey = [IO.File]::ReadAllText($privatePath)
    PrivatePath = $privatePath
    PublicPath = $publicPath
  }
}

function New-WindowsSigningBundle {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Prefix,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][string]$FriendlyName,
    [Parameter(Mandatory = $true)][string]$Password
  )

  $certificate = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -FriendlyName $FriendlyName `
    -CertStoreLocation 'Cert:\CurrentUser\My' `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -NotAfter (Get-Date).AddYears(3)

  $codeSigningOid = '1.3.6.1.5.5.7.3.3'
  $ekuOids = @($certificate.EnhancedKeyUsageList | ForEach-Object {
      [string]$_.ObjectId
    })
  if ($codeSigningOid -notin $ekuOids) {
    throw "$FriendlyName does not contain the Code Signing EKU."
  }

  $pfxPath = Join-Path $Directory "$Prefix.pfx"
  $cerPath = Join-Path $Directory "$Prefix.cer"
  $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

  try {
    Export-PfxCertificate `
      -Cert $certificate `
      -FilePath $pfxPath `
      -Password $securePassword | Out-Null
    Export-Certificate `
      -Cert $certificate `
      -FilePath $cerPath | Out-Null
  } finally {
    $store = [Security.Cryptography.X509Certificates.X509Store]::new(
      [Security.Cryptography.X509Certificates.StoreName]::My,
      [Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
    )
    $store.Open(
      [Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite
    )
    try {
      $store.Remove($certificate)
    } finally {
      $store.Close()
    }
  }

  $publicCertificate =
    [Security.Cryptography.X509Certificates.X509Certificate2]::new($cerPath)
  $fingerprint = $publicCertificate.GetCertHashString(
    [Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))
  if ($base64.Length -ge 49152) {
    throw "$Prefix.pfx exceeds GitHub's 48 KB secret limit after base64 encoding."
  }

  return [pscustomobject]@{
    Base64 = $base64
    CertificatePath = $cerPath
    FingerprintSha256 = $fingerprint
    PfxPath = $pfxPath
    StoreThumbprint = $certificate.Thumbprint
  }
}

function Export-SecretJson {
  param(
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $object = [ordered]@{}
  foreach ($entry in $Values.GetEnumerator()) {
    $object[[string]$entry.Key] = [string]$entry.Value
  }
  $json = $object | ConvertTo-Json -Depth 4
  Write-Utf8File -Path $Path -Content $json
}

function Write-Utf8File {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $utf8 = [Text.UTF8Encoding]::new($false)
  [IO.File]::WriteAllText($Path, $Content, $utf8)
}

$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputPath) {
  $existing = @(Get-ChildItem -LiteralPath $outputPath -Force)
  if ($existing.Count -gt 0) {
    throw "Output directory is not empty: $outputPath"
  }
} else {
  New-Item -ItemType Directory -Path $outputPath | Out-Null
}
Protect-SecretDirectory -Path $outputPath

$writeProbe = Join-Path $outputPath '.write-probe'
[IO.File]::WriteAllText($writeProbe, 'ok')
[IO.File]::Delete($writeProbe)

$keyTool = Find-KeyTool
$passwords = [ordered]@{
  AndroidProductionStore = New-RandomSecret
  AndroidProductionKey = New-RandomSecret
  AndroidStagingStore = New-RandomSecret
  AndroidStagingKey = New-RandomSecret
  WindowsProductionPfx = New-RandomSecret
  WindowsStagingPfx = New-RandomSecret
}
$passwordCheckpointPath = Join-Path `
  $outputPath 'generation-passwords.generated.json'
Export-SecretJson `
  -Values $passwords `
  -Path $passwordCheckpointPath

$androidProduction = New-AndroidSigningBundle `
  -KeyTool $keyTool `
  -Directory $outputPath `
  -Prefix 'opshub-production-2026' `
  -Alias 'opshub-production-2026' `
  -DistinguishedName 'CN=PhongVu OpsHub Production, OU=Internal Apps, O=Phong Vu, C=VN' `
  -StorePassword $passwords.AndroidProductionStore `
  -KeyPassword $passwords.AndroidProductionKey

$androidStaging = New-AndroidSigningBundle `
  -KeyTool $keyTool `
  -Directory $outputPath `
  -Prefix 'opshub-staging-2026' `
  -Alias 'opshub-staging-2026' `
  -DistinguishedName 'CN=PhongVu OpsHub Staging, OU=Internal Apps, O=Phong Vu, C=VN' `
  -StorePassword $passwords.AndroidStagingStore `
  -KeyPassword $passwords.AndroidStagingKey

$sshProduction = New-SshDeployKey `
  -Directory $outputPath `
  -FileName 'opshub-production-deploy-2026' `
  -Comment 'github-actions-opshub-production-2026'

$sshStaging = New-SshDeployKey `
  -Directory $outputPath `
  -FileName 'opshub-staging-deploy-2026' `
  -Comment 'github-actions-opshub-staging-2026'

$windowsProduction = New-WindowsSigningBundle `
  -Directory $outputPath `
  -Prefix 'opshub-production-signing-2026' `
  -Subject 'CN=PhongVu OpsHub Production 2026' `
  -FriendlyName 'PhongVu OpsHub Production 2026' `
  -Password $passwords.WindowsProductionPfx

$windowsStaging = New-WindowsSigningBundle `
  -Directory $outputPath `
  -Prefix 'opshub-staging-signing-2026' `
  -Subject 'CN=PhongVu OpsHub Staging 2026' `
  -FriendlyName 'PhongVu OpsHub Staging 2026' `
  -Password $passwords.WindowsStagingPfx

$productionValues = [ordered]@{
  ANDROID_KEYSTORE_BASE64 = $androidProduction.Base64
  ANDROID_KEYSTORE_PASSWORD = $passwords.AndroidProductionStore
  ANDROID_KEY_ALIAS = $androidProduction.Alias
  ANDROID_KEY_PASSWORD = $passwords.AndroidProductionKey
  OPSHUB_VPS_PORT = '22'
  OPSHUB_VPS_USER = 'ubuntu'
  OPSHUB_VPS_SSH_KEY = $sshProduction.PrivateKey
  WINDOWS_SIGNING_PFX_BASE64 = $windowsProduction.Base64
  WINDOWS_SIGNING_PFX_PASSWORD = $passwords.WindowsProductionPfx
}

$stagingValues = [ordered]@{
  ANDROID_STAGING_KEYSTORE_BASE64 = $androidStaging.Base64
  ANDROID_STAGING_KEYSTORE_PASSWORD = $passwords.AndroidStagingStore
  ANDROID_STAGING_KEY_ALIAS = $androidStaging.Alias
  ANDROID_STAGING_KEY_PASSWORD = $passwords.AndroidStagingKey
  OPSHUB_STAGING_VPS_PORT = '22'
  OPSHUB_STAGING_VPS_USER = 'hhh'
  OPSHUB_STAGING_SSH_KEY = $sshStaging.PrivateKey
  WINDOWS_STAGING_SIGNING_PFX_BASE64 = $windowsStaging.Base64
  WINDOWS_STAGING_SIGNING_PFX_PASSWORD = $passwords.WindowsStagingPfx
}

$productionVault = Join-Path $outputPath 'production-secrets.generated.json'
$stagingVault = Join-Path $outputPath 'staging-secrets.generated.json'
Export-SecretJson -Values $productionValues -Path $productionVault
Export-SecretJson -Values $stagingValues -Path $stagingVault
[IO.File]::Delete($passwordCheckpointPath)

$getSecretScript = @'
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('production', 'staging')]
  [string]$Environment,

  [string]$Name,

  [switch]$List,

  [switch]$Copy
)

$ErrorActionPreference = 'Stop'
$vaultPath = Join-Path $PSScriptRoot "$Environment-secrets.generated.json"
$entries = Get-Content -LiteralPath $vaultPath -Raw | ConvertFrom-Json

if ($List) {
  $entries.PSObject.Properties.Name | Sort-Object
  exit 0
}

if (-not $Name) {
  throw 'Pass -Name or use -List.'
}

$entry = $entries.PSObject.Properties[$Name]
if (-not $entry) {
  throw "Secret is not present in the $Environment vault: $Name"
}

$value = [string]$entry.Value
if ($Copy) {
  Set-Clipboard -Value $value
  Write-Output "Copied $Name to the clipboard. Clear the clipboard after use."
} else {
  Write-Output $value
}
'@
Write-Utf8File `
  -Path (Join-Path $outputPath 'Get-OpsHubSecret.ps1') `
  -Content $getSecretScript

$setSecretScript = @'
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('production', 'staging')]
  [string]$Environment,

  [Parameter(Mandatory = $true)]
  [string]$Name
)

$ErrorActionPreference = 'Stop'
$vaultPath = Join-Path $PSScriptRoot "$Environment-secrets.generated.json"
$entries = Get-Content -LiteralPath $vaultPath -Raw | ConvertFrom-Json
$secureValue = Read-Host "Paste $Name" -AsSecureString
$plainValue = [Net.NetworkCredential]::new('', $secureValue).Password
$entries | Add-Member `
  -NotePropertyName $Name `
  -NotePropertyValue $plainValue `
  -Force
$entries | ConvertTo-Json -Depth 4 |
  Set-Content -LiteralPath $vaultPath -Encoding utf8
Write-Output "Stored $Name in the $Environment secret file."
'@
Write-Utf8File `
  -Path (Join-Path $outputPath 'Set-OpsHubSecret.ps1') `
  -Content $setSecretScript

$publishScript = @'
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('production', 'staging')]
  [string]$Environment,

  [string]$Repository = 'hoanghochoi/phongvu-opshub'
)

$ErrorActionPreference = 'Stop'
$required = if ($Environment -eq 'production') {
  @(
    'ANDROID_KEYSTORE_BASE64',
    'ANDROID_KEYSTORE_PASSWORD',
    'ANDROID_KEY_ALIAS',
    'ANDROID_KEY_PASSWORD',
    'OPSHUB_VPS_HOST',
    'OPSHUB_VPS_PORT',
    'OPSHUB_VPS_USER',
    'OPSHUB_VPS_SSH_KEY',
    'TS_OAUTH_CLIENT_ID',
    'TS_OAUTH_SECRET',
    'WINDOWS_SIGNING_PFX_BASE64',
    'WINDOWS_SIGNING_PFX_PASSWORD'
  )
} else {
  @(
    'ANDROID_STAGING_KEYSTORE_BASE64',
    'ANDROID_STAGING_KEYSTORE_PASSWORD',
    'ANDROID_STAGING_KEY_ALIAS',
    'ANDROID_STAGING_KEY_PASSWORD',
    'OPSHUB_STAGING_VPS_HOST',
    'OPSHUB_STAGING_VPS_PORT',
    'OPSHUB_STAGING_VPS_USER',
    'OPSHUB_STAGING_SSH_KEY',
    'TS_OAUTH_CLIENT_ID',
    'TS_OAUTH_SECRET',
    'WINDOWS_STAGING_SIGNING_PFX_BASE64',
    'WINDOWS_STAGING_SIGNING_PFX_PASSWORD'
  )
}

if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
  throw 'gh.exe is not installed or is not in PATH.'
}

$vaultPath = Join-Path $PSScriptRoot "$Environment-secrets.generated.json"
$entries = Get-Content -LiteralPath $vaultPath -Raw | ConvertFrom-Json
$names = @($entries.PSObject.Properties.Name)
$missing = @($required | Where-Object { $_ -notin $names })
if ($missing.Count -gt 0) {
  throw "Vault is incomplete. Missing: $($missing -join ', ')"
}

foreach ($name in $required) {
  $value = [string]$entries.PSObject.Properties[$name].Value
  $value | & gh.exe secret set $name `
    --env $Environment `
    --repo $Repository
  if ($LASTEXITCODE -ne 0) {
    throw "gh secret set failed for $name."
  }
  Write-Output "Uploaded $Environment/$name"
}
'@
Write-Utf8File `
  -Path (Join-Path $outputPath 'Publish-OpsHubSecretsToGitHub.ps1') `
  -Content $publishScript

$inventory = [ordered]@{
  generatedAt = (Get-Date).ToString('o')
  generatedBy = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  production = [ordered]@{
    generated = @($productionValues.Keys)
    manual = @(
      'OPSHUB_VPS_HOST',
      'TS_OAUTH_CLIENT_ID',
      'TS_OAUTH_SECRET'
    )
  }
  staging = [ordered]@{
    generated = @($stagingValues.Keys)
    manual = @(
      'OPSHUB_STAGING_VPS_HOST',
      'TS_OAUTH_CLIENT_ID',
      'TS_OAUTH_SECRET'
    )
    hostCandidateFromRepository = '100.127.127.89'
  }
  fingerprints = [ordered]@{
    androidProductionSha256 = $androidProduction.FingerprintSha256
    androidStagingSha256 = $androidStaging.FingerprintSha256
    windowsProductionSha256 = $windowsProduction.FingerprintSha256
    windowsStagingSha256 = $windowsStaging.FingerprintSha256
    sshProduction = $sshProduction.Fingerprint
    sshStaging = $sshStaging.Fingerprint
  }
  windowsCertificateStoreThumbprints = [ordered]@{
    production = $windowsProduction.StoreThumbprint
    staging = $windowsStaging.StoreThumbprint
  }
}
$inventoryJson = $inventory | ConvertTo-Json -Depth 8
Write-Utf8File `
  -Path (Join-Path $outputPath 'inventory.json') `
  -Content $inventoryJson

$readme = @"
# OpsHub Secrets 2026

Thư mục này chứa khóa production/staging. Không đưa vào Git, email hoặc chat.

## Đã tạo tự động

- Android production/staging JKS và public certificate.
- Windows production/staging PFX và public certificate.
- SSH production/staging private/public key.
- File JSON nhạy cảm chứa các GitHub secret đã tạo được.
- Helper scripts để xem, bổ sung và upload secret.

Hai file `production-secrets.generated.json` và
`staging-secrets.generated.json` chứa secret dạng rõ để anh có thể nhập GitHub.
ACL của thư mục chỉ cấp quyền cho tài khoản Windows của anh, SYSTEM và tiến
trình sandbox đã tạo file. Sau khi upload và lưu mật khẩu vào password manager,
phải xóa hai file JSON này.

## Còn phải bổ sung thủ công

Production:

- OPSHUB_VPS_HOST
- TS_OAUTH_CLIENT_ID
- TS_OAUTH_SECRET

Staging:

- OPSHUB_STAGING_VPS_HOST
- TS_OAUTH_CLIENT_ID
- TS_OAUTH_SECRET

Repository hiện ghi nhận staging host candidate là 100.127.127.89. Phải xác minh
lại bằng tailscale ip -4 trên staging server trước khi lưu.

## Xem tên secret đã có

```powershell
.\Get-OpsHubSecret.ps1 -Environment staging -List
.\Get-OpsHubSecret.ps1 -Environment production -List
```

## Copy một secret vào clipboard

```powershell
.\Get-OpsHubSecret.ps1 `
  -Environment staging `
  -Name ANDROID_STAGING_KEY_ALIAS `
  -Copy
```

Xóa clipboard sau khi dùng:

```powershell
Set-Clipboard -Value ''
```

## Bổ sung secret còn thiếu

```powershell
.\Set-OpsHubSecret.ps1 `
  -Environment staging `
  -Name OPSHUB_STAGING_VPS_HOST
```

Lặp lại cho hai Tailscale OAuth secrets và production host.

## Upload lên GitHub sau khi vault đủ 12 secret

```powershell
.\Publish-OpsHubSecretsToGitHub.ps1 -Environment staging
.\Publish-OpsHubSecretsToGitHub.ps1 -Environment production
```

## Public key cần thêm lên VPS

- Production: opshub-production-deploy-2026.pub
- Staging: opshub-staging-deploy-2026.pub

Không upload private key lên VPS.

## Chốt quyền file sau khi chuyển thư mục

Sau khi chuyển thư mục ra khỏi TEMP, chạy:

```powershell
.\finalize-opshub-secret-permissions.ps1
```

Script chỉ giữ quyền cho Windows user hiện tại và SYSTEM.

## Fingerprint

- Android production SHA-256: $($androidProduction.FingerprintSha256)
- Android staging SHA-256: $($androidStaging.FingerprintSha256)
- Windows production SHA-256: $($windowsProduction.FingerprintSha256)
- Windows staging SHA-256: $($windowsStaging.FingerprintSha256)
- SSH production: $($sshProduction.Fingerprint)
- SSH staging: $($sshStaging.Fingerprint)

## Backup

Lưu mật khẩu từ hai file JSON vào password manager, sau đó tạo thêm một backup
offline được mã hóa. File JKS production phải được giữ cho mọi bản Android sau.
Xóa hai file `*.generated.json` sau khi GitHub và password manager đã đủ dữ liệu.
"@
Write-Utf8File `
  -Path (Join-Path $outputPath 'README-FIRST.md') `
  -Content $readme

$checksumPath = Join-Path $outputPath 'checksums-sha256.csv'
Get-ChildItem -LiteralPath $outputPath -File |
  Where-Object { $_.FullName -ne $checksumPath } |
  Get-FileHash -Algorithm SHA256 |
  Select-Object Path, Hash |
  Export-Csv -LiteralPath $checksumPath -NoTypeInformation

Write-Output "OUTPUT_DIRECTORY=$outputPath"
Write-Output "PRODUCTION_VAULT_SECRET_COUNT=$($productionValues.Count)"
Write-Output "STAGING_VAULT_SECRET_COUNT=$($stagingValues.Count)"
Write-Output "MANUAL_SECRET_COUNT=6"
Write-Output "ANDROID_PRODUCTION_SHA256=$($androidProduction.FingerprintSha256)"
Write-Output "ANDROID_STAGING_SHA256=$($androidStaging.FingerprintSha256)"
Write-Output "WINDOWS_PRODUCTION_SHA256=$($windowsProduction.FingerprintSha256)"
Write-Output "WINDOWS_STAGING_SHA256=$($windowsStaging.FingerprintSha256)"
Write-Output "SSH_PRODUCTION_FINGERPRINT=$($sshProduction.Fingerprint)"
Write-Output "SSH_STAGING_FINGERPRINT=$($sshStaging.Fingerprint)"
