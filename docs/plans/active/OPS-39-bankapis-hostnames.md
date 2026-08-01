# Execution Plan: OPS-39 BIDV Bank API hostnames

Date: 2026-08-01

## Status

Active

## Outcome

The BIDV H2H boundary uses `https://bankapis-staging.hoanghochoi.com` for UAT
and `https://bankapis.hoanghochoi.com` for production. Each remains an
API-only dedicated host.

## Context

The prior nested hostnames are not covered by the available
`*.hoanghochoi.com` certificate. `backend-nest/src/config/env.ts` pins the
public host while Caddy obtains the dedicated origin host from
`BIDV_H2H_DOMAIN`.

## Scope

In scope:

- Runtime hostname validation, deploy defaults, documentation and tests.
- Bank-facing playbook update without operational/internal control notes.

Out of scope:

- Creating Cloudflare DNS/tunnel records, changing protected env files or
  activating ingest/projection.
- OAuth, OpenPGP, client/key lifecycle and downstream projection behavior.

## Approach

1. Replace the two public hostname defaults and fail-closed validation.
2. Update bank-facing and operator documents; remove source-IP allowlist and
   mTLS references from the current contract.
3. Validate focused Nest/Flutter behavior, static deployment contracts and
   the absence of retired hostnames from current OPS-39 surfaces.

## Risks And Recovery

- DNS/tunnel does not exist yet: keep both activation switches false and do
  not issue a bank handoff until public TLS/route smoke passes.
- Wrong origin host header could expose the staff host: validate that every
  non-H2H path returns `404` after infrastructure deployment.
- Recovery: restore the prior environment values and redeploy; no migration or
  persisted bank data changes are part of this work.

## Progress

- [x] Create worktree from `origin/staging` SHA
  `5739ff1239c37039ee5aaedbdc11c2b47fe52e89`.
- [x] Apply runtime/config/documentation change.
- [x] Add dedicated-IP rate limits and update the infrastructure handoff.

## Decisions

- 2026-08-01: Đại Ca selected direct-child `bankapis` hostnames because the
  available zone certificate does not cover the old nested hostnames.
- 2026-08-01: The contract is OAuth 2.0 plus OpenPGP. Bank-facing material
  states the required integration steps without internal control commentary.

## Validation

- Focused proof: Nest environment tests and Flutter API connection screen test.
- Static proof: deploy workflow/env/Caddy contract and retired-hostname scan.
- Runtime proof after approved infrastructure work: TLS, default-deny routes,
  unauthenticated API behavior and UAT fixture.

## Result

Implemented locally: hostname validation/deploy defaults, dedicated-IP throttle
(60 token requests/minute/IP; 600 balance-change requests/minute/IP), expanded
operator handoff, focused Nest proof (42 tests), Nest build, focused Flutter
test (4/4), Flutter analyze and regenerated bank playbook PDF. DNS/tunnel/TLS
smoke and BIDV UAT remain external steps.
