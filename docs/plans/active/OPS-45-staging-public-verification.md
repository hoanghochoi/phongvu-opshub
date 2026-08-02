# OPS-45: Staging public artifact verification

## Objective

Restore reliable public staging deployment verification without weakening
rollback, content, or artifact checks.

## Evidence

GitHub Actions runs 30759850730 and 30759924146 both passed client builds and
backend deployment, returned `ok` from `/health`, then exited silently in
`Verify staging public health and version metadata`. The affected workflow uses
direct `curl -fIs` calls for package and manifest URLs, providing neither retry
nor status diagnostics. The first follow-up showed that Cloudflare Access has
now been intentionally removed from staging, so all verification must use the
public contract rather than service credentials or an Access redirect.

## Plan

1. Add a bounded public range-request helper to validate public download
   artifacts without downloading complete packages.
2. Route all package and manifest artifact checks through that helper. Keep
   verification fail-closed after the retry budget is exhausted.
3. Extend the release workflow regression test to require the guarded helper
   and reject direct silent `curl -fIs` checks.
4. Validate locally, publish a PR to `staging`, merge only after checks pass,
   then observe the exact staging deploy and record evidence in OPS-45.

## Protected behavior

- The staging download page is public and must render the download landing page,
  not the SPA fallback.
- Staging rollback still occurs when public artifacts cannot be verified.
- Large installers are not fully downloaded during verification.
