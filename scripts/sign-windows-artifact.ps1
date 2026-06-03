param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,

  [string]$PfxPath = $env:WINDOWS_SIGNING_PFX_PATH,
  [string]$PfxPassword = $env:WINDOWS_SIGNING_PFX_PASSWORD
)

$ErrorActionPreference = 'Stop'

function Get-SignToolPath {
  $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  if (Test-Path $kitsRoot) {
    $candidate = Get-ChildItem -Path $kitsRoot -Filter signtool.exe -Recurse |
      Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($candidate) {
      return $candidate.FullName
    }
  }

  $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  throw 'signtool.exe was not found. Install the Windows SDK on the runner.'
}

if ([string]::IsNullOrWhiteSpace($PfxPath) -or -not (Test-Path $PfxPath)) {
  throw 'Windows signing PFX path is missing or does not exist.'
}

if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
  throw 'Windows signing PFX password is missing.'
}

$signTool = Get-SignToolPath

foreach ($item in $Path) {
  $resolvedPath = (Resolve-Path $item).Path
  Write-Host "Signing Windows artifact: $resolvedPath"

  & $signTool sign /fd SHA256 /f $PfxPath /p $PfxPassword /tr http://timestamp.digicert.com /td SHA256 $resolvedPath
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Timestamped signing failed; retrying without timestamp for internal distribution.'
    & $signTool sign /fd SHA256 /f $PfxPath /p $PfxPassword $resolvedPath
  }

  if ($LASTEXITCODE -ne 0) {
    throw "signtool failed for $resolvedPath with exit code $LASTEXITCODE."
  }

  $signature = Get-AuthenticodeSignature -FilePath $resolvedPath
  if ($signature.Status -eq 'NotSigned') {
    throw "Windows artifact is still unsigned after signtool completed: $resolvedPath"
  }

  Write-Host ('Signature status for {0}: {1}' -f $resolvedPath, $signature.Status)
}
