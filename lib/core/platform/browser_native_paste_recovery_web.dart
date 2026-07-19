import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../logging/app_logger.dart';
import 'browser_native_paste_recovery_policy.dart';

const _flutterTextEditingClass = 'flt-text-editing';
const _pasteDedupeWindow = Duration(milliseconds: 180);
const _repeatedTapWindow = Duration(milliseconds: 550);
const _ownedClickWindow = Duration(milliseconds: 300);
const _completedTouchBlurWindow = Duration(milliseconds: 220);
const _transientCalloutRetentionWindow = Duration(seconds: 10);

bool _initialized = false;
bool _preserveRepeatedTapTarget = false;
bool _clickListenerInstalled = false;
bool _iosGestureListenersInstalled = false;
late final JSFunction _pasteListener;
late final JSFunction _beforeInputListener;
late final JSFunction _focusInListener;
late final JSFunction _editableClickListener;
late final JSFunction _editablePointerDownListener;
late final JSFunction _editablePointerMoveListener;
late final JSFunction _editablePointerUpListener;
late final JSFunction _editablePointerCancelListener;
late final JSFunction _editableBlurListener;
late final JSFunction _visibilityChangeListener;
late final JSFunction _pageHideListener;

// Flutter Web renders the actual editable DOM node separately from the
// painted TextField. Safari can temporarily move focus away from that node
// while the native callout is open, so keep the last valid node as a fallback.
web.HTMLElement? _lastEditableElement;
EditableTextState? _lastFocusedEditable;
_HandledPaste? _lastHandledPaste;
_PendingEmptyPaste? _pendingEmptyPaste;
web.HTMLElement? _lastPointerTarget;
DateTime? _lastPointerDownAt;
bool _suppressPointerSequence = false;
int? _ownedPointerId;
web.HTMLElement? _ownedPointerTarget;
web.HTMLElement? _pendingOwnedClickTarget;
DateTime? _pendingOwnedClickAt;
web.HTMLElement? _recentOwnedTouchTarget;
DateTime? _recentOwnedTouchAt;
web.HTMLElement? _transientCalloutTarget;
DateTime? _transientCalloutAt;

Future<void> initializeBrowserNativePasteRecovery({
  bool preserveRepeatedTapTarget = false,
}) async {
  final shouldInstallIosGestureListeners =
      preserveRepeatedTapTarget && !_preserveRepeatedTapTarget;
  _preserveRepeatedTapTarget =
      _preserveRepeatedTapTarget || preserveRepeatedTapTarget;
  if (_initialized) {
    if (shouldInstallIosGestureListeners || preserveRepeatedTapTarget) {
      _installIosGestureListeners();
    }
    return;
  }
  _initialized = true;

  _pasteListener = ((web.ClipboardEvent event) {
    _handlePasteEvent(event);
  }).toJS;
  _beforeInputListener = ((web.InputEvent event) {
    _handleBeforeInputEvent(event);
  }).toJS;
  _focusInListener = ((web.Event event) {
    _rememberEditableDomTarget(event.target);
  }).toJS;
  _editableClickListener = ((web.Event event) {
    _keepEditableClickOnBrowserInput(event);
  }).toJS;
  _editablePointerDownListener = ((web.Event event) {
    _handleEditablePointerDown(event);
  }).toJS;
  _editablePointerMoveListener = ((web.Event event) {
    _handleEditablePointerMove(event);
  }).toJS;
  _editablePointerUpListener = ((web.Event event) {
    _handleEditablePointerUp(event);
  }).toJS;
  _editablePointerCancelListener = ((web.Event event) {
    _handleEditablePointerCancel(event);
  }).toJS;
  _editableBlurListener = ((web.FocusEvent event) {
    _keepNativeEditableConnectionOnTransientBlur(event);
  }).toJS;
  _visibilityChangeListener = ((web.Event _) {
    _handleDocumentVisibilityChange();
  }).toJS;
  _pageHideListener = ((web.Event _) {
    _resetNativePasteInteraction(reason: 'pageHide');
  }).toJS;

  final capture = web.EventListenerOptions(capture: true);
  web.document.addEventListener('paste', _pasteListener, capture);
  web.document.addEventListener('beforeinput', _beforeInputListener, capture);
  web.document.addEventListener('focusin', _focusInListener, capture);
  if (_preserveRepeatedTapTarget) {
    _installIosGestureListeners();
  }
  FocusManager.instance.addListener(_rememberFocusedEditable);

  await AppLogger.instance.info(
    'TextInput',
    'Browser-native paste bridge initialized',
    context: {
      'listenerPhase': 'capture',
      'targetClass': _flutterTextEditingClass,
      'handlesBeforeInput': true,
      'keepsTransientCalloutTarget': true,
      'preservesRepeatedTapTarget': _preserveRepeatedTapTarget,
      'keepsOwnedIosClicksOnDomInput': _preserveRepeatedTapTarget,
      'ownsFocusedIosTouchGestures': _preserveRepeatedTapTarget,
      'protectsActiveIosCalloutBlur': _preserveRepeatedTapTarget,
    },
  );
}

