# Support Chat Phase 1 Contract

## Intent

OpsHub provides one long-lived private support conversation between each
authenticated staff user and the shared Super Admin support inbox. The feature
is additive, in-app only, and disabled by default until the complete backend,
realtime, Flutter and staging proof is ready.

## Product Authority

- Linear `OPS-40` is the business, permission, privacy and rollout authority.
- `docs/decisions/0010-client-cache-and-realtime-invalidation.md` remains the
  authority for HTTP-as-source-of-truth and the single authenticated `/ws/v2`
  connection.
- The owner has explicitly authorized Phase 1 Flutter implementation with the
  current runtime UI, existing design system and shared components/tokens.
  Support Chat must not create or modify Figma artifacts and does not wait for
  exact Support Chat frames in this implementation lane.
- That authorization is temporary current/legacy-UI authority only. It does
  not approve a redesign, replace OPS-34 R2.9, or authorize visual migration of
  any other surface. A later redesign requires its own exact approved frames.

## Conversation And Permission Model

- A requester has at most one conversation. The first requester message creates
  it; an admin cannot create a requester conversation proactively.
- Conversation status is `OPEN` or `RESOLVED`.
- Every active Super Admin can list and read the shared inbox. Only the current
  assignee can reply or resolve.
- A Super Admin can claim an unassigned conversation, release their assignment,
  or take over another assignment after explicit confirmation. Claim is a
  conditional write, so concurrent claims have one winner.
- A requester message appended to a resolved conversation reopens it and clears
  the assignee in the same database transaction.
- Resolve requires `expectedLastMessageSequence`; a newer message returns a
  conflict and the client refreshes instead of overwriting the active state.
- Demoted, disabled or non-Super-Admin principals lose privileged REST and media
  access immediately. Cached UI or realtime claims never grant access.
- An authenticated requester whose organization assignment is pending can use
  Support Chat. Anonymous users cannot.

## Message And Media Contract

- Supported content is plain text/emoji and up to four private images per
  message. Phase 1 excludes Markdown/HTML/link preview, documents, voice/video,
  reactions, typing/presence, edit/delete and offline send queues.
- Text contains 1–4,000 Unicode characters and at most 16 KiB UTF-8.
- Each image is at most 5 MiB; a message is at most 20 MiB total. Accepted input
  types are JPEG, PNG, WebP, HEIC and HEIF, with at most 24 MP and one frame.
- The server decodes and re-encodes images, strips metadata and never persists
  or returns the original filename.
- Media uses `MediaObject.ownerFeature = SUPPORT_CHAT` and
  `ownerRecordId = SupportMessage.id`. User access is authorized from the
  conversation, not from a client-supplied owner or URL.
- Flutter loads protected images with authenticated memory-only image providers.
  Chat history, drafts and protected images are not persisted to local disk;
  logout and account switch clear in-memory chat/image state.

## REST Contract

Requester endpoints:

- `GET /support-chat/me?beforeSequence=&limit=`
- `POST /support-chat/me/messages`
- `POST /support-chat/me/image-messages`
- `POST /support-chat/me/read`

Super Admin endpoints:

- `GET /support-chat/admin/conversations?bucket=UNASSIGNED|MINE|ACTIVE|RESOLVED&query=&cursor=&limit=`
- `GET /support-chat/admin/conversations/:id`
- `POST /support-chat/admin/conversations/:id/claim`
- `POST /support-chat/admin/conversations/:id/release`
- `POST /support-chat/admin/conversations/:id/takeover`
- `POST /support-chat/admin/conversations/:id/resolve`
- `POST /support-chat/admin/conversations/:id/read`
- `POST /support-chat/admin/conversations/:id/messages`
- `POST /support-chat/admin/conversations/:id/image-messages`

The authenticated server derives requester, sender, role, recipient, assignee
and status. They are never accepted from a client DTO. Message pagination uses
monotonic per-conversation sequence values serialized as decimal strings and a
maximum page size of 50. `clientMessageId` is idempotent within the authenticated
sender/conversation boundary.

Text sends allow 30/minute and image sends allow 6/minute per composite
principal. They remain inside the accepted global principal budget of
120/minute. Rate-limit responses include `Retry-After`; no raw principal, IP,
query or payload appears in logs.

## Durable Invalidation And Notifications

- Every message/state mutation and its `DomainOutboxEvent` commit atomically.
  The outbox stores identifiers, revision, sequence, change type and timestamp
  only—never message text, filename, media URL, binary data or audience payload.
