# Execution Plan: OPS-39 BIDV H2H ingress and API connection management

Date: 2026-07-30

## Status

Active - the approved three-state backend, environment-local KEK and promotion
boundary are being implemented. The OPS-39 Figma proposal is now approved and
its exact responsive revision/node map is the UI source of truth. Runtime migration,
staging UI-only activation, restore drill, UAT fixture and external bank gates
remain pending. The public transport
hostname/path is superseded by OPS-210; this plan remains authoritative for the
BIDV wire contract, security, persistence, projection and external-bank gates.

During the bounded rollback compatibility window, a platform owner may run the
local breakglass script `deploy/home-server/prepare-bidv-legacy-rollback.sh`.
It copies the environment-local file KEK and the synchronized legacy boolean
pair into the protected local runtime env so the pre-mode backend can start
without changing database state. No workflow invokes this script and no secret
leaves the server. After recovery returns to the current backend, the owner runs
the script with action `clear`; normal Super Admin operation never uses this
bridge.

## Current transport authority

OPS-210 owns the OpsHub domain migration and supersedes the dedicated-host
transport described by older sections of this plan. The current public
endpoints are:

- staging: `https://api-staging.phongvu.work/v1/bidv/oauth2/token` and
  `https://api-staging.phongvu.work/v1/bidv/balance-changes`;
- production: `https://api.phongvu.work/v1/bidv/oauth2/token` and
  `https://api.phongvu.work/v1/bidv/balance-changes`.

The former `bankapis*.hoanghochoi.com` dedicated-host design is retained only
as implementation history and rollback evidence. It is not a current public
contract and is not a compatibility target.

## Outcome

Deliver a production-ready BIDV H2H boundary that:

- exposes `POST /v1/bidv/oauth2/token` and
  `POST /v1/bidv/balance-changes` on the environment API hosts;
- accepts the BIDV revision 1.3 OAuth/OpenPGP wire contract atomically and
  idempotently;
- records canonical bank ingress without placing Flutter, realtime, speaker,
  Home or BigQuery work on the HTTP request path;
- projects eligible Credit/VND/integer/showroom-mapped transactions exactly
  once into the existing payment pipeline while retaining non-eligible rows for
  90-day audit;
- lets Super Admin create, rotate, revoke and audit OAuth clients and OpenPGP
  keys without re-exposing secrets, then select `STOPPED`,
  `UAT_INGEST_ONLY` or `LIVE` after readiness checks; and
- keeps operational runbooks and the bank-facing PDF only in the ignored local
  `output/bidv-private/` boundary, outside source promotion and CI artifacts.

## Context

- Linear: `OPS-39`, including the accepted 2026-07-30 host, control-plane and
  playbook addendum.
- BIDV authority: `Tai lieu dac ta bien dong so du H2H 202606`, revision 1.3,
  27 pages. Pages 1-6 define the wire contract; pages 6-27 provide OpenPGP
  examples. The document is local input and is not copied into Git or Linear.
- Public hosts:
  - UAT/staging: `https://bankapis-staging.hoanghochoi.com`
  - production: `https://bankapis.hoanghochoi.com`
- Public routes:
  - `POST /oauth2/token`
  - `POST /v1/balance-changes`
- Repository authority:
  - `AGENTS.md`
  - `docs/WORKFLOW.md`
  - `docs/FEATURE_INTAKE.md`
  - `docs/product/backend-platform.md`
  - `docs/product/profile-admin.md`
  - `docs/product/vietqr.md`
  - `docs/product/map-vietin-bigquery.md`
  - `docs/stories/PAYMENT-STATEMENT-001-bank-statement/*`
  - `docs/stories/OPS-9-map-vietin-bigquery-sync/*`
  - `docs/runbooks/git-release-playbook.md`
- Git checkpoint:
  - canonical branch: `staging`
  - base/live `origin/staging`: `0341fb76c22e5e1c4c94aaa61495441a58574243`
  - task branch: `codex/ops-39-bidv-h2h-api`
  - task worktree: `C:\Users\ASUS1\Documents\flutter_projects\opshub-ops-39`
  - both canonical and task worktrees were clean at lifecycle start.

