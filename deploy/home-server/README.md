# OpsHub Home Server Deploy

Target layout:

- SSD runtime: containers, Postgres data, Redis data, upload images under `/srv/opshub`.
- TrueNAS backup: mount an SMB/NFS dataset at `/mnt/truenas/opshub-backups`.
- FIFO BigQuery cache can run while `DATA_SYNC_SOURCE=local`; legacy inventory
  and user BigQuery sync remain disabled unless explicitly configured.

## Live OpsHub Source Of Truth

- Production host alias from the developer machine: `ssh hoang-n8n`.
- Runtime env file: `/srv/opshub/env`.
- Current deployed release symlink: `/home/ubuntu/phongvu-opshub/current`.
- Compose file for runtime checks: `/home/ubuntu/phongvu-opshub/current/deploy/home-server/docker-compose.home.yml`.
- Piper TTS sidecar runs as `opshub-piper-tts.service` with
  `PIPER_LEADING_SILENCE_MS=0` and `PIPER_TAIL_SILENCE_MS=500`. The API uses
  `PAYMENT_CUE_GAIN=0.80`, so the quieter cue joins directly into the spoken
  "Phong Vũ" while only the final tail silence remains.
- MAP global sync reads `100` rows per MAP page and defaults to
  `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES=2`, for at most `200` rows per sync loop.
  After each backend MAP-history fetch finishes, the next scheduled fetch waits
  a random `3000`-`5000` ms. Background MAP sync runs only from `07:00` to
  before `22:00` Vietnam time.

## Checklist

1. Create folders on the home server:

```bash
sudo mkdir -p /srv/opshub/{postgres,redis,uploads,private-media,downloads,web,import,payment-audio,caddy/data,caddy/config}
sudo chown -R 1000:1000 /srv/opshub/{uploads,private-media,payment-audio,caddy/data,caddy/config}
sudo chmod 755 /srv/opshub/uploads
sudo chmod 700 /srv/opshub/{private-media,payment-audio}
sudo mkdir -p /mnt/truenas/opshub-backups
```

2. Copy `deploy/home-server/env.example` to `deploy/home-server/env` and replace all secrets/domain values.

   Registration and password reset code emails require SMTP settings in the env
   file: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, and
   `SMTP_FROM`. For Gmail, use an app password for `SMTP_USER`; `SMTP_FROM` can
   be the verified Gmail "Send mail as" alias `admin@hoanghochoi.com`.

3. Start the stack:

```bash
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile migrate run --rm migrate
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml up -d --build
```

Before `up`, verify the non-root API UID can write only its runtime data
directories:

```bash
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile maintenance run --rm --no-deps maintenance sh -eu -c 'for d in /data/app_images /data/private-media /data/payment-audio; do f="$d/.write-test-$$"; : > "$f"; rm -f "$f"; done'
```

`OPSHUB_ENV_FILE` is required for every runtime compose command. Do not rely on
`--env-file` alone: the compose services also read the same file through
`env_file`, and missing `OPSHUB_ENV_FILE` should stop the command immediately
instead of silently falling back to `deploy/home-server/env.example`.
Only the API container reads the full runtime env file. Infrastructure services
use explicit environment keys so changing app-version metadata does not recreate
Postgres, Redis, realtime, or Caddy by accident.

The long-running API uses the Dockerfile `runtime` target (production
dependencies only, non-root); migration/admin jobs use the separate `ops`
target. Before the first recreate, complete the UID/volume, Redis rotation and
rollback checklist in `SECURITY_HARDENING_RUNBOOK.md`.

