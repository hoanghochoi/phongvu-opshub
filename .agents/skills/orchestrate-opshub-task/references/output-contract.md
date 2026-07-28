# Delegated handoff contract

Every agent returns this compact structure. Use `None` for an empty section and
`Unverified` when runtime evidence is unavailable.

## Status

`Completed` | `Blocked` | `Needs decision` | `Unverified`

## Scope

Exact task slice, paths, symbols, and ownership boundary.

## Evidence

Files/lines, issue acceptance, source/base/head SHA, runtime metadata, logs,
screenshots, or exact commands that support the result.

## Findings

Actionable conclusions ordered by severity. Separate fact, inference, and
unknown; do not include style-only comments.

## Changes

Files changed, or `None` for read-only work.

## Verification

Exact command and result counts. Name protected old consumers and state checks
not run or blocked.

## Risks

Residual regression, permission, platform, stale-SHA, or environment risk.

## Handoff

One bounded next agent or human action. No implicit commit, push, PR, Linear
transition, deployment, or release authorization.

Review findings use: severity, location, problem, impact, evidence, minimal
correction, and required regression test.
