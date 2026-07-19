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
- Flutter's mobile-web engine also moves its hidden `.flt-text-editing` input
  to `-9999px` from a target-level click handler for roughly 100ms. During a
  fast second tap, the event can land on the full-screen `SelectionArea`
  platform view, so Safari never gets a stable native input target for its
  callout.
- Even when the input stays in place, Flutter's pointer recognizers can process
  the same double-tap/long-press sequence and overwrite native selection while
  the callout is opening. Flutter 3.44.x also treats a null-target hidden-input
  blur as a closed text connection, so a transient WebKit callout focus change
  can make the following paste intermittent.

## Accepted behavior

- Native inputs use `SystemContextMenu` when Flutter reports support and fall
  back to `AdaptiveTextSelectionToolbar` otherwise.
- iOS/Android PWA enables the browser context menu. Flutter web then suppresses
  its own editable toolbar and lets the browser DOM input perform Paste in one
  native interaction.
- On iOS PWA, the first touch used to focus a field and mouse, keyboard, or
  programmatic clicks continue to Flutter. Only a touch sequence on the
  already-focused DOM input, or a fast repeated touch on that same input, is
  WebKit-owned. Its pointer events use `stopPropagation` but never
  `preventDefault`, leaving WebKit responsible for caret placement, native
  selection, and the callout. Ownership requires the same `pointerId`, so a
  second finger or unrelated touch remains independent. Matching pointer-up and
  pointer-cancel events remain WebKit-owned even if selection handling retargets
  them away from the input.
- Only an exact-input click within the 300ms lease after owned pointer-up is
  stopped before Flutter's transient `-9999px` relocation handler.
  Pointer-cancel never creates a click lease; first-focus clicks and clicks
  without owned-touch correlation still reach Flutter normally.
- A null-target blur is kept away from Flutter's hidden-input listener while
  the exact owned touch is active or during one single-use 220ms grace
  immediately after matching pointer-up or pointer-cancel. The guard still
  requires `relatedTarget` to be null and the document to remain focused and
  visible. An outside pointer, focus on another control, hidden/page lifecycle,
  or a new primary touch clears stale ownership; later and keyboard-dismissal
  blur continue normally.
- The mobile-web bootstrap observes both the browser `paste` event and
  `beforeinput` with `inputType=insertFromPaste` in capture phase. It resolves
  the direct or active `.flt-text-editing` DOM input, replaces the exact DOM
  selection synchronously, and emits one bubbling `input` event for Flutter.
  If the guarded transient blur temporarily moves focus to `body`, it may reuse
  only the exact DOM target retained from that blur, only for a bounded
  10-second lease, and only while it still matches the retained focused
  `EditableTextState`. An empty first browser event retains one 180ms lease only
  for the immediate opposite event carrying text; another empty, same-source,
  late, foreign, focus, or lifecycle event consumes it. The bridge never queries
  an arbitrary node or redirects paste from a foreign input.
- If the engine still drops the DOM update, the retained `EditableTextState`
  receives the same replacement through `userUpdateTextEditingValue`, so input
  formatters and `onChanged` are preserved. A single-use 180ms source-aware
  marker consumes only the paired opposite `paste`/`beforeinput` event, even if
  Safari targets the second event at `body` or a formatter changes the
  intermediate DOM value. The recovery never reads the clipboard outside the
  browser paste gesture and never renders a second menu.
- Desktop web disables the browser context menu and renders one adaptive Flutter
  toolbar.
- `AppGlobalSelectionScope` keeps visible text selectable; shared editable
  controls remain isolated with `SelectionContainer.disabled` so the outer
  selection region cannot compete with input selection.
- All runtime editable fields reuse `AppTextInput`, `AppFormTextInput`, or
  `AppCombobox`; no feature-local paste workaround is allowed.

## Logging

Startup logs record context-menu bootstrap start, resolved platform/mode,
success, skip, and sanitized failure through `AppLogger`. Mobile-web text-input
events record the owned-touch click guard, source (`paste`/`beforeinput`),
touch ownership and lifecycle reset, guarded transient callout blur/expiry,
field/selection/text lengths, duplicate suppression, fallback, and sanitized
errors through `AppLogger`; no clipboard contents are logged.
