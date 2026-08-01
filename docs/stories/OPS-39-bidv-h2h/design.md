# OPS-39 - Design

```text
BIDV -> dedicated Caddy host -> OAuth hash lookup -> OpenPGP decrypt
     -> complete-batch validation -> receipt + canonical rows + outbox
     -> leased projector -> MapVietinTransaction
     -> payment notification / realtime / Home / BigQuery
```

The HTTP request ends after canonical commit; Redis, TTS, realtime, BigQuery
and Flutter are not dependencies of the acknowledgement. Rollback disables
projection first and ingress only for auth/decrypt/persistence safety. The
expand-only migration and canonical/audit rows stay in place.

Path contracts cover `backend-nest/src/bidv-h2h/**`, Prisma/migration,
payment/BigQuery/Go consumers, Flutter Admin/router/platform, and
deploy/Caddy/env/workflow files.
