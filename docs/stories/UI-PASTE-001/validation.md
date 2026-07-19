# UI-PASTE-001 - Validation

## Automated proof

- Shared/native bundle:
  `flutter test --no-pub test/browser_native_paste_recovery_policy_test.dart test/app_form_controls_test.dart test/text_input_context_menu_bootstrap_test.dart test/design_system_migration_guard_test.dart --reporter expanded`
- Required web compilation: `flutter build web --release --no-pub`.
- Required static proof: `flutter analyze --no-pub`.
- Required final gate: full `flutter test --no-pub` and Harness intake 74
  affected-runtime run/check.

The native iOS widget regression opens the shared system/adaptive toolbar, taps
Paste, and asserts the controller receives the mock clipboard text. The web
regressions require iOS PWA to enable `BrowserContextMenu`, reject a Flutter
toolbar/Paste button, and cover both shared text input and combobox. The
migration guard proves all runtime editable fields still use the shared input
primitives, retain system plus adaptive fallbacks, and keep browser-native mode
for mobile web.

Previous result at staging build `2026.07.19.210`: physical iOS PWA exposed the
duplicate Flutter plus Safari Paste controls. Intake 73 corrected the owner
policy. Automated proof now passes the focused shared/native bundle (40 tests),
`flutter analyze --no-pub`, and `flutter build web --release --no-pub` with the
Wasm dry run. A Playwright iPhone-profile smoke with `navigator.platform`
overridden to `iPhone` verified browser context-menu events are not canceled,
DOM paste inserts `IOS-PWA-PASTE` once, and no Flutter `Paste` semantic label is
rendered. The Chrome widget-test runner still times out before its test-manager
handshake. The full Flutter run reached 570 passed and 3 intentional skips but
hit unrelated timing assertions in realtime tests; isolated reruns of
`statement realtime max-wait prevents refresh starvation` and
`SalesReportProvider filters and coalesces shared realtime v2 events` both
passed. Intake 74 adds an idempotent browser-paste recovery path for the
intermittent case where Safari emits a paste event but Flutter's hidden DOM
input misses the result. It uses the focused `EditableText` controller snapshot
and applies the replacement only when Flutter has not already changed it.
Focused shared/native proof passed 42 tests, `flutter analyze --no-pub` was
clean, the release web build plus Wasm dry run succeeded, and the full Flutter
suite passed 573 tests with 3 intentional platform skips. Physical iOS PWA
smoke on staging remains the final device gate for this follow-up. Intake 74
affected-runtime run/record passed for four protected consumers:
`PAYMENT-STATEMENT-KEYBOARD-001`, `UI-KEYBOARD-001`, `UI-PASTE-001`, and
`UI-UX-001`.

## Manual proof

On a physical iPhone using the installed/PWA staging build:

1. Copy text from another application.
2. Open representative plain, validated, and combobox inputs.
3. Verify tap/double tap/long press exposes the appropriate menu.
4. Tap Paste and verify text is inserted once, keyboard remains open, and the
   focused control stays above the keyboard.
5. Repeat with an existing value to verify selection handles, Cut, Copy,
   Select All, and Paste.

## Current environment gap

The local Flutter 3.38 Chrome test runner launched Chrome 150 headless but did
not complete its test-manager handshake. This is recorded as a runner gap, not
as web interaction proof; physical iOS PWA smoke remains required.
