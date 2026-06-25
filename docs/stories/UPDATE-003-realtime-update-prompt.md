# UPDATE-003 Realtime Update Prompt

## Goal

Show the update overlay to an already-running Android or Windows client as soon
as a deploy publishes newer app-version metadata, without waiting for an app
restart.

## Contract

- `GET /app-version?platform=...` remains the source of truth for whether an
  update exists, whether it is required, and which URL should open.
- After the API starts with deploy-published metadata, NestJS publishes an
  `APP_VERSION_UPDATED` Redis event containing only public build metadata.
- The Go realtime service broadcasts that signal as `APP_UPDATE` through the
  public, updates-only `/ws/app-updates` endpoint. Public clients on this route
  must never receive warranty, payment, or other authenticated events.
- `AppUpdateGate` verifies every realtime signal through `GET /app-version`
  before changing UI. It also verifies after WebSocket reconnect and app resume
  so an event missed during service restart is recovered.
- Dismissing an optional build suppresses that same build for the current app
  process. A newer build or a required update can show again.
- WebSocket errors never block app startup or remove the existing startup HTTP
  check.

## Risks And Rollback

- This crosses Redis, Go WebSocket, Flutter lifecycle, and deployment restart
  timing. Focused tests must prove event filtering and missed-event recovery.
- Roll back by removing the API bootstrap publish and public updates-only route;
  the startup HTTP update check remains functional.

## Validation

- Focused NestJS app-version tests and full NestJS build/tests.
- Go realtime tests, including public-client event isolation.
- Focused Flutter update-gate tests, analyze, full tests, and Android/Windows
  build proof.
- `git diff --check` and exact diff review.
- Live deploy proof remains the final end-to-end verification for Redis publish,
  WebSocket delivery, and the prompt on an already-running old client.
