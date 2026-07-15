# Windows Internal Distribution And Download Trust

## Contract

- OpsHub direct Windows distribution is internal-only. The primary package is
  the Inno Setup installer EXE; the portable ZIP remains a manual fallback.
- New Windows clients update without opening the browser or waiting for a button
  press: when `AppUpdateGate` detects a newer build, it downloads the installer
  EXE from `/app-version.packageUrl`, verifies `packageSha256` and
  `packageSizeBytes`, launches the Inno installer with the published silent
  args, then exits so Setup can replace the running app.
- The runtime updater is checksum-only by product decision: it keeps the HTTPS
  build-scoped host/path allowlist, redirect rejection, package type/size checks,
  and exact SHA-256 verification, but does not require Windows Authenticode to
  report `Valid` and does not enforce a signer pin before launching Setup.
- Authenticode signing, timestamp verification, configured signer-pin matching
  and Microsoft Defender scanning remain mandatory CI release gates for both
  staging and production. An unsigned artifact is never published.
  Runtime checksum-only verification cannot protect against an attacker who
  replaces both release metadata and the hosted package; restore a public-CA or
  centrally managed certificate trust rollout before re-enabling a runtime
  Authenticode gate.
- If automatic installation fails, the blocking update prompt clears stale
  progress, explains that the automatic install did not finish, offers `Thử
  lại`, and provides `Cập nhật thủ công` as a browser fallback to `/download`.
  The technical failure reason remains in `AppLogger` for support diagnosis.
- Microsoft Store/MSIX packaging is a separate submission track. The manual
  `Build Windows MSIX Store Package` workflow may build a Store MSIX artifact,
  but it must not publish to `/download`, change `/app-version`, or replace the
  EXE update URL until Store rollout proof exists.
- CI always applies internal Authenticode signing with a self-signed or
  company-issued code-signing certificate. Managed OS publisher trust is a
  separate rollout step: IT deploys the matching public certificate to company
  PCs when the publisher must appear trusted without a first-run warning.
- A self-signed signature only helps machines that trust the certificate. Install
  the public `.cer` into both `Trusted Root Certification Authorities` and
  `Trusted Publishers` on target Windows PCs.
- GitHub Actions requires `WINDOWS_SIGNING_PFX_BASE64`,
  `WINDOWS_SIGNING_PFX_PASSWORD` and the configured signer fingerprint for a
  production release; staging requires the corresponding `WINDOWS_STAGING_*`
  values. A missing PFX/password/pin, invalid signature/timestamp, pin mismatch
  or unsigned file fails the workflow before publication.
- Before verification, CI imports only the PFX's public signer/issuer
  certificates into the ephemeral runner's current-user trust stores. A
  self-signed signer is added to that runner's Root and Trusted Publishers
  stores; a private-CA PFX must include its issuer chain. Verification accepts
  only `Get-AuthenticodeSignature` status `Valid`, a present RFC 3161 timestamp,
  and a successful `signtool verify`; `NotTrusted`/`UnknownError` never pass from
  a matching pin alone.
- CI signs the app and installer but never
  bundles or installs its own trust certificate. A package must not add its own
  signer to `Trusted Root Certification Authorities` or `Trusted Publishers`;
  IT deploys the public `.cer` separately through a managed channel.
- CI updates Microsoft Defender security intelligence and scans the final signed
  installer and portable ZIP before checksums are generated or files are
  uploaded. A missing scanner, failed update, detection, quarantine, or non-zero
  scan exit code blocks the release. CI may retry a transient Defender
  signature-update lock from the Windows runner, but it must not skip the final
  artifact scan.
- Direct downloads still publish a SHA256 checksum file beside the Windows ZIP
  and installer EXE. The checksum is generated after signing, so it matches the
  final downloadable files.
- The staff download page is served at `/download` and reads
  `/downloads/latest.json` for the current APK, Windows installer, Windows ZIP,
  and checksum links.