## Intake And Authority

Lane: high-risk.

Risk flags: Auth, Authorization, Data model/migration, Audit/security, External
system, Public contract, Existing behavior, Shared runtime, Background
pipeline, Upgrade state, Runtime artifact, Multi-domain and Weak external
fixture proof.

Accepted task-local decisions:

1. OAuth uses `client_credentials`. Token requests use HTTP Basic
   `base64(client_id:client_secret)` and form body
   `grant_type=client_credentials`. Clients receive an opaque, short-lived
   bearer token with the server-assigned `balance-changes:write` scope.
2. Push requests carry `REQUESTID`, bearer auth and JSON
   `{ "bankCode": "BIDV", "data": "<base64 OpenPGP armor>" }`.
3. BIDV encrypts with OpsHub's public key; OpsHub decrypts with the matching
   private key. Revision 1.3 does not require a BIDV payload signature, so no
   signature-verification behavior is invented.
4. Pin `openpgp` exactly at `6.3.1`. Generate the documented ECC layout
   (Ed25519 primary plus X25519 encryption subkey); accept an imported key only
   after fingerprint, capability and round-trip validation.
5. Each deployment manages only its own environment. `SUPER_ADMIN` is the only
   Phase 1 operator. The dedicated backend capability remains fail-closed even
   if a Flutter route is called directly.
6. Client secrets are generated server-side, returned exactly once and stored
   only as a verifier. Opaque access tokens are stored only as hashes.
7. OpenPGP private material is envelope-encrypted with a required,
   environment-specific 32-byte KEK. There is no fallback to `JWT_SECRET`, the
   MAP credential key or a development constant. Public key, fingerprint,
   algorithm, timestamps and status are the only key material returned later.
8. Credential/key rotation allows at most two active versions and a 24-hour
   overlap. Revoke is audited and cannot remove the last usable version without
   an explicit recovery override.
9. Access-token TTL is five minutes. Revoked/expired clients are checked on
   every ingress request, so an outstanding token cannot bypass a client
   revocation until natural expiry.
10. The first implementation uses the current AppShell/shared Admin components,
    not the retired legacy scaffold and not a new visual redesign. Secret
    administration is exposed on Windows and web; unsupported platforms show
    an actionable Vietnamese state instead of rendering secret controls.
11. The documented BIDV retry contract is three retries, 15 seconds apart, for
    non-200 responses. Accepted and valid duplicate requests return stable
    HTTP 200 `{ "errorCode": "000", "errorDesc": "Success" }`.
12. Default safe bounds, pending BIDV UAT confirmation, are 1 MiB encoded body,
    100 decrypted transactions per batch, 10-second decrypt/persist timeout,
    and a dedicated principal limit that permits the accepted 10 QPS target.
    These bounds are explicit runtime configuration, validated on startup and
    documented in the playbook.
13. Canonical transaction identity defaults to a hash of normalized
    `bankCode + accountNo + refNo + seq + businessDate`. `channelRef` is retained
    as conflict/audit evidence but is not the primary idempotency key. Projection
    remains disabled until BIDV confirms the identity tuple in UAT.
14. BIDV `transDate`/`businessDate` use `ddMMyy`, `transTime` uses `HHmmss`, and
    the initial business timezone is `Asia/Ho_Chi_Minh`. Projection remains off
    until BIDV confirms this interpretation.

External evidence still required before UAT activation (not before local
implementation with generated fixtures):

- BIDV-produced plaintext/ciphertext/expected-response fixture encrypted with
  the exported OpsHub UAT public key;
- confirmation of the transaction identity tuple, maximum batch size, timezone
  and reconciliation procedure;
- Cloudflare DNS/tunnel routing for the two accepted dedicated hostnames.

## Scope

In scope:

- NestJS OAuth client lifecycle, token issuance/validation, OpenPGP key
  generation/import/decryption, admin audit APIs and kill switches.
