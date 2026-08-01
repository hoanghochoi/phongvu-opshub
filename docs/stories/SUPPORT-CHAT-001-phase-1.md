# SUPPORT-CHAT-001 — In-app Support Chat Phase 1

## Status

`implementation_in_progress`; local implementation/proof only. Staging QA,
release approval and production deployment remain separate gates.

## Intake

- Input: new initiative linked to Linear `OPS-40`.
- Lane: high-risk.
- Affected domains: auth/authorization, PostgreSQL migration, private media,
  shared AppShell, notification feed, durable outbox, Redis, `/ws/v2`, Flutter
  session lifecycle, deployment and retention.
- Visual authority: owner-authorized current/legacy UI with existing shared
  components/tokens. No Figma mutation and no redesign approval.
- Product authority: `docs/product/support-chat.md` and Linear `OPS-40`.

## Observable Outcome

An authenticated requester, including assignment-pending staff, can maintain
one private support conversation. Super Admins share an inbox with atomic
claim/release/takeover/resolve behavior. Text and private images persist before
best-effort realtime invalidation. Capability-off clients keep the existing
Seatalk path.

## Accepted Behavior

- Authorization, DTO derivation, idempotency, sequence, media, rate-limit,
  outbox, notification, retention, UI copy and rollback behavior follow
  `docs/product/support-chat.md` exactly.
- HTTP/PostgreSQL is authoritative; realtime signals only invalidate.
- The feature is disabled by default and introduces no legacy `/ws` event.
- Current notification, auth/bootstrap ETag, media, shell, quick-action,
  assignment, logout/access-revoke and platform contracts remain compatible.

## Path Contracts

| Changed producer/path | Protected consumers |
| --- | --- |
| `backend-nest/prisma/**`, `backend-nest/src/support-chat/**` | auth/session, user deletion, shared Prisma startup/migrations, private-media references |
| `backend-nest/src/auth/**` | bootstrap ETag, saved-session compatibility, assignment-pending, realtime topic claims |
| `backend-nest/src/notification-feed/**` | statement-transfer and offset-adjustment feed sections and old-client schema v1 |
| `backend-nest/src/upload/**` | warranty, feedback and avatar media access/cleanup |
| `backend-nest/src/common/realtime-event.*`, outbox publisher | all existing typed Redis events; no sensitive payload/audience logging |
| `backend-go/**` | every existing `/ws/v2` topic, v1 `/ws`, public app-update channel, reconnect behavior |
| `lib/app/**`, `lib/features/support_chat/**` | AppShell desktop/mobile, notification bell/toast, Seatalk fallback, Quick Actions, routes |
| `lib/features/auth/**` | saved session, assignment-pending, logout/account switch/access revoke |
| `lib/core/network/**` | shared authenticated socket and private media headers |
| `lib/features/notifications/**` | current feed rows, badges, read state and realtime debounce |
| `deploy/**`, `.env.example` | feature-off default, public `/seatalk-support`, rollback/deploy ordering |

## Affected Verify Command

The reviewed path-contract wrapper runs every mapped old consumer without
calling removed Harness commands. Local pre-commit proof keeps the default
working-tree/index/untracked discovery:

```powershell
node scripts/validate-ops40-affected-consumers.mjs
```

The final publish gate resolves and validates the requested base commit, then
adds the no-rename `<base>...HEAD` path set without dropping or duplicating the
current working-tree/index/untracked paths:

```powershell
node scripts/validate-ops40-affected-consumers.mjs --base origin/staging
```

Its focused self-test covers committed rename discovery, dirty and untracked
paths, deduplication, default-mode compatibility and invalid-base/argument
failure:

```powershell
node --test scripts/validate-ops40-affected-consumers.test.mjs
```

The final broad proof then uses the same Windows-native worktree and exact
changeset:

```powershell
Set-Location backend-nest
npx prisma validate
npx prisma generate
npm run build
npm test -- --runInBand

Set-Location ..\backend-go
go test ./...
go vet ./...

Set-Location ..
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build windows --debug --no-pub
flutter build apk --debug --flavor staging --no-pub
flutter build web --debug --no-pub
git diff --check
```

Focused suites and disposable PostgreSQL migration/concurrency/media proof run
before the broad commands. The final affected proof is rerun after the last
source, test, documentation, contract or migration edit.

## Required Security Proof

- Requester A cannot read/send/mark-read or load media for requester B.
- Non-Super-Admin cannot access inbox operations; non-assignee cannot reply or
  resolve; demotion/disable takes effect without trusting cached UI/tickets.
- First-send, idempotent retry, claim and resolve/reopen races remain atomic.
- MIME spoof, size/pixel/frame limits, partial failures and orphan cleanup are
  covered.
- Missing/malformed realtime audience fails closed; audience/body/media
  metadata is never forwarded.
- Sentinel body and filename do not appear in logs, outbox or client storage.

## Remaining Release Proof

- Staging with two requesters and two Super Admins.
- Redis outage/recovery, Nest/Go restart and history/media durability.
- Android/Windows/web current-UI responsive/accessibility smoke.
- 20 text messages/second load and outbox/latency blocker metrics.
- Backup/restore purge rehearsal and feature-flag rollback.
- A future redesign/Figma follow-up is separate and does not block this
  owner-authorized current-UI Phase 1 implementation.
