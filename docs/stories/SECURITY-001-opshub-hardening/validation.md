# SECURITY-001 Validation

## Required proof

| Area       | Required evidence                                                      | Current state                                                                          |
| ---------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Flutter    | format, analyze, full test, web/APK/Windows build                      | pass; final full 458 pass, 2 skip; signed artifacts verified                           |
| NestJS     | Prisma validate/generate, focused security tests, build, full Jest     | pass; final full Jest 64/64 suites, 629/629 tests                                      |
| Go         | gofmt, test, vet, govulncheck, slow-client/audience tests              | pass with Go 1.25.12                                                                   |
| Web edge   | HTTP redirect, HTTPS headers, CSP report, CORS matrix                  | production HTTP 308, HSTS/CSP enforce, origin/API/WS smoke pass                        |
| Media      | owner/admin/scope matrix, traversal/checksum/dual-read                 | focused + strict production audit/dry-run pass; apply/cutover follow-up                |
| Container  | build, non-root uid, read-only write check, health                     | staging/production live inspect pass on `0a949268...`                                  |
| Backup     | permission/encryption/restore drill                                    | encrypted restore proof + TrueNAS `20260715-012644` 6/6 pass; retention follow-up      |
| Dependency | npm audit, govulncheck, package/source contract                        | npm production 0; govulncheck pass                                                     |
| Data       | migration validation, row/checksum/backfill dry-run, rollback manifest | 58 migrations current; 750-candidate strict dry-run pass; apply intentionally deferred |

## Baseline

- Flutter analyze passed on the audit checkpoint.
- Flutter test passed with 416 passed and 1 skipped.
- NestJS build passed.
- NestJS full Jest had 534/536 passing; the two failures were already present in
  the protected dirty Sales Report worktree.
- Go test and go vet passed.

## Evidence log

- 2026-07-12: checkpoint captured and Harness intake 54 recorded.
- 2026-07-12: `npx prisma format` and `npx prisma generate` pass.
- 2026-07-12: Nest `npm run build` pass. Focused security 171/171,
  outbound/bounded response 124/124 and log/scope 215/215 pass.
- 2026-07-12: full Jest 57/59 suites, 584/586 tests. Both failures reproduce
  the protected Sales Report baseline: code now refuses fallback showroom but
  two specs still expect `CP62`/`CP01` from non-authoritative fields.
- 2026-07-12: `npm audit --omit=dev` reports 0 vulnerabilities; SheetJS CE is
  pinned to official `0.20.3` tarball.
- 2026-07-12: Flutter analyze pass. Focused redaction/private-media/ticket/
  updater tests 21/21 and payment-provider/app-log focused tests 33/33 pass.
- 2026-07-13: full Flutter pass with 515 tests, 1 skipped, 0 errors after
  injecting the realtime ticket URI issuer into the reconnect test. Web release,
  Android staging debug and Windows debug builds pass.
- 2026-07-12: Go test/vet pass; govulncheck with `GOTOOLCHAIN=go1.25.12`
  reports no called vulnerabilities.
- 2026-07-12: platform security script, GitHub workflow/Compose YAML parse,
  three `bash -n` checks, signer PowerShell parse and both Compose config checks
  pass.
- 2026-07-13: release builder fails closed while reviewed runtime files are
  untracked. Explicit local preview includes them and produced 234 runtime
  files, 11,093,245 bytes, with manifest SHA-256 and no env/test/xlsx/keystore.
- 2026-07-13: staging run `29240025639` attempt 3 deployed source SHA
  `af32413074c6fd71cc4afe7b15f647877ce2c5b4`. Windows EXE/installer signing,
  pinned signer validation, Defender scan, artifact publication, public health
  and version metadata passed.
- 2026-07-13: published staging installer version `2026.07.13.132` build `200132`
  matched its public SHA-256 checksum. A controlled Windows workstation reported
  Authenticode `Valid` and staging signer SHA-256
  `1BE124CCBD3CB609F1CD0F9DADE5F53ECAAD2B3978914F4E295E4AF9CEE43BF7`.
  Staging admin login smoke passed.
- 2026-07-13: Đại Ca accepted temporary waiver `SEC-WIN-SELF-SIGNED-20260713`
  because a public CA code-signing certificate is not currently budgeted. The
  waiver retains mandatory checksum, signer pin, timestamp, Defender and HTTPS
  controls and must be reviewed by 2026-10-13.
