# PhongVu OpsHub Nest API

NestJS API service for the OpsHub mobile app. It owns authentication, users, inventory lookup, FIFO check/sort, FIFO history, warranty uploads, feedback, and Redis events for the realtime service.

## Runtime Dependencies

- Node.js and npm
- PostgreSQL
- Redis
- BigQuery service account and dataset/table IDs for inventory/user sync
- Writable image directory on the host or VPS

Local PostgreSQL and Redis can be started from the repository root:

```bash
docker compose up -d
```

## Environment

Create a local `.env` from the template:

```bash
copy .env.example .env
```

Important variables:

- `DATABASE_URL`: PostgreSQL connection string.
- `JWT_SECRET`: JWT signing secret. There is no runtime fallback; use a long random value.
- `EMAIL_DOMAIN_FILE`: Optional path to the accepted Phong Vu email domain list.
  Defaults to `../data/email_domain.txt` when running from `backend-nest/`.
- `REDIS_HOST` / `REDIS_PORT`: Redis connection used to publish realtime events.
- `BIGQUERY_*`: Project, dataset, and table values for sync jobs. `BIGQUERY_KEY_FILE` is used when the VPS authenticates with a service-account JSON; keep that JSON outside the repo checkout, for example under `/data/import`, or omit it when the runtime uses Google Application Default Credentials.
- `UPLOAD_BASE_DIR`: Directory where uploaded warranty/feedback images are written.
- `IMAGE_BASE_URL`: Public URL that serves files from `UPLOAD_BASE_DIR`.
- `UPLOAD_MAX_BYTES`: Maximum bytes per warranty/feedback image. Defaults to 10 MiB.
- `AVATAR_UPLOAD_MAX_BYTES`: Maximum bytes per avatar image. Defaults to 2 MiB.

The API validates env values on startup. Local development may omit all BigQuery values, which makes sync jobs skip themselves. Production requires complete BigQuery project/dataset/table values and rejects placeholder values such as `change-me` and `https://img.example.com`.

Image links are generated as:

- Warranty: `${IMAGE_BASE_URL}/{receipt}/{receipt}-{index}.jpg`
- Feedback: `${IMAGE_BASE_URL}/feedback/{feedbackId}/{feedbackId}-{index}.jpg`

On a VPS, keep `UPLOAD_BASE_DIR` on persistent storage and configure the image domain to serve that directory.

## Database

Generate the Prisma client after install or schema changes:

```bash
npx prisma generate
```

Apply migrations in deployed environments:

```bash
npx prisma migrate deploy
```

For local development, create and apply a migration with:

```bash
npx prisma migrate dev
```

## Development

```bash
npm install
npm run build
npm run start:dev
```

The service listens on `PORT` or `3000` by default.

## Smoke Check

```bash
curl http://localhost:3000/health
```

Expected response:

```json
{ "status": "ok", "service": "backend-nest" }
```

## Verification

```bash
npm run build
npm test -- --runInBand
```

Run these before committing backend changes.

## Notes

- Do not commit `.env`, service-account JSON, or local database scratch scripts.
- In local development, BigQuery sync is skipped when all BigQuery env vars are missing.
- Redis events are published on `WARRANTY_STATUS_UPDATED` and consumed by `backend-go`.