void _installIosGestureListeners() {
  final capture = web.EventListenerOptions(capture: true);
  if (!_clickListenerInstalled) {
    // Flutter's iOS web engine moves the hidden input to -9999px from its
    // target-level click handler. Only a click paired with an owned native
    // touch is stopped; the first tap used to focus/open the keyboard, mouse,
    // keyboard and programmatic clicks still reach the engine normally.
    web.document.addEventListener('click', _editableClickListener, capture);
    _clickListenerInstalled = true;
  }
  if (_iosGestureListenersInstalled) return;

  // Once an editable DOM node already owns focus, let WebKit own touch
  // selection. Flutter's RenderEditable recognizers otherwise compete with
  // the native long-press/double-tap callout. Mouse, pen and the first touch
  // used to focus a field continue to Flutter. stopPropagation deliberately
  // leaves the browser default action intact (caret movement and callout).
  web.document.addEventListener(
    'pointerdown',
    _editablePointerDownListener,
    capture,
  );
  web.document.addEventListener(
    'pointermove',
    _editablePointerMoveListener,
    capture,
  );
  web.document.addEventListener(
    'pointerup',
    _editablePointerUpListener,
    capture,
  );
  web.document.addEventListener(
    'pointercancel',
    _editablePointerCancelListener,
    capture,
  );
  web.document.addEventListener('blur', _editableBlurListener, capture);
  web.document.addEventListener(
    'visibilitychange',
    _visibilityChangeListener,
    capture,
  );
  web.window.addEventListener('pagehide', _pageHideListener, capture);
  _iosGestureListenersInstalled = true;
}

void _handlePasteEvent(web.ClipboardEvent event) {
  final pastedText = _readPlainText(event.clipboardData);
  final target = _resolveEditableTarget(event.target);
  _handlePasteGesture(
    event,
    target: target,
    pastedText: pastedText,
    source: 'paste',
  );
}

void _handleBeforeInputEvent(web.InputEvent event) {
  if (event.inputType != 'insertFromPaste') return;

  final target = _resolveEditableTarget(event.target);
  final eventData = event.data;
  final pastedText = eventData != null && eventData.isNotEmpty
      ? eventData
      : _readPlainText(event.dataTransfer);
  _handlePasteGesture(
    event,
    target: target,
    pastedText: pastedText,
    source: 'beforeinput',
  );
}

