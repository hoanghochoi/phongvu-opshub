# SECURITY-001 OpsHub Security Hardening

## Status

in_progress

## Input

Maintenance/security implementation based on:

- app-audit-21072026.md
- app-improve-implement-plan-12072026.md
- Harness intake 54

## Risk reason

This is a high-risk, multi-domain change. It touches authentication,
authorization, WebSocket sessions, Redis, private media, uploads, exports,
container policy, web edge behavior, Android release safety, dependency
advisories, staging credentials, and existing staff-facing contracts.

## Checkpoint

- Branch: main
- HEAD: 4e1ced4b8ecfce8ea33ff3c1440fdb5e5676a25b
- Upstream: origin/main
- Production SHA observed during the audit: same HEAD
- The Sales Report source/spec/migration and its product/test documentation were
  already dirty before SECURITY-001. They are protected from unrelated edits.
- The audit and implementation-plan Markdown files were already untracked at
  the start of this implementation turn.

## Objective

Close every security finding that can be fixed safely in source and deployment
configuration, preserve compatibility through explicit migrations, prove the
result with the required validation ladder, and document every action that
requires credentials, external dashboards, production data, or human approval.

## Acceptance criteria

- HTTP does not serve app content after the external edge action is completed.
- Static responses have reviewed security headers and a CSP rollout path.
- WebSocket clients no longer put long-lived JWTs in query strings.
- WebSocket authentication uses single-use, short-lived tickets and server-side
  session/audience enforcement.
- Realtime broadcasting cannot be blocked by one slow client and does not
  deliver sensitive events outside the server-resolved audience.
- Startup never creates or elevates a hard-coded administrator.
- OTP uses a cryptographically secure generator and public auth responses do
  not enumerate accounts.
- Rate limiting cannot be bypassed by rotating a caller-provided client id.
- Private warranty, feedback, and avatar media are no longer served as a public
  directory after the migration/cutover steps are completed.
- CSV exports neutralize spreadsheet formulas.
- Uploads verify actual content and apply bounded aggregate resource limits.
- Runtime containers, logs, backups, external URLs, API keys, Android release
  signing, and local Compose defaults follow the hardening plan.
- Dependency scans no longer report an unmitigated High issue on a called
  runtime path, or a specific manual/deferred item records the blocker.
- app-security-implementation-checklist-12072026.md is current and every item
  is marked done, manual, deferred with owner/date, or blocked with evidence.
- app-security-manual-actions-12072026.md contains executable, secret-safe steps
  for every action Codex cannot perform autonomously.

## Rollback rule

Rollback must be per workstream. It must never re-enable raw-token logging,
public directory access, hard-coded break-glass credentials, or a less secure
auth fallback. Database/media changes require forward-compatible dual-read and
an explicit restore manifest.
