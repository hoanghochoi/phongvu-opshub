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

function Set-Utf8NoBomText {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )

  $encoding = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Apply-StagingWebShell {
  $indexPath = Join-RepoPath -Segments @('web', 'index.html')
  if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "Missing web index file: $indexPath"
  }

  $indexContent = [System.IO.File]::ReadAllText($indexPath)
  $indexContent = $indexContent.Replace(
    'PhongVu OpsHub - Operations Hub for PhongVu staff.',
    'PhongVu OpsHub Staging - Operations Hub staging environment for PhongVu staff.'
  )
  $indexContent = $indexContent.Replace(
    'content="PhongVu OpsHub"',
    'content="PhongVu OpsHub Staging"'
  )
  $indexContent = $indexContent.Replace(
    '<title>PhongVu OpsHub</title>',
    '<title>PhongVu OpsHub Staging</title>'
  )
  Set-Utf8NoBomText -Path $indexPath -Content $indexContent
  Write-Host "Applied staging web shell: $indexPath"

  $manifestPath = Join-RepoPath -Segments @('web', 'manifest.json')
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing web manifest file: $manifestPath"
  }

  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  $manifest.name = 'phongvu-opshub-staging'
  $manifest.short_name = 'OpsHub Staging'
  $manifest.description = 'PhongVu OpsHub Staging - Operations Hub staging environment for PhongVu staff.'
  $manifestJson = $manifest | ConvertTo-Json -Depth 16
  Set-Utf8NoBomText -Path $manifestPath -Content ($manifestJson + [Environment]::NewLine)
  Write-Host "Applied staging web manifest: $manifestPath"
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

  Apply-StagingWebShell
}