void _handlePasteGesture(
  web.Event event, {
  required _DomEditableTarget? target,
  required String pastedText,
  required String source,
}) {
  if (pastedText.isEmpty) {
    final existingEmptyPaste = _pendingEmptyPaste;
    if (existingEmptyPaste != null) {
      // A second empty event has no payload to recover and must not refresh the
      // lease. Consume it so a later unrelated event cannot reuse this field.
      _clearTransientCalloutTarget(existingEmptyPaste.element);
      _lastHandledPaste = null;
      unawaited(
        AppLogger.instance.info(
          'TextInput',
          'Browser empty paste pair consumed without retaining a target',
          context: {'source': source},
        ),
      );
      return;
    }
    final transientTarget = _transientCalloutTarget;
    final retainsTargetForPairedEvent =
        _isNeutralPasteTarget(event.target) &&
        target != null &&
        transientTarget != null &&
        _sameDomElement(target.element, transientTarget);
    if (retainsTargetForPairedEvent) {
      // Some iOS builds expose no clipboardData on `paste` but provide the
      // actual text on the immediately paired `beforeinput` (or vice versa).
      // Keep exactly one short opposite-source lease; a same-source or late
      // event invalidates the target before it can be reused.
      _pendingEmptyPaste = _PendingEmptyPaste(
        element: transientTarget,
        source: source,
        receivedAt: DateTime.now(),
      );
    } else {
      _clearTransientCalloutTarget(transientTarget);
    }
    _lastHandledPaste = null;
    unawaited(
      AppLogger.instance.info(
        'TextInput',
        'Browser paste event contained no plain text',
        context: {
          'source': source,
          'hasDomTarget': target != null,
          'retainedForPairedEvent': retainsTargetForPairedEvent,
        },
      ),
    );
    return;
  }

  final pendingEmptyPaste = _pendingEmptyPaste;
  if (pendingEmptyPaste != null) {
    final pendingAge = DateTime.now().difference(pendingEmptyPaste.receivedAt);
    final isImmediateOppositePair =
        _isNeutralPasteTarget(event.target) &&
        target != null &&
        _sameDomElement(target.element, pendingEmptyPaste.element) &&
        pendingEmptyPaste.source != source &&
        !pendingAge.isNegative &&
        pendingAge <= _pasteDedupeWindow;
    _pendingEmptyPaste = null;
    if (!isImmediateOppositePair) {
      _clearTransientCalloutTarget(pendingEmptyPaste.element);
      if (target != null &&
          _sameDomElement(target.element, pendingEmptyPaste.element) &&
          _isNeutralPasteTarget(event.target)) {
        target = null;
      }
    }
  }

  if (target != null) {
    if (_takeDuplicatePaste(target, pastedText, source)) {
      // A few iOS versions emit both `paste` and `beforeinput` for one native
      // action. Consume the second event so the value is never inserted twice.
      event.preventDefault();
      event.stopImmediatePropagation();
      unawaited(
        AppLogger.instance.info(
          'TextInput',
          'Browser paste duplicate event ignored',
          context: {
            'source': source,
            'fieldTextLength': target.value.length,
            'pastedTextLength': pastedText.length,
          },
        ),
      );
      return;
    }

    final replacement = _replacementFor(target, pastedText);
    if (replacement == null) {
      final frameworkBefore = _lastFocusedEditableValue();
      if (frameworkBefore != null && frameworkBefore.text == target.value) {
        _applyFrameworkFallback(
          event,
          before: frameworkBefore,
          pastedText: pastedText,
          source: source,
          element: target.element,
        );
      }
      unawaited(
        AppLogger.instance.warn(
          'TextInput',
          'Browser paste bridge skipped because DOM selection was invalid',
          context: {
            'source': source,
            'fieldTextLength': target.value.length,
            'selectionStart': target.selectionStart,
            'selectionEnd': target.selectionEnd,
            'pastedTextLength': pastedText.length,
          },
        ),
      );
      _clearTransientCalloutTarget(target.element);
      return;
    }

    final frameworkBefore = _frameworkValueIfAligned(target);
    try {
      // Apply synchronously while this capture handler still owns the event.
      // Consume the browser/engine default only after the DOM update succeeds;
      // if the DOM operation throws, the safe EditableText fallback below can
      // still handle the original event.
      _applyReplacement(target, replacement);
      event.preventDefault();
      if (source == 'beforeinput') {
        // Flutter's engine has its own beforeinput listener on the hidden
        // element. Do not let it infer a second delta for our replacement.
        event.stopImmediatePropagation();
      }
      _lastHandledPaste = _HandledPaste(
        element: target.element,
        pastedText: pastedText,
        source: source,
        handledAt: DateTime.now(),
      );
      _clearTransientCalloutTarget(target.element);

      // Normally the synthetic input above synchronously reaches Flutter's
      // EditableText. If an iOS engine build drops that input while its focus
      // is moving, this state-level fallback still uses Flutter's formatter
      // and onChanged pipeline instead of assigning the controller directly.
      if (frameworkBefore != null) {
        _scheduleFrameworkFallback(
          before: frameworkBefore,
          pastedText: pastedText,
        );
      }

      unawaited(
        AppLogger.instance.info(
          'TextInput',
          'Browser paste bridge applied synchronously to Flutter DOM input',
          context: {
            'source': source,
            'fieldTextLength': replacement.text.length,
            'selectionOffset': replacement.selectionOffset,
            'pastedTextLength': pastedText.length,
            'trustedEvent': event.isTrusted,
          },
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'TextInput',
          'Browser paste bridge failed before framework input update',
          error: error,
          stackTrace: stackTrace,
          context: {
            'source': source,
            'fieldTextLength': target.value.length,
            'pastedTextLength': pastedText.length,
          },
        ),
      );
      _applyFrameworkFallback(
        event,
        before: frameworkBefore,
        pastedText: pastedText,
        source: source,
        element: target.element,
      );
      _clearTransientCalloutTarget(target.element);
    }
    return;
  }

  // If Safari sends the clipboard event after it has already blurred the
  // hidden DOM input, use the last focused EditableText. This branch is
  // synchronous and formatter-safe, and does not depend on a short timer.
  if (_isNeutralPasteTarget(event.target)) {
    final handledElement = _lastHandledPaste?.element;
    if (handledElement != null &&
        _takeDuplicatePasteMarker(handledElement, pastedText, source)) {
      _consumeDuplicatePasteEvent(event, pastedText, source);
      _clearTransientCalloutTarget(_transientCalloutTarget);
      return;
    }
  }
  if (!_isSafeFrameworkFallbackContext(event.target)) return;
  final transientTarget = _transientCalloutTarget;
  if (_takeDuplicatePasteMarker(transientTarget, pastedText, source)) {
    _consumeDuplicatePasteEvent(event, pastedText, source);
    _clearTransientCalloutTarget(transientTarget);
    return;
  }
  _applyFrameworkFallback(
    event,
    before: _lastFocusedEditableValue(),
    pastedText: pastedText,
    source: source,
    element: transientTarget,
  );
  _clearTransientCalloutTarget(transientTarget);
}

