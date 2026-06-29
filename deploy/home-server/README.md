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
sudo mkdir -p /srv/opshub/{postgres,redis,uploads,downloads,import,caddy/data,caddy/config}
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

`OPSHUB_ENV_FILE` is required for every runtime compose command. Do not rely on
`--env-file` alone: the compose services also read the same file through
`env_file`, and missing `OPSHUB_ENV_FILE` should stop the command immediately
instead of silently falling back to `deploy/home-server/env.example`.
Only the API container reads the full runtime env file. Infrastructure services
use explicit environment keys so changing app-version metadata does not recreate
Postgres, Redis, realtime, or Caddy by accident.

4. Build Flutter for production with the home-server API:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://opshub.hoanghochoi.com/api
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
APP_RELEASE_NOTES=Release notes shown in the app
APP_FORCE_UPDATE=true
```

6. Back up to TrueNAS:

```bash
bash deploy/home-server/backup.sh deploy/home-server/env
```

Add that backup command to cron after the first manual restore test succeeds.

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
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml exec api npm run import:inventory -- /data/import/inventory.csv --replace
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml exec api npm run import:users -- /data/import/users.csv
```

Useful CSV headers:

- `inventory` table: `sku`, `sku_name`, `serial_number`, `bin`, `zone`, `import_date`, `count`.
- `Store`: create stores first with `storeId` and `storeName`.
- `User`: first-use password login can auto-create users, then admins can update role/store directly in Postgres until an admin UI exists.

## Network

Expose only `80` and `443` to the LAN/internet. Postgres and Redis stay inside the Docker network. If this server is reachable from outside, keep Caddy HTTPS enabled and set `ALLOWED_ORIGINS` to the exact public origin.

On a VPS that already has host Nginx or Cloudflare Tunnel, set
`OPSHUB_HTTP_BIND=127.0.0.1:8090` and point the tunnel at
`http://127.0.0.1:8090` instead of binding Caddy directly to public `80`.

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

For internal-only Windows rollout, configure optional Windows signing secrets so
the workflow signs `phongvu_opshub.exe` before packaging and signs the final Inno
installer after compilation. Target PCs must trust the matching public
certificate in both `Trusted Root Certification Authorities` and `Trusted
Publishers`; otherwise a self-signed signature will still look untrusted. When
signing is enabled, the workflow also exports the public certificate and bundles
it into the Inno installer for current-user trust import on first run. That import
helps later updates, but it cannot prevent the very first browser or SmartScreen
prompt on a PC that has not already trusted the certificate. When signing secrets
are missing, the workflow keeps producing unsigned artifacts and logs that state
instead of failing. It also publishes a `.sha256` file beside the direct Windows
downloads so operators can verify the ZIP and installer hash.

The Android and Windows build jobs upload the finished client packages directly
to a per-run staging directory on the VPS instead of storing them as GitHub
Actions artifacts. The deploy job promotes those staged files to
`/srv/opshub/downloads/`, writes the public download manifest from the published
files, points Windows update metadata at the installer EXE, updates the backend
generic `APP_*`, `APP_ANDROID_APP_*`, and `APP_WINDOWS_APP_*` env values, runs
Prisma migrations, rebuilds the Docker stack, and keeps only the five newest
release folders plus the newest client downloads.

The public staff download page is served at `/download`. Full deploys publish
`/srv/opshub/downloads/latest.json` beside the APK, Windows installer, Windows
ZIP, and SHA256 checksum so that page can render the current links. The public
staff help page is served at `/help` from built Markdown and image assets under
`/srv/opshub/downloads/help/`. For static download/help-page changes only, run
the workflow manually with `skip_client_build=true`; that path uploads the
static landing page/icon/help site, regenerates `latest.json` from the already
live app-version metadata and files, updates the current Caddyfile, and reloads
Caddy without rebuilding APK, Windows packages, backend images, or app-version
metadata.

Required GitHub repository secrets:

- `OPSHUB_VPS_HOST` - VPS IP or DNS name.
- `OPSHUB_VPS_SSH_KEY` - private SSH key allowed to deploy as the VPS user.
- `OPSHUB_VPS_USER` - optional, defaults to `ubuntu`.
- `OPSHUB_VPS_PORT` - optional, defaults to `22`.
- `ANDROID_KEYSTORE_BASE64` - base64 text of the Android release keystore.
- `ANDROID_KEYSTORE_PASSWORD` - Android release keystore password.
- `ANDROID_KEY_ALIAS` - Android release key alias.
- `ANDROID_KEY_PASSWORD` - Android release key password.
- `WINDOWS_SIGNING_PFX_BASE64` - optional base64 text of the internal Windows
  code-signing PFX.
- `WINDOWS_SIGNING_PFX_PASSWORD` - optional password for that PFX; required when
  `WINDOWS_SIGNING_PFX_BASE64` is set.

The Android signing secrets must stay stable across releases. If the APK is
signed with a different key, Android will reject in-place updates with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` and users must uninstall the old app.
