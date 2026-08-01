# BIDV H2H operations runbook

## Safety boundary

Production and staging are separate deployments. Never copy a client secret,
token, private key, KEK or canonical payload between them. The UI exports only
the public key. Keep `BIDV_H2H_PROJECTION_ENABLED=false` until UAT
reconciliation is approved.

## First setup

1. Generate an environment-specific 32-byte KEK outside Git and store its
   canonical Base64 value in `BIDV_H2H_KEK_BASE64` with runtime-env permissions.
2. Set the dedicated domain/public base URL/environment. Leave both master
   switches false and deploy the expand-only migration plus application.
3. Validate Caddy: the dedicated host returns 200 only for `/health`, forwards
   `/oauth2/token` and `/v1/balance-changes`, and returns 404 for `/`, `/api`,
   `/ws`, `/download`, `/uploads`, `/help` and staff admin paths.
4. In Admin > Quản lý kết nối API, create one client and one OpenPGP key. Save
   the one-time secret in the approved bank handoff channel. Export only the
   public key and verify its fingerprint through a second channel.
5. Configure Cloudflare DNS/tunnel origin host header for the dedicated host.

## UAT activation

1. Confirm backup/restore and exact release SHA. Install the KEK and set
   `BIDV_H2H_INGEST_ENABLED=true`; keep projection master false.
2. Request an audited UI change to enable ingest. Receive the BIDV-produced
   fixture and reconcile receipt count, canonical count, identity, dates,
   amounts and the stable duplicate response.
3. Exercise invalid auth, wrong key, malformed/mixed batch, conflicting
   identity, Debit, foreign currency, fractional and unmapped showroom cases.
4. After written reconciliation approval, set projection master true and use
   the UI confirmation to request projection. Verify exactly once in Tiền vào,
   Sao kê, VietQR, speaker/realtime, Home and BigQuery.

## Rotation

- Create/rotate the new client or key; the old version receives a 24-hour
  overlap. Save a new secret immediately or rotate again if its response is
  lost. There is no recovery/re-reveal.
- For keys, send only the new public armor and fingerprint. Wait for BIDV
  confirmation and a fixture encrypted with the new key before revoking old.
- Revocation immediately invalidates client tokens. The backend blocks removal
  of the last usable version unless a recovery override is explicitly audited.

## Incident and rollback

- Downstream duplicate/incorrect mapping: turn off projection in UI, then the
  projection master switch. Keep safe ingest on while reconciling canonical
  rows.
- Auth/decrypt/persistence risk or key loss: disable ingest in UI/master and
  return non-200 so BIDV retry behavior remains explicit. Activate a valid
  overlap key or exchange a new public key; never extract private material.
- Application rollback uses the normal staging/release process. Leave tables,
  additive columns, audit and canonical rows intact. Do not delete receipt or
  outbox evidence as rollback.
- Re-enable only after lease/dead-letter backlog, duplicate counts, consumer
  sums and runtime health are reconciled.

## Retention and monitoring

Canonical rows default to 90 days. Cleanup is a separately reviewed operator
job and must preserve audit/reconciliation needs. Monitor ingress failures,
decrypt duration, receipt/transaction counts, pending/retry/dead-letter age and
projection duration using sanitized IDs/counts only. Never log REQUESTID raw,
authorization, accounts, payload, client secret, token, KEK or private armor.
