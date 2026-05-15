# OpsHub Home Server Deploy

Target layout:

- SSD runtime: containers, Postgres data, Redis data, upload images under `/srv/opshub`.
- TrueNAS backup: mount an SMB/NFS dataset at `/mnt/truenas/opshub-backups`.
- Local DB mode: `DATA_SYNC_SOURCE=local`; BigQuery sync is disabled.

## Checklist

1. Create folders on the home server:

```bash
sudo mkdir -p /srv/opshub/{postgres,redis,uploads,import,caddy/data,caddy/config}
sudo mkdir -p /mnt/truenas/opshub-backups
```

2. Copy `deploy/home-server/env.example` to `deploy/home-server/env` and replace all secrets/domain values.

3. Start the stack:

```bash
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml --profile migrate run --rm migrate
OPSHUB_ENV_FILE=./env docker compose --env-file deploy/home-server/env -f deploy/home-server/docker-compose.home.yml up -d --build
```

4. Build Flutter for production with the home-server API:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://opshub.example.com/api
```

5. Back up to TrueNAS:

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
