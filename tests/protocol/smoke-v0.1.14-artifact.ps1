param(
    [Parameter(Mandatory = $true)]
    [string]$Artifact
)

# Frozen compatibility contract for the immutable initial protocol release.
# Do not add current behavior here; current candidates use smoke-native-artifact.ps1.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$BaselineCommit = "d2f89eeabe8d01df95fd19cd6ba981b01a71730f"
$Artifact = (Resolve-Path $Artifact).Path
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("harness-v0.1.14-" + [guid]::NewGuid())
$Db = Join-Path $Temp "harness.db"

$Version = @(& $Artifact --version) -join "`n"
if ($LASTEXITCODE -ne 0 -or $Version.Trim() -ne "harness-cli 0.1.14") {
    throw "Frozen v0.1.14 smoke received the wrong binary: $Version"
}

function Invoke-HarnessJson {
    param(
        [string[]]$Arguments,
        [int]$ExpectedExit = 0
    )
    $stderr = Join-Path $Temp ("stderr-" + [guid]::NewGuid() + ".txt")
    $lines = @(& $Artifact @Arguments 2>$stderr)
    $exit = $LASTEXITCODE
    if ($exit -ne $ExpectedExit) {
        $detail = if (Test-Path $stderr) { Get-Content -Raw $stderr } else { "" }
        $text = $lines -join "`n"
        throw "Harness '$($Arguments -join ' ')' exited $exit, expected $ExpectedExit. stdout=$text stderr=$detail"
    }
    $text = $lines -join "`n"
    try { return $text | ConvertFrom-Json -Depth 100 }
    catch { throw "Harness did not emit one JSON document: $text" }
}

try {
    New-Item -ItemType Directory -Force $Temp | Out-Null
    $CommitObject = $BaselineCommit + "^{commit}"
    & git -C $RepoRoot cat-file -e $CommitObject
    if ($LASTEXITCODE -ne 0) { throw "Frozen schema commit is unavailable: $BaselineCommit" }
    $SchemaArchive = Join-Path $Temp "v0.1.14-schema.tar"
    & git -C $RepoRoot archive --format=tar "--output=$SchemaArchive" $BaselineCommit scripts/schema
    if ($LASTEXITCODE -ne 0) { throw "Could not archive frozen v0.1.14 schema" }
    & tar -xf $SchemaArchive -C $Temp
    if ($LASTEXITCODE -ne 0) { throw "Could not extract frozen v0.1.14 schema" }

    $env:HARNESS_REPO_ROOT = $Temp
    $env:HARNESS_DB_PATH = $Db

    $contract = Invoke-HarnessJson -Arguments @("query", "contract", "--json")
    if ($contract.result.cli_version -ne "0.1.14" -or
        $contract.result.schema_maximum -ne 13 -or
        $contract.result.database_state -ne "missing" -or
        (Test-Path $Db)) {
        throw "Frozen contract discovery drifted or mutated the missing database"
    }

    & $Artifact init | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "harness init failed" }
    $null = Invoke-HarnessJson -Arguments @("story", "add", "--id", "US-A", "--title", "Alpha", "--lane", "normal", "--verify", "true", "--json")
    $null = Invoke-HarnessJson -Arguments @("story", "add", "--id", "US-B", "--title", "Beta", "--lane", "normal", "--verify", "true", "--json")
    $null = Invoke-HarnessJson -Arguments @("story", "dependency", "add", "--blocker", "US-A", "--blocked", "US-B", "--json")
    $null = Invoke-HarnessJson -Arguments @("story", "hierarchy", "add", "--parent", "US-A", "--child", "US-B", "--json")
    $graph = Invoke-HarnessJson -Arguments @("query", "work-graph", "--json")
    if ($graph.result.revision.Length -ne 64 -or $graph.result.dependencies.Count -ne 1 -or $graph.result.hierarchy.Count -ne 1) {
        throw "Frozen work graph contract is incomplete"
    }

    # This direct transition is historical v0.1.14 behavior, not a current rule.
    $cas = Invoke-HarnessJson -Arguments @("story", "update", "--id", "US-A", "--status", "implemented", "--expected-status", "planned", "--require-runnable", "--json")
    if ($cas.result.before_status -ne "planned" -or $cas.result.after_status -ne "implemented") {
        throw "Frozen CAS result did not report the transition"
    }
    $conflict = Invoke-HarnessJson -Arguments @("story", "hierarchy", "add", "--parent", "US-B", "--child", "US-A", "--json") -ExpectedExit 3
    if ($conflict.error.code -ne "CONFLICT") { throw "Frozen hierarchy cycle was not a stable conflict" }

    $changeset = Join-Path $Temp "protocol-smoke.jsonl"
    '{"base_schema_version":13,"op":"changeset.header","run_id":"protocol_smoke","version":1}' | Set-Content -Encoding utf8NoBOM $changeset
    $status = Invoke-HarnessJson -Arguments @("db", "changeset", "status", $changeset, "--json")
    if ($status.result.applied) { throw "Fresh frozen changeset unexpectedly reported applied" }
    $apply = Invoke-HarnessJson -Arguments @("db", "changeset", "apply", $changeset, "--json")
    if (-not $apply.result.applied -or $apply.result.content_sha256.Length -ne 64) { throw "Frozen changeset apply result is incomplete" }

    $SnapshotDir = Join-Path $Temp "path with spaces"
    New-Item -ItemType Directory -Force $SnapshotDir | Out-Null
    $Snapshot = Join-Path $SnapshotDir "snapshot.db"
    $snapshotResult = Invoke-HarnessJson -Arguments @("db", "snapshot", "--output", $Snapshot, "--json")
    if ($snapshotResult.result.snapshot_file_sha256.Length -ne 64 -or -not (Test-Path $Snapshot)) {
        throw "Frozen snapshot result is incomplete"
    }
    $env:HARNESS_DB_PATH = $Snapshot
    $snapshotContract = Invoke-HarnessJson -Arguments @("query", "contract", "--json")
    if ($snapshotContract.result.database_state -ne "current") { throw "Frozen snapshot is not current" }

    Write-Host "frozen harness-cli v0.1.14 PowerShell protocol smoke passed"
}
finally {
    Remove-Item Env:HARNESS_REPO_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:HARNESS_DB_PATH -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Temp -ErrorAction SilentlyContinue
}
