param(
  [string]$DisplayName = $env:WINDOWS_MSIX_DISPLAY_NAME,
  [string]$PublisherDisplayName = $env:WINDOWS_MSIX_PUBLISHER_DISPLAY_NAME,
  [string]$IdentityName = $env:WINDOWS_MSIX_INTERNAL_IDENTITY_NAME,
  [string]$MsixVersion = $env:WINDOWS_MSIX_VERSION,
  [string]$OutputName = $env:WINDOWS_MSIX_OUTPUT_NAME,
  [string]$OutputPath = $env:WINDOWS_MSIX_OUTPUT_PATH,
  [string]$LogoPath = 'assets\icon\source\app_icon_padded.png',
  [string]$CertificatePath = $env:WINDOWS_MSIX_SIGNING_PFX_PATH,
  [string]$CertificatePassword = $env:WINDOWS_MSIX_SIGNING_PFX_PASSWORD,
  [string]$Capabilities = 'internetClient',
  [switch]$BuildWindows
)

$ErrorActionPreference = 'Stop'

function Assert-RequiredValue {
  param(
    [string]$Name,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    throw "$Name is required for internal MSIX packaging."
  }
}

function Assert-MsixVersion {
  param([string]$Value)

  Assert-RequiredValue -Name 'WINDOWS_MSIX_VERSION' -Value $Value
  if ($Value -notmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$') {
    throw 'WINDOWS_MSIX_VERSION must use four numeric parts: a.b.c.d.'
  }

  foreach ($part in $Value.Split('.')) {
    $number = [int]$part
    if ($number -lt 0 -or $number -gt 65535) {
      throw 'Each WINDOWS_MSIX_VERSION part must be between 0 and 65535.'
    }
  }
}

if ([string]::IsNullOrWhiteSpace($DisplayName)) {
  $DisplayName = 'PhongVu OpsHub'
}
if ([string]::IsNullOrWhiteSpace($PublisherDisplayName)) {
  $PublisherDisplayName = 'PhongVu OpsHub'
}
if ([string]::IsNullOrWhiteSpace($IdentityName)) {
  $IdentityName = 'com.phongvu.opshub'
}
if ([string]::IsNullOrWhiteSpace($OutputName)) {
  $OutputName = 'phongvu-opshub-windows-internal-msix'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = 'build\windows\msix'
}

Assert-MsixVersion -Value $MsixVersion
Assert-RequiredValue -Name 'WINDOWS_MSIX_SIGNING_PFX_PATH' -Value $CertificatePath
Assert-RequiredValue -Name 'WINDOWS_MSIX_SIGNING_PFX_PASSWORD' -Value $CertificatePassword

$resolvedCertificatePath = (Resolve-Path $CertificatePath).Path
$resolvedLogoPath = (Resolve-Path $LogoPath).Path
$resolvedOutputPath = (New-Item -ItemType Directory -Force -Path $OutputPath).FullName
$expectedMsixPath = Join-Path $resolvedOutputPath "$OutputName.msix"

if (Test-Path $expectedMsixPath) {
  Remove-Item -LiteralPath $expectedMsixPath -Force
}

$buildWindowsValue = if ($BuildWindows) { 'true' } else { 'false' }
$msixArgs = @(
  'run',
  'msix:create',
  '--sign-msix',
  'true',
  '--install-certificate',
  'false',
  '--build-windows',
  $buildWindowsValue,
  '--display-name',
  $DisplayName,
  '--publisher-display-name',
  $PublisherDisplayName,
  '--identity-name',
  $IdentityName,
  '--version',
  $MsixVersion,
  '--certificate-path',
  $resolvedCertificatePath,
  '--certificate-password',
  $CertificatePassword,
  '--logo-path',
  $resolvedLogoPath,
  '--capabilities',
  $Capabilities,
  '--architecture',
  'x64',
  '--output-path',
  $resolvedOutputPath,
  '--output-name',
  $OutputName
)

Write-Host "Building internal signed MSIX: $OutputName.msix"
Write-Host "MSIX identity: $IdentityName"
Write-Host "MSIX version: $MsixVersion"

& dart @msixArgs
if ($LASTEXITCODE -ne 0) {
  throw "msix:create failed with exit code $LASTEXITCODE."
}

if (-not (Test-Path $expectedMsixPath)) {
  throw "MSIX output was not created: $expectedMsixPath"
}

$signature = Get-AuthenticodeSignature -FilePath $expectedMsixPath
if ($signature.Status -eq 'NotSigned') {
  throw "Internal MSIX is not signed: $expectedMsixPath"
}

$hash = (Get-FileHash -Algorithm SHA256 -Path $expectedMsixPath).Hash.ToLowerInvariant()
Set-Content -Path "$expectedMsixPath.sha256" -Value "$hash  $OutputName.msix" -Encoding ascii

Write-Host "MSIX output: $expectedMsixPath"
Write-Host "MSIX signature status: $($signature.Status)"
Write-Host "MSIX SHA256: $hash"