- Manual/unverified: Docker image build/runtime inspection, Cloudflare,
  credential rotation, private-media live migration, remaining realtime smoke,
  host ACL/retention and production smoke.

## Windows in-app updater regression 14/07/2026

> Historical proof only. Decision 0012 superseded the runtime Authenticode
> signer-pin contract on 15/07/2026; signer, timestamp and Defender validation
> remain mandatory CI release gates, while runtime now verifies the exact
> same-origin package SHA-256.

- Root cause: the Authenticode verifier passed the installer path after
  `powershell.exe -Command`; Windows PowerShell parsed that path as additional
  command text instead of exposing it through `$args[0]`. The workstation also
  exposes PowerShell 7 modules before Windows PowerShell modules, so automatic
  discovery can select an incompatible `Microsoft.PowerShell.Security` module.
- Fix contract: pass the path only through the child process environment and
  keep the PowerShell command text constant; import the Security module from
  the child process `$PSHOME`. A signed file whose path contains spaces, a
  quote, plus and semicolon must verify successfully; an unsigned executable
  must fail closed with `WINDOWS_SIGNATURE_NOT_VALID`.
- Required release proof: focused updater tests, Flutter analyze, Windows
  release build, signed staging installer, then an installed-build in-app
  update from the previous staging build to the new build.
- 2026-07-14: commit `3d3334ef2874c08a9dff8a1e68720962b5cac0e2`
  passed full Flutter (439 passed, 1 skipped), NestJS (60 suites, 596 tests),
  platform-security, Windows release-build and staging run `29302684759`.
  Public build `200146` matched checksum, Authenticode was `Valid`, and signer
  SHA-256 matched the staging pin.
- Installed staging build `200146` then received realtime build `200147` from
  run `29303262807`, downloaded and hash-verified the installer, logged
  `Windows package signature verification succeeded` with signer prefix
  `1BE124CCBD3C`, installed it, and relaunched as build `200147`. The relaunched
  app reported `currentBuild=200147` and `latestBuild=200147`.

## Production maintenance regression 14/07/2026

- Production run `29345053379` rolled back to `4e1ced4b...` after the new API
  failed health because `PRIVATE_MEDIA_BASE_DIR` was absent. All five primary
  containers recovered healthy; the old compose remains root/writable and is
  not accepted as hardening proof.
- Production env now contains the required private-media directory/public URL;
  a one-shot new-image env validation passed. Workflow preflight now checks all
  upload/private-media variables before stopping services.
- Staging smoke exposed a missing controller guard on
  `/sales-reports/follow-up-cases`: the database principal was `SUPER_ADMIN`, but
  the service received no authenticated user. The local fix adds JWT and
  `FeatureGuard`; metadata and unscoped Super Admin tests pass.
- Current local proof after the fix: Prisma validate, Nest build, platform
  security contract, workflow YAML parse, focused 138/138 tests, full Nest
  62/62 suites with 609/609 tests, focused Flutter 30/30 and `flutter analyze`.
  Tại checkpoint này runtime proof còn chờ staging SHA mới; mục final bên dưới
  ghi bằng chứng đã đóng sau staging/production.
- Pre-production backup regression: runtime dotenv release notes contained
  spaces, while the installed NAS job sourced the whole file as Bash. The job is
  hardened to parse only backup keys as dotenv data. Backup `20260714-234003`
  then published atomically with 6/6 destination checksum and no `.incoming`.
- 2026-07-15 pre-release refresh: Flutter analyze and full 458-test suite pass;
  Nest build, focused Sales Report 65/65 and full 64/64 suites with 629/629
  tests pass; Prisma migration scratch drill remains `90/90/90`; npm production
  audit reports 0 vulnerability. Go test/vet/govulncheck on the exact pinned
  production builder `go1.25.12 linux/arm64` reports 0 called vulnerability;
  `go test -race` also passes after client removal publishes the lower count
  only once close metadata and limiter release are complete. The host-only Go
  1.26.0 scan is intentionally not used as runtime evidence.

## Final staging/production proof 15/07/2026

- Release SHA `0a949268865afcfb120c8b521bd2c1733ca7ea3a` passed staging run
  `29356202412` and production run `29358234827`; both remote branches and live
  release/manifest matched the same source commit at verification time.
- Production API/realtime/Postgres/Redis were healthy and Caddy up. API ran
  `1000:1000`, realtime `app`, Caddy `1000:1000`; runtime services had
  read-only rootfs, `CapDrop=ALL`, `no-new-privileges` and bounded logs.
