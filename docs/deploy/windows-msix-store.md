# Windows MSIX Packaging

OpsHub keeps the current Windows runtime distribution unchanged: production and
staging deploys still publish the Inno Setup `.exe`, portable `.zip`, checksum,
`/download`, and `/app-version?platform=windows` metadata. The MSIX path is
artifact-only and must not become the runtime update URL until the selected
MSIX channel has its own smoke proof.

## Internal Sideload MSIX

When Partner Center identity secrets are not ready, build an internal signed
MSIX with the same Windows signing PFX used for the direct EXE installer. This
is useful for controlled IT testing, but it is not a Store submission package
and does not by itself bypass Microsoft Defender malware detections.

Required secrets in the selected GitHub environment:

- Production: `WINDOWS_SIGNING_PFX_BASE64` and `WINDOWS_SIGNING_PFX_PASSWORD`.
- Staging: `WINDOWS_STAGING_SIGNING_PFX_BASE64` and
  `WINDOWS_STAGING_SIGNING_PFX_PASSWORD`.

Run the manual workflow:

```powershell
gh workflow run "Build Windows MSIX Package" `
  --ref main `
  -f environment=production `
  -f package_kind=internal `
  -f version_name=2026.07.01.102 `
  -f version_code=100102 `
  -f msix_version=2026.7.1.102
```

The workflow compiles the Windows app with the selected API base URL, creates a
signed internal MSIX under `build/windows/msix`, scans it with Microsoft
Defender, and uploads the `.msix` plus `.sha256` as a GitHub Actions artifact.
It does not SSH to the VPS, does not update `/srv/opshub/downloads`, and does
not change `APP_WINDOWS_APP_UPDATE_URL`.

## Required Store Identity

Create these secrets in the GitHub environment that will build the package
(`production` first; `staging` only if a separate Store identity exists):

- `WINDOWS_MSIX_IDENTITY_NAME`: Partner Center package identity name.
- `WINDOWS_MSIX_PUBLISHER`: Partner Center package publisher, usually a
  `CN=...` value.
- `WINDOWS_MSIX_PUBLISHER_DISPLAY_NAME`: public publisher display name from
  Partner Center.
- `WINDOWS_MSIX_DISPLAY_NAME`: optional. Defaults to `PhongVu OpsHub`.

Do not reuse the internal Inno/Authenticode PFX for Store submission. The MSIX
workflow builds with `--store --sign-msix false`, and Microsoft Store signs the
package after submission.

## Build Command

Run the manual workflow for Partner Center submission:

```powershell
gh workflow run "Build Windows MSIX Package" `
  --ref main `
  -f environment=production `
  -f package_kind=store
```

Use the branch/ref that contains the workflow. While this change is being
validated, that can be `staging`; after merge, use `main` for a production Store
submission.

Optional version override for a Partner Center resubmission:

```powershell
gh workflow run "Build Windows MSIX Package" `
  --ref main `
  -f environment=production `
  -f package_kind=store `
  -f version_name=2026.06.27.1 `
  -f version_code=100001 `
  -f msix_version=2026.6.27.1
```

The workflow compiles the Windows app with the selected API base URL, creates a
Store MSIX under `build/windows/msix`, scans it with Microsoft Defender, and
uploads the `.msix` plus `.sha256` as a GitHub Actions artifact. It does not SSH
to the VPS, does not update `/srv/opshub/downloads`, and does not change
`APP_WINDOWS_APP_UPDATE_URL`.

## Local Smoke

After a Windows release build exists, the packaging step can be checked locally:

```powershell
$env:WINDOWS_MSIX_IDENTITY_NAME = '<Partner Center identity name>'
$env:WINDOWS_MSIX_PUBLISHER = 'CN=<Partner Center publisher>'
$env:WINDOWS_MSIX_PUBLISHER_DISPLAY_NAME = '<Partner Center publisher name>'
$env:WINDOWS_MSIX_VERSION = '2026.6.27.1'

.\scripts\build-windows-msix-store.ps1 `
  -OutputName phongvu-opshub-windows-store-local
```

For local install testing outside Store submission, use a disposable test
identity/certificate path in a separate sandbox. Do not overwrite production
Store identity values just to smoke local install.

## Rollout Guard

Before switching any user-facing update path from EXE to Store/MSIX, verify all
of the following:

- Existing production `.exe` update prompt still opens the Inno installer URL.
- `/download` and `/downloads/latest.json` still expose EXE, ZIP, and checksum.
- Internal MSIX has a Defender scan pass and the package signature is not
  `NotSigned`.
- Partner Center accepts the MSIX package identity, publisher, and version.
- A clean Windows VM can install/update through the selected MSIX channel.
- Windows startup toggle, app restart, payment audio, local logs, and app update
  prompt have separate MSIX smoke evidence.
