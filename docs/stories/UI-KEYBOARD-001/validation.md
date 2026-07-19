# UI-KEYBOARD-001 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Reproduction and fixes | Bank Statement and barcode fallback tests use compact mobile viewports plus non-zero software-keyboard insets. |
| Representative safe consumers | Registration last field and supported-camera barcode input are tested with the keyboard open. |
| Existing feature consumers | Bank Statement mobile filter behavior, barcode scanner suite, Auth pre-shell suite, and app-shell viewport tests. |
| Static regression | `flutter analyze --no-pub` and the relevant focused Flutter tests. |
| Release boundary | `git diff --check`, Harness affected-runtime record/check, and exact staged-diff review before the local commit. |

## Reproduction Evidence

- Before the source fix, the Bank Statement test produced a
  `RenderFlex overflowed by 132 pixels on the bottom` with the expanded compact
  filters and a 360 px keyboard inset.
- Before the source fix, the unsupported-camera barcode fallback produced a
  `RenderFlex overflowed by 36 pixels on the bottom` with a 260 px keyboard
  inset.
- The supported-camera and registration cases are regression sentinels for
  layouts that were already structurally safe.

## Automated Assertions

- No rendering exception occurs after the keyboard inset changes.
- The focused input rectangle stays inside the visible scroll/body rectangle.
- The Bank Statement and barcode fallback scrollables use drag-to-dismiss.
- Wide Bank Statement behavior remains on the existing header-plus-list path.

## Fresh Evidence

- `flutter analyze --no-pub`: passed with no issues.
- The 13-file keyboard and representative-screen bundle passed 68 tests. It
  covered Bank Statement, both barcode modes, registration, Profile, Feedback,
  Warranty, VietQR, Not Purchased, Offset Adjustment, FIFO, Sort, Help, and the
  mobile/desktop app shell.
- Three focused existing Bank Statement consumers passed: content workspace,
  compact filter collapse after search, and transaction editor identity after
  list reorder.
- Full `flutter test --no-pub --reporter compact` passed 569 tests with 3
  platform skips. The income-type row-message test now also advances through
  the intended 3-second display window and verifies that the message clears.

## Manual Risk

- Final keyboard animation, predictive-text height changes, and third-party
  keyboard appearance still need a physical iOS/Android smoke test.
- Flutter cannot restyle the key surface of a separately installed iOS keyboard
  extension such as Laban Key.
