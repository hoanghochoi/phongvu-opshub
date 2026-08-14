param(
  [switch]$CleanupOnly,
  [string]$CleanupPath
)

$ErrorActionPreference = 'Stop'

function Remove-Ops40TempCluster([string]$Path) {
  $expectedRoot = [IO.Path]::GetFullPath($env:TEMP)
  $resolved = [IO.Path]::GetFullPath($Path)
  $leaf = [IO.Path]::GetFileName($resolved)
  if (
    -not $resolved.StartsWith(
      $expectedRoot,
      [StringComparison]::OrdinalIgnoreCase
    ) -or
    $leaf -notmatch '^opshub-ops40-pg-[0-9a-f]{32}$'
  ) {
    throw 'Unsafe PostgreSQL proof cleanup target.'
  }
  if (Test-Path -LiteralPath $resolved) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

if ($CleanupOnly) {
  if ([string]::IsNullOrWhiteSpace($CleanupPath)) {
    throw 'CleanupPath is required for cleanup-only mode.'
  }
  Remove-Ops40TempCluster $CleanupPath
  Write-Output 'OPS40_POSTGRES_TEMP_CLEANUP_PASS'
  exit 0
}

$pgBin = $env:OPSHUB_POSTGRES_BIN
if ([string]::IsNullOrWhiteSpace($pgBin)) {
  $initdb = Get-Command initdb.exe -ErrorAction SilentlyContinue
  if ($initdb) {
    $pgBin = Split-Path -Parent $initdb.Source
  }
}
if ([string]::IsNullOrWhiteSpace($pgBin)) {
  throw 'Set OPSHUB_POSTGRES_BIN to a PostgreSQL bin directory for proof.'
}
$pgBin = [IO.Path]::GetFullPath($pgBin)
$required = @('initdb.exe', 'pg_ctl.exe', 'createdb.exe', 'psql.exe')
foreach ($name in $required) {
  if (-not (Test-Path -LiteralPath (Join-Path $pgBin $name))) {
    throw "PostgreSQL proof binary missing: $name"
  }
}

$token = [guid]::NewGuid().ToString('N')
$expectedRoot = [IO.Path]::GetFullPath($env:TEMP)
$tempRoot = [IO.Path]::GetFullPath(
  (Join-Path $expectedRoot "opshub-ops40-pg-$token")
)
if (-not $tempRoot.StartsWith(
  $expectedRoot,
  [StringComparison]::OrdinalIgnoreCase
)) {
  throw 'Unsafe PostgreSQL proof directory.'
}

$port = Get-Random -Minimum 55500 -Maximum 55999
$database = 'opshub_ops40'
$started = $false
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$freshSql = @'
SELECT (to_regclass('"SupportConversation"') IS NOT NULL)::int || ':' ||
       (SELECT is_nullable FROM information_schema.columns
        WHERE table_name='SupportConversation' AND column_name='requesterId') || ':' ||
       (SELECT confdeltype FROM pg_constraint
        WHERE conname='SupportConversation_requesterId_fkey');
'@
$rollbackSql = @'
SELECT (to_regclass('"SupportConversation"') IS NULL)::int || ':' ||
       (to_regclass('"User"') IS NOT NULL)::int || ':' ||
       (to_regclass('"MediaObject"') IS NOT NULL)::int || ':' ||
       (to_regclass('"DomainOutboxEvent"') IS NOT NULL)::int;
'@

try {
  & (Join-Path $pgBin 'initdb.exe') `
    -D $tempRoot -U postgres -A trust --encoding=UTF8 --locale=C | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "initdb failed: $LASTEXITCODE" }

  & (Join-Path $pgBin 'pg_ctl.exe') `
    -D $tempRoot `
    -l (Join-Path $tempRoot 'postgres.log') `
    -o "-p $port -h 127.0.0.1" -w start
  if ($LASTEXITCODE -ne 0) { throw "pg_ctl start failed: $LASTEXITCODE" }
  $started = $true

  & (Join-Path $pgBin 'createdb.exe') `
    -h 127.0.0.1 -p $port -U postgres $database
  if ($LASTEXITCODE -ne 0) { throw "createdb failed: $LASTEXITCODE" }

  $env:DATABASE_URL = "postgresql://postgres@127.0.0.1:$port/$database?schema=public"
  & node ..\scripts\run-with-toolchain.mjs `
    --root .. `
    --profile nestjs `
    --cwd backend-nest `
    -- npx --no-install prisma migrate deploy
  if ($LASTEXITCODE -ne 0) {
    throw "fresh Prisma migration failed: $LASTEXITCODE"
  }

  $fresh = & (Join-Path $pgBin 'psql.exe') `
    -h 127.0.0.1 -p $port -U postgres -d $database -Atc $freshSql
  if ($LASTEXITCODE -ne 0 -or $fresh.Trim() -ne '1:YES:n') {
    throw "fresh verification failed: $fresh"
  }
  Write-Output "OPS40_POSTGRES_FRESH_PASS=$fresh"

  & (Join-Path $pgBin 'psql.exe') -v ON_ERROR_STOP=1 `
    -h 127.0.0.1 -p $port -U postgres -d $database `
    -f 'prisma/migrations/20260801090000_support_chat_phase1/rollback.sql' |
    Out-Host
  if ($LASTEXITCODE -ne 0) { throw "rollback failed: $LASTEXITCODE" }

  $rollback = & (Join-Path $pgBin 'psql.exe') `
    -h 127.0.0.1 -p $port -U postgres -d $database -Atc $rollbackSql
  if ($LASTEXITCODE -ne 0 -or $rollback.Trim() -ne '1:1:1:1') {
    throw "rollback verification failed: $rollback"
  }
  Write-Output "OPS40_POSTGRES_ROLLBACK_PASS=$rollback"

  & (Join-Path $pgBin 'psql.exe') -v ON_ERROR_STOP=1 `
    -h 127.0.0.1 -p $port -U postgres -d $database `
    -f 'prisma/migrations/20260801090000_support_chat_phase1/migration.sql' |
    Out-Host
  if ($LASTEXITCODE -ne 0) { throw "upgrade apply failed: $LASTEXITCODE" }

  $upgrade = & (Join-Path $pgBin 'psql.exe') `
    -h 127.0.0.1 -p $port -U postgres -d $database -Atc $freshSql
  if ($LASTEXITCODE -ne 0 -or $upgrade.Trim() -ne '1:YES:n') {
    throw "upgrade verification failed: $upgrade"
  }
  Write-Output "OPS40_POSTGRES_UPGRADE_PASS=$upgrade"
} finally {
  if ($started) {
    & (Join-Path $pgBin 'pg_ctl.exe') -D $tempRoot -m fast -w stop
  }
  Remove-Ops40TempCluster $tempRoot
}