- The download page links to the public `/help` page so staff can read setup
  and usage guidance before or after installing the app.
- Store MSIX artifacts are uploaded only as GitHub Actions artifacts. They are
  not copied to the VPS download directory and are not included in
  `/downloads/latest.json`.
- Manual GitHub Actions dispatch with `skip_client_build=true` may update only
  the download landing page, help page, Caddy route, icon, and manifest from
  already live artifacts. This path must not create a new Windows package,
  change app-version metadata, or repack an existing version.
- Browser warnings for uncommon downloads can still appear on public browser
  download paths. For internal rollout, prefer managed deployment, trusted
  intranet download, or an IT allow-list over asking staff to bypass warnings.
- The first install on a PC that does not already trust the certificate can still
  show browser or SmartScreen warnings. Provision the public certificate before
  download when the first install must be warning-free; do not ask staff to
  bypass a Defender malware detection.

## Internal Certificate Setup

- Create one long-lived internal code-signing certificate and keep the private
  PFX secret restricted to release automation.
- Export the public `.cer` file and deploy it to company PCs through GPO,
  Intune, device-management tooling, or a documented admin install step when the
  first install must avoid trust prompts. The installer deliberately does not
  import or trust the certificate itself.
- Add these GitHub Environment values only after the certificate is created:
  secrets `WINDOWS_SIGNING_PFX_BASE64` and
  `WINDOWS_SIGNING_PFX_PASSWORD`, plus variable
  `WINDOWS_UPDATE_SIGNER_SHA256`. Configure the corresponding
  `WINDOWS_STAGING_*` values in the staging environment. The signer fingerprint
  remains a CI input and is not a Flutter runtime build define.
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

- Confirm the required PFX, password and signer-pin values are present; a
  Windows release must fail rather than produce an unsigned artifact when any
  value is missing.
- For Microsoft Store submissions, confirm the Store identity secrets are
  present in the selected GitHub environment:
  `WINDOWS_MSIX_IDENTITY_NAME`, `WINDOWS_MSIX_PUBLISHER`,
  `WINDOWS_MSIX_PUBLISHER_DISPLAY_NAME`, and optionally
  `WINDOWS_MSIX_DISPLAY_NAME`.
- Confirm the `Scan final Windows artifacts with Microsoft Defender` workflow
  step passed after signing and before checksum generation.
- Confirm the separate Store MSIX workflow passed its Microsoft Defender scan
  before uploading the MSIX to Partner Center.
- Verify CI reports `Get-AuthenticodeSignature` as `Valid` for the final
  executable and installer, the signer fingerprint matches the configured pin,
  and timestamp evidence is valid. Target staff PCs still need the public
  certificate provisioned for a self-signed publisher to appear trusted.
- Publish the installer EXE, portable ZIP, and `.sha256` file together.
- Verify `/download` and `/downloads/latest.json` point to the same installer,
  portable ZIP, and checksum files after release.
- Verify `/api/app-version?platform=windows` includes the same installer URL in
  `updateUrl` and `packageUrl`, a 64-character lowercase SHA-256 in
  `packageSha256`, a positive `packageSizeBytes`, `packageType` of
  `windowsInstaller`, and silent Inno args including `/VERYSILENT`.
- Verify the Flutter build inputs and compiled runtime contain no
  `WINDOWS_UPDATE_SIGNER_SHA256`; signer verification belongs only to the CI
  release gate.
- Do not rebuild or repack an already published version under the same name.
- Scan final artifacts with Microsoft Defender before rollout.
- If Defender, Edge, Chrome, or Safe Browsing flags the file as malware or
  unwanted software, preserve the exact file and SHA256, then submit it for
  vendor review instead of asking staff to bypass the warning.
- Do not point `APP_WINDOWS_APP_UPDATE_URL` at a Store/MSIX artifact until
  Windows startup, restart, payment audio, logs, and update prompt have been
  smoked under MSIX packaging.
