# OpsHub Staging On `mementoamoris`

Staging uses `mementoamoris` through Tailscale and exposes the staging API at
`opshub-staging.hoanghochoi.com` through a dedicated Cloudflare Tunnel. Staging
client downloads are linked from the production domain under
`https://opshub.hoanghochoi.com/staging-download` so they stay separate from the
production `/download` page.

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

3. Edit `/srv/opshub-staging/env`; replace every placeholder and keep secrets staging-only.

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
   - optional: `WINDOWS_STAGING_SIGNING_PFX_BASE64`, `WINDOWS_STAGING_SIGNING_PFX_PASSWORD`
   - shared Tailscale CI secrets: `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_SECRET`

## Deploy

The staging branch is the deploy source for this environment. When the operator
says `push staging` or `deploy staging`, collect the ready local changes on the
`staging` branch, run the required validation, then push `origin/staging`. The
`Deploy OpsHub Staging` workflow also supports manual `workflow_dispatch` for
operator-controlled reruns.

The workflow builds staging Android and Windows packages, uploads them to
`/srv/opshub-staging/downloads`, publishes manifest URLs under
`https://opshub.hoanghochoi.com/staging-download`, updates app-version metadata
in `/srv/opshub-staging/env`, runs migrations, and recreates only the staging
Docker services.

Every manual `docker compose` command against the runtime stack must export
`OPSHUB_ENV_FILE` to the same file passed through `--env-file`. The compose
file now fails fast when `OPSHUB_ENV_FILE` is missing so operators do not
silently fall back to `deploy/home-server/env.example`.

Production deploys must not be pushed directly from feature branches. After
staging is accepted, fast-forward `main` from `staging` and push `origin/main`
to run the production workflow.

## Sanitized DB refresh

Refreshing staging from production is manual and destructive to staging only.
It streams the production dump through SSH without writing the raw dump to disk
on the Windows machine.

```bash
STAGING_TEST_PASSWORD='<known staging password>' \
  bash deploy/staging/refresh-sanitized-db.sh --confirm-staging-refresh
```

The sanitizer creates these known users with the password above:

- `staging.admin@phongvu.vn`
- `staging.staff@phongvu.vn`
- `staging.acare@acare.vn`

After deploy or refresh, run `deploy/staging/smoke-checklist.md`.
