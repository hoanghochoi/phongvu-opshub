# UI-PASTE-001 - Shared paste menu reliability

## Problem

On iOS PWA, Paste first appeared in a Flutter toolbar. Tapping it then opened a
second iOS browser Paste confirmation, so insertion required two separate
actions. The failure affected every runtime input because all editable controls
reuse the same shared menu policy.

## Root cause

- The shared bootstrap disabled `BrowserContextMenu` for every web target.
- On iOS PWA, Flutter therefore rendered its own Paste button and read the web
  clipboard. Safari then required its native Paste confirmation, producing two
  stacked controls and a two-step interaction.
- Existing web tests asserted that Flutter Paste existed, which encoded the
  duplicate-owner behavior instead of rejecting it.

## Accepted behavior

- Native inputs use `SystemContextMenu` when Flutter reports support and fall
  back to `AdaptiveTextSelectionToolbar` otherwise.
- iOS/Android PWA enables the browser context menu. Flutter web then suppresses
  its own editable toolbar and lets the browser DOM input perform Paste in one
  native interaction.
- Desktop web disables the browser context menu and renders one adaptive Flutter
  toolbar.
- `AppGlobalSelectionScope` keeps visible text selectable; shared editable
  controls remain isolated with `SelectionContainer.disabled` so the outer
  selection region cannot compete with input selection.
- All runtime editable fields reuse `AppTextInput`, `AppFormTextInput`, or
  `AppCombobox`; no feature-local paste workaround is allowed.

## Logging

Startup logs record context-menu bootstrap start, resolved platform/mode,
success, skip, and sanitized failure through `AppLogger`.
