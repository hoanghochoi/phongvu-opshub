import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../logging/app_logger.dart';
import 'browser_native_paste_recovery_policy.dart';

const Duration _pasteRecoveryDelay = Duration(milliseconds: 120);

bool _initialized = false;
late final JSFunction _pasteListener;
TextEditingController? _lastFocusedController;
DateTime? _lastFocusedAt;

Future<void> initializeBrowserNativePasteRecovery() async {
  if (_initialized) return;
  _initialized = true;
  _pasteListener = ((web.ClipboardEvent event) {
    _handlePasteEvent(event);
  }).toJS;
  web.document.addEventListener('paste', _pasteListener);
  FocusManager.instance.addListener(_rememberFocusedEditable);
  await AppLogger.instance.info(
    'TextInput',
    'Browser-native paste recovery initialized',
    context: {'delayMs': _pasteRecoveryDelay.inMilliseconds},
  );
}

void _handlePasteEvent(web.ClipboardEvent event) {
  final controller = _focusedController();
  if (controller == null) {
    unawaited(
      AppLogger.instance.info(
        'TextInput',
        'Browser paste event ignored because no editable field is focused',
      ),
    );
    return;
  }

  final pastedText = event.clipboardData?.getData('text/plain') ?? '';
  if (pastedText.isEmpty) {
    unawaited(
      AppLogger.instance.info(
        'TextInput',
        'Browser paste event contained no plain text',
        context: {'fieldTextLength': controller.text.length},
      ),
    );
    return;
  }

  final before = controller.value;
  unawaited(
    AppLogger.instance.info(
      'TextInput',
      'Browser paste event captured for focused editable field',
      context: {
        'fieldTextLength': before.text.length,
        'selectionStart': before.selection.start,
        'selectionEnd': before.selection.end,
        'pastedTextLength': pastedText.length,
      },
    ),
  );

  Timer(_pasteRecoveryDelay, () {
    _recoverIfFrameworkDidNotReceivePaste(controller, before, pastedText);
  });
}

TextEditingController? _focusedController() {
  final editableState = FocusManager.instance.primaryFocus?.context
      ?.findAncestorStateOfType<EditableTextState>();
  final currentController = editableState?.widget.controller;
  if (currentController != null) {
    _lastFocusedController = currentController;
    _lastFocusedAt = DateTime.now();
    return currentController;
  }

  final lastFocusedAt = _lastFocusedAt;
  if (_lastFocusedController != null &&
      lastFocusedAt != null &&
      DateTime.now().difference(lastFocusedAt) <= const Duration(seconds: 2)) {
    return _lastFocusedController;
  }
  return null;
}

void _rememberFocusedEditable() {
  final editableState = FocusManager.instance.primaryFocus?.context
      ?.findAncestorStateOfType<EditableTextState>();
  if (editableState == null) return;
  _lastFocusedController = editableState.widget.controller;
  _lastFocusedAt = DateTime.now();
}

void _recoverIfFrameworkDidNotReceivePaste(
  TextEditingController controller,
  TextEditingValue before,
  String pastedText,
) {
  try {
    if (controller.text != before.text) {
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
          'Browser paste recovery skipped invalid selection',
          context: {
            'selectionStart': before.selection.start,
            'selectionEnd': before.selection.end,
          },
        ),
      );
      return;
    }

    controller.value = nextValue;
    unawaited(
      AppLogger.instance.warn(
        'TextInput',
        'Browser paste recovery applied after framework update timeout',
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
        'Browser paste recovery failed; keeping browser result',
        error: error,
        stackTrace: stackTrace,
        context: {'pastedTextLength': pastedText.length},
      ),
    );
  }
}