- Prisma expand-only schema/migration for credentials, hashed tokens, PGP keys,
  immutable audit, ingress receipts, canonical bank transactions and
  projection checkpoints/status.
- Atomic ingress receipt + canonical transaction + `DomainOutboxEvent` writes.
- Retry-safe leased projection worker that writes the compatibility
  `MapVietinTransaction` projection, then uses existing idempotent payment
  notification/realtime behavior.
- Compatibility fields for bank source, currency, direction and exact Decimal
  amount while retaining the legacy integer amount contract for eligible rows.
- Existing BigQuery/Home triggers and workers extended for BIDV source fields
  without exporting raw payload, full accounts or credentials.
- Current Flutter Admin catalog, dedicated API-connection repository/models,
  status/list/create/rotate/revoke/activate/export-public-key UI and sanitized
  `AppLogger` coverage.
- Caddy, compose/env examples, deploy workflow checks, Cloudflare/manual
  routing documentation, kill-switch rollout and health/smoke proof.
- Product/story/decision/test-matrix updates, internal operations runbook and
  bank-facing connection playbook source plus PDF.

Out of scope:

- Sending the playbook, credentials or public key to BIDV.
- Storing or committing a real client secret, private key, passphrase, access
  token, account number, raw BIDV payload or production Cloudflare credential.
- Contracting/removing legacy `MapVietinTransaction.amount` or existing
  MAP/eFAST provider behavior; that remains a later expand/contract issue.
- Enabling production ingest/projection, changing protected branches, deploying,
  merging or marking OPS-39 Done in this implementation phase.
- A multi-environment control plane or scoped `ADMIN` delegation.
- Assuming BIDV signs the OpenPGP message unless a later authoritative contract
  explicitly requires it.

## Architecture And File Ownership

Exactly one `opshub_implementer` owns production/runtime files in this worktree.
A serialized `opshub_test_engineer` may edit only assigned test/fixture files
after the writer wave. Reviewers remain non-mutating.

### 1. Durable product and design truth

Planned files:

- `docs/product/bidv-h2h.md` - accepted wire, data, projection, admin and
  operations behavior.
- `docs/product/backend-platform.md`, `docs/product/profile-admin.md`,
  `docs/product/vietqr.md`, `docs/product/map-vietin-bigquery.md` - affected
  contract amendments.
- `docs/stories/OPS-39-bidv-h2h/{overview,design,validation}.md` - high-risk
  acceptance, path contracts, recovery and proof.
- `docs/decisions/0028-canonical-bank-ingress-and-managed-h2h-credentials.md`
  - bank-agnostic canonical ingress, managed secrets and compatibility
  projection decision.
- `docs/TEST_MATRIX.md` - exact local/staging/external proof and residual gaps.

### 2. Prisma and secret/control plane

Planned files:

- `backend-nest/prisma/schema.prisma` and one new expand-only migration.
- New models: `BankApiClient`, `BankAccessToken`, `BankPgpKey`,
  `BankConnectionAudit`, `BankIngressReceipt`, `BankTransaction` and, if a
  separate lease is clearer than the shared outbox fields,
  `BankProjectionCheckpoint`.
- `backend-nest/src/bidv-h2h/bidv-h2h-crypto.service.ts` - exact openpgp 6.3.1
  operations and dedicated KEK envelope format/version.
- `backend-nest/src/bidv-h2h/bidv-h2h-admin.*` - Super Admin lifecycle,
  redacted serializers and immutable audit.
- `backend-nest/src/bidv-h2h/bidv-h2h-oauth.*` - Basic parsing, secret verifier,
  opaque token issuance/hash lookup and no-store responses.
- `backend-nest/src/bidv-h2h/bidv-h2h.dto.ts`, guards/decorators and module.
- `backend-nest/src/config/env.ts`, both env examples and focused env tests -
  required KEK/environment/bounds/kill-switch validation with no fallback.
- `backend-nest/package.json` and lockfile - exact `openpgp` 6.3.1 pin.