bool _isSafeFrameworkFallbackContext(web.EventTarget? candidate) {
  if (!_isNeutralPasteTarget(candidate)) return false;
  final focusedState = FocusManager.instance.primaryFocus?.context
      ?.findAncestorStateOfType<EditableTextState>();
  final retainedState = _lastFocusedEditable;
  if (retainedState == null ||
      !retainedState.mounted ||
      focusedState != retainedState) {
    return false;
  }
  final activeElement = web.document.activeElement;
  if (activeElement != null && activeElement != web.document.body) return false;
  final transientTarget = _transientCalloutTarget;
  final transientAt = _transientCalloutAt;
  if (transientTarget == null || transientAt == null) return false;
  final transientAge = DateTime.now().difference(transientAt);
  if (transientAge.isNegative ||
      transientAge > _transientCalloutRetentionWindow) {
    _clearTransientCalloutTarget(transientTarget);
    unawaited(
      AppLogger.instance.info(
        'TextInput',
        'Expired iOS native callout paste target discarded',
        context: {
          'retentionMs': _transientCalloutRetentionWindow.inMilliseconds,
        },
      ),
    );
    return false;
  }
  return web.document.hasFocus() &&
      transientTarget.isConnected &&
      _sameDomElement(transientTarget, _lastEditableElement);
}

void _applyFrameworkFallback(
  web.Event event, {
  required TextEditingValue? before,
  required String pastedText,
  required String source,
  required web.HTMLElement? element,
}) {
  final state = _lastFocusedEditable;
  if (state == null || !state.mounted || before == null) {
    unawaited(
      AppLogger.instance.info(
        'TextInput',
        'Browser paste event ignored because no editable target was retained',
        context: {'pastedTextLength': pastedText.length},
      ),
    );
    return;
  }

  final nextValue = recoverBrowserPasteValue(
    before: before,
    pastedText: pastedText,
  );
  if (nextValue == null) {
    unawaited(
      AppLogger.instance.warn(
        'TextInput',
        'Browser paste fallback skipped invalid framework selection',
        context: {
          'selectionStart': before.selection.start,
          'selectionEnd': before.selection.end,
          'pastedTextLength': pastedText.length,
        },
      ),
    );
    return;
  }

  try {
    state.userUpdateTextEditingValue(nextValue, SelectionChangedCause.toolbar);
    event.preventDefault();
    event.stopImmediatePropagation();
    _lastHandledPaste = _HandledPaste(
      element: element,
      pastedText: pastedText,
      source: source,
      handledAt: DateTime.now(),
    );
    unawaited(
      AppLogger.instance.warn(
        'TextInput',
        'Browser paste fallback applied through EditableText',
        context: {
          'beforeTextLength': before.text.length,
          'afterTextLength': nextValue.text.length,
          'pastedTextLength': pastedText.length,
        },
      ),
    );
  } catch (error, stackTrace) {
    unawaited(
      AppLogger.instance.error(
        'TextInput',
        'Browser paste fallback failed',
        error: error,
        stackTrace: stackTrace,
        context: {'pastedTextLength': pastedText.length},
      ),
    );
  }
}

void _scheduleFrameworkFallback({
  required TextEditingValue before,
  required String pastedText,
}) {
  final state = _lastFocusedEditable;
  if (state == null || !state.mounted) return;

  scheduleMicrotask(() {
    if (!state.mounted || state.textEditingValue != before) return;
    final nextValue = recoverBrowserPasteValue(
      before: before,
      pastedText: pastedText,
    );
    if (nextValue == null) return;
    try {
      state.userUpdateTextEditingValue(
        nextValue,
        SelectionChangedCause.toolbar,
      );
      unawaited(
        AppLogger.instance.warn(
          'TextInput',
          'Browser paste fallback applied after DOM input was not reflected',
          context: {
            'beforeTextLength': before.text.length,
            'afterTextLength': nextValue.text.length,
            'pastedTextLength': pastedText.length,
          },
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'TextInput',
          'Browser paste delayed fallback failed',
          error: error,
          stackTrace: stackTrace,
          context: {'pastedTextLength': pastedText.length},
        ),
      );
    }
  });
}

