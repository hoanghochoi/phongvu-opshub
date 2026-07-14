# PhongVu OpsHub Realtime Service

Go service that subscribes to Redis events from the NestJS API and broadcasts updates to WebSocket clients.

## Environment

The service reads environment variables from the process:

- `PORT`: HTTP/WebSocket port, defaults to `8080`.
- `REDIS_HOST`: Redis host, defaults to `localhost`.
- `REDIS_PORT`: Redis port, defaults to `6379`.
- `REDIS_USERNAME`, `REDIS_PASSWORD`, `REDIS_DB`: Redis authentication and DB.
- `WS_TICKET_KEY_PREFIX`: defaults to `opshub:realtime:ticket:`.
- `WS_ALLOW_LEGACY_JWT`: disabled by default. Enable only during the measured
  client migration window.
- `JWT_SECRET`: required only while legacy JWT compatibility is enabled.
- `ALLOWED_ORIGINS`: comma-separated WebSocket origins. Defaults to localhost
  only when unset. Do not use `*` in production.
- `WS_SEND_QUEUE_SIZE`, `WS_WRITE_TIMEOUT_SECONDS`,
  `WS_PONG_TIMEOUT_SECONDS`, `WS_READ_LIMIT_BYTES`: per-connection backpressure
  and heartbeat limits.
- `WS_MAX_CONNECTIONS`, `WS_MAX_CONNECTIONS_PER_IP`,
  `WS_MAX_CONNECTIONS_PER_USER`, `WS_MAX_HANDSHAKES_PER_IP_MINUTE`: minimum
  connection and handshake abuse controls. The per-user default is 12 because
  the current Flutter client can keep seven authenticated feature sockets open
  concurrently; this leaves bounded reconnect overlap without weakening the
  independent per-IP and handshake limits. Tune them from staging load proof.

`.env.example` is a template for deployment tools or process managers. `go run .` does not load `.env` automatically.

## Development

```bash
go test ./...
go run .
```

The authenticated WebSocket endpoints are `/ws` (legacy features) and `/ws/v2`
(shared versioned platform signals). Both request a one-time 256-bit ticket from
NestJS and consume it atomically before upgrading the connection. The service
never logs the query string. A ticket is single-use, so each endpoint needs its
own ticket.

`/ws/v2` currently accepts `HOME_SUMMARY_UPDATED`. It emits only
`affectedDates` and `projectionVersion`; KPI values remain behind the
authenticated Home API. Redis loss closes only v2 sockets with retryable code
`1012` and reason `resync_required`, forcing clients to reconnect and re-read
HTTP state. Legacy `/ws` clients remain connected during the two-release
migration window.

Legacy `Authorization: Bearer <jwt>` and `access_token` query authentication are
accepted only when `WS_ALLOW_LEGACY_JWT=true`. The flag is a temporary rollout
escape hatch, not the final authentication contract.

### One-time ticket contract

NestJS must generate at least 256 random bits and return the raw Base64URL or
hex ticket only to the authenticated client. Redis stores only this key:

```text
opshub:realtime:ticket:<lowercase SHA-256 hex of raw ticket>
```

The key must have a 45-second TTL and the following JSON value. Go consumes it
with Redis `GETDEL`, so expiry, reuse, malformed content, Redis outage, or a
wrong audience all fail closed.

```json
{
  "version": 1,
  "audience": "opshub-realtime",
  "userId": "user-id",
  "email": "user@example.com",
  "role": "MANAGER",
  "storeId": "store-uuid",
  "storeCode": "CP01",
  "departmentCode": "SALES",
  "organizationNodeId": "node-id",
  "organizationAccessCodes": ["CP01"],
  "featureCodes": ["WARRANTY"],
  "sessionId": "session-id",
  "platform": "web",
  "sessionVersion": 1,
  "tokenVersion": 2,
  "issuedAt": "2026-07-12T00:00:00Z",
  "expiresAt": "2026-07-12T00:00:45Z"
}
```

`expiresAt` accepts RFC 3339, Unix seconds, or Unix milliseconds during rollout,
but may not be more than two minutes in the future. NestJS remains responsible
for validating the current user/session/token versions before issuing the
ticket. `store_id` can only narrow a connection to a store already represented
by `storeCode`, `organizationAccessCodes`, or the `SUPER_ADMIN` role; it never
adds scope.

The public `/ws/app-updates` endpoint broadcasts only `APP_UPDATE` signals. It
does not accept or expose warranty and payment events; clients verify the signal
against the public `/api/app-version` HTTP contract before showing an update.

The liveness and readiness endpoints are:

```text
http://localhost:8080/health
http://localhost:8080/ready
```

`/health` reports only process liveness. `/ready` returns 503 until the Redis
subscription is active and Redis responds to `PING`.

## Redis Event

The service subscribes to:

```text
WARRANTY_STATUS_UPDATED
PAYMENT_NOTIFICATION_READY
PAYMENT_SPEAKER_STREAM
APP_VERSION_UPDATED
STATEMENT_ORDER_TRANSFER_REQUESTED
OFFSET_ADJUSTMENT_UPDATED
SALES_REPORT_ORDERS_UPDATED
HOME_SUMMARY_UPDATED
```

Home uses the strict v2 Redis envelope below. `audience.kind` must be
`AUTHENTICATED`, and payload dates must be unique ISO calendar dates:

```json
{
  "schemaVersion": 2,
  "type": "HOME_SUMMARY_UPDATED",
  "eventId": "event-id",
  "occurredAt": "2026-07-14T10:30:05Z",
  "audience": { "kind": "AUTHENTICATED" },
  "payload": {
    "affectedDates": ["2026-07-14"],
    "projectionVersion": 42
  }
}
```

Clients receive `{v, kind, id, topic, seq, ts, data}` with
`topic=home.summary`; the gateway does not forward the Redis audience object.

Sensitive events use a versioned Redis envelope. Audience data is used only by
the Go router and is not forwarded to clients:

```json
{
  "schemaVersion": 1,
  "type": "WARRANTY_EVENT",
  "eventId": "event-id",
  "occurredAt": "2026-07-12T00:00:00Z",
  "audience": {
    "storeCodes": ["CP01"],
    "recipientUserIds": ["user-id"],
    "roles": [],
    "departmentCodes": [],
    "organizationAccessCodes": [],
    "featureCodes": ["WARRANTY"]
  },
  "payload": {
    "warrantyId": "warranty-id",
    "newStatus": "DONE"
  }
}
```

At least one audience selector is required. All sensitive event types are
server-filtered. During the publisher migration, payment, payment stream,
statement transfer, offset adjustment, and sales-report events can infer a
restricted audience from their existing `storeCode`, `storeCodes`,
`recipientUserId`, or `recipientUserIds` fields. A sensitive event with no
routable audience is dropped. In particular, the historical warranty payload
has no safe scope and must be upgraded to the versioned envelope before this
service is promoted.

Each client has a bounded send queue and a dedicated writer goroutine. A full
queue disconnects only that slow client; it cannot block the hub or other
connections. Write deadlines, ping/pong, read limits, active connection caps,
and per-IP handshake limits are enforced by the service.
