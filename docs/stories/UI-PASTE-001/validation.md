# UI-PASTE-001 - Validation

## Automated proof

- Shared/native bundle:
  `flutter test --no-pub test/app_form_controls_test.dart test/text_input_context_menu_bootstrap_test.dart test/design_system_migration_guard_test.dart --reporter expanded`
- Required web compilation: `flutter build web --release --no-pub`.
- Required static proof: `flutter analyze --no-pub`.
- Required final gate: full `flutter test --no-pub` and Harness intake 72
  affected-runtime run/check.

The iOS widget regression opens the shared toolbar, taps Paste, and asserts the
controller receives the mock clipboard text. The migration guard proves all
runtime editable fields still use the shared input primitives and that the
shared builder retains system plus adaptive implementations.

Current result: the shared/native bundle passed 40 tests,
`flutter analyze --no-pub` passed, and the release web build plus Wasm dry run
completed successfully. Full Flutter regression passed 571 tests with 3
platform skips.

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