The generic `AdminSetting` APIs and `common/secret-cipher.ts` will not store or
encrypt OPS-39 secret material.

### 3. Public ingress and canonical persistence

Planned files:

- `backend-nest/src/bidv-h2h/bidv-h2h.controller.ts` - public routes with
  route-specific auth, body/rate limits and stable response envelopes.
- `backend-nest/src/bidv-h2h/bidv-h2h-ingress.service.ts` - request hash,
  decrypt, complete-batch validation, canonical hashes/identity and one Prisma
  transaction for receipt + rows + projection outbox events.
- `backend-nest/src/bidv-h2h/bidv-h2h-parser.ts` - 28-field parsing, exact
  Decimal/date/direction/currency validation and the authoritative strict
  `remark` suffix candidate (`<storeId> BOT` or `<storeId>`).
- `backend-nest/src/request-body-parsers.ts` only if a route-specific parser is
  required; otherwise retain the global 1 MiB cap and enforce decoded bounds in
  the DTO/service.
- `backend-nest/src/common/user-aware-throttler.guard.ts` plus focused tests -
  skip the staff global 120/min bucket only for H2H routes and replace it with
  a dedicated client/IP-hashed limiter that can sustain the accepted 10 QPS.
- `backend-nest/src/request-log.ts` and sanitizer tests only as needed to prove
  no query/header/body/secret leakage.

Canonical persistence stores masked account display values and deterministic
hashes, not full accounts in logs or BigQuery. Sensitive raw metadata is
minimized and retained only under the 90-day canonical retention policy.

### 4. Async compatibility projection and old-consumer protection

Planned files:

- `backend-nest/src/bidv-h2h/bidv-h2h-projection.worker.ts` - lease/retry/
  backoff/dead-letter and projection kill switch.
- `backend-nest/prisma/schema.prisma`/migration - additive
  `MapVietinTransaction` bank source, currency, direction, exact Decimal amount
  and canonical bank transaction link; legacy `amount` remains populated only
  for eligible integer VND Credit rows.
- Existing MAP/eFAST logic remains unchanged except for shared serializers or
  type compatibility proven necessary by additive columns.
- `backend-nest/src/payment-notifications/payment-notifications.service.ts` -
  only the minimum transaction-type/generalized entry needed for BIDV
  projection; unique `transactionId` continues to prevent duplicate speaker
  side effects.
- BigQuery migrations/provisioning, row mapper/types/worker tests - add the
  sanitized bank/source/currency/direction/exact amount schema version while
  preserving v1/v2 compatibility and current-row semantics.
- Home projection tests - prove valid BIDV compatibility rows flow through the
  existing database triggers/queue and non-eligible canonical rows do not.
- Go code changes are not expected; Go tests must prove the existing scoped
  `PAYMENT_NOTIFICATION` path remains compatible.

Eligibility is fail-closed: only `dorc=C`, `currency=VND`, mathematically
integral positive amount, existing uniquely matched showroom, active projection
switch and conflict-free identity create a compatibility row. Debit, foreign
currency, fractional VND, missing/ambiguous showroom and conflicts remain
canonical/auditable without payment side effects.

### 5. Flutter Admin UI using the current runtime design

Planned files:

- `lib/features/admin/domain/api_connection.dart`
- `lib/features/admin/data/api_connection_repository.dart`
- `lib/features/admin/presentation/screens/api_connection_admin_screen.dart`
- `lib/features/admin/presentation/widgets/api_connection_*` only when shared
  components cannot keep the screen readable without duplication.
- `lib/features/admin/presentation/screens/admin_menu_screen.dart`
- `lib/app/navigation/app_router.dart`, `app_nav_model.dart` and
  `app_platform_capabilities.dart` as required for feature and platform guards.
- `backend-nest/src/feature/feature.constants.ts`, policy constants/seeding and
  migration for hidden `ADMIN_API_CONNECTIONS`; backend still explicitly
  requires `SUPER_ADMIN`.

