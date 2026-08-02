# OPS-45: Staging public artifact verification

## Objective

Restore reliable staging deployment verification without weakening rollback or
security checks.

## Evidence

GitHub Actions runs 30759850730 and 30759924146 both passed client builds and
backend deployment, returned `ok` from `/health`, then exited silently in
`Verify staging public health and version metadata`. The affected workflow uses
direct `curl -fIs` calls for package and manifest URLs, bypassing the
Cloudflare Access-aware request helper and providing neither retry nor status
diagnostics.

## Plan

1. Add a bounded, Access-aware range-request helper to validate public download
   artifacts without downloading complete packages.
2. Route all package and manifest artifact checks through that helper. Keep
   verification fail-closed after the retry budget is exhausted.
3. Extend the release workflow regression test to require the guarded helper
   and reject direct silent `curl -fIs` checks.
4. Validate locally, publish a PR to `staging`, merge only after checks pass,
   then observe the exact staging deploy and record evidence in OPS-45.

## Protected behavior

- Cloudflare Access remains required for protected staging requests.
- Staging rollback still occurs when public artifacts cannot be verified.
- Large installers are not fully downloaded during verification.
