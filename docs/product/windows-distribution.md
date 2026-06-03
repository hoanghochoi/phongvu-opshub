# Windows Internal Distribution And Download Trust

## Contract

- OpsHub Windows distribution is internal-only. The primary package is the Inno
  Setup installer EXE; the portable ZIP remains a manual fallback.
- The preferred free trust path is internal Authenticode signing: sign the app
  executable and installer with a self-signed or company-issued code-signing
  certificate, then deploy the public certificate to company PCs.
- A self-signed signature only helps machines that trust the certificate. Install
  the public `.cer` into both `Trusted Root Certification Authorities` and
  `Trusted Publishers` on target Windows PCs.
- GitHub Actions signs Windows artifacts only when both
  `WINDOWS_SIGNING_PFX_BASE64` and `WINDOWS_SIGNING_PFX_PASSWORD` secrets are
  configured. Without those secrets, CI keeps building unsigned artifacts and
  logs that the Windows build is unsigned.
- When signing secrets are configured, CI exports the public certificate from the
  PFX and bundles it into the Inno installer. The installer imports that `.cer`
  into the current Windows user's `Trusted Root Certification Authorities` and
  `Trusted Publishers` stores so later updates signed by the same certificate are
  already trusted for that user.
- Direct downloads still publish a SHA256 checksum file beside the Windows ZIP
  and installer EXE. The checksum is generated after signing, so it matches the
  final downloadable files.
- Browser warnings for uncommon downloads can still appear on public browser
  download paths. For internal rollout, prefer managed deployment, trusted
  intranet download, or an IT allow-list over asking staff to bypass warnings.
- The first install on a PC that does not already trust the certificate can still
  show browser or SmartScreen warnings, because the bundled certificate can only
  be installed after the user starts the installer.

## Internal Certificate Setup

- Create one long-lived internal code-signing certificate and keep the private
  PFX secret restricted to release automation.
- Export the public `.cer` file and deploy it to company PCs through GPO,
  Intune, device-management tooling, or a documented admin install step when the
  first install must avoid trust prompts. The installer also imports the bundled
  `.cer` for the current user after it starts.
- Add these GitHub repository secrets only after the certificate is created:
  `WINDOWS_SIGNING_PFX_BASE64` and `WINDOWS_SIGNING_PFX_PASSWORD`.
- Do not commit the PFX, password, private key, or real certificate files.

Example one-time certificate creation on a trusted Windows admin machine:

```powershell
$password = Read-Host 'PFX password' -AsSecureString
$cert = New-SelfSignedCertificate `
  -Type CodeSigningCert `
  -Subject 'CN=PhongVu OpsHub Internal Code Signing' `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -KeyAlgorithm RSA `
  -KeyLength 3072 `
  -HashAlgorithm SHA256 `
  -NotAfter (Get-Date).AddYears(3)
Export-PfxCertificate -Cert $cert -FilePath .\opshub-codesign.pfx -Password $password
Export-Certificate -Cert $cert -FilePath .\opshub-codesign.cer
[Convert]::ToBase64String([IO.File]::ReadAllBytes('.\opshub-codesign.pfx')) |
  Set-Content .\opshub-codesign.pfx.base64
```

Manual trust install on a target PC, run as Administrator:

```powershell
Import-Certificate -FilePath .\opshub-codesign.cer `
  -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath .\opshub-codesign.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

## Release Checklist

- Confirm Windows signing secrets are present before expecting signed artifacts.
- Verify `Get-AuthenticodeSignature` on the final installer is not `NotSigned`.
  A self-signed certificate may report `UnknownError` on machines that have not
  trusted the public `.cer`; the target staff PCs must trust the certificate for
  Windows to treat the publisher as trusted.
- Publish the installer EXE, portable ZIP, and `.sha256` file together.
- Do not rebuild or repack an already published version under the same name.
- Scan final artifacts with Microsoft Defender before rollout.
- If Defender, Edge, Chrome, or Safe Browsing flags the file as malware or
  unwanted software, preserve the exact file and SHA256, then submit it for
  vendor review instead of asking staff to bypass the warning.
