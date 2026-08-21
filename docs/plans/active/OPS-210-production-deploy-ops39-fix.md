# OPS-210 Production deploy reliability and OPS-39 integration

Date: 2026-08-21

## Outcome

Repair the production deployment handoff for the `phongvu.work` migration and
integrate the approved, still-uncommitted OPS-39 bank-operation changes without
altering the original OPS-39 worktree.

## Checkpoint

- Base: `origin/staging` `500c3e955ff762a228c96d5ff53f51f86d04f8e9`.
- Production promotion reached the same SHA, but Deploy OpsHub run
  `32479258037` failed before runtime health verification.
- The original `codex/ops-39-ui-only-bank-operations` worktree remains intact;
  its tracked and untracked changes were copied into this task worktree.

## Root cause and repair

Production passed `OPSHUB_PUBLIC_BASE_URL` to local build and smoke steps but
omitted it from the environment assignment sent to its remote SSH shell. That
shell uses `set -u` and later expands the variable to publish `PUBLIC_BASE_URL`,
`IMAGE_BASE_URL`, and `ALLOWED_ORIGINS`, so it terminated with an unbound-variable
error. Staging already passes the value.

The repair explicitly passes the public URL in the production SSH environment
block and adds a release-workflow regression assertion. No production runtime
is patched directly; a new SHA must complete staging deploy and QA before a new
explicit production promotion.

## Validation and recovery

- Validate workflow YAML, release workflow regression tests, platform security,
  OPS-39 local-only/backup/Caddy boundaries, Nest, Flutter, Go, and affected
  consumers from this exact worktree.
- Commits `e7b76b8685504943ef985a33bce9b2fda8ec2b6b` (implementation) and
  `88e8cb6a` (evidence refresh) are the local release candidate. The retained
  owner manifest now binds to the implementation commit and records normalized
  SHA/byte metadata for the changed release workflows.
- `node scripts/verify-retained-owner-review.mjs --input
  docs/migrations/ops-73-retained-owner-review.json` passed with 4 candidates
  and 19 retained paths.
- `node scripts/verify-task.mjs --full` passed every selected repository
  profile, including Nest/Flutter/Go, deployment/Caddy, OPS-39 affected
  consumers, platform security, and lifecycle verification. The worktree is
  clean and `git diff --check` passes.
- Confirm the production deploy passes its remote runtime step before changing
  the production Tunnel from fail-closed routing.
- If staging deploy fails, keep production on the prior healthy release and
  investigate the staging log; do not retry production.

## Staging follow-up

The first exact-SHA staging deploy after PR #354 (`32486763960`) built and
published the runtime, then failed the direct-origin gate because canonical
`/help` returned `404`; the workflow completed its controlled rollback. The
failure is reproducible at the release boundary, while the public rollback
state remains healthy. This follow-up makes the `/help` SPA entrypoint explicit
in Caddy and adds a static contract assertion before the next staging attempt.

The next exact-SHA attempt (`32490005811`, `bcd4c281`) reproduced the same
`/help` 404 even though the candidate Caddyfile contained the explicit handler;
an isolated candidate Caddy container served `/help` correctly. The remaining
boundary was the full deploy transaction: shared web/Caddyfile paths are
replaced by inode and the full staging workflow did not explicitly recreate and
reload Caddy before the direct-origin gate. The follow-up now forces a Caddy
recreate, reloads the config, compares the mounted Caddyfile SHA to the active
release and verifies `/srv/web/index.html` is mounted before probing routes.
The production full deploy receives the same guard because it uses the same
bind-mount topology.

## Readiness follow-up

The next exact-SHA staging deploy (`32496859461`, SHA
`500c3e955ff762a228c96d5ff53f51f86d04f8e9`) still failed closed at the direct
origin `/help` probe and rolled back. The candidate Caddyfile, mounted web
bundle, exact host routing and an isolated Compose reproduction all served
`/help` successfully; the deployment Compose service had no Caddy healthcheck,
so `--wait` did not prove that Caddy had finished serving the newly recreated
bind mounts before the probe. Staging was restored to the prior release and
public `/health` plus API health were rechecked at 200 afterward.

Implementation commit `b1825c7d6873911b3838cf90fe216ccfe6c78178` adds a Caddy
HTTP healthcheck, waits after every runtime/static Caddy recreate in staging
and production, and waits for direct-origin `/health` before canonical route
verification. Retained-owner evidence refresh commit `0ffff21a` binds the
changed release workflows to that implementation SHA. A new staging deploy
from the resulting exact SHA is required before production promotion.

## SSH stdin boundary follow-up

Exact-SHA staging run `32503013705` built Windows and Android successfully, but
the remote deploy output stopped immediately after the BIDV KEK preflight. The
subsequent migration, runtime recreation, mounted Caddy hash checks and
direct-origin verification never ran; the remote step nevertheless exited `0`,
and the next job-level `/help` probe correctly failed against the unchanged old
Caddy before controlled rollback completed.

The cause is `bootstrap-bidv-kek.sh` invoking `docker compose exec/run -T`
while inheriting stdin from the parent SSH heredoc. `-T` disables a TTY but does
not close stdin, so Compose consumed the remaining remote transaction. Both
staging and production call this bootstrap from `bash -s`; no other helper
script is invoked that way in either deploy heredoc. The repair routes every
bootstrap Compose call through one wrapper with `< /dev/null`, adds static
guards against bypassing the wrapper, and adds a dynamic regression whose mock
Compose drains stdin and proves the command after the bootstrap still runs.
