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
- Android opens the system Package Installer through a FileProvider URI. Before
  doing that, native code verifies the APK package name, versionCode, and
  signing certificate against the currently installed app. Android may still
  require the user to approve "install unknown apps" and confirm installation;
  the app must guide that flow without using the browser.
- Web remains reload-only and does not use package install metadata.

## Risks And Rollback

- Windows installer handoff can fail if the package is unsigned, blocked by
  Defender/SmartScreen, or cannot close the running app. The old `/download`
  page and installer artifacts remain available for manual fallback.
- Android self-host APK updates only work when the new APK uses the same
  signing certificate. If Android denies unknown-source install permission, the
  client opens the per-app Settings screen and asks the user to retry.
- Roll back by shipping metadata without valid `packageSha256`/size; new clients
  will stop before downloading an unsafe package, while older clients can still
  use `updateUrl` and `/download`.

## Validation

- Focused Flutter update tests:
  `flutter test test/app_update_info_test.dart test/app_self_update_service_test.dart test/app_update_gate_test.dart --reporter expanded`.
- Focused backend metadata tests:
  `npm test -- app-version.service.spec.ts --runInBand` from `backend-nest/`.
- Required broader proof before release: `flutter analyze`, Android build,
  Windows build, backend build, `git diff --check`, and at least one manual
  Android + Windows update smoke from an older installed build.