String _readPlainText(web.DataTransfer? dataTransfer) {
  if (dataTransfer == null) return '';
  try {
    final plainText = dataTransfer.getData('text/plain');
    if (plainText.isNotEmpty) return plainText;
    return dataTransfer.getData('text');
  } catch (error, stackTrace) {
    // Some WebKit builds expose DataTransfer but deny getData while focus is
    // transitioning. Leave the event untouched so the browser can still use
    // its native default path instead of turning that denial into a lost paste.
    unawaited(
      AppLogger.instance.error(
        'TextInput',
        'Browser paste payload could not be read; keeping native default',
        error: error,
        stackTrace: stackTrace,
        context: {'hasDataTransfer': true},
      ),
    );
    return '';
  }
}

TextEditingValue? _frameworkValueIfAligned(_DomEditableTarget target) {
  final value = _lastFocusedEditableValue();
  if (value == null || value.text != target.value) return null;
  final selectionStart = target.selectionStart;
  final selectionEnd = target.selectionEnd;
  if (selectionStart == null || selectionEnd == null) return value;
  return value.copyWith(
    selection: TextSelection(
      baseOffset: selectionStart,
      extentOffset: selectionEnd,
    ),
  );
}

TextEditingValue? _lastFocusedEditableValue() {
  final state = _lastFocusedEditable;
  if (state == null || !state.mounted) return null;
  return state.textEditingValue;
}

void _rememberFocusedEditable() {
  final editableState = FocusManager.instance.primaryFocus?.context
      ?.findAncestorStateOfType<EditableTextState>();
  if (editableState != null && editableState.mounted) {
    _lastFocusedEditable = editableState;
    return;
  }
  _lastFocusedEditable = null;
  _clearNativeGestureCorrelation(clearTapHistory: true);
  _lastHandledPaste = null;
}

void _rememberEditableDomTarget(web.EventTarget? candidate) {
  final target = _editableElement(candidate);
  if (target != null) {
    if (!_sameDomElement(_lastEditableElement, target)) {
      _clearNativeGestureCorrelation(clearTapHistory: true);
      _clearTransientCalloutTarget(null);
      _lastHandledPaste = null;
    }
    _lastEditableElement = target;
    return;
  }
  if (candidate != null && candidate.isA<web.HTMLElement>()) {
    if (candidate == web.document.body) return;
    _clearNativeGestureCorrelation(clearTapHistory: true);
    _lastEditableElement = null;
    _clearTransientCalloutTarget(null);
    _lastHandledPaste = null;
  }
}

void _keepEditableClickOnBrowserInput(web.Event event) {
  final pendingTarget = _pendingOwnedClickTarget;
  final pendingAt = _pendingOwnedClickAt;
  _pendingOwnedClickTarget = null;
  _pendingOwnedClickAt = null;
  final target = _editableElement(event.target);
  if (target == null) return;
  final ownsClick =
      _sameDomElement(target, pendingTarget) &&
      pendingAt != null &&
      DateTime.now().difference(pendingAt) <= _ownedClickWindow;
  if (!ownsClick) return;

  event.stopPropagation();
  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'Owned iOS touch click kept on native text input',
      context: {
        'targetClass': _flutterTextEditingClass,
        'defaultPrevented': event.defaultPrevented,
      },
    ),
  );
}

