# OPS-8 Flutter Web Break Iterator Compatibility

## Status

implemented

## Problem

Chrome reports `Intl.v8BreakIterator is deprecated` from generated
`main.dart.js`. The call is emitted by Flutter web's Chromium-optimized
CanvasKit text line breaker, not by application code or the app's `intl`
dependency. `Intl.Segmenter` does not expose line segmentation, so replacing
the call in OpsHub or upgrading unrelated packages cannot resolve it safely.

## Product Contract

- Flutter web must load the full CanvasKit variant from the source-controlled
  bootstrap on production and staging builds.
- The bootstrap must retain Flutter's generated build configuration and
  service-worker version token.
- Deployment cache busting must continue to version both
  `flutter_bootstrap.js` and `main.dart.js`.
- The build/publish guard must fail when the full CanvasKit selection or the
  required generated artifacts are missing.
- Chrome smoke proof must report zero `IntlV8BreakIterator` deprecation issues
  and load `/canvaskit/canvaskit.wasm`, not the `/canvaskit/chromium/` variant.

## Boundaries

- No Flutter SDK fork or patch to generated `main.dart.js`.
- No unrelated package updates; the current dependency graph is not the source
  of the warning.
- No user-facing copy, API, database, authentication, or navigation change.
- Existing `AppLogger` startup remains unchanged. CanvasKit selection happens
  before Dart starts, so bootstrap failures are diagnosed by the fail-closed
  build verifier and Chrome CDP evidence rather than an in-app log event.

## Accepted Trade-off

The full CanvasKit Wasm artifact is 7,083,768 bytes, 1,374,813 bytes (about
24.1%) larger than the 5,708,955-byte Chromium-specific artifact before
transport compression. The browser loads only the selected full artifact. This
compatibility cost is accepted until Flutter removes the deprecated upstream
line-breaking path.

## Affected Areas

- Flutter web bootstrap and generated release artifact.
- Deployment cache-busting guard.
- Existing Flutter application behavior, service-worker startup, and login
  route are protected consumers.
