# UPDATE-003 Realtime Update Prompt

## Goal

Show the update overlay to an already-running Android, Windows, or web client
as soon as a deploy publishes newer app-version metadata, without waiting for
an app restart.

## Contract

- `GET /app-version?platform=...` remains the source of truth for whether an
  update exists, whether it is required, and which URL should open. Web clients
  use `platform=web`, receive web metadata with an empty update URL, and reload
  the current page instead of opening an app download URL.
- After the API starts with deploy-published metadata, NestJS publishes an
  `APP_VERSION_UPDATED` Redis event containing only public build metadata.
- The Go realtime service broadcasts that signal as `APP_UPDATE` through the
  public, updates-only `/ws/app-updates` endpoint. Public clients on this route
  must never receive warranty, payment, or other authenticated events.
- `AppUpdateGate` verifies every realtime signal through `GET /app-version`
  before changing UI. It also verifies after WebSocket reconnect and app resume
  so an event missed during service restart is recovered.
- Dismissing an optional build suppresses that same build for the current app
  process. A newer build or a required update can show again. On web, the
  primary action is `Tải lại`, and web metadata must not force the APK/installer
  update path.
- Android and Windows prompt actions are handled by `UPDATE-004`: the client
  downloads and verifies the package inside the app before handing off to the OS
  installer instead of opening the package URL in a browser.
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
- Focused Flutter update-gate tests, analyze, full tests, and Android/Windows/
  web build proof when the changed surface affects build output.
- `git diff --check` and exact diff review.
- 2026-07-03 live staging smoke published `APP_VERSION_UPDATED` through staging
  Redis and proved public WebSocket delivery plus deployed Flutter web recheck:
  raw WS received `APP_UPDATE`; Chrome CDP on staging web saw `/ws/app-updates`,
  the smoke frame, and one follow-up `/api/app-version?platform=web` request
  with console/runtime errors at 0.
- The live smoke reused current metadata to avoid forcing staff updates; visible
  forced-prompt rendering remains covered by widget/local update-gate tests.