void _handleEditablePointerDown(web.Event event) {
  if (!event.isA<web.PointerEvent>() ||
      (event as web.PointerEvent).pointerType != 'touch') {
    // The iOS bridge owns touch only. A mouse/pen session is independent and
    // also proves any touch owner left behind without a terminal event is stale.
    _clearNativeGestureCorrelation(clearTapHistory: true);
    return;
  }
  final pointerEvent = event;
  final currentOwnedPointerId = _ownedPointerId;
  if (_suppressPointerSequence &&
      currentOwnedPointerId != null &&
      currentOwnedPointerId != pointerEvent.pointerId) {
    // A second finger must remain independent from the native selection touch.
    if (!pointerEvent.isPrimary) return;

    // WebKit can omit pointerup/cancel when a PWA backgrounds or the hidden
    // input is retargeted. A new primary touch proves the old owner is stale;
    // release it before classifying this new session.
    _clearNativeGestureCorrelation(clearTapHistory: true);
    unawaited(
      AppLogger.instance.warn(
        'TextInput',
        'Stale iOS native touch ownership reset by a new primary pointer',
        context: {'pointerType': pointerEvent.pointerType},
      ),
    );
  }
  if (!pointerEvent.isPrimary) return;
  final target = _editableElement(event.target);
  if (target == null) {
    _clearNativeGestureCorrelation(clearTapHistory: true);
    return;
  }

  final now = DateTime.now();
  final previousTarget = _lastPointerTarget;
  final previousAt = _lastPointerDownAt;
  final repeatedTarget =
      _sameDomElement(previousTarget, target) &&
      previousAt != null &&
      now.difference(previousAt) <= _repeatedTapWindow;
  final activeElement = web.document.activeElement;
  final focusedTarget =
      activeElement != null && target.isSameNode(activeElement);
  final ownsNativeGesture = focusedTarget || repeatedTarget;

  _lastPointerTarget = target;
  _lastPointerDownAt = now;
  _suppressPointerSequence = ownsNativeGesture;
  _ownedPointerId = ownsNativeGesture ? pointerEvent.pointerId : null;
  _ownedPointerTarget = ownsNativeGesture ? target : null;
  _pendingOwnedClickTarget = null;
  _pendingOwnedClickAt = null;
  _recentOwnedTouchTarget = null;
  _recentOwnedTouchAt = null;
  _clearTransientCalloutTarget(null);
  if (!ownsNativeGesture) return;

  event.stopPropagation();
  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'iOS native editable gesture kept outside Flutter recognizers',
      context: {
        'targetClass': _flutterTextEditingClass,
        'reason': focusedTarget ? 'focusedDomTarget' : 'repeatedTap',
      },
    ),
  );
}

void _handleEditablePointerMove(web.Event event) {
  if (_matchesOwnedPointer(event)) event.stopImmediatePropagation();
}

void _handleEditablePointerUp(web.Event event) {
  if (!_matchesOwnedPointer(event)) return;
  final ownedTarget = _ownedPointerTarget;
  event.stopImmediatePropagation();
  final now = DateTime.now();
  if (ownedTarget != null) {
    // Keep the short blur grace even when WebKit retargets pointerup to a
    // selection handle or ancestor. Flutter must never receive a terminal
    // event for an owned pointerdown it did not receive.
    _recentOwnedTouchTarget = ownedTarget;
    _recentOwnedTouchAt = now;
    // A retargeted pointerup can still be followed by the engine's click on
    // the hidden input. The later click must match this exact target and the
    // 300ms lease; any new pointerdown clears the lease first.
    _pendingOwnedClickTarget = ownedTarget;
    _pendingOwnedClickAt = now;
  }
  _resetPointerSequence();
}

void _handleEditablePointerCancel(web.Event event) {
  if (!_matchesOwnedPointer(event)) return;
  // The owned pointerdown never reached Flutter, so its cancel must not reach
  // Flutter either, even if WebKit retargeted the terminal event.
  event.stopImmediatePropagation();
  final ownedTarget = _ownedPointerTarget;
  if (ownedTarget != null) {
    // Native long-press commonly hands control to WebKit with pointercancel.
    // Keep the same short blur grace as pointerup, but never correlate a click.
    _recentOwnedTouchTarget = ownedTarget;
    _recentOwnedTouchAt = DateTime.now();
  }
  _pendingOwnedClickTarget = null;
  _pendingOwnedClickAt = null;
  _resetPointerSequence();
}

void _resetPointerSequence() {
  _suppressPointerSequence = false;
  _ownedPointerId = null;
  _ownedPointerTarget = null;
}

bool _matchesOwnedPointer(web.Event event) {
  if (!_suppressPointerSequence || !event.isA<web.PointerEvent>()) return false;
  final pointerEvent = event as web.PointerEvent;
  return pointerEvent.pointerType == 'touch' &&
      pointerEvent.pointerId == _ownedPointerId;
}

void _clearNativeGestureCorrelation({required bool clearTapHistory}) {
  _resetPointerSequence();
  _pendingOwnedClickTarget = null;
  _pendingOwnedClickAt = null;
  _recentOwnedTouchTarget = null;
  _recentOwnedTouchAt = null;
  _clearTransientCalloutTarget(null);
  if (clearTapHistory) {
    _lastPointerTarget = null;
    _lastPointerDownAt = null;
  }
}

