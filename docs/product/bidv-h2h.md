# BIDV H2H balance-change integration

## Outcome

OpsHub receives BIDV balance-change batches through a dedicated OAuth 2.0 and
OpenPGP boundary, persists each validated batch atomically, then projects only
eligible transactions into the existing payment pipeline.

- UAT: `https://api-staging.phongvu.work/v1/bidv`
- Production: `https://api.phongvu.work/v1/bidv`
- Token: `POST /v1/bidv/oauth2/token`
- Push: `POST /v1/bidv/balance-changes`

BIDV uses an exact-path namespace on the environment API hostname. The Caddy
edge rewrites only these two paths to the existing NestJS BIDV controllers;
other `/v1/bidv/*` paths return `404`. The API hostname does not serve the
OpsHub SPA, uploads, downloads or help routes, and the staging and production
hostnames cannot cross-route.

## Authentication and cryptography

- OAuth uses `client_credentials`, HTTP Basic and the fixed
  `balance-changes:write` scope. Opaque tokens expire after five minutes by
  default and are stored only as SHA-256 hashes.
- The dedicated token endpoint permits 60 requests per minute per trusted
  source IP; the balance-change endpoint permits 600 requests per minute per
  trusted source IP. Both return `429` with `Retry-After` when limited.
- Client secrets are generated server-side, shown once and stored only as a
  bcrypt verifier. A lost response requires rotation; there is no re-reveal.
- BIDV encrypts the JSON array with the active OpsHub public key, then
  Base64-encodes the armored message. Revision 1.3 adds no payload signature.
- `openpgp` is pinned to `6.3.1`. Generated pairs use an Ed25519 signing primary
  and X25519 encryption subkey. Imported pairs must match and pass a round trip.
- Private armor uses AES-256-GCM with a dedicated 32-byte KEK mounted read-only
  from `/run/secrets/bidv-h2h-kek`. Each environment creates and backs up its
  own secret; source promotion never transports it.

## Ingress contract

The push requires `REQUESTID`, bearer authorization and:

```json
{"bankCode":"BIDV","data":"<base64-openpgp-message>"}
```

The decrypted value is a non-empty array within the configured batch limit.
The 28 accepted fields are `transDate`, `transTime`, `accountNo`, `dorc`,
`currency`, `amount`, `remark`, `refNo`, `frBankCode`, `frAccName`, `frAccNo`,
`frBankName`, `seq`, `endBal`, `channelRef`, `channelID`, `toBankCode`,
`toAccName`, `toAccNo`, `toBankName`, `va`, `transCode`, `businessDate`, and
`ext1` through `ext5`. Unknown fields fail the whole batch. Dates use `ddMMyy`,
time uses `HHmmss`, and the business timezone is `Asia/Ho_Chi_Minh`.

Valid persistence is one PostgreSQL transaction covering receipt, new
canonical rows and sanitized outbox events. Repeated `REQUESTID` plus the same
hash returns stable success; reuse for other content fails. Identity is the
hash of normalized `bankCode + accountNo + refNo + seq + businessDate`.
Same identity/payload is a duplicate. A different payload is retained as a
conflict and never projected.

Canonical storage keeps account HMACs and masked display values, not the
encrypted request, plaintext batch, client secret, token or plaintext private
key. Rows are retained for 90 days by default.

## Projection and consumers

The audited database operating mode is `STOPPED`, `UAT_INGEST_ONLY` or `LIVE`.
Migration and every new environment start at `STOPPED`; UAT accepts canonical
data without projection, while LIVE also enables projection. A separate
platform emergency disable remains fail-closed and is not part of normal UI
operation. Eligibility requires a
conflict-free Credit, VND, positive integral legacy-safe amount and exactly one
showroom match. Showroom matching uses only the exact normalized `remark`
suffix `<storeId> BOT` or `<storeId>`, then verifies that candidate against one
existing showroom. Within BIDV H2H projection, account and virtual-account
values never infer showroom; existing MAP/Vietin account/VA mapping remains
unchanged. Other rows remain canonical without payment side effects.

The leased worker retries with backoff and dead-letters after eight attempts.
It creates one additive `MapVietinTransaction` with bank source, currency,
direction, exact Decimal amount and canonical link. Existing unique payment
notification, realtime, Home and BigQuery revision contracts protect retries.

## Administration and activation

Only `SUPER_ADMIN` can use `/admin/api-connections/bidv`. The control-plane
snapshot reports requested/effective mode, sanitized readiness, blockers and
pending projection count. Mode changes use an advisory lock, optimistic
version and immutable audit. Legacy boolean controls remain synchronized for a
bounded compatibility window. Secrets and private keys never enter Flutter
cache, analytics or AppLogger.

Token creation, receipt persistence and each projection side-effect boundary
take the same control-plane advisory lock, then re-evaluate the shared complete
readiness policy inside their final transaction. Lock order is control plane,
then REQUESTID/identity where applicable. Therefore a completed downgrade
precedes every later forbidden write; work that acquired the control lock first
finishes before the downgrade returns.

During the compatibility window, rollback to the pre-mode backend is a local
platform-owner breakglass action only. The bridge reads the environment-local
secret file and synchronized legacy booleans, writes them to the protected
local runtime env, and is never called by deployment or promotion workflows.
Its `clear` action removes all bridge variables after recovery.

At most two usable versions overlap for 24 hours. The last usable client/key
requires an explicit audited recovery override; Phase 1 UI does not expose it.

Operational runbooks, bank playbooks and generated PDFs are local-only under
the ignored `output/bidv-private/` boundary. Promotion carries only code,
migrations, tests and this minimal technical authority; environment databases,
credentials, keys, mode, audit and bank transactions remain separate.
