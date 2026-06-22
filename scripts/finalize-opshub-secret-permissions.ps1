param(
  [string]$Directory = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$resolvedDirectory = (Resolve-Path -LiteralPath $Directory).Path
$identity = "$env:USERDOMAIN\$env:USERNAME"
$sandboxIdentity = "$env:USERDOMAIN\CodexSandboxOffline"

$privateKeyNames = @(
  'opshub-production-deploy-2026',
  'opshub-staging-deploy-2026'
)

foreach ($privateKeyName in $privateKeyNames) {
  $privateKeyPath = Join-Path $resolvedDirectory $privateKeyName
  if (-not (Test-Path -LiteralPath $privateKeyPath)) {
    throw "Private key was not found: $privateKeyPath"
  }

  & takeown.exe /F $privateKeyPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not take ownership of $privateKeyName."
  }

  & icacls.exe $privateKeyPath /inheritance:r | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not disable inheritance for $privateKeyName."
  }

  & icacls.exe $privateKeyPath /grant:r "${identity}:(F)" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Could not grant $identity access to $privateKeyName."
  }

  foreach ($otherIdentity in @(
      $sandboxIdentity,
      'BUILTIN\Administrators',
      'NT AUTHORITY\SYSTEM'
    )) {
    & icacls.exe $privateKeyPath /remove:g $otherIdentity | Out-Null
  }

  $actualAcl = Get-Acl -LiteralPath $privateKeyPath
  $otherAllowRules = @(
    $actualAcl.Access |
      Where-Object {
        $_.AccessControlType -eq 'Allow' -and
        $_.IdentityReference.Value -ne $identity
      }
  )
  if ($otherAllowRules.Count -gt 0) {
    $others = $otherAllowRules.IdentityReference.Value -join ', '
    throw "$privateKeyName is still readable by: $others"
  }

  & ssh-keygen.exe -y -f $privateKeyPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "OpenSSH rejected the permissions for $privateKeyName."
  }

  Write-Output "Private key permissions verified: $privateKeyName"
}

& icacls.exe $resolvedDirectory `
  /inheritance:r `
  /grant:r "${identity}:(OI)(CI)(F)" 'SYSTEM:(OI)(CI)(F)' |
  Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Could not secure the OpsHub secret directory.'
}

& icacls.exe $resolvedDirectory `
  /remove:g $sandboxIdentity `
  /T `
  /C |
  Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Could not remove $sandboxIdentity from the secret directory."
}

& icacls.exe $resolvedDirectory /setowner $identity /T /C | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Warning 'Could not set ownership on every file; private key ACLs are still verified.'
}

Write-Output "Secret directory permissions finalized for $identity."
