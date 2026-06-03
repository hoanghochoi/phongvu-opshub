# WINDOWS-DIST-001 Windows Internal Distribution Trust

## Goal

Reduce Windows and browser trust warnings for internal staff rollout without
using Microsoft Store or buying a public code-signing certificate.

## Contract

- GitHub Actions keeps building the existing Windows ZIP and Inno installer.
- If `WINDOWS_SIGNING_PFX_BASE64` and `WINDOWS_SIGNING_PFX_PASSWORD` are set,
  the workflow signs `phongvu_opshub.exe` before packaging and signs the final
  installer EXE after Inno compilation.
- If signing secrets are missing, the workflow continues unsigned and logs the
  unsigned state instead of failing release builds.
- When signing secrets are present, the workflow exports the public `.cer` from
  the PFX and passes it to Inno so the installer imports the certificate into the
  current user's `Trusted Root Certification Authorities` and `Trusted
  Publishers` stores on first run.
- Direct Windows downloads publish a SHA256 checksum file beside the ZIP and
  installer EXE. Checksums are generated after signing.
- Documentation defines the internal trust requirement: deploy the public code-
  signing certificate to `Trusted Root Certification Authorities` and `Trusted
  Publishers` on target PCs.
- Store/MSIX distribution is out of scope for this internal-only rollout.

## Validation

- Run Flutter dependency resolution, static analysis, and tests.
- Build the Windows release app.
- Compile the Inno installer.
- Compile the Inno installer with and without the optional internal certificate
  define.
- Generate and inspect the Windows `.sha256` file.
- Parse the GitHub workflow YAML.
- Run `git diff --check`.
- Manual gap: signed CI run requires real GitHub signing secrets; target-PC
  warning smoke requires a managed PC with the public `.cer` installed.