4. Build Flutter clients for production with the home-server API:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api
flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api
```

5. Publish the APK and app-version metadata:

```bash
sudo cp build/app/outputs/flutter-apk/app-release.apk /srv/opshub/downloads/phongvu-opshub.apk
```

Set these values in the runtime env so mobile clients can require the update:

```bash
APP_VERSION=1.1.2
APP_BUILD_NUMBER=3
APP_MIN_SUPPORTED_BUILD=3
APP_UPDATE_URL=https://opshub.hoanghochoi.com/downloads/phongvu-opshub.apk
APP_PACKAGE_URL=https://opshub.hoanghochoi.com/downloads/phongvu-opshub.apk
APP_PACKAGE_SHA256=<sha256-of-final-apk>
APP_PACKAGE_SIZE_BYTES=<apk-size-bytes>
APP_PACKAGE_TYPE=apk
APP_RELEASE_NOTES=Release notes shown in the app
APP_FORCE_UPDATE=true
```

6. Back up to TrueNAS:

```bash
bash deploy/home-server/backup.sh deploy/home-server/env
```

The backup command fails closed until `BACKUP_AGE_RECIPIENT` is configured and
the host has `age`. Keep the private identity outside the server and backup
destination. Add the command to cron only after checksum verification and the
first isolated restore test succeed; see `SECURITY_HARDENING_RUNBOOK.md`.

## Local Data

Legacy inventory and user/store data now live in Postgres. With
`DATA_SYNC_SOURCE=local`, the legacy NestJS inventory/user cron jobs skip
BigQuery. FIFO inventory is separate: configure `BIGQUERY_PROJECT_ID`,
`BIGQUERY_FIFO_DATASET_ID`, `BIGQUERY_FIFO_TABLE_ID`, and `BIGQUERY_KEY_FILE`
to refresh `fifo_inventory` from BigQuery every day at 08:00
Asia/Ho_Chi_Minh. Admin manual FIFO inventory import remains supplemental and
does not replace/deactivate BigQuery rows.

CSV import from the running API container:

```bash
sudo cp inventory.csv users.csv /srv/opshub/import/
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile maintenance run --rm maintenance npm run import:inventory -- /data/import/inventory.csv --replace
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile maintenance run --rm maintenance npm run import:users -- /data/import/users.csv
```

Useful CSV headers:

- `inventory` table: `sku`, `sku_name`, `serial_number`, `bin`, `zone`, `import_date`, `count`.
- `Store`: create stores first with `storeId` and `storeName`.
- `User`: first-use password login can auto-create users, then admins can update role/store directly in Postgres until an admin UI exists.

## Network

Expose only `80` and `443` to the LAN/internet. Postgres and Redis stay inside
the Docker network and Redis requires the shared runtime password. Set
`ALLOWED_ORIGINS` to exact HTTPS origins.

On a VPS that already has host Nginx or Cloudflare Tunnel, set
`OPSHUB_HTTP_BIND=127.0.0.1:8090` and point the tunnel at
`http://127.0.0.1:8090` instead of binding Caddy directly to public `80`.
TLS is terminated at Cloudflare in this layout. Enable Always Use HTTPS at the
edge; Caddy also redirects only requests forwarded with
`X-Forwarded-Proto: http` so HTTPS tunnel traffic does not loop.

## GitHub Deploy

The repository deploys from two long-lived branches only: `staging` and `main`.
When the operator says `push staging` or `deploy staging`, collect the ready
changes on `staging`, validate them, and push `origin/staging` to run the
staging workflow. When the operator says `push production` or
`deploy production`, fetch GitHub, confirm `main` is an ancestor of `staging`,
fast-forward `main` from `staging`, re-check the final diff, and push
`origin/main`.

The repository includes `.github/workflows/deploy-opshub.yml`. On every push to
`main`, it builds an Android APK, a portable Windows ZIP, and a Windows installer
EXE with:

- `API_BASE_URL=https://opshub.hoanghochoi.com/api`
- `--build-name <utc-date>.<github-run-number>`
- `--build-number 100000+<github-run-number>`

The Windows installer bundles the Microsoft Visual C++ Redistributable x64 and
runs it as an elevated prerequisite when the target PC is missing the required
runtime files, has an older runtime, or has a partial install. The portable ZIP is
kept for internal/manual use and does not install prerequisites by itself. The
latest Microsoft Visual C++ v14 Redistributable supports Windows 10/11 and
Windows Server 2016+; older Windows versions remain an unsupported install risk.
The installer also performs a non-blocking Windows audio preflight; missing
Windows Audio services or playback devices are logged and shown as an interactive
warning, but setup continues because audio devices can be fixed after install.

For every internal Windows release, configure the required PFX, password and
expected signer fingerprint so the workflow signs `phongvu_opshub.exe` before
packaging and signs the final Inno installer after compilation. It must also
validate the Authenticode timestamp and signer pin, then pass a fail-closed
Microsoft Defender scan before checksums or upload. Missing signing inputs,
unsigned artifacts or any failed gate stop the release. Target PCs must trust
the matching public
certificate in both `Trusted Root Certification Authorities` and `Trusted
Publishers`; otherwise a self-signed signature will still look untrusted. When
signing succeeds, the workflow still does not bundle or import a trust
certificate. Operators export the public `.cer` separately from the approved
certificate source and IT provisions it through a managed channel. A
self-signed publisher cannot prevent the first browser or SmartScreen prompt on
a PC where IT has not already provisioned that certificate. The workflow
publishes a `.sha256` file beside the direct Windows downloads so operators and
the runtime updater can verify the final signed bytes.

