# Support Chat Phase 1 Operations

Support Chat is disabled by default. `SUPPORT_CHAT_ENABLED=false` is the fast,
non-destructive rollback: PostgreSQL remains authoritative, queued events and
private media stay retained, and Flutter keeps the existing Seatalk fallback.

## Staging enablement

1. Confirm Nest, Go realtime and Flutter are deployed from the same accepted
   staging SHA and all OPS-40 affected-consumer proof is current.
2. Confirm the migration is applied, Redis is healthy, no Support Chat outbox
   row is older than 60 seconds, and no row is dead-lettered.
3. Set `SUPPORT_CHAT_ENABLED=true` only in staging, restart Nest, then verify
   `/auth/bootstrap` advertises `supportChat` and `support.chat`.
4. Exercise requester, assignment-pending, two-Super-Admin claim/takeover,
   image, reconnect and Redis-outage recovery flows before QA acceptance.

## Fast rollback

Set `SUPPORT_CHAT_ENABLED=false` and restart Nest. Verify bootstrap removes the
capability/topic, the admin tile/route fails closed, and the current Seatalk
path plus public `/seatalk-support` still work. Do not down-migrate or delete
Support Chat data in production.

## Restore-time purge

Restored encrypted backups may contain Support Chat data past the 180-day
online retention window. Before enabling the feature on an isolated restored
environment:

```powershell
Set-Location backend-nest
npm run build
npm run support-chat:purge-expired
```

Keep the feature flag false while the command runs. It uses the same advisory-
locked, bounded retention worker as runtime and exits non-zero when the lock,
database, media cleanup or batch limit fails. Record the restored backup ID,
exact SHA, command exit code, purged counts and post-purge sentinel query; never
copy raw message bodies, filenames, media URLs or credentials into proof logs.

For a disposable local fresh/upgrade/rollback rehearsal, set
`OPSHUB_POSTGRES_BIN` to a PostgreSQL `bin` directory and run
`npm run verify:ops40:postgres`. The verifier creates an isolated cluster under
`%TEMP%`, binds only loopback on a random high port, and validates its cleanup
target before deletion. It must never point at or reuse an existing cluster.
