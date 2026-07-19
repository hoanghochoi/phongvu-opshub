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
passed. The follow-up replaces the timer/controller recovery with a narrowly
owned iOS touch path plus a capture-phase DOM bridge for both `paste` and
`beforeinput(insertFromPaste)`. The first touch used to focus a field and all
mouse, keyboard, or programmatic clicks still reach Flutter. Only a touch on an
already-focused input, or a fast repeated touch on that same input, is kept
outside Flutter's editable recognizers without canceling WebKit defaults. The
owned `pointerId` must match, so unrelated multi-touch events are not
suppressed. Matching pointer-up/cancel stays owned even when retargeted, while
only an exact-input click in the 300ms pointer-up lease is stopped before
Flutter 3.44.x can move the hidden input to `-9999px`. A null-target blur is
guarded while that owned touch is active or during one single-use 220ms grace
immediately after its matching pointer-up or pointer-cancel, and only when the
document remains focused and visible. An outside pointer, focus on another
control, hidden/page lifecycle, or a new primary touch clears stale ownership.
The bridge
uses the direct or active Flutter DOM input. It may reuse a cached input only
when that exact target produced the guarded transient blur within the bounded
10-second lease and still matches the retained focused `EditableTextState`.
An empty first event retains one 180ms lease only for its immediate opposite
event carrying text; another empty, same-source, late, foreign, focus, or
lifecycle event consumes it. The bridge never queries or redirects a foreign
input. It emits one synthetic `input` event, uses a
single-use 180ms marker for the paired opposite browser event even when it lands
on `body`, and calls
`userUpdateTextEditingValue` as a formatter-safe fallback when the engine drops
the DOM update. Focused policy/guard/bootstrap
proof passed 29 tests, `flutter analyze --no-pub` was clean, and
`flutter build web --release --no-pub` (including the Wasm dry run) succeeded.
A local Playwright iPhone-profile smoke on the final release build verified the
first-focus touch/click passed through, a focused native touch kept the same
`.flt-text-editing` transform instead of moving it to `-9999px`, and no browser
default was canceled. Same-pointer up/cancel stayed owned when retargeted;
pointer-cancel kept the null-target blur but did not create a click lease.
`pagehide` released the old pointer, a new primary touch recovered stale owner
state, unrelated/non-primary touches bubbled, and blur/click propagated after
their 220/300ms windows. A paired `paste`/`beforeinput` inserted once, an
immediate new paste with the same clipboard inserted again, and foreign-input
paste was not redirected. On an actual focused Flutter input, neutral
`paste(empty)` followed by data-bearing `beforeinput` inserted exactly once;
the next body paste and an empty/empty/data sequence did not reuse the stale
field. The Flutter Chrome widget runner
still times out before its test-manager handshake, so it remains an environment
gap rather than a passing proof. Physical iOS PWA smoke on staging remains the
final device gate for this follow-up. Intake 74 affected-runtime
run/record/check passed against the narrowed implementation fingerprint for all
four protected consumers: `PAYMENT-STATEMENT-KEYBOARD-001`,
`UI-KEYBOARD-001`, `UI-PASTE-001`, and `UI-UX-001`.

Final local proof on 2026-07-20 additionally held the focused input for 700ms,
verified active and post-pointer owned-touch blur versus ordinary later blur,
verified `beforeinput`-only plus guarded transient-blur replacements, and
covered the single-use 220ms pointer-up/pointer-cancel grace, retargeted
terminal events, 220/300ms expiry, lifecycle/new-primary reset, 10-second target
expiry, empty-to-data pairing and double-empty consumption, and unrelated
`pointerId` rejection. The
full Flutter run reached 574 passed and 3 intentional skips, with one unrelated
existing timing assertion failing in
`OffsetAdjustmentProvider offset realtime max-wait prevents refresh
starvation` (`expected 2`, `actual 3`); an isolated rerun reproduced that same
offset-refresh failure. No paste, input, keyboard, or shared-control regression
failed.

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
