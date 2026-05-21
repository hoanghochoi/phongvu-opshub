# OpsHub Home Server Deploy

Target layout:

- SSD runtime: containers, Postgres data, Redis data, upload images under `/srv/opshub`.
- TrueNAS backup: mount an SMB/NFS dataset at `/mnt/truenas/opshub-backups`.
- Local DB mode: `DATA_SYNC_SOURCE=local`; BigQuery sync is disabled.

## Checklist

1. Create folders on the home server:

```bash
sudo mkdir -p /srv/opshub/{postgres,redis,uploads,downloads,import,caddy/data,caddy/config}
sudo mkdir -p /mnt/truenas/opshub-backups
```

2. Copy `deploy/home-server/env.example` to `deploy/home-server/env` and replace all secrets/domain values.

   Registration email verification requires SMTP settings in the env file:
   `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`, `SMTP_PASS`, and
   `SMTP_FROM`. For Gmail, use an app password.

3. Start the stack:

```bash
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile migrate run --rm migrate
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml up -d --build
```

4. Build Flutter for production with the home-server API:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://opshub.example.com/api
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
APP_UPDATE_URL=https://opshub.example.com/downloads/phongvu-opshub.apk
APP_RELEASE_NOTES=Release notes shown in the app
APP_FORCE_UPDATE=true
```

6. Back up to TrueNAS:

```bash
bash deploy/home-server/backup.sh deploy/home-server/env
```

Add that backup command to cron after the first manual restore test succeeds.

## Local Data

Inventory and user/store data now live in Postgres. With `DATA_SYNC_SOURCE=local`, the NestJS startup and cron jobs skip BigQuery. Use direct Postgres import, Prisma Studio, or a future admin import screen to maintain local data.

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
`main`, it builds a release APK with:

- `API_BASE_URL=https://opshub.hoanghochoi.com/api`
- `--build-name <utc-date>.<github-run-number>`
- `--build-number 100000+<github-run-number>`

Then it uploads the APK to `/srv/opshub/downloads/`, updates the backend
`APP_*` env values, runs Prisma migrations, rebuilds the Docker stack, and
keeps only the five newest release folders and APK downloads.

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