- Edge/origin smoke: HTTP `308`; HSTS one year + CSP enforce; API health/root
  `200`; public WebSocket `101`; anonymous `/api/media/:id` `401`; Redis
  unauthenticated `NOAUTH` and internal authenticated `PONG`.
- API/realtime logs in the 30-minute post-deploy window had 0
  `access_token=`/`ticket=` hits and 0 fatal-pattern hits. Prisma reported all
  58 migrations applied.
- TrueNAS backup `20260715-012644` atomically published six verified artifacts;
  timer remained enabled/active and `.incoming` count was zero.
- Production private-media strict audit reported 0 missing/orphan/size mismatch.
  Strict migration dry-run scanned 750 references and produced 750 candidates,
  with 0 missing/rejected/error. No `--apply`, purge or deletion was performed.
- Residual: 764 legacy files (~1.5 GB) remain under public `/uploads`; Caddy has
  no access-log directive, so 0 Docker-log hits is inconclusive. Media cutover,
  two-admin/MFA/secret rotation, retention/ZFS, sustained live load soak and
  Windows self-signed waiver review remain explicit follow-up controls.

## Backup closure and persistent legacy-media telemetry 20/07/2026

- TrueNAS Maproot was corrected to `root:root` for the NFS client path observed
  by TrueNAS. A write/read/SHA-256/delete probe passed before the backup job ran.
- Manual backup `20260720-100144` finished with systemd `Result=success` and
  exit code `0`. An independent destination check passed all six checksum
  entries; NAS `.incoming` and local `.nas-staging-*` counts were zero. The
  timer remained enabled/active and all five production containers stayed up,
  with API/realtime/PostgreSQL/Redis healthy and origin HTTP `200`.
- The current Caddy container started at `2026-07-20T00:13:40Z`. Its filtered
  legacy-upload telemetry contained one valid hashed `GET` hit at
  `2026-07-20T02:30:20Z`, status `304`, with zero malformed entries. Therefore
  private-media cutover remains blocked; no `--apply`, route removal, cache
  purge or legacy-file deletion was performed.
- Docker-only access history cannot survive a Caddy recreation. The follow-up
  source change writes only the already-filtered logger to the persistent
  `/data/legacy-uploads-access.log`, mode `0600`, rolling at 10 MiB with at most
  14 files retained for 14 days. Local platform-security checks, all four
  access-audit tests and Caddyfile adaptation with the production Caddy binary
  passed. Staging deploy and a fresh privacy probe remain required before the
  seven-day observation clock starts.
- Staging workflow `29722657920` deployed exact SHA `76380540...`. The release
  symlink matched that SHA; five containers were up, the four stateful/runtime
  services reported healthy, and the persistent log was created as `0600`.
  A loopback-origin probe returned `404` and produced exactly one hashed entry;
  strict audit reported one hit, one unique hash and zero malformed entries,
  while raw path and query sentinels were absent.
- Production workflow `29723471724` then deployed the same SHA successfully.
  The release symlink matched, API/realtime/PostgreSQL/Redis were healthy,
  Caddy was up, and edge plus origin health returned `200`. Production created
  `/srv/opshub/caddy/data/legacy-uploads-access.log` as `0600`, owner UID/GID
  mapped to `opc:opc`, with zero hits and zero malformed entries. No production
  probe was generated, so the observation window starts clean at Caddy start
  `2026-07-20T07:17:17.446Z` (14:17:17 UTC+7). Earliest seven-day gate is
  27/07/2026 after 14:17:17 UTC+7; the fourteen-day limit is 03/08/2026.
- Pre-maintenance review found that the original migration `--limit` always
  selected the first records and therefore was not resumable. The follow-up
  branch now requires bounded apply batches (maximum 250 records per category),
  reports `hasMore`/`nextOffset`, advances migration over a stable offset, and
  keeps rollback on the shrinking head. Ten focused telemetry/batch tests and
  the platform-security contract pass locally. No production apply or runtime
  restart was performed, so the observation continuity is unchanged.
- Staging workflow `29725449833` completed successfully at exact SHA
  `c86c2611d6ab5b69b329d5541a594ded848f9f02`. The live maintenance image
  rejected apply without `--limit`; a complete strict dry-run returned zero
  errors with the new batch report. All five staging services remained up with
  the four healthchecked services healthy and no one-shot maintenance container
  left behind. Production remained on `76380540...`; this proof did not restart
  the production Caddy or authorize migration apply.
