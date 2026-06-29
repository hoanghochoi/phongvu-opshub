param(
  [ValidateSet('all', 'windows', 'web')]
  [string]$Platform = 'all'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$stagingIconRoot = Join-Path (Join-Path (Join-Path $repoRoot 'assets') 'icon') 'staging'

function Join-RepoPath {
  param(
    [Parameter(Mandatory = $true)][string[]]$Segments
  )

  $path = $repoRoot
  foreach ($segment in $Segments) {
    $path = Join-Path $path $segment
  }
  return $path
}

function Join-StagingIconPath {
  param(
    [Parameter(Mandatory = $true)][string[]]$Segments
  )

  $path = $stagingIconRoot
  foreach ($segment in $Segments) {
    $path = Join-Path $path $segment
  }
  return $path
}

function Copy-RequiredFile {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
    throw "Missing staging icon source: $Source"
  }

  $destinationDir = Split-Path -Parent $Destination
  if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Force
  Write-Host "Applied staging icon: $Destination"
}

if ($Platform -in @('all', 'windows')) {
  Copy-RequiredFile `
    -Source (Join-StagingIconPath -Segments @('windows', 'app_icon.ico')) `
    -Destination (Join-RepoPath -Segments @('windows', 'runner', 'resources', 'app_icon.ico'))
}

if ($Platform -in @('all', 'web')) {
  Copy-RequiredFile `
    -Source (Join-StagingIconPath -Segments @('web', 'favicon.png')) `
    -Destination (Join-RepoPath -Segments @('web', 'favicon.png'))

  foreach ($iconName in @('Icon-192.png', 'Icon-512.png', 'Icon-maskable-192.png', 'Icon-maskable-512.png')) {
    Copy-RequiredFile `
      -Source (Join-StagingIconPath -Segments @('web', 'icons', $iconName)) `
      -Destination (Join-RepoPath -Segments @('web', 'icons', $iconName))
  }
}
