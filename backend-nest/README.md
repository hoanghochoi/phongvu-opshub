# PhongVu OpsHub Nest API

NestJS API service for the OpsHub mobile app. It owns authentication, users, inventory lookup, FIFO check/sort, FIFO history, warranty uploads, feedback, and Redis events for the realtime service.

## Runtime Dependencies

- Node.js and npm
- PostgreSQL
- Redis
- Google OAuth client ID
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
- `GOOGLE_CLIENT_ID`: Google OAuth client ID used by the Flutter app.
- `ALLOWED_DOMAIN`: Comma-separated email domains allowed to sign in.
- `REDIS_HOST` / `REDIS_PORT`: Redis connection used to publish realtime events.
- `BIGQUERY_*`: Project, dataset, and table values for sync jobs. `BIGQUERY_KEY_FILE` is used when the VPS authenticates with a service-account JSON; it can be omitted when the runtime uses Google Application Default Credentials.
- `UPLOAD_BASE_DIR`: Directory where uploaded warranty/feedback images are written.
- `IMAGE_BASE_URL`: Public URL that serves files from `UPLOAD_BASE_DIR`.

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