- The dedicated worker uses bounded batches, leases/`SKIP LOCKED`, retry with
  backoff and a dead-letter terminal state. Redis failure never rolls back or
  fails an already committed send.
- Redis channel is `SUPPORT_CHAT_UPDATED`; v2 kind is
  `SUPPORT_CHAT_INVALIDATED`; topic is `support.chat`.
- Support Chat is `/ws/v2` only. No new socket and no legacy `/ws` event are
  introduced. The gateway validates a complete server-derived audience and
  never forwards audience metadata.
- Queue invalidation is Super-Admin-role scoped and contains no conversation
  identifier. Thread invalidation targets the exact requester/current assignee
  and may contain conversation ID, revision and last sequence.
- HTTP remains the source of truth. Reconnect/resume requests one resync; there
  is no periodic chat polling timer.
- `/auth/bootstrap` adds the optional capability `supportChat` and advertises
  `support.chat` only while `SUPPORT_CHAT_ENABLED=true`.
- `/notifications/feed` stays `schemaVersion=1` and may add an optional
  `supportChat` section. Existing statement-transfer and offset-adjustment
  sections are unchanged, and older clients can ignore the new section.

## Current-UI Flutter Contract

- A memory-only `SupportChatProvider` uses the shared
  `RealtimeConnectionManager` and the existing auth lifecycle.
- The support bubble is available on authenticated `AppShell` routes and the
  standalone `/assignment-pending` surface. Super Admin opens the shared inbox;
  another user opens their own conversation.
- The existing `Hỗ trợ` action and the new bubble open in-app Support Chat when
  the capability is enabled. If the capability is missing/disabled, they retain
  the current Seatalk fallback. Public `/seatalk-support` remains unchanged.
- The bubble and Windows `QuickActionsLauncher` share one floating-action stack
  and must not overlap navigation, keyboard, toast or safe areas.
- Compact layouts use a full-height sheet/surface. Medium and desktop layouts
  use a bounded side panel based on current shared layout tokens. The composer
  keeps attachment, input and send in one horizontal row.
- The Super Admin route is `/admin/support-chats` with the visible tile
  `Hỗ trợ nhân viên`. Queue labels are `Chưa tiếp nhận`, `Của tôi`,
  `Đang xử lý` and `Đã xử lý`.
- User status copy is Vietnamese-first: `Đang chờ tiếp nhận`,
  `Đang được hỗ trợ`, `Đã xử lý`, and the neutral expectation
  `Sẽ phản hồi khi có người tiếp nhận`.

## Retention, Rollout And Recovery

- Messages, audit events and Support Chat media are retained for 180 days.
  A daily advisory-locked job purges bounded batches and cleans orphaned
  `SUPPORT_CHAT` media. Published chat outbox entries use a shorter documented
  operating window.
- Encrypted backups can retain already-purged data for the existing backup
  window, currently up to 30 additional days. Restore procedure purges expired
  Support Chat data before enabling the feature.
- `SUPPORT_CHAT_ENABLED=false` is the deploy default. Fast rollback disables the
  flag so Flutter returns to Seatalk; it does not down-migrate or delete data.
- Staging enables the flag only after Nest, Go and Flutter are all deployed.
  Production promotes only the exact staging SHA accepted by QA.

## Capacity And Reliability Envelope

OPS-40 does not choose a new platform architecture or create a new SLO. It uses
the existing shared OpsHub deployment: one internal organization, Nest modular
monolith + PostgreSQL for authoritative writes, asynchronous durable outbox,
Redis invalidation and the existing Go gateway.

- Acceptance load is 20 text messages/second with queue/history p95 under
  500 ms and healthy outbox p95 under 2 seconds.
- The existing production recovery target remains RPO 24 hours / RTO 4 hours;
  release readiness requires backup and restore/purge evidence rather than a
  new feature-specific promise.
- No end-user response-time SLA is promised. Unpublished outbox older than
  60 seconds or any dead-letter row is a release blocker.

## Privacy And Logging

All user-facing flows log start, success, failure and important branches through
the established sanitized logger. Logs may contain opaque IDs/hashes, counts,
status, duration, outbox lag and sanitized error type. They never contain
message text, filenames, email, raw DTO/response, credentials, authorization,
media URL, binary data or full audience. Sentinel text/filename must remain
absent from Flutter, activity upload, Nest, Go/container and outbox proof.