UI states: loading, empty, cached-data-with-refresh-error, permission denied,
unsupported platform, client/key active-overlap-expiring-revoked, secret
one-time reveal, response-lost rotate guidance, kill-switch confirmation and
sanitized failure. Copy is Vietnamese-first. Client IDs and fingerprints may
appear as admin-only technical identifiers; secrets/private keys never appear
after the one-time response. Copy is an explicit button action, never automatic.

### 6. Deployment, operations and BIDV handoff

Planned files:

- `deploy/home-server/Caddyfile` - separate dedicated-host site that exposes
  only `/oauth2/token`, `/v1/balance-changes` and a minimal health route; no SPA,
  download, upload, staff API or WebSocket route is reachable on the BIDV host.
- `deploy/home-server/docker-compose.home.yml`, production/staging env examples
  and both deploy workflows - fail-closed `BIDV_H2H_DOMAIN`, KEK and kill-switch
  handling; Caddy validation and dedicated-host smoke.
- Cloudflare tunnel/DNS remains an explicit operator step using the current
  tunnel. The playbook/runbook records the exact hostname, origin host header,
  rollback and code never embeds tunnel credentials.
- `docs/runbooks/bidv-h2h-operations.md` - internal enable/disable, rotation,
  recovery, retention, reconciliation and rollback.
- `docs/runbooks/bidv-h2h-connection-playbook.md` - sanitized bank-facing source.
- `output/pdf/BIDV-H2H-OpsHub-Connection-Playbook.pdf` - generated after the
  Markdown content matches verified behavior; render every page to PNG and
  inspect headers, tables, code blocks, Vietnamese glyphs, links and pagination.

The bank-facing playbook includes both hosts/routes, OAuth request/response,
push header/body/response, public-key exchange and fingerprint confirmation,
retry/idempotency, UAT matrix, activation/rotation, contacts/placeholders and
troubleshooting. It contains no live secret or private material, and Codex does
not send it.

## Affected-Consumer Contracts

The implementation must create `scripts/validate-ops39-affected-consumers.mjs`
as the reviewed, fingerprint-participating proof wrapper. It must run commands
without changing shells or silently skipping a missing suite.

| Producer/change | Protected existing consumers and proof |
| --- | --- |
| `MapVietinTransaction` additive fields/projection | Tiền vào list/search/detail, Sao kê/order/tracking/export, VietQR reconciliation |
| payment notification creation | unique notification, speaker ready/stream/ack, no duplicate audio |
| DB triggers/outbox | Home finance queue/freshness and BigQuery revision/current view/tombstone |
| realtime event | Go v2 `payment.transactions`, legacy compatibility and scoped audience |
| auth/throttling/request logging | staff JWT/bootstrap/session, existing 120/min semantics, sanitized logs |
| admin feature/router | existing Admin destinations, permission-empty state and direct-route denial |
| Caddy/deploy/env | existing app `/api`, `/ws`, help/download/upload plus dedicated-host route isolation |

No pass may be reused after a participating source, migration, contract, test,
wrapper or plan fingerprint changes.

## Approach

1. Finalize repository product/story/decision contracts and generated non-secret
   test fixtures. Add the affected-proof wrapper skeleton with fail-closed suite
   discovery.
2. Add the expand-only Prisma migration and verify fresh/upgraded/rollback-safe
   behavior before application code depends on it.
3. Implement the dedicated secret/key control plane, exact OpenPGP pin and admin
   APIs. Prove redaction, one-time reveal, concurrent rotation/revoke and KEK
   failure behavior.
4. Implement OAuth, dedicated throttling and atomic canonical ingress. Prove
   valid, duplicate, conflict, mixed-invalid, replay, timeout and kill-switch
   paths with generated fixtures.
5. Implement the leased compatibility projection and only then exercise payment,
   realtime, Home and BigQuery consumers. Keep projection disabled by default.
6. Implement the current-style Flutter Admin screen and responsive/platform/
   accessibility states with sanitized logging.
