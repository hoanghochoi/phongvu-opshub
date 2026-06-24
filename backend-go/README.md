# PhongVu OpsHub Realtime Service

Go service that subscribes to Redis events from the NestJS API and broadcasts updates to WebSocket clients.

## Environment

The service reads environment variables from the process:

- `PORT`: HTTP/WebSocket port, defaults to `8080`.
- `REDIS_HOST`: Redis host, defaults to `localhost`.
- `REDIS_PORT`: Redis port, defaults to `6379`.
- `JWT_SECRET`: required for `/ws`; use the same value as the NestJS API.
- `ALLOWED_ORIGINS`: comma-separated WebSocket origins. Defaults to localhost
  only when unset. Do not use `*` in production.

`.env.example` is a template for deployment tools or process managers. `go run .` does not load `.env` automatically.

## Development

```bash
go test ./...
go run .
```

The authenticated WebSocket endpoint is `/ws`. Send the JWT with
`Authorization: Bearer <jwt>`; avoid query-string tokens because URLs can be
logged by proxies and diagnostics. The legacy `access_token` query parameter is
still accepted for compatibility.

The public `/ws/app-updates` endpoint broadcasts only `APP_UPDATE` signals. It
does not accept or expose warranty and payment events; clients verify the signal
against the public `/api/app-version` HTTP contract before showing an update.

The liveness endpoint is:

```text
http://localhost:8080/health
```

## Redis Event

The service subscribes to:

```text
WARRANTY_STATUS_UPDATED
PAYMENT_NOTIFICATION_READY
APP_VERSION_UPDATED
```

NestJS publishes these events for warranty status, payment notifications, and
new deploy version metadata respectively.
