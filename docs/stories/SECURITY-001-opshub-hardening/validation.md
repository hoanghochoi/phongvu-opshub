# SECURITY-001 Validation

## Required proof

| Area | Required evidence | Current state |
| --- | --- | --- |
| Flutter | format, analyze, full test, web/APK/Windows build | pass; signed release remains manual |
| NestJS | Prisma validate/generate, focused security tests, build, full Jest | generate/build/focused pass; 2 protected Sales Report baseline failures |
| Go | gofmt, test, vet, govulncheck, slow-client/audience tests | pass with Go 1.25.12 |
| Web edge | HTTP redirect, HTTPS headers, CSP report, CORS matrix | manual after deploy |
| Media | owner/admin/scope matrix, traversal/checksum/dual-read | focused pass; live backfill/cutover manual |
| Container | build, non-root uid, read-only write check, health | config contract pass; image/live checks manual |
| Backup | permission/encryption/restore drill | manual |
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
- Manual/unverified: Docker image build/runtime inspection, Cloudflare,
  credential rotation, signed release artifacts, private-media live migration,
  encrypted restore drill and staging/production smoke.