7. Add dedicated-host Caddy/deploy/env behavior, internal operations runbook and
   bank-facing playbook source. Keep both switches disabled in examples.
8. Run focused proof, serialized test corrections, independent code/security/UI
   reviews, the final affected-consumer wrapper and PDF render inspection.
9. Update this plan, product/story/test matrix and Linear implementation proof.
   Stop before commit/push/PR/staging mutation until separately authorized.

## Risks And Recovery

- Secret/key disclosure: dedicated KEK, hash-only secrets/tokens, no-store
  responses, redacted serializers/logs and negative leakage tests. If a reveal
  response is lost, rotate; never add a re-reveal endpoint.
- Incorrect identity creates duplicates or conflicts: projection starts off,
  identity/hash conflicts remain canonical only, and UAT reconciliation must
  approve the tuple before enabling projection.
- Projection duplicates speaker/realtime/BigQuery: outbox lease + dedupe key,
  compatibility transaction unique key, unique payment notification and
  existing BigQuery current-view revision semantics.
- Shared trigger deadlock/regression: preserve canonical lock ordering, run the
  current Home/MAP deadlock and BigQuery migration proof, and do not delete or
  weaken existing guards.
- Global throttler blocks BIDV target or H2H bypass weakens staff routes: route
  isolation plus dedicated tests for both buckets and Retry-After behavior.
- Dedicated hostname exposes the OpsHub SPA/admin API: separate Caddy site with
  default deny and host/path isolation smoke.
- Multi-replica stale key/client state: correctness reads PostgreSQL; Redis may
  cache only versioned metadata and must fail back to DB. Activation/revocation
  updates a version and invalidates cache after commit.
- OpenPGP compatibility: local generated round-trip is necessary but not enough;
  UAT activation remains blocked until BIDV encrypts a fixture with the exported
  public key and OpsHub decrypts it exactly.
- Runtime rollback: disable `BIDV_H2H_PROJECTION_ENABLED` first while keeping
  ingest on when persistence/decrypt remains safe; disable ingest only for
  auth/decrypt/persistence safety. Revert application/Caddy code through the
  normal staging path. Leave expand-only tables/columns in place and preserve
  audit/canonical rows; destructive contract migration is a separate issue.
- Lost/corrupt active private key: disable ingest, activate the overlapping key
  if available, otherwise generate a new pair and re-exchange only the public
  key with BIDV. Never recover by extracting plaintext private material from UI.

## Progress

- [x] Read applicable repository workflow/product/release authority.
- [x] Read Linear OPS-39, relations and comments.
- [x] Render and visually inspect all 27 BIDV PDF pages; inspect wire pages 1-6
      individually.
- [x] Reconcile spec and repository exploration through `opshub_spec_analyst`
      and `opshub_repo_explorer` read-only waves.
- [x] Record the accepted endpoints/control-plane/playbook addendum in Linear,
      post the planning proof comment, transition to `In Progress`, and read
      both artifacts back.
- [x] Run lifecycle dry-run and `start --execute`; create the exact-SHA task
      branch/worktree.
- [x] Record this durable implementation, recovery and verification plan.
- [x] Obtain `Duyet plan, implement` for local implementation only.
- [x] Run one `opshub_implementer` writer wave.
- [x] Run serialized correction plus code/security/UI review of the final diff;
      the exhaustive Codex Security workspace scan was not opened because it
      requires a separate interactive scan session.
- [x] Run final local affected-consumer, render and repository proof. Runtime
      PostgreSQL migration, real Caddy, load and external BIDV proof remain
      explicitly pending.
- [x] Extend the Flutter API-connection model/repository with the three-state
      operating-mode contract, readiness/blockers/backlog fields and
      optimistic-version writes while keeping the legacy boolean request path
      available during the compatibility window. Focused model/repository and
      Admin screen tests, targeted Flutter analysis, and focused NestJS proof
      pass on the current checkpoint.
