param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,

  [switch]$SkipSignatureUpdate,

  [int]$SignatureUpdateAttempts = 5,

  [int]$SignatureUpdateDelaySeconds = 30
)

$ErrorActionPreference = 'Stop'

function Get-MpCmdRunPath {
  $command = Get-Command MpCmdRun.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $platformRoot = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
  if (Test-Path $platformRoot) {
    $platformCandidate = Get-ChildItem -Path $platformRoot -Directory |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
      Where-Object { Test-Path $_ } |
      Select-Object -First 1
    if ($platformCandidate) {
      return $platformCandidate
    }
  }

  $legacyCandidate = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
  if (Test-Path $legacyCandidate) {
    return $legacyCandidate
  }

  throw 'Microsoft Defender command-line scanner was not found. Refusing to publish unscanned Windows artifacts.'
}

function Write-DefenderStatus {
  $statusCommand = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
  if (-not $statusCommand) {
    Write-Warning 'Get-MpComputerStatus is unavailable; MpCmdRun remains the release gate.'
    return
  }

  $status = Get-MpComputerStatus
  Write-Host (
    'Defender status: antivirusEnabled={0}, realTimeProtectionEnabled={1}, signatureVersion={2}, signatureUpdated={3:O}' -f
      $status.AntivirusEnabled,
      $status.RealTimeProtectionEnabled,
      $status.AntivirusSignatureVersion,
      $status.AntivirusSignatureLastUpdated
  )
}

function Invoke-DefenderSignatureUpdate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Scanner,

    [int]$Attempts = 5,

    [int]$DelaySeconds = 30
  )

  if ($Attempts -lt 1) {
    $Attempts = 1
  }
  if ($DelaySeconds -lt 1) {
    $DelaySeconds = 1
  }

  for ($attempt = 1; $attempt -le $Attempts; $attempt += 1) {
    Write-Host "Defender signature update attempt $attempt of $Attempts."
    & $Scanner -SignatureUpdate
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
      Write-Host "Defender signature update succeeded on attempt $attempt."
      return
    }

    if ($attempt -lt $Attempts) {
      Write-Warning (
        'Defender signature update failed with exit code {0}. Retrying in {1}s because GitHub runners can have a transient installer/update lock.' -f
          $exitCode,
          $DelaySeconds
      )
      Start-Sleep -Seconds $DelaySeconds
      continue
    }

    throw "Microsoft Defender signature update failed with exit code $exitCode after $Attempts attempts. Refusing to publish artifacts."
  }
}

$scanner = Get-MpCmdRunPath
Write-Host "Microsoft Defender release gate starting. scanner=$scanner artifactCount=$($Path.Count)"
Write-DefenderStatus

if ($SkipSignatureUpdate) {
  Write-Host 'Defender signature update skipped by explicit local validation option.'
} else {
  Write-Host 'Updating Microsoft Defender security intelligence before scanning release artifacts.'
  Invoke-DefenderSignatureUpdate `
    -Scanner $scanner `
    -Attempts $SignatureUpdateAttempts `
    -DelaySeconds $SignatureUpdateDelaySeconds
  Write-DefenderStatus
}

foreach ($item in $Path) {
  $resolvedPath = (Resolve-Path $item).Path
  $artifact = Get-Item $resolvedPath
  $hash = (Get-FileHash -Algorithm SHA256 -Path $resolvedPath).Hash.ToLowerInvariant()
  $startedAt = Get-Date

  Write-Host (
    'Defender scan start: file={0}, bytes={1}, sha256={2}' -f
      $artifact.Name,
      $artifact.Length,
      $hash
  )

  & $scanner -Scan -ScanType 3 -File $resolvedPath -DisableRemediation
  $scanExitCode = $LASTEXITCODE
  $durationMs = [math]::Round(((Get-Date) - $startedAt).TotalMilliseconds)

  if ($scanExitCode -ne 0) {
    throw (
      'Microsoft Defender rejected {0}. exitCode={1}, durationMs={2}, sha256={3}. Refusing to publish artifacts.' -f
        $artifact.Name,
        $scanExitCode,
        $durationMs,
        $hash
    )
  }

  if (-not (Test-Path $resolvedPath)) {
    throw "Microsoft Defender removed or quarantined $($artifact.Name). Refusing to publish artifacts."
  }

  Write-Host (
    'Defender scan passed: file={0}, durationMs={1}, sha256={2}' -f
      $artifact.Name,
      $durationMs,
      $hash
  )
}

Write-Host 'Microsoft Defender release gate passed for all Windows artifacts.'