void _keepNativeEditableConnectionOnTransientBlur(web.FocusEvent event) {
  final target = _editableElement(event.target);
  if (target == null) return;
  final now = DateTime.now();
  final recentOwnedTouchAt = _recentOwnedTouchAt;
  final ownsActiveTouch =
      _suppressPointerSequence && _sameDomElement(target, _ownedPointerTarget);
  final followsCompletedOwnedTouch =
      _sameDomElement(target, _recentOwnedTouchTarget) &&
      recentOwnedTouchAt != null &&
      now.difference(recentOwnedTouchAt) <= _completedTouchBlurWindow;
  final documentRetainsFocus =
      web.document.hasFocus() && web.document.visibilityState == 'visible';
  final protectsNativeCallout =
      event.relatedTarget == null &&
      documentRetainsFocus &&
      (ownsActiveTouch || followsCompletedOwnedTouch);
  if (!protectsNativeCallout) {
    _recentOwnedTouchTarget = null;
    _recentOwnedTouchAt = null;
    _clearTransientCalloutTarget(target);
    return;
  }

  // A WebKit selection/callout transition can blur the hidden input with no
  // related target even though the user is still editing it. Flutter 3.44.x
  // interprets that blur as a closed text connection. Keep the engine listener
  // from seeing only a blur delivered during, or immediately after, the exact
  // owned touch while this visible document retains focus. The completion
  // marker is consumed here. Window/app changes, keyboard dismissal after an
  // outside touch, field changes and later blurs continue to Flutter normally.
  event.stopPropagation();
  _transientCalloutTarget = target;
  _transientCalloutAt = now;
  _recentOwnedTouchTarget = null;
  _recentOwnedTouchAt = null;
  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'Transient iOS native callout blur kept outside Flutter engine',
      context: {
        'targetClass': _flutterTextEditingClass,
        'pointerSequenceActive': ownsActiveTouch,
        'afterPointerUp': followsCompletedOwnedTouch,
        'documentFocused': documentRetainsFocus,
      },
    ),
  );
}

void _handleDocumentVisibilityChange() {
  if (web.document.visibilityState == 'visible') return;
  _resetNativePasteInteraction(reason: 'documentHidden');
}

void _resetNativePasteInteraction({required String reason}) {
  final hadOwnedPointer = _suppressPointerSequence;
  final hadTransientTarget = _transientCalloutTarget != null;
  final hadPendingClick = _pendingOwnedClickTarget != null;
  _clearNativeGestureCorrelation(clearTapHistory: true);
  _lastHandledPaste = null;
  if (!hadOwnedPointer && !hadTransientTarget && !hadPendingClick) return;

  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'iOS native paste interaction state reset for page lifecycle',
      context: {
        'reason': reason,
        'hadOwnedPointer': hadOwnedPointer,
        'hadTransientTarget': hadTransientTarget,
        'hadPendingClick': hadPendingClick,
      },
    ),
  );
}

_DomEditableTarget? _resolveEditableTarget(web.EventTarget? candidate) {
  if (_isForeignEditable(candidate)) return null;
  final direct = _domEditableTarget(candidate);
  if (direct != null) {
    _lastEditableElement = direct.element;
    return direct;
  }

  if (_isNeutralPasteTarget(candidate)) {
    final active = _domEditableTarget(web.document.activeElement);
    if (active != null) {
      _lastEditableElement = active.element;
      return active;
    }
  }

  if (!_isSafeFrameworkFallbackContext(candidate)) return null;
  return _domEditableTarget(_transientCalloutTarget);
}

web.HTMLElement? _editableElement(web.EventTarget? candidate) {
  if (candidate == null || !candidate.isA<web.HTMLElement>()) return null;
  final element = candidate as web.HTMLElement;
  if (!element.isConnected ||
      !element.classList.contains(_flutterTextEditingClass)) {
    return null;
  }
  if (!candidate.isA<web.HTMLInputElement>() &&
      !candidate.isA<web.HTMLTextAreaElement>()) {
    return null;
  }
  return element;
}

bool _isForeignEditable(web.EventTarget? candidate) {
  if (candidate == null || !candidate.isA<web.HTMLElement>()) return false;
  final element = candidate as web.HTMLElement;
  if (_editableElement(element) != null) return false;
  return element.isA<web.HTMLInputElement>() ||
      element.isA<web.HTMLTextAreaElement>() ||
      element.isContentEditable;
}

bool _isNeutralPasteTarget(web.EventTarget? candidate) {
  return candidate == null ||
      candidate == web.document ||
      candidate == web.document.body;
}

void _clearTransientCalloutTarget(web.HTMLElement? target) {
  if (target == null || _sameDomElement(target, _transientCalloutTarget)) {
    _transientCalloutTarget = null;
    _transientCalloutAt = null;
    _pendingEmptyPaste = null;
  }
}

bool _sameDomElement(web.HTMLElement? first, web.HTMLElement? second) {
  if (first == null || second == null) return first == second;
  return first.isSameNode(second);
}

