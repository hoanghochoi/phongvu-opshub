# 0001 Adopt OpsHub Harness

## Status

accepted

## Context

PhongVu OpsHub is already a working multi-surface project: Flutter app, NestJS
API, Go realtime service, PostgreSQL, Redis, and deployment notes. The generic
`harness-experimental` repository provides a useful human-agent workflow, but it
assumes a project with no application implementation.

## Decision

Adopt the harness pattern, but tune it for OpsHub instead of copying the generic
files verbatim.

## Consequences

- Root `AGENTS.md` describes OpsHub-specific operating rules and validation.
- Product docs describe current OpsHub domains.
- Existing behavior starts as `existing_unverified` in the test matrix until
  fresh proof is attached.
- Runtime source code is not changed by this adoption.