The Android and Windows build jobs upload the finished client packages directly
to a per-run staging directory on the VPS instead of storing them as GitHub
Actions artifacts. The deploy job promotes those staged files to
`/srv/opshub/downloads/`, writes the public download manifest from the published
files, points Windows update metadata at the installer EXE, updates the backend
generic `APP_*`, `APP_ANDROID_APP_*`, and `APP_WINDOWS_APP_*` env values, runs
Prisma migrations, rebuilds the Docker stack, and keeps only the five newest
release folders plus the newest client downloads.

Full production deploys also build the Flutter web app with
`API_BASE_URL=https://opshub.hoanghochoi.com/api`, sync it to
`/srv/opshub/web/`, and serve it as the SPA root at `/`. Caddy must keep the
runtime/static routes `/api`, `/ws`, `/download`, `/help`, `/uploads`,
`/downloads`, `/staging-download`, and `/health` ahead of the SPA fallback.
Staging deploys build the web app with
`API_BASE_URL=https://opshub-staging.hoanghochoi.com/api` and publish it under
`/srv/opshub-staging/web/`. Android/Windows metadata and downloads use only the
same staging origin under
`https://opshub-staging.hoanghochoi.com/downloads/`; production and the legacy
cross-origin staging-download path are not valid release targets.

The public staff download page is served at `/download`. Full deploys publish
`/srv/opshub/downloads/latest.json` beside the APK, Windows installer, Windows
ZIP, and SHA256 checksum so that page can render the current links. The public
staff help page now uses the Flutter `/help` route backed by
`/api/help-content/public`, while Caddy still serves `/help/assets/*` from
`/srv/opshub/downloads/help/`. For static download/help-page changes only, run
the workflow manually with `skip_client_build=true`; that path uploads the
static landing page/icon/help asset bundle, syncs `docs/help/*` into the
current release as the runtime seed/rollback source, regenerates `latest.json`
from the already live app-version metadata and files, updates the current
Caddyfile, and reloads Caddy without rebuilding APK, Windows packages, backend
images, or app-version metadata.

New Android and Windows clients use `/app-version` package metadata to update
inside the app: they download `packageUrl`, verify `packageSha256` and
`packageSizeBytes`, then open the OS installer. Windows uses silent Inno Setup
args from `APP_WINDOWS_APP_INSTALLER_ARGS`; include `/OPSHUBRELAUNCH=1` so
self-update launches OpsHub again after the silent installer completes. Android
still uses the system Package Installer confirmation screen for self-hosted
APKs.

The Windows runtime intentionally does not receive or enforce
`WINDOWS_UPDATE_SIGNER_SHA256`; it also verifies HTTPS same-origin/source,
redirect, package type and size before SHA-256. The configured signer pin stays
inside CI as a mandatory release gate together with Authenticode timestamp and
Defender checks.

Required GitHub repository secrets:

- `OPSHUB_VPS_HOST` - VPS IP or DNS name.
- `OPSHUB_VPS_SSH_KEY` - private SSH key allowed to deploy as the VPS user.
- `OPSHUB_VPS_USER` - optional, defaults to `ubuntu`.
- `OPSHUB_VPS_PORT` - optional, defaults to `22`.
- `ANDROID_KEYSTORE_BASE64` - base64 text of the Android release keystore.
- `ANDROID_KEYSTORE_PASSWORD` - Android release keystore password.
- `ANDROID_KEY_ALIAS` - Android release key alias.
- `ANDROID_KEY_PASSWORD` - Android release key password.
- `WINDOWS_SIGNING_PFX_BASE64` - required base64 text of the internal Windows
  code-signing PFX.
- `WINDOWS_SIGNING_PFX_PASSWORD` - required password for that PFX.
- GitHub Environment variable `WINDOWS_UPDATE_SIGNER_SHA256` - required
  SHA-256 certificate fingerprint used only by the CI signing gate.

The Android signing secrets must stay stable across releases. If the APK is
signed with a different key, Android will reject in-place updates with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` and users must uninstall the old app.
