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
- MAP global sync reads `100` rows per MAP page and defaults to
  `MAP_VIETIN_GLOBAL_SYNC_MAX_PAGES=2`, for at most `200` rows per sync loop.
  After each backend MAP-history fetch finishes, the next scheduled fetch waits
  a random `3000`-`5000` ms. Background MAP sync runs only from `08:00` to
  before `22:00` Vietnam time.

## Checklist

1. Create folders on the home server:

```bash
sudo mkdir -p /srv/opshub/{postgres,redis,uploads,downloads,import,caddy/data,caddy/config}
sudo mkdir -p /mnt/truenas/opshub-backups
```

2. Copy `deploy/home-server/env.example` to `deploy/home-server/env` and replace all secrets/domain values.

   Registration email verification requires SMTP settings in the env file:
   `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, and
   `SMTP_FROM`. For Gmail, use an app password. Password reset links use PUBLIC_BASE_URL, currently https://opshub.hoanghochoi.com, and expire according to PASSWORD_RESET_TTL_MINUTES.

3. Start the stack:

```bash
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile migrate run --rm migrate
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml up -d --build
```

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

Then it uploads the client artifacts to `/srv/opshub/downloads/`, points Windows
update metadata at the installer EXE, updates the backend generic `APP_*`,
`APP_ANDROID_APP_*`, and `APP_WINDOWS_APP_*` env values, runs Prisma migrations,
rebuilds the Docker stack, and keeps only the five newest release folders plus
the newest client downloads.

Required GitHub repository secrets:

- `OPSHUB_VPS_HOST` - VPS IP or DNS name.
- `OPSHUB_VPS_SSH_KEY` - private SSH key allowed to deploy as the VPS user.
- `OPSHUB_VPS_USER` - optional, defaults to `ubuntu`.
- `OPSHUB_VPS_PORT` - optional, defaults to `22`.
- `ANDROID_KEYSTORE_BASE64` - base64 text of the Android release keystore.
- `ANDROID_KEYSTORE_PASSWORD` - Android release keystore password.
- `ANDROID_KEY_ALIAS` - Android release key alias.
- `ANDROID_KEY_PASSWORD` - Android release key password.

The Android signing secrets must stay stable across releases. If the APK is
signed with a different key, Android will reject in-place updates with
`INSTALL_FAILED_UPDATE_INCOMPATIBLE` and users must uninstall the old app.
