# OPS-10 Validation

## Required Proof

| Layer | Proof |
| --- | --- |
| Baseline reproduction | Design System migration guard fails at the three accepted violation groups before the fix. |
| Modal behavior | Sales Report widget flow marks a selected file dirty, intercepts outside dismissal, keeps the editor after `Tiếp tục chỉnh sửa`, and still completes import normally. |
| Shared UI contracts | Dialog contract and Design System migration guard suites pass without changing the guard source. |
| Existing consumers | Full Flutter suite and analyzer pass after the focused proof. |
| Fingerprint boundary | `git diff --check` plus Harness intake 87 affected-runtime `run/record/check --strict`. |

## Automated Assertions

- The selected Excel filename remains visible after canceling the discard
  confirmation.
- Preview, commit, successful close and list reload retain their existing
  behavior.
- The showroom filter still sends the selected `storeCode`.
- Feature code has no locked dialog dismissal, raw feature `Button`/`Card`, or
  visible `SR` abbreviation covered by the global guard.

## Fresh Local Evidence

- Focused Design System, dialog contract and Sales Report bundle: 35 tests
  passed.
- `flutter analyze --no-pub`: passed with no issues.
- Full `flutter test --no-pub --reporter compact`: 591 tests passed with 3
  intentional platform skips.
- Harness intake 87 is the canonical fingerprinted completion record for this
  changeset.

## Remaining Runtime Risk

- Automated widget proof covers the modal state transitions and existing
  responsive layout. A physical mobile/desktop visual smoke remains useful
  after the change reaches staging, but it is not required to prove the three
  static baseline violations.
