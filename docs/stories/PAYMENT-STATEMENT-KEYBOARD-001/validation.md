# PAYMENT-STATEMENT-KEYBOARD-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Focused Flutter | `flutter test --no-pub --reporter expanded test/bank_statement_keyboard_test.dart` |
| Existing consumers | Focused bank-statement screen and app-shell viewport widget tests |
| Static analysis | `flutter analyze --no-pub` |
| Formatting | `dart format --output=none --set-exit-if-changed` for changed Dart files |
| Release boundary | `git diff --check`, Harness affected-runtime record/check, exact staged diff review |

## Evidence

- Before the source fix, the keyboard regression test reproduced a mobile
  `RenderFlex overflowed by 132 pixels on the bottom` when a 360 px software
  keyboard inset opened over the expanded statement filters.
- After the source fix, the same focused test passes. It verifies that the
  `Nội dung chuyển khoản` field remains inside the visible mobile scroll
  viewport, no rendering exception occurs, and drag-to-dismiss is enabled.

## Unverified Risk

- A real-device iOS/Android keyboard click-through remains manual.
- Laban Key's key colors/transparency are controlled by its iOS keyboard
  extension and cannot be verified or restyled by a Flutter widget test.
