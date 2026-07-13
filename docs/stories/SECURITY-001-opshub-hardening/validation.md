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