- A shared Flutter dual-read contract now covers avatar, warranty and feedback
  references together: legacy URLs remain credential-free, same-origin private
  media URLs receive the bearer token, and model/parser layers preserve mixed
  references in order. The platform checker pins the header helper at Home,
  Profile, Warranty Detail, and both Feedback image surfaces. The focused test
  passed 3/3 and full Flutter analyze reported no issues. Live post-batch smoke
  remains mandatory because source proof does not prove production data access.
- Pre-maintenance audit hardening now distinguishes storage integrity from
  legacy-reference closure. The report classifies only aggregate counts by
  exact origin/path (including relative references that resolve to `/uploads`),
  emits no URL/path/record id, and supports `--fail-on-legacy` for the final
  post-batch gate. Preflight `--strict` remains compatible while legacy rows are
  expected; route cutover requires `legacyReferencesClear=true` and zero legacy
  references. Four new reference-audit tests plus the ten telemetry/batch tests
  passed 14/14, and the platform-security contract passed. Prisma generate,
  Nest build and reviewed runtime packaging (284 files, auditor/helper both
  present) passed. Staging run `29729119859` deployed exact SHA `bc9ca1c8...`.
  A run without `--build` proved the maintenance tag could remain stale even
  after the migrate image was built; rerunning with `-T --build` and closed
  stdin loaded the new auditor, passed preflight and final zero-legacy gates,
  rejected an unknown flag, left no maintenance container and kept all five
  services healthy. Live production post-batch proof remains pending.
- The cutover command now reads the persistent current and rolled telemetry
  files (including `.gz`) server-side and pipes them directly into the auditor;
  it no longer relies on container-local `docker logs --since 168h`. Platform
  verification prevents regression to the ephemeral source.
- Backup contract review found v2 omitted `private-media` despite valid checksums.
  The host script was checkpointed and upgraded to v3 with bounded live-tree
  retry. Manual run `20260720-164144` finished `Result=success`, NAS checksum
  `6/6`, manifest paths include both `uploads` and `private-media`, `.incoming=0`,
  and all five containers remained running (four healthchecked). Retention/ZFS
  expiry is still not enabled or approved.
- `/uploads` is explicitly blocked as an independent lane until no earlier than
  `2026-07-27 14:17:17 UTC+7`. The daily monitor is read-only and cannot invoke
  migration apply, route removal, cache purge or file deletion; other security
  lanes may proceed without weakening this stop condition.
- Eleven historical local backup files (1,406,850,712 bytes) were encrypted and
  archived to NAS as `local-recovery-20260720T102843Z`; checksum passed `3/3`
  and `.incoming=0`. The local backup directory now contains only 11,139 bytes
  of checkpoints. SEC-12 therefore no longer carries a plaintext-local-backup
  residual; retention/ZFS policy and periodic restore governance remain open.
- GitHub API recheck reported CodeQL, Dependabot and Secret Scanning at `0 open`.
  Default workflow permission is read-only and third-party Actions are limited
  to two pinned SHAs. Ruleset `19202484` now blocks deletion and
  non-fast-forward updates on `main` and `staging`; both branches report
  `protected=true`, while normal fast-forward pushes remain allowed.
- Every workflow action reference uses a full commit SHA. Repository Actions
  policy now reports `sha_pinning_required=true` through API version
  `2026-03-10`. Secret validity-check enablement did not persist (verified GET
  remained `disabled`), so it is recorded as unavailable/unverified rather than
  claimed as enabled.
- The independent realtime residual is closed at the measured staging level:
  121,628 authenticated HTTP requests across the 25/50/100-QPS ladder, a
  15-minute 100-QPS hold, 100% success, p95/p99 85.976/176.193 ms, zero
  unexpected 429/5xx/timeout/drop, and 60/60 `/ws/v2` sessions. One-time ticket
  replay, cross-scope audience rejection, session/access revocation and
  slow-client isolation remain covered by focused contracts. Cleanup revoked
  60 sessions, deleted 60 synthetic users and verified zero residual records or
  token artifacts. This proof is not a 1,000-user capacity claim.
- A read-only production aggregate found 3 active `SUPER_ADMIN`, 35 active
  `ADMIN`, zero locked privileged accounts and 38 active privileged sessions.
  The database schema contains no MFA/TOTP/WebAuthn/recovery field or table.
  Identity is therefore blocked on an owner decision and enrollment plan, not
  on admin redundancy: choose the second factor and recovery owner, define a
  grace/enforcement window, then revoke existing sessions in a maintenance
  window. No account, credential or session was changed during this check.
