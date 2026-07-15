# OpsHub Staging On `mementoamoris`

Staging uses `mementoamoris` through Tailscale and exposes the staging API at
`opshub-staging.hoanghochoi.com` through a dedicated Cloudflare Tunnel. Staging
client downloads and manifests are served directly from
`https://opshub-staging.hoanghochoi.com/downloads/`; the protected download page
is `https://opshub-staging.hoanghochoi.com/download`.

## One-time server setup

1. Confirm SSH uses Tailscale:

   ```bash
   ssh -G mementoamoris | grep '^hostname 100.127.127.89'
   ssh mementoamoris 'tailscale ip -4 && sudo ufw status verbose'
   ```

2. Copy or checkout this repo on `mementoamoris`, then bootstrap directories:

   ```bash
   bash deploy/staging/bootstrap.sh
   ```

3. Edit `/srv/opshub-staging/env`; replace every placeholder and keep secrets
   staging-only. Keep the file owned by `root:<operator-group>` with mode `0640`.
   Store `STAGING_TEST_PASSWORD` only in this protected env file (or an approved
   secret manager), never in a command line, shell history, issue or document.

4. In Cloudflare, create a dedicated tunnel named `opshub-staging`, then install
   the tunnel service on `mementoamoris`. If `~/.cloudflared/cert.pem` is
   present, the script can create the service token automatically:

   ```bash
   bash deploy/staging/install-cloudflare-tunnel.sh
   ```

   DNS for `opshub-staging.hoanghochoi.com` must be created in the Cloudflare
   account that owns the `hoanghochoi.com` zone. If the local cert belongs to
   that zone, the script can also create the DNS route:

   ```bash
   CLOUDFLARED_ROUTE_DNS=true bash deploy/staging/install-cloudflare-tunnel.sh
   ```

   If the host does not have `cert.pem`, pass a token created from Cloudflare
   Zero Trust instead:

   ```bash
   CLOUDFLARED_TUNNEL_TOKEN='<token>' bash deploy/staging/install-cloudflare-tunnel.sh
   ```

5. Add GitHub staging secrets:

   - `OPSHUB_STAGING_VPS_HOST=100.127.127.89`
   - `OPSHUB_STAGING_VPS_USER=hhh`
   - `OPSHUB_STAGING_SSH_KEY`
   - `ANDROID_STAGING_KEYSTORE_BASE64`
   - `ANDROID_STAGING_KEYSTORE_PASSWORD`
   - `ANDROID_STAGING_KEY_ALIAS`
   - `ANDROID_STAGING_KEY_PASSWORD`
   - required: `WINDOWS_STAGING_SIGNING_PFX_BASE64`,
     `WINDOWS_STAGING_SIGNING_PFX_PASSWORD`
   - required staging Environment variable:
     `WINDOWS_STAGING_UPDATE_SIGNER_SHA256`
   - shared Tailscale CI secrets: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`

## Deploy

The staging branch is the deploy source for this environment. When the operator
says `push staging` or `deploy staging`, collect the ready local changes on the
`staging` branch, run the required validation, then push `origin/staging`. The
`Deploy OpsHub Staging` workflow also supports manual `workflow_dispatch` for
operator-controlled reruns.

The workflow builds staging Android and Windows packages, uploads them to
`/srv/opshub-staging/downloads`, publishes manifest URLs under
`https://opshub-staging.hoanghochoi.com/downloads/`, updates app-version metadata
in `/srv/opshub-staging/env`, runs migrations, and recreates only the staging
Docker services.

The Windows staging job is fail-closed: PFX/password/pin, valid Authenticode
signatures and timestamps, a matching signer fingerprint and a clean Defender
scan are mandatory. The signer pin is a CI-only release input; it is not passed
to the Flutter runtime. The signing helper installs only public certificates
from the protected PFX chain into the ephemeral runner's current-user trust
stores, so `Get-AuthenticodeSignature` must return exactly `Valid`; an untrusted
chain is not accepted as a pin-only exception.

Before recreating services, the workflow records the previous `current`
release, a protected copy of the old env, and an exact snapshot of shared
staging publication state: web bundle, Help assets, download page/icon/manifest,
and any versioned client file whose target name already existed. New client and
static files remain under run/attempt-scoped staging paths until this checkpoint
is complete; release directories are also run/attempt-scoped so rerunning the
same SHA cannot mutate the active release in place. Migration, recreate, health
check, direct-origin routes, public API/metadata, Cloudflare Access, or `/ws/v2`
route proof failure restores the env, symlink/services and every shared file;
only target-version files that did not exist before promotion are removed. The
protected metadata remains on the server until every public gate is green and
is deleted only by the final success step. A failure before `deploy_runtime`
does not invoke runtime rollback because it has not written an active shared
path. The deploy must still be reported failed; a successful rollback is
containment, not release proof. This batch has no database migration, so runtime
rollback does not create a schema-version mismatch.

If a runner is lost after a checkpoint is created, the same GitHub run is
deliberately blocked from overwriting that checkpoint on rerun. Recover or
roll back the retained checkpoint first; clean reruns still use a distinct
run/attempt release directory and cannot mutate an existing release in place.

Every staging deploy also fixes side-effect controls to these values before
startup:

```dotenv
ERP_ORDER_CACHE_SYNC_ENABLED=false
ERP_ORDER_STATUS_SYNC_ENABLED=false
VIETQR_AUTO_RECONCILE_ENABLED=false
MAP_VIETIN_GLOBAL_SYNC_ENABLED=false
HOME_SUMMARY_ERP_BACKFILL_ENABLED=false
```

All `SMTP_*` values are removed. Do not enable a sync/reconcile/backfill or
production SMTP credential for capacity proof.

Every manual `docker compose` command against the runtime stack must export
`OPSHUB_ENV_FILE` to the same file passed through `--env-file`. The compose
file now fails fast when `OPSHUB_ENV_FILE` is missing so operators do not
silently fall back to `deploy/home-server/env.example`.
The API is the only service that reads the full env file. Postgres, realtime,
and Caddy receive explicit environment keys, so staging app-version updates
should not recreate database infrastructure during a deploy.

Production deploys must not be pushed directly from feature branches. After
staging is accepted, fast-forward `main` from `staging` and push `origin/main`
to run the production workflow.

## Sanitized DB refresh

Refreshing staging from production is manual and destructive to staging only.
It streams the production dump through SSH without writing the raw dump to disk
on the Windows machine.

First rotate `STAGING_TEST_PASSWORD` in `/srv/opshub-staging/env`, then run:

```bash
bash deploy/staging/refresh-sanitized-db.sh --confirm-staging-refresh
```

The refresh script reads the secret inside the API container through the
protected runtime env file. It deliberately does not accept or forward the
password on the local command line.

The sanitizer creates these known users with the password above:

- `staging.admin@phongvu.vn`
- `staging.staff@phongvu.vn`
- `staging.acare@acare.vn`

Rotate the staging password and revoke test sessions after every shared test
window. Before exposing this environment, place the hostname behind Cloudflare
Access, VPN or an equivalent identity-aware allowlist; DNS plus a tunnel alone
is not an access-control boundary.

After deploy or refresh, run `deploy/staging/smoke-checklist.md`.

For the bounded 100-QPS Home/realtime release proof, follow
`deploy/staging/load-proof-runbook.md`. It is staging-only, seeds temporary
accounts without SMTP, and requires revoke/delete/token cleanup even when the
test fails.
