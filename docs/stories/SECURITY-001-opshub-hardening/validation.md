# SECURITY-001 Validation

## Required proof

| Area | Required evidence | Current state |
| --- | --- | --- |
| Flutter | format, analyze, full test, web/APK/Windows build | pass; signed staging installer verified |
| NestJS | Prisma validate/generate, focused security tests, build, full Jest | pass; full Jest 59/59 suites, 586/586 tests |
| Go | gofmt, test, vet, govulncheck, slow-client/audience tests | pass with Go 1.25.12 |
| Web edge | HTTP redirect, HTTPS headers, CSP report, CORS matrix | manual after deploy |
| Media | owner/admin/scope matrix, traversal/checksum/dual-read | focused pass; live backfill/cutover manual |
| Container | build, non-root uid, read-only write check, health | config contract pass; image/live checks manual |
| Backup | permission/encryption/restore drill | encrypted backup and isolated restore drill pass; host ACL/retention follow-up remains |
| Dependency | npm audit, govulncheck, package/source contract | npm production 0; govulncheck pass |
| Data | migration validation, row/checksum/backfill dry-run, rollback manifest | pending/manual runtime |

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
  Runtime proof remains pending a new staging SHA.
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