- [x] Receive Đại Ca's approval for the exact OPS-39 Figma proposal revision
      (`2450:6`, `2450:68`, `2451:5`, `2451:67`, `2451:129`, `2451:191`,
      `2451:256`, `2451:318`, `2451:338`) and mark the proposal page as
      `ĐÃ DUYỆT`; Flutter visual implementation is now unblocked.
- [x] Record factual implementation/proof in Linear comment
      `dc03f05a-805b-4b1c-b72e-6c74c7169258`; read back the comment and verify
      OPS-39 remains `In Progress` with no lifecycle transition.
- [x] Implement the approved Figma Admin surface for the three operating modes,
      including compact/medium/expanded/wide geometry, centered readiness chips
      and action buttons, loading/failure/emergency states, backlog confirmation,
      and compatibility-safe `emergencyDisabled` parsing. Targeted Admin tests
      and Flutter analysis pass.
- [x] Re-run the affected-consumer wrapper after the UI correction: 15 Nest
      suites/304 tests, Flutter Admin/router/platform/consumer tests, Go realtime,
      migration/static, Caddy isolation, local-only promotion, backup/KEK and
      whitespace guards all pass.

## Decisions

- 2026-07-30: Use dedicated public hosts for the BIDV H2H boundary.
- 2026-07-30: “Key” means the OpsHub OpenPGP key pair used by BIDV encryption,
  not the existing MAP signature key or VietQR n8n API key.
- 2026-07-30: Reuse the current Admin runtime components. This is an unmigrated
  feature addition, not visual-redesign authority and not permission to restore
  retired legacy presentation.
- 2026-07-30: Separate canonical bank ingress from compatibility payment
  projection so projection can be paused while safe ingest continues.
- 2026-07-30: Do not use generic `AdminSetting` or the MAP/JWT-fallback cipher
  for OPS-39 secret material.
- 2026-07-30: Generate the bank-facing playbook as Markdown plus PDF after its
  contents match verified implementation; do not send it externally.
- 2026-08-01: Finalize the transport contract as OAuth plus OpenPGP and use
  `bankapis-staging.hoanghochoi.com` / `bankapis.hoanghochoi.com` so the
  existing zone certificate can cover the public hosts.

## Validation

Focused NestJS proof:

- DTO/parser/date/Decimal/showroom/identity tests for all 28 fields and exact
  optional/null behavior.
- OAuth Basic parsing, secret verifier, token hash/expiry/scope/revoke, no-store
  and generic error tests.
- OpenPGP generated/imported key, wrong key/passphrase/armor/Base64, payload
  limits and no-secret serialization/log tests.
- Admin permission, one-time reveal, immutable audit, concurrency, overlap and
  last-active protection tests.
- Atomic valid/duplicate/conflict/mixed-invalid/outbox-failure rollback tests.
- Projection eligibility, lease retry/restart/dead-letter and no-side-effect
  tests for Debit/foreign/fractional/unmapped/conflict rows.

Migration and database proof:

- `npx prisma format` and `npx prisma validate`.
- Fresh disposable PostgreSQL migration.
- Upgrade from the current staging schema with existing MAP/eFAST rows.
- Constraint/index/trigger checks, transaction rollback and non-destructive
  rollback rehearsal with both kill switches off.
- Existing Home deadlock and MAP BigQuery migration verification scripts plus a
  new OPS-39 migration verifier.

Focused Flutter proof:

- `test/admin_menu_screen_test.dart`, `test/app_router_test.dart`,
  `test/app_nav_model_test.dart`, platform-capability and design-system guard.
- New API connection repository/model/screen tests for loading, empty, error,
  permission, unsupported, one-time reveal, rotate/revoke, key export and kill
  switches.
- Compact, medium, expanded and wide geometry; keyboard/focus/semantics, long
  Vietnamese copy and text scaling.

Protected existing-consumer proof:

