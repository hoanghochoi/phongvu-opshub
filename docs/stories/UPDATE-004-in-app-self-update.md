# UPDATE-004 In-App Self Update

## Goal

Android and Windows users can update OpsHub from the update gate without
opening a browser or pressing the update button when a new build is detected.

## Contract

- `GET /app-version?platform=android|windows` remains the source of truth.
  It returns the legacy `updateUrl` plus self-update fields:
  `packageUrl`, `packageSha256`, `packageSizeBytes`, `packageType`, and
  Windows `installerArgs`.
- Production and staging deploy workflows publish `packageUrl` equal to the
  released APK/installer URL, compute SHA-256 and size from the final published
  files, write those values into the backend env file, and verify the public
  `/app-version` response before the deploy is accepted.
- `AppUpdateGate` no longer opens the browser for Android/Windows. When
  startup, realtime, reconnect, resume, or metadata retry detects a newer
  build, it automatically starts the in-app download when safe package metadata
  is present, shows progress, verifies SHA-256 and size, logs start, download,
  verify, installer handoff, and failure decisions through `AppLogger`, then
  hands off to the OS installer. If package metadata is incomplete, it keeps the
  visible update gate and logs the skipped automatic start.
- Windows launches the Inno Setup installer with the published silent args
  such as `/VERYSILENT`, `/SUPPRESSMSGBOXES`, `/NORESTART`, and
  `/CLOSEAPPLICATIONS`, then exits the running app so Setup can replace files.
- Windows runtime verification is intentionally limited to an HTTPS,
  same-origin, allowlisted source; redirect rejection; package type/size; and
  exact SHA-256. The Flutter build does not receive a signer fingerprint and
  does not pin Authenticode at runtime.
- The release boundary remains fail-closed in CI. Production and staging require
  the correct PFX/password and configured signer fingerprint; Authenticode on
  the final executable/installer, a valid timestamp, signer-pin match and a
  clean Microsoft Defender scan must all pass before publication. Unsigned
  artifacts are rejected.
- Android opens the system Package Installer through a FileProvider URI. Before
  doing that, native code verifies the APK package name, versionCode, and
  signing certificate against the currently installed app. Android may still
  require the user to approve "install unknown apps" and confirm installation;
  the app must guide that flow without using the browser.
- Web remains reload-only and does not use package install metadata.

## Failure And Logging Contract

- Every `AppSelfUpdateException` has a non-empty stable `code` and one of these
  stages: `preparing`, `downloading`, `verifying`, `installing`, or
  `unexpected`. Unknown failures use a dedicated unexpected code rather than
  the generic string `error`.
- Preparing covers missing metadata, rejected source, invalid contract/limit or
  package type. Downloading covers network/HTTP, timeouts, size overflow,
  mismatch or incomplete transfer. Verifying covers SHA-256 mismatch.
  Installing covers unsupported platform, native validation and installer
  launch. Unexpected is reserved for failures outside those contracts.
- Integrity, contract, native and unexpected failures use `AppLogger.error`
  with upload enabled only when authenticated. Network, HTTP, timeout and
  incomplete-transfer failures use local `warn` logs and feed the daily
  activity summary.
- Logs contain only code, stage, duration, platform/build, sanitized host and
  safe byte counts. They never include a URL query, token, payload or local file
  path. Staff see Vietnamese, action-oriented copy rather than codes or HTTP
  details, and can still choose the manual `/download` fallback.

## Risks And Rollback

- Windows installer handoff can still fail if SmartScreen blocks an uncommon
  signed artifact or Setup cannot close the running app. The `/download` page
  and installer artifacts remain available for manual fallback.
- SHA-256 runtime verification does not authenticate the publisher if an
  attacker replaces both metadata and the hosted installer. This residual risk
  is explicitly accepted; CI signing/timestamp/pin/Defender gates remain
  mandatory and are not equivalent to a runtime signer pin.
- Android self-host APK updates only work when the new APK uses the same
  signing certificate. If Android denies unknown-source install permission, the
  client opens the per-app Settings screen and asks the user to retry.
- Roll back by shipping metadata without valid `packageSha256`/size; new clients
  will stop before downloading an unsafe package, while older clients can still
  use `updateUrl` and `/download`.

## Validation

- Focused Flutter update tests:
  `flutter test test/app_update_info_test.dart test/app_self_update_service_test.dart test/app_update_gate_test.dart --reporter expanded`.
- Focused tests must cover every code/stage/severity class, SHA mismatch file
  cleanup, safe log fields, authenticated upload policy, no runtime signer pin,
  and manual fallback copy.
- Focused backend metadata tests:
  `npm test -- app-version.service.spec.ts --runInBand` from `backend-nest/`.
- Required broader proof before release: `flutter analyze`, full Flutter tests,
  Android build, Windows build, backend build, workflow/security-contract
  checks and `git diff --check`.
- Staging release proof must inspect the published artifact's Authenticode
  signer and timestamp, confirm the Defender gate passed and metadata SHA/size
  matches, then update the already installed OpsHub Staging build N to N+1. The
  app must download, launch Inno Setup, close and relaunch as N+1 without
  changing the separate production installation.
