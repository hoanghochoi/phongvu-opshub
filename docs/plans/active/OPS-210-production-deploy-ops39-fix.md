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

## Production Tunnel and rollback transaction follow-up

Production run `32511199264` deployed candidate SHA
`c462c94c4502dfe2ff96213f878451e495e7af4d` successfully at the direct runtime
boundary, then failed all public checks because the locally managed production
Tunnel still omitted `phongvu.work` and `api.phongvu.work` and therefore matched
its final `http_status:404` rule. The automatic rollback then failed because the
exact previous release requires `BIDV_H2H_DOMAIN`, while its protected env
snapshot predates that compatibility key.

The failed rollback left production inconsistent: `current` points to the old
release while candidate containers remain active, and app-version metadata can
advertise a candidate package that the restored shared download tree does not
contain. The rollback also selected Compose project `opshub`, while the deploy
uses the default `home-server` project, so even a parseable rollback could have
recreated a second project instead of replacing the candidate containers. The
next release must use one explicit Compose project identity and reconcile the
release pointer, runtime env, running containers, app-version metadata and
shared package files as one transaction.

The bounded repair is ordered as follows:

1. Prepare a transaction-local rollback env from the untouched protected
   snapshot. If the exact previous Compose requires the legacy BIDV hostname,
   derive `BIDV_H2H_DOMAIN`, `BIDV_H2H_PUBLIC_BASE_URL` and
   `BIDV_H2H_ENVIRONMENT` from that release's tracked `env.example`, then run
   `docker compose config` for that exact release before any runtime switch.
2. Make runtime rollback coherent: install the prepared env and switch the
   release pointer only inside a guarded rollback attempt; if recreating the
   old release fails, restore the pre-attempt env/pointer and recreate that
   release instead of leaving mixed state. Deploy, rollback and proof use the
   same explicit Compose project name.
3. Verify the candidate directly at `127.0.0.1:8090` with exact production web,
   API and legacy hosts before opening Cloudflare ingress.
4. Snapshot `/etc/cloudflared/config.yml`, preserve every unrelated rule, add
   exact `phongvu.work` and `api.phongvu.work` rules before the final 404,
   validate the candidate config, install it atomically, restart `cloudflared`,
   and prove both rules target only `http://localhost:8090`.
5. On public verification failure restore the Tunnel snapshot first. Keep the
   directly verified dual-domain candidate as the production foundation; do
   not roll that boundary back to the pre-domain release merely because the
   external cutover failed. Runtime failures before direct-origin acceptance
   still use the compatible exact-release rollback above.
6. Finalization removes only the transaction-specific Tunnel/runtime snapshots
   after public verification and release-consistency proof pass.

Regression proof must cover Tunnel activate/restore/idempotency/unknown config,
the exact pre-domain rollback contract, failure recovery without mixed state,
explicit Compose project identity, production direct-origin ordering,
workflow/security validators and the full affected-consumer profile. No manual
production mutation is authorized by this plan; publish, staging deploy and a
new production promotion retain their normal approval gates.

## Correctness review follow-up

Wave 4 closed the Tunnel CAS, signal-safe historical restore, immutable-release
and full-web identity findings, but exposed one affected consumer that must be
fixed before publication. Static-only publication now updates only
`/srv/opshub/downloads/help`, while the API container still reads
`/app/docs/help` from the immutable release mount. This can leave
`/help-content/public` on old Markdown/navigation even though static assets and
the non-empty smoke check pass.

Keep release bytes immutable, but provide one shared/versioned Help source for
both the API docs loader and the web Help assets. The static transaction must
snapshot, promote and restore that source atomically, refresh the API mount
safely, and verify a content sentinel through `/help-content/public` rather
than only checking that pages are non-empty. Update and execute
`deploy/staging/static-transaction-rehearsal.sh` for the immutable static
contract; it must no longer expect Caddy/current-release mutation or call the
removed `opshub_txn_restore_static_current` helper. Also remove the duplicate
`DOWNLOADS_DIR`/`WEB_DIR` assignments in the production SSH environment block.

The bounded implementation uses `/srv/opshub/downloads/help` as that one
shared source: the API mounts it read-only at `/app/docs/help`, while Caddy
continues serving its `assets/` subtree. Full deploys therefore stage the whole
`docs/help` tree, not only `assets`. Static promote and rollback recreate only
the `home-server` API service after the host directory swap so the bind mount
cannot retain a stale inode. Verification captures the pre-deploy public Help
snapshot: when every page is docs-managed (`seededFromDocsAt` is present), the
post-deploy response must match the new navigation/Markdown content; when any
page is editor-managed, the response must remain unchanged so deployment does
not overwrite accepted runtime edits.

