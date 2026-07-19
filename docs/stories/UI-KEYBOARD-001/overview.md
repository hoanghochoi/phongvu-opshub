# UI-KEYBOARD-001

## Goal

Audit every Flutter presentation file that owns a text input and keep focused
mobile inputs inside the visible app viewport when the software keyboard opens.
The change must preserve desktop layouts, camera behavior, modal presentation,
and existing feature data flows.

## Audit Scope

The source audit covered 31 input-owning presentation files and their shared
shells. They fall into these runtime patterns:

| Pattern | Screen families | Verdict |
| --- | --- | --- |
| Full-page scroll | Auth, Feedback, Warranty, VietQR, Sales Report, Not Purchased, Help, Profile, Notifications | Safe through `AuthFormPanel` or `AppResponsiveScrollView`; representative mobile-keyboard tests cover Auth and the shared responsive behavior. |
| Fixed command header plus shrinking result list | FIFO, Sort, Check Warranty, user/policy/organization/feature admin | Safe: the input stays in the resized header while the result region owns the flexible height. |
| Scrollable dialog or bottom sheet | Profile password, finance/admin editors, notification and Sales Report sheets | Safe through `SingleChildScrollView`/`ListView` and, where needed, explicit `viewInsets.bottom`. |
| Camera overlay | Barcode scanner with a supported camera | Safe: the bottom input panel follows the resized `Scaffold` body; covered by a keyboard-inset widget test. |
| Tall fixed filter/header | Bank Statement | Risk found and fixed with one compact `CustomScrollView` plus focused-field visibility handling. |
| Unsupported-camera fallback | Barcode scanner manual fallback | Risk found and fixed by replacing fixed responsive content with `AppResponsiveScrollView`. |

Shared leaf inputs such as `AppFormTextInput`, `AppSearchInput`, combobox search,
and the embedded FIFO command input do not own viewport geometry. Their parent
screen or modal is therefore the keyboard-avoidance boundary audited above.

## Accepted Behavior

- Opening a mobile software keyboard produces no flex overflow on the two
  previously risky layouts.
- The focused Bank Statement filter and manual barcode field remain above the
  keyboard and can be reached by scrolling.
- Dragging the new mobile scroll surfaces dismisses the keyboard.
- The supported-camera barcode panel moves with the resized body.
- Desktop Bank Statement keeps its fixed filter header and independent result
  list; supported-camera behavior and feature business logic remain unchanged.
- Keyboard-avoidance logs contain only field identifiers, viewport inset, and
  duration. User-entered filter values are never logged.
- The app follows its active light/dark keyboard appearance. A third-party iOS
  keyboard extension owns its own colors and transparency.

## Changed Runtime Paths

- `lib/features/bank_statement/presentation/screens/bank_statement_screen.dart`
- `lib/features/fifo_check/presentation/widgets/barcode_scanner_screen.dart`

Existing income-type work in the Bank Statement feature was present at the
checkpoint and is explicitly outside this story and commit.
