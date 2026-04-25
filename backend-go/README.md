# PhongVu OpsHub Realtime Service

Go service that subscribes to Redis events from the NestJS API and broadcasts updates to WebSocket clients.

## Environment

The service reads environment variables from the process:

- `PORT`: HTTP/WebSocket port, defaults to `8080`.
- `REDIS_HOST`: Redis host, defaults to `localhost`.
- `REDIS_PORT`: Redis port, defaults to `6379`.

`.env.example` is a template for deployment tools or process managers. `go run .` does not load `.env` automatically.

## Development

```bash
go test ./...
go run .
```

The WebSocket endpoint is:

```text
ws://localhost:8080/ws
```

## Redis Event

The service subscribes to:

```text
WARRANTY_STATUS_UPDATED
```

NestJS publishes this event when a warranty status changes.
