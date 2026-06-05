# UPDATE-002 Download Landing Page

## Goal

Give staff one public download page for the latest OpsHub client packages without
requiring a new APK/Windows build when only the landing page changes.

## Contract

- `GET /download` serves a static public landing page for internal staff.
- `GET /download/` redirects to `/download`.
- The root path `/` remains reserved for a future web app.
- The landing page reads `GET /downloads/latest.json` and renders download links
  for Android APK, Windows setup EXE, Windows portable ZIP, and the Windows
  SHA256 checksum file.
- Normal `main` deploys still build APK, Windows installer, Windows ZIP, and a
  fresh `latest.json` manifest, but the build jobs upload client packages
  directly to VPS staging instead of storing them as GitHub Actions artifacts.
- Manual `workflow_dispatch` with `skip_client_build=true` does not rebuild APK,
  Windows installer, Windows ZIP, backend images, or app-version metadata. It
  uploads the static landing files, regenerates `latest.json` from live metadata
  plus existing downloadable files, updates the current Caddyfile, and reloads
  Caddy.

## Validation

- Current patch validation: `git diff --check`, workflow YAML parse,
  `node --check scripts/download-manifest.mjs`, temp artifact manifest smoke,
  live artifact manifest smoke against the current public APK/EXE/ZIP/checksum,
  inline HTML JavaScript syntax check, and local static route smoke for
  `/download`, `/download/`, `/downloads/latest.json`, and the icon asset.
- Local Caddy validation was unavailable because neither a local `caddy` binary
  nor a running Docker daemon was available. The workflow validates the Caddyfile
  on the VPS with `caddy:2-alpine` before applying it.
- Live proof after rollout: dispatch with `skip_client_build=true`, verify build
  jobs are skipped, then smoke `/download`, `/downloads/latest.json`, all file
  URLs in the manifest, and unchanged Android/Windows app-version metadata.