- MAP/Vietin list, Sao ke/order/tracking/XLSX and VietQR reconciliation suites.
- Payment notification/speaker stream/delivery dedupe suites.
- Home finance projection/freshness/deadlock suites.
- BigQuery trigger/revision/row mapper/worker/backfill/current-view suites.
- Go `go test ./...` for realtime audience and compatibility.
- Staff auth/bootstrap/session and user-aware throttler suites.
- Admin menu/router/permission-empty and direct-route regression suites.
- Caddy/deploy workflow/env parser and existing app route smoke.

Broader gates after the final participating edit:

- `npm run build` and `npm test -- --runInBand` from `backend-nest/`.
- `flutter analyze` and `flutter test` from the repository root.
- `go test ./...` from `backend-go/`.
- `node scripts/validate-ops39-affected-consumers.mjs`.
- `git diff --check` and exact diff/secret scan.
- Caddy configuration validation with both staging and production example host
  values, plus default-deny path tests.
- Generated k6/HTTP proof at the accepted 10 QPS target with p95 <= 500 ms and
  p99 <= 1 s; no live external call without staging authorization/credentials.
- Render every final playbook PDF page to PNG and visually inspect it; reopen the
  PDF and verify page count, text presence, headers/footers and absence of
  secret/private fixture material.

Staging/external proof still required before production readiness:

- Deploy exact staging SHA with both switches initially off.
- Exchange only the UAT public key, configure the dedicated hostname and
  then enable ingest while projection stays off.
- Run BIDV-produced happy/duplicate/conflict/invalid/debit/foreign/fractional
  fixtures and reconcile counts, sums and identity.
- Enable projection and verify Tiền vào, Sao kê, VietQR, speaker dedupe,
  realtime, Home and BigQuery exactly once.
- Exercise outbox recovery, retention, kill switches, backup/restore and
  rollback; verify SLO/load evidence.

## Result

Local implementation is complete on `codex/ops-39-bidv-h2h-api` at base HEAD
`0341fb76c22e5e1c4c94aaa61495441a58574243`. It adds the managed client/secret
and OpenPGP control plane, hash-only OAuth tokens, canonical atomic ingress,
leased compatibility projection, current-style Windows/web Admin UI, dedicated
BIDV hosts, operations documentation and a four-page bank-facing PDF playbook.

Verified locally on 2026-07-31: Prisma schema validation; Nest build; all 98
Nest suites / 1,065 tests; all 679 Flutter tests with 3 existing skips; focused
Admin/router/platform/consumer tests; Go realtime tests; additive BigQuery and
static migration contracts; dedicated-host static isolation; and the affected-
consumer wrapper. The implementation also verifies payload-size rejection,
stable per-identity concurrency locks and recovery of expired projection
leases.

Final review corrections force HTTP 200 on both public POST success paths, set
no-store on every Admin connection response, bind OAuth clients/tokens to BIDV
and the fixed scope, reject non-Ed25519/X25519 imported keys and oversized
decompressed OpenPGP messages, and recheck conflict state under the shared
identity advisory lock immediately before projection.
Showroom resolution was also reconciled back to Linear authority: only the
exact normalized `remark` suffix `<storeId> BOT` or `<storeId>` may propose a
candidate, which must match one existing showroom; account and virtual-account
values never infer showroom for BIDV. Existing MAP/Vietin account/VA mapping is
unchanged and remains covered by its regression suites.

Runtime fresh/upgrade PostgreSQL migration, real Caddy validation, 10 QPS load,
BIDV-produced OpenPGP fixture, DNS/tunnel routing, staging reconciliation and
release evidence remain pending. Both kill-switch layers stay disabled by
default. No real credential, key or account fixture was created. At this local
proof checkpoint, no commit, push, PR, Linear transition, deployment or release
had been performed.
The regenerated four-page connection playbook is 92,559 bytes with SHA-256
`042ea293845151a43cb3c7b30d6879bbdf08171569f6beed221bab679cc1a197`;
structural extraction confirms both hosts/routes, `REQUESTID`, the fixed scope
and the absence of internal operational-control notes, while the removed
placeholders and credential/private-key disclaimer text are absent.
The factual implementation/proof note was recorded in Linear without changing
the issue status.