Wave 5 review tightened two ownership boundaries. Anonymous Help responses are
not authoritative for the whole runtime because private or draft pages are
filtered out; the static transaction must classify docs-managed versus
editor-managed from the complete database state inside the API maintenance
boundary, then use the public response only for behavioral comparison. Add a
mixed-visibility regression where a hidden editor-managed page suppresses docs
sync and the deployment preserves the public snapshot. Update
`docs/product/help.md` and `docs/product/backend-platform.md` to describe the
immutable release plus shared read-only Help source.

The Tunnel sidecar must also record whether the production host pair was
inserted by this transaction or already existed before it. Surgical restore may
remove the pair only in the inserted case. For a pre-existing pair, unrelated
config drift is preserved together with the exact owned routes; changed owned
routes still fail closed. Add a pre-existing-active plus unrelated-drift
regression and re-check the live hash immediately before restart/install.

The server-side Help deploy-state probe must use the repository's Prisma 7
PostgreSQL adapter boundary (`pg.Pool` plus `PrismaPg`), not a bare
`new PrismaClient()`. Add executable proof for the probe construction/runtime
path in addition to pure projection tests so a build-only pass cannot hide an
adapter initialization failure.

The workflow must execute the actual Nest build output at
`dist/src/help-content/help-content-deploy-state.js`; verification must bind the
workflow command to that compiled path and reject the shorter non-existent
`dist/help-content/*` path.

## Cloudflare Bot Fight Mode public-probe follow-up

Exact-SHA staging run `32527557089` deployed merge SHA
`d029b6215be5b1daf5d3825d708a28e40413e73d`, passed Windows, Android, backend,
container health and direct-origin canonical-route proof, then retried
`https://staging.phongvu.work/health` twelve times from `21:29:54Z` through
`21:30:49Z` without receiving a 2xx response. Controlled rollback completed and
restored the previous public staging release.

The origin and Tunnel were not the failing boundary. Post-rollback web/API and
legacy health checks returned `200` from SIN and HKG; the staging Tunnel had one
connector with four healthy QUIC connections and exact version-7 ingress for
`staging.phongvu.work` and `api-staging.phongvu.work` to
`http://127.0.0.1:8090`. Cloudflare Security Events recorded eleven matching
requests from GitHub runner IP `64.236.135.2`, every five seconds from
`04:29:54` through `04:30:49` GMT+7, each receiving `Managed Challenge` from
`Bot fight mode`. No corresponding request reached the Tunnel, which explains
why direct origin passed while runner-side public verification failed.

Free-plan Bot Fight Mode cannot be skipped by a WAF custom rule. Disabling it
zone-wide would weaken the accepted public protection boundary. Full and
static-only release verification therefore run curl from the target environment
host over the public URL while requiring both `Server: cloudflare` and a
non-empty `CF-Ray` on successful responses. This preserves DNS, TLS, edge,
Tunnel and exact-host proof without classifying GitHub's known automated egress
as application failure. Failed retries report sanitized URL, HTTP status,
CF-Ray and edge server without logging response bodies. Regression guards bind
both staging and production workflows to the remote-egress plus Cloudflare-edge
contract, including baseline and rollback/static Help probes.

Independent review then found two fail-open risks in the first implementation.
Production response capture used an `&&` chain whose failed status/header check
could still fall through to `cat` under Bash `set -e`, and artifact verification
searched every redirect header block instead of the final response. A shared
`cloudflare-public-probe.sh` now emits bodies only after an exact 2xx plus final
`Server: cloudflare` and `CF-Ray`, and artifact proof additionally requires a
positive final `Content-Length`, `%{url_effective}`, and an explicit
per-environment final-host allowlist: `phongvu.work` plus
`opshub.hoanghochoi.com` for production, and `staging.phongvu.work` plus
`opshub-staging.hoanghochoi.com` for staging. Authority parsing rejects
userinfo, non-HTTPS URLs and ports other than the implicit/default `443`. The
runtime release allowlist includes this helper, while pre-deploy/static-only
jobs stream the reviewed checkout copy over SSH.

A second correctness review reproduced that the streamed `bash -s` path could
define functions and exit zero without dispatching because `BASH_SOURCE[0]` is
empty for stdin scripts. The CLI guard now explicitly treats an empty
`BASH_SOURCE[0]` as direct stdin execution while ordinary `source` use remains
definition-only. Executable fixtures exercise both direct-file and exact stdin
`body`/`artifact` invocation, assert curl executes exactly once, reject 403 and
missing edge headers without body output, reject a Cloudflare redirect ending
at a non-Cloudflare response, reject cross-environment/userinfo/non-contract
port targets, and accept only an allowlisted Cloudflare final response. Focused
workflow, security, transaction, YAML, shell and whitespace
proof pass. Full verification is intentionally pending the implementation
commit and retained-owner evidence refresh; production remains unchanged.