_DomEditableTarget? _domEditableTarget(web.EventTarget? candidate) {
  final element = _editableElement(candidate);
  if (element == null) return null;

  if (element.isA<web.HTMLInputElement>()) {
    final input = element as web.HTMLInputElement;
    return _DomEditableTarget(
      element: element,
      value: input.value,
      selectionStart: input.selectionStart,
      selectionEnd: input.selectionEnd,
      apply: (value, start, end) {
        input.value = value;
        input.setSelectionRange(start, end);
        input.dispatchEvent(_syntheticInputEvent());
      },
    );
  }

  final textArea = element as web.HTMLTextAreaElement;
  return _DomEditableTarget(
    element: element,
    value: textArea.value,
    selectionStart: textArea.selectionStart,
    selectionEnd: textArea.selectionEnd,
    apply: (value, start, end) {
      textArea.value = value;
      textArea.setSelectionRange(start, end);
      textArea.dispatchEvent(_syntheticInputEvent());
    },
  );
}

BrowserPasteTextReplacement? _replacementFor(
  _DomEditableTarget target,
  String pastedText,
) {
  return recoverBrowserPasteText(
    beforeText: target.value,
    selectionStart: target.selectionStart ?? -1,
    selectionEnd: target.selectionEnd ?? -1,
    pastedText: pastedText,
  );
}

void _applyReplacement(
  _DomEditableTarget target,
  BrowserPasteTextReplacement replacement,
) {
  target.apply(
    replacement.text,
    replacement.selectionOffset,
    replacement.selectionOffset,
  );
}

bool _takeDuplicatePaste(
  _DomEditableTarget target,
  String pastedText,
  String source,
) {
  return _takeDuplicatePasteMarker(target.element, pastedText, source);
}

bool _takeDuplicatePasteMarker(
  web.HTMLElement? element,
  String pastedText,
  String source,
) {
  final handled = _lastHandledPaste;
  if (handled == null) return false;
  if (DateTime.now().difference(handled.handledAt) > _pasteDedupeWindow) {
    _lastHandledPaste = null;
    return false;
  }
  final sameTarget = _sameDomElement(handled.element, element);
  // One native iOS action can emit paste and beforeinput for the same
  // clipboard payload. A formatter may normalize the DOM value between the
  // two events, so comparing raw result text is not reliable. Only suppress
  // the immediately paired opposite event kind. The marker is single-use and
  // short-lived so a new user paste with the same clipboard is never made
  // intermittent by an old event pair.
  final duplicate =
      sameTarget &&
      handled.source != source &&
      handled.pastedText == pastedText;
  _lastHandledPaste = null;
  return duplicate;
}

void _consumeDuplicatePasteEvent(
  web.Event event,
  String pastedText,
  String source,
) {
  event.preventDefault();
  event.stopImmediatePropagation();
  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'Browser paste duplicate event ignored',
      context: {
        'source': source,
        'pastedTextLength': pastedText.length,
        'hasDomTarget': false,
      },
    ),
  );
}

web.Event _syntheticInputEvent() => web.Event(
  'input',
  web.EventInit(bubbles: true, cancelable: false, composed: true),
);

@visibleForTesting
bool applyBrowserPasteToDomForTesting(
  web.EventTarget target,
  String pastedText,
) {
  final editableTarget = _resolveEditableTarget(target);
  if (editableTarget == null) return false;
  final replacement = _replacementFor(editableTarget, pastedText);
  if (replacement == null) return false;
  _applyReplacement(editableTarget, replacement);
  return true;
}

@visibleForTesting
void expireTransientCalloutTargetForTesting() {
  if (_transientCalloutTarget == null) return;
  _transientCalloutAt = DateTime.now().subtract(
    _transientCalloutRetentionWindow + const Duration(milliseconds: 1),
  );
}

class _DomEditableTarget {
  final web.HTMLElement element;
  final String value;
  final int? selectionStart;
  final int? selectionEnd;
  final void Function(String value, int start, int end) apply;

  const _DomEditableTarget({
    required this.element,
    required this.value,
    required this.selectionStart,
    required this.selectionEnd,
    required this.apply,
  });
}

class _HandledPaste {
  final web.HTMLElement? element;
  final String pastedText;
  final String source;
  final DateTime handledAt;

  const _HandledPaste({
    required this.element,
    required this.pastedText,
    required this.source,
    required this.handledAt,
  });
}

class _PendingEmptyPaste {
  final web.HTMLElement element;
  final String source;
  final DateTime receivedAt;

  const _PendingEmptyPaste({
    required this.element,
    required this.source,
    required this.receivedAt,
  });
}
