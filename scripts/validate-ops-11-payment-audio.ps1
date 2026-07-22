$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-NativeStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  Write-Host "==> $Name"
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

Push-Location $repoRoot
try {
  Invoke-NativeStep 'Validate source payment audio pack' {
    python scripts/verify_payment_audio_assets.py `
      --pack windows/assets/payment_audio/piper_vi_vais1000_chunk_v1
  }
  Invoke-NativeStep 'Analyze Flutter' { flutter analyze --no-pub }
  Invoke-NativeStep 'Test payment and affected Flutter consumers' {
    flutter test --no-pub `
      test/payment_amount_audio_composer_test.dart `
      test/payment_wav_tools_test.dart `
      test/payment_monitor_provider_test.dart `
      test/payment_speaker_io_test.dart `
      test/bank_statement_provider_test.dart `
      test/bank_statement_screen_test.dart `
      test/vietqr_screen_test.dart `
      test/realtime_connection_manager_test.dart
  }
  Push-Location (Join-Path $repoRoot 'backend-nest')
  try {
    Invoke-NativeStep 'Build NestJS' { npm run build }
    Invoke-NativeStep 'Test payment notification backend' {
      npm test -- --runInBand src/payment-notifications/payment-notifications.service.spec.ts
    }
  } finally {
    Pop-Location
  }
  Push-Location (Join-Path $repoRoot 'backend-go')
  try {
    Invoke-NativeStep 'Test realtime gateway' { go test ./... }
  } finally {
    Pop-Location
  }
  Invoke-NativeStep 'Build Windows Release' {
    flutter build windows --release --no-pub
  }
  Invoke-NativeStep 'Validate Windows Release payment audio pack' {
    python scripts/verify_payment_audio_assets.py `
      --pack build/windows/x64/runner/Release/data/payment_audio/piper_vi_vais1000_chunk_v1
  }
  Invoke-NativeStep 'Check Git diff whitespace' { git diff --check }
} finally {
  Pop-Location
}