The final review pass also removed an accidental host-Node dependency created
when the full public verification moved behind SSH. JSON checks now use the
shared `opshub_api_node` boundary, which executes Node inside the already
running API container with the exact Compose project/env/current release and
stdin closed. BIDV response files remain host-local: the workflow reads and
removes them on the host, then passes only the JSON strings to the container;
containerized validation never receives host `/tmp` paths. Executable mock
proof covers the Compose argv and closed-stdin boundary, and structural guards
reject bare host `node -e`, removed `public_curl` calls, and host-file reads in
the remote verification blocks.

## Production Compose env-path boundary follow-up

Production promotion run `32542781325` fast-forwarded both remote branches to
exact staging SHA `0704354537c6de649de44cae831773afb1f905d1`. Downstream deploy
run `32542937396` built and uploaded all client artifacts, then failed before
Cloudflare activation while reconciling the previous production baseline.
The baseline runtime itself became coherent, but
`production-runtime-identity.sh` invoked Compose after a `sudo env` privilege
boundary that intentionally discarded the caller environment. The Compose
file requires `OPSHUB_ENV_FILE` for its `env_file` mounts, while the helper
accepted that exact path only as a positional argument and did not republish it
for Compose interpolation. This production-only reconciliation branch is not
executed by the staging deploy, which is why the exact staging SHA passed.

The hotfix makes every production helper that accepts an env path
self-contained: baseline verification, runtime identity, and runtime rollback
bind `OPSHUB_ENV_FILE` to their positional env argument for each Compose call.
The executable cutover fixture now unsets the ambient variable and rejects any
Compose invocation that does not receive the exact expected path. Validation
must include the cutover transaction fixture, release workflow tests, platform
security checks, YAML/shell parsing, whitespace proof, and the full task gate
before another staging deploy or production promotion.

## Unknown-host fail-closed follow-up

Production deploy run `32549706821` reached a healthy candidate runtime, then
the direct-origin acceptance gate rejected it because
`unknown.phongvu.work/health` returned Caddy's default empty `200` instead of
`404`. The production transaction restored release `430e1ffd`, runtime env,
containers, shared metadata and package publication, and the legacy public
web/API/Help/download surfaces returned `200` after rollback. The production
Tunnel was never activated.

The root cause is Caddy's behavior when no configured host route matches. Add
an explicit hostless HTTP catch-all site that returns `404`; Caddy's exact site
addresses retain precedence for the three allowed environment hostnames. Also add
the equivalent unknown-host direct-origin assertion to the guarded staging
deploy transaction; staging previously verified canonical/legacy routes but
did not exercise this production acceptance contract. Static workflow/security
guards and a live Caddy routing smoke must prove known web/legacy hosts still
work while an unknown host returns `404` before another staging deploy.
The required PR `Release guard` invokes that pinned-image runtime smoke
directly; merely registering it in the local affected-consumer profile is not
sufficient CI evidence.

## Production retained-identity retry follow-up

Production workflow-dispatch run `32556993336` reached the guarded baseline
preflight at exact SHA `c06f023f0515c03087c98f35bbeb5212f7f9ea04`. Release
pointer, live env, home-server containers, Caddy, shared web/Help/manifest,
direct-origin REST/realtime/BIDV and package coherence passed, but the retained
runtime identity differed in `envSha256`, `apiImageId`, and `realtimeImageId`.
Source commit, Caddy, web tree, manifest, and Help hashes still matched.

The stale proof was created by an earlier retry boundary: a baseline preflight
failure occurred before any shared snapshot or candidate mutation, but the
outer error trap still ran runtime rollback. That rollback normalized the env
and recreated the exact release images; because shared restoration had no
snapshot, identity refresh was skipped. Every later run therefore rejected the
otherwise coherent baseline and repeated the same recovery loop.

The durable fix keeps recovery disarmed throughout baseline preflight and arms
it immediately before the first live env mutation. A baseline whose executable
behavior and shared publication are fully coherent may refresh only its stale
retained identity and verify the new record before proceeding. An armed runtime
rollback refreshes identity only after the shared snapshot was restored, or
when the missing `SNAPSHOT_READY` marker proves live shared mutation never
began; a genuinely mixed shared state still fails closed. Executable cutover
proof must cover coherent baseline plus stale image identity, while workflow/
security guards bind the preflight-disarmed and mutation-armed ordering.
