# WINDOWS-DIST-001 Windows Internal Distribution Trust

## Goal

Reduce Windows and browser trust warnings for internal staff rollout without
using Microsoft Store or buying a public code-signing certificate.

## Contract

- GitHub Actions keeps building the existing Windows ZIP and Inno installer.
- Production requires `WINDOWS_SIGNING_PFX_BASE64`,
  `WINDOWS_SIGNING_PFX_PASSWORD` and the configured signer fingerprint;
  staging requires the corresponding `WINDOWS_STAGING_*` values. The workflow
  signs `phongvu_opshub.exe` before packaging and the final installer after Inno
  compilation.
- Missing PFX/password/pin, an unsigned or invalid Authenticode signature, an
  invalid timestamp, or a signer-pin mismatch fails the release before upload.
- The installer never bundles, imports, or trusts its own signing certificate.
  The public `.cer` is provisioned separately through GPO, Intune, device
  management, or a documented administrator step.
- CI validates Authenticode, timestamp and signer pin, then updates Microsoft
  Defender security intelligence and scans
  the final installer and portable ZIP. Any unavailable scanner, failed update,
  detection, quarantine, or non-zero scan exit blocks publication.
- Direct Windows downloads publish a SHA256 checksum file beside the ZIP and
  installer EXE. Checksums are generated after signing.
- Documentation defines the internal trust requirement: deploy the public code-
  signing certificate to `Trusted Root Certification Authorities` and `Trusted
  Publishers` on target PCs.
- MSIX distribution is in scope as a separate manual packaging path. The MSIX
  workflow can build an internal signed sideload artifact with the Windows
  signing PFX, or a Store artifact with Partner Center identity secrets. Neither
  path deploys to the VPS or changes the live EXE/ZIP/download/app-version
  runtime contract.

## Validation

- Run Flutter dependency resolution, static analysis, and tests.
- Build the Windows release app.
- Compile the Inno installer.
- Compile the Inno installer and verify it contains no certificate-import path.
- Parse and smoke-test the Defender release-gate PowerShell script.
- Scan the local installer and portable ZIP with Microsoft Defender.
- Generate and inspect the Windows `.sha256` file.
- Parse the GitHub workflow YAML.
- Build the internal MSIX with Windows signing secrets or the Store MSIX with
  Partner Center identity secrets, scan it with Microsoft Defender, and upload
  the MSIX plus checksum as workflow artifacts.
- Run `git diff --check`.
- Signed CI proof must show the final Defender gate passing before checksums and
  upload, plus valid Authenticode/timestamp and a matching signer pin. Target-PC
  trust still requires a managed PC with the public `.cer` installed separately.
- Store/MSIX proof must also show the selected channel's identity/signature
  acceptance, Partner Center identity acceptance when applicable, and a clean
  install/update smoke before replacing any EXE update path.
