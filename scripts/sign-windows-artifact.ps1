param(
  [Parameter(Mandatory = $true)]
  [string[]]$Path,

  [string]$PfxPath = $env:WINDOWS_SIGNING_PFX_PATH,
  [string]$PfxPassword = $env:WINDOWS_SIGNING_PFX_PASSWORD,
  [string]$TrustedSignerSha256 = $env:WINDOWS_UPDATE_SIGNER_SHA256
)

$ErrorActionPreference = 'Stop'

function Invoke-SignTool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ToolPath,

    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,

    [int]$TimeoutSeconds = 180
  )

  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  $stdout = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
  $stderr = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
  $process = [System.Diagnostics.Process]::new()

  try {
    $process.StartInfo.FileName = $ToolPath
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) {
      [void]$process.StartInfo.ArgumentList.Add($argument)
    }

    $stdoutHandler = [System.Diagnostics.DataReceivedEventHandler]{
      param($sender, $eventArgs)
      if ($null -ne $eventArgs.Data) {
        $stdout.Enqueue($eventArgs.Data)
      }
    }
    $stderrHandler = [System.Diagnostics.DataReceivedEventHandler]{
      param($sender, $eventArgs)
      if ($null -ne $eventArgs.Data) {
        $stderr.Enqueue($eventArgs.Data)
      }
    }
    $process.add_OutputDataReceived($stdoutHandler)
    $process.add_ErrorDataReceived($stderrHandler)

    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      try {
        $process.Kill($true)
      } catch {
        $process.Kill()
      }
      throw "signtool timed out after ${TimeoutSeconds}s."
    }
    $process.WaitForExit()

    $timer.Stop()
    [string]$line = $null
    while ($stdout.TryDequeue([ref]$line)) {
      Write-Host $line
    }
    while ($stderr.TryDequeue([ref]$line)) {
      Write-Host "signtool stderr: $line"
    }
    Write-Host ('signtool completed: exitCode={0}, durationMs={1}' -f $process.ExitCode, $timer.ElapsedMilliseconds)
    return $process.ExitCode
  } finally {
    if ($timer.IsRunning) {
      $timer.Stop()
    }
    if ($null -ne $process) {
      $process.Dispose()
    }
  }
}

function Get-SignToolPath {
  $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
  if (Test-Path $kitsRoot) {
    $candidatePath = Join-Path $kitsRoot '*\x64\signtool.exe'
    $candidate = Get-ChildItem -Path $candidatePath -File -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($candidate) {
      Write-Host "Using Windows SDK signtool: $($candidate.FullName)"
      return $candidate.FullName
    }
  }

  $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($command) {
    Write-Host "Using PATH signtool: $($command.Source)"
    return $command.Source
  }

  throw 'signtool.exe was not found. Install the Windows SDK on the runner.'
}

function Add-PublicCertificateToStore {
  param(
    [Parameter(Mandatory = $true)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [Parameter(Mandatory = $true)]
    [System.Security.Cryptography.X509Certificates.StoreName]$StoreName
  )

  $publicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
  )
  $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
    $StoreName,
    [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
  )
  try {
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $store.Add($publicCertificate)
  } finally {
    $store.Dispose()
    $publicCertificate.Dispose()
  }
}

function Install-EphemeralSigningTrust {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [string]$CertificatePassword
  )

  $collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
  $collection.Import(
    $CertificatePath,
    $CertificatePassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
  )
  try {
    $signingCertificates = @($collection | Where-Object { $_.HasPrivateKey })
    if ($signingCertificates.Count -ne 1) {
      throw 'Windows signing PFX must contain exactly one certificate with a private key.'
    }

    $signer = $signingCertificates[0]
    Add-PublicCertificateToStore `
      -Certificate $signer `
      -StoreName ([System.Security.Cryptography.X509Certificates.StoreName]::TrustedPublisher)

    foreach ($certificate in $collection) {
      if ($certificate.Subject -eq $certificate.Issuer) {
        Add-PublicCertificateToStore `
          -Certificate $certificate `
          -StoreName ([System.Security.Cryptography.X509Certificates.StoreName]::Root)
      } elseif ($certificate.Thumbprint -ne $signer.Thumbprint) {
        Add-PublicCertificateToStore `
          -Certificate $certificate `
          -StoreName ([System.Security.Cryptography.X509Certificates.StoreName]::CertificateAuthority)
      }
    }
  } finally {
    foreach ($certificate in $collection) {
      $certificate.Dispose()
    }
  }
}

if ([string]::IsNullOrWhiteSpace($PfxPath) -or -not (Test-Path $PfxPath)) {
  throw 'Windows signing PFX path is missing or does not exist.'
}

if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
  throw 'Windows signing PFX password is missing.'
}

$trustedPins = @($TrustedSignerSha256 -split '[,;\s]+' |
  ForEach-Object { $_.Replace(':', '').ToUpperInvariant() } |
  Where-Object { $_ })
if ($trustedPins.Count -eq 0 -or @($trustedPins | Where-Object { $_ -notmatch '^[0-9A-F]{64}$' }).Count -gt 0) {
  throw 'WINDOWS_UPDATE_SIGNER_SHA256 must contain valid SHA-256 certificate fingerprints.'
}

$signTool = Get-SignToolPath
Install-EphemeralSigningTrust -CertificatePath $PfxPath -CertificatePassword $PfxPassword

foreach ($item in $Path) {
  $resolvedPath = (Resolve-Path $item).Path
  Write-Host "Signing Windows artifact: $resolvedPath"

  $signExitCode = Invoke-SignTool `
    -ToolPath $signTool `
    -ArgumentList @('sign', '/fd', 'SHA256', '/f', $PfxPath, '/p', $PfxPassword, '/tr', 'http://timestamp.digicert.com', '/td', 'SHA256', $resolvedPath)
  if ($signExitCode -ne 0) {
    throw "Timestamped signtool failed for $resolvedPath with exit code $signExitCode."
  }

  $signature = Get-AuthenticodeSignature -FilePath $resolvedPath
  if ($null -eq $signature.SignerCertificate) {
    throw "Windows artifact signer certificate is missing after signing: $resolvedPath"
  }
  if ($null -eq $signature.TimeStamperCertificate) {
    throw "Windows artifact RFC 3161 timestamp is missing after signing: $resolvedPath"
  }
  $algorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
  $actualPin = $signature.SignerCertificate.GetCertHashString($algorithm).ToUpperInvariant()
  if ($actualPin -notin $trustedPins) {
    throw "Windows artifact signer does not match the pinned publisher: $resolvedPath"
  }

  $statusName = [string]$signature.Status
  if ($statusName -ne 'Valid') {
    throw "Windows artifact signature verification failed with status ${statusName}: $resolvedPath"
  }

  $verifyExitCode = Invoke-SignTool `
    -ToolPath $signTool `
    -ArgumentList @('verify', '/pa', '/all', '/v', $resolvedPath)
  if ($verifyExitCode -ne 0) {
    throw "Timestamped Authenticode verification failed for $resolvedPath with exit code $verifyExitCode."
  }

  Write-Host ('Signature status for {0}: {1}' -f $resolvedPath, $statusName)
}
