# UI-PASTE-001 - Shared paste menu reliability

## Problem

On iOS, staff could focus inputs and open the software keyboard, but tap,
double tap, and long press did not expose Paste. The failure affected every
runtime input because all editable controls reuse the same shared menu policy.

## Root cause

- Native and desktop modes passed an explicit null `contextMenuBuilder`, which
  disables the `TextField` default context menu.
- Mobile web/PWA returned an empty Flutter menu and enabled the browser menu.
  That browser menu did not reliably attach to Flutter's rendered editable.
- Existing tests asserted which owner was selected but did not execute Paste
  and verify that clipboard text reached the controller.

## Accepted behavior

- Native inputs use `SystemContextMenu` when Flutter reports support and fall
  back to `AdaptiveTextSelectionToolbar` otherwise.
- Every web target disables the browser context menu and renders one adaptive
  Flutter toolbar.
- `AppGlobalSelectionScope` keeps visible text selectable; shared editable
  controls remain isolated with `SelectionContainer.disabled` so the outer
  selection region cannot compete with input selection.
- All runtime editable fields reuse `AppTextInput`, `AppFormTextInput`, or
  `AppCombobox`; no feature-local paste workaround is allowed.

## Logging

Startup logs record context-menu bootstrap start, resolved platform/mode,
success, skip, and sanitized failure through `AppLogger`.
