@TestOn('chrome')
library;

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/browser_native_paste_recovery_web.dart'
    as recovery;
import 'package:web/web.dart' as web;

void main() {
  test(
    'captures a native paste event before Flutter engine listeners',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'showroom-old';
      web.document.body!.append(input);
      addTearDown(() => input.remove());

      input.focus();
      input.setSelectionRange(9, 12);
      var inputEventCount = 0;
      final listener = ((web.Event _) {
        inputEventCount += 1;
      }).toJS;
      input.addEventListener('input', listener);
      addTearDown(() => input.removeEventListener('input', listener));

      final dataTransfer = web.DataTransfer()..setData('text/plain', 'CP01');
      final pasteEvent = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clipboardData: dataTransfer,
        ),
      );
      input.dispatchEvent(pasteEvent);

      expect(pasteEvent.defaultPrevented, isTrue);
      expect(input.value, 'showroom-CP01');
      expect(input.selectionStart, 13);
      expect(input.selectionEnd, 13);
      expect(inputEventCount, 1);
    },
  );

  test(
    'allows first focus touch but stabilizes focused iOS native touches',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'showroom CP01'
        ..style.transform = 'matrix(1, 0, 0, 1, 94, 380)';

      // Flutter 3.44.x installs this click behavior before the app bridge. It
      // moves the input away for 100ms, so a fast second tap otherwise lands
      // on SelectionArea's full-screen platform view.
      var engineClickCount = 0;
      final engineClickListener = ((web.Event _) {
        engineClickCount += 1;
        input.style.transform = 'translate(-9999px, -9999px)';
      }).toJS;
      input.addEventListener('click', engineClickListener);
      var enginePointerDownCount = 0;
      final enginePointerDownListener = ((web.Event _) {
        enginePointerDownCount += 1;
      }).toJS;
      input.addEventListener('pointerdown', enginePointerDownListener);
      web.document.body!.append(input);
      addTearDown(() {
        input.removeEventListener('click', engineClickListener);
        input.removeEventListener('pointerdown', enginePointerDownListener);
        input.remove();
      });

      var bubbledClicks = 0;
      final clickListener = ((web.Event _) {
        bubbledClicks += 1;
      }).toJS;
      web.document.addEventListener('click', clickListener);
      addTearDown(() {
        web.document.removeEventListener('click', clickListener);
      });
      var bubbledPointerDowns = 0;
      var bubbledPointerUps = 0;
      final pointerDownBubbleListener = ((web.Event _) {
        bubbledPointerDowns += 1;
      }).toJS;
      final pointerUpBubbleListener = ((web.Event _) {
        bubbledPointerUps += 1;
      }).toJS;
      web.document.addEventListener('pointerdown', pointerDownBubbleListener);
      web.document.addEventListener('pointerup', pointerUpBubbleListener);
      addTearDown(() {
        web.document.removeEventListener(
          'pointerdown',
          pointerDownBubbleListener,
        );
        web.document.removeEventListener('pointerup', pointerUpBubbleListener);
      });

      // The first touch is allowed through so Flutter can focus the field and
      // run its keyboard anti-scroll placement path.
      final firstPointerDown = web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: 'touch',
          isPrimary: true,
        ),
      );
      input.dispatchEvent(firstPointerDown);
      final firstPointerUp = web.PointerEvent(
        'pointerup',
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: 'touch',
          isPrimary: true,
        ),
      );
      input.dispatchEvent(firstPointerUp);
      final firstClick = web.MouseEvent(
        'click',
        web.MouseEventInit(bubbles: true, cancelable: true, detail: 1),
      );
      input.dispatchEvent(firstClick);

      expect(firstPointerDown.defaultPrevented, isFalse);
      expect(firstPointerUp.defaultPrevented, isFalse);
      expect(enginePointerDownCount, 1);
      expect(bubbledPointerDowns, 1);
      expect(bubbledPointerUps, 1);
      expect(engineClickCount, 1);
      expect(bubbledClicks, 1);
      expect(input.style.transform, 'translate(-9999px, -9999px)');
      expect(firstClick.defaultPrevented, isFalse);

      // Once the real DOM input owns focus, WebKit owns the next native touch
      // sequence and its paired click cannot start another off-screen timer.
      input
        ..focus()
        ..style.transform = 'matrix(1, 0, 0, 1, 94, 380)';
      final secondPointerDown = web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: 'touch',
          isPrimary: true,
        ),
      );
      input.dispatchEvent(secondPointerDown);
      final secondPointerUp = web.PointerEvent(
        'pointerup',
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 1,
          pointerType: 'touch',
          isPrimary: true,
        ),
      );
      input.dispatchEvent(secondPointerUp);

      expect(secondPointerDown.defaultPrevented, isFalse);
      expect(secondPointerUp.defaultPrevented, isFalse);
      expect(
        enginePointerDownCount,
        1,
        reason: 'Only the first focus touch should reach Flutter.',
      );
      expect(bubbledPointerDowns, 1);
      expect(bubbledPointerUps, 1);

      final secondClick = web.MouseEvent(
        'click',
        web.MouseEventInit(bubbles: true, cancelable: true, detail: 2),
      );
      input.dispatchEvent(secondClick);

      expect(input.style.transform, 'matrix(1, 0, 0, 1, 94, 380)');
      expect(
        engineClickCount,
        1,
        reason: 'Flutter must not start its off-screen relocation timer.',
      );
      expect(
        bubbledClicks,
        1,
        reason: 'Only the first focus click should bubble.',
      );
      expect(secondClick.defaultPrevented, isFalse);

      // A click without an owned touch correlation is not swallowed.
      final mouseClick = web.MouseEvent(
        'click',
        web.MouseEventInit(bubbles: true, cancelable: true, detail: 1),
      );
      input.dispatchEvent(mouseClick);
      expect(engineClickCount, 2);
      expect(bubbledClicks, 2);
      expect(mouseClick.defaultPrevented, isFalse);
    },
  );

  test(
    'keeps only gesture-correlated iOS callout blur from the engine',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'showroom CP01';
      final outside = web.HTMLDivElement();
      web.document.body!
        ..append(input)
        ..append(outside);
      addTearDown(() {
        input.remove();
        outside.remove();
      });

      var engineBlurCount = 0;
      final engineBlurListener = ((web.Event _) {
        engineBlurCount += 1;
      }).toJS;
      input.addEventListener('blur', engineBlurListener);
      addTearDown(() {
        input.removeEventListener('blur', engineBlurListener);
      });

      input.focus();
      final pointerDown = web.PointerEvent(
        'pointerdown',
        web.PointerEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          pointerId: 2,
          pointerType: 'touch',
          isPrimary: true,
        ),
      );
      input.dispatchEvent(pointerDown);

      final fieldChangeBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: outside),
      );
      input.dispatchEvent(fieldChangeBlur);
      expect(engineBlurCount, 1);

      final calloutBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(calloutBlur);

      expect(engineBlurCount, 1);
      expect(calloutBlur.defaultPrevented, isFalse);

      input.dispatchEvent(
        web.PointerEvent(
          'pointerup',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 2,
            pointerType: 'touch',
            isPrimary: true,
          ),
        ),
      );

      // A pointer outside the editable clears the callout correlation, so a
      // subsequent ordinary blur still reaches Flutter's engine listener.
      outside.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 3,
            pointerType: 'touch',
            isPrimary: true,
          ),
        ),
      );
      final ordinaryBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(ordinaryBlur);

      expect(engineBlurCount, 2);
      expect(ordinaryBlur.defaultPrevented, isFalse);
    },
  );

  test(
    'keeps post-pointer callout blur but lets unrelated pointers bubble',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'order CP01';
      final outside = web.HTMLDivElement();
      web.document.body!
        ..append(input)
        ..append(outside);
      addTearDown(() {
        input.remove();
        outside.remove();
      });

      var engineBlurCount = 0;
      final engineBlurListener = ((web.Event _) {
        engineBlurCount += 1;
      }).toJS;
      input.addEventListener('blur', engineBlurListener);
      addTearDown(() => input.removeEventListener('blur', engineBlurListener));

      var unrelatedPointerCount = 0;
      final unrelatedPointerListener = ((web.Event event) {
        if (event.isA<web.PointerEvent>() &&
            (event as web.PointerEvent).pointerId == 42) {
          unrelatedPointerCount += 1;
        }
      }).toJS;
      web.document.addEventListener('pointerdown', unrelatedPointerListener);
      web.document.addEventListener('pointerup', unrelatedPointerListener);
      addTearDown(() {
        web.document.removeEventListener(
          'pointerdown',
          unrelatedPointerListener,
        );
        web.document.removeEventListener('pointerup', unrelatedPointerListener);
      });

      input.focus();
      input.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 41,
            pointerType: 'touch',
            isPrimary: true,
          ),
        ),
      );

      // A second pointer must not be mistaken for the owned native touch.
      outside.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 42,
            pointerType: 'touch',
            isPrimary: false,
          ),
        ),
      );
      outside.dispatchEvent(
        web.PointerEvent(
          'pointerup',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 42,
            pointerType: 'touch',
            isPrimary: false,
          ),
        ),
      );
      expect(unrelatedPointerCount, 2);

      input.dispatchEvent(
        web.PointerEvent(
          'pointerup',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 41,
            pointerType: 'touch',
            isPrimary: true,
          ),
        ),
      );
      final postPointerCalloutBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(postPointerCalloutBlur);
      expect(engineBlurCount, 0);
      expect(postPointerCalloutBlur.defaultPrevented, isFalse);

      outside.dispatchEvent(
        web.PointerEvent(
          'pointerdown',
          web.PointerEventInit(
            bubbles: true,
            cancelable: true,
            composed: true,
            pointerId: 43,
            pointerType: 'touch',
            isPrimary: true,
          ),
        ),
      );
      final ordinaryBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(ordinaryBlur);
      expect(engineBlurCount, 1);
    },
  );

  test(
    'suppresses owned terminal events even when WebKit retargets them',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'order CP01';
      final outside = web.HTMLDivElement();
      web.document.body!
        ..append(input)
        ..append(outside);
      addTearDown(() {
        input.remove();
        outside.remove();
      });

      var retargetedTerminalCount = 0;
      var engineClickCount = 0;
      var engineBlurCount = 0;
      final terminalListener = ((web.Event event) {
        if (event.isA<web.PointerEvent>()) {
          final pointerId = (event as web.PointerEvent).pointerId;
          if (pointerId == 51 || pointerId == 52) {
            retargetedTerminalCount += 1;
          }
        }
      }).toJS;
      final engineClickListener = ((web.Event _) {
        engineClickCount += 1;
      }).toJS;
      final engineBlurListener = ((web.Event _) {
        engineBlurCount += 1;
      }).toJS;
      web.document.addEventListener('pointerup', terminalListener);
      web.document.addEventListener('pointercancel', terminalListener);
      input.addEventListener('click', engineClickListener);
      input.addEventListener('blur', engineBlurListener);
      addTearDown(() {
        web.document.removeEventListener('pointerup', terminalListener);
        web.document.removeEventListener('pointercancel', terminalListener);
        input.removeEventListener('click', engineClickListener);
        input.removeEventListener('blur', engineBlurListener);
      });

      input.focus();
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 51));
      final retargetedUp = _touchPointer('pointerup', pointerId: 51);
      outside.dispatchEvent(retargetedUp);
      input.dispatchEvent(
        web.MouseEvent(
          'click',
          web.MouseEventInit(bubbles: true, cancelable: true, detail: 2),
        ),
      );

      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 52));
      final retargetedCancel = _touchPointer('pointercancel', pointerId: 52);
      outside.dispatchEvent(retargetedCancel);
      final cancelCalloutBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(cancelCalloutBlur);
      input.dispatchEvent(
        web.MouseEvent(
          'click',
          web.MouseEventInit(bubbles: true, cancelable: true, detail: 2),
        ),
      );

      expect(retargetedTerminalCount, 0);
      expect(
        engineClickCount,
        1,
        reason: 'pointercancel must not create a click ownership lease.',
      );
      expect(engineBlurCount, 0);
      expect(retargetedUp.defaultPrevented, isFalse);
      expect(retargetedCancel.defaultPrevented, isFalse);
    },
  );

  test(
    'expires blur and click ownership after their bounded windows',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'order CP01';
      web.document.body!.append(input);
      addTearDown(() => input.remove());

      var engineBlurCount = 0;
      var engineClickCount = 0;
      final blurListener = ((web.Event _) {
        engineBlurCount += 1;
      }).toJS;
      final clickListener = ((web.Event _) {
        engineClickCount += 1;
      }).toJS;
      input.addEventListener('blur', blurListener);
      input.addEventListener('click', clickListener);
      addTearDown(() {
        input.removeEventListener('blur', blurListener);
        input.removeEventListener('click', clickListener);
      });

      input.focus();
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 61));
      input.dispatchEvent(_touchPointer('pointerup', pointerId: 61));

      await Future<void>.delayed(const Duration(milliseconds: 250));
      final expiredBlur = web.FocusEvent(
        'blur',
        web.FocusEventInit(relatedTarget: null),
      );
      input.dispatchEvent(expiredBlur);
      expect(engineBlurCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      final expiredClick = web.MouseEvent(
        'click',
        web.MouseEventInit(bubbles: true, cancelable: true, detail: 2),
      );
      input.dispatchEvent(expiredClick);
      expect(engineClickCount, 1);
      expect(expiredClick.defaultPrevented, isFalse);
    },
  );

  test(
    'resets lost pointer ownership for lifecycle and new primary touch',
    () async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'order CP01';
      final outside = web.HTMLDivElement();
      web.document.body!
        ..append(input)
        ..append(outside);
      addTearDown(() {
        input.remove();
        outside.remove();
      });

      var enginePrimaryPointerCount = 0;
      var oldTerminalAfterPageHideCount = 0;
      final pointerListener = ((web.Event event) {
        if (event.isA<web.PointerEvent>()) {
          final pointerId = (event as web.PointerEvent).pointerId;
          if (pointerId == 72 || pointerId == 74) {
            enginePrimaryPointerCount += 1;
          }
        }
      }).toJS;
      final oldTerminalListener = ((web.Event event) {
        if (event.isA<web.PointerEvent>() &&
            (event as web.PointerEvent).pointerId == 71) {
          oldTerminalAfterPageHideCount += 1;
        }
      }).toJS;
      input.addEventListener('pointerdown', pointerListener);
      web.document.addEventListener('pointerup', oldTerminalListener);
      addTearDown(() {
        input.removeEventListener('pointerdown', pointerListener);
        web.document.removeEventListener('pointerup', oldTerminalListener);
        web.window.dispatchEvent(web.Event('pagehide'));
      });

      input.focus();
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 71));
      web.window.dispatchEvent(web.Event('pagehide'));
      outside.dispatchEvent(_touchPointer('pointerup', pointerId: 71));
      expect(oldTerminalAfterPageHideCount, 1);
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 72));
      expect(enginePrimaryPointerCount, 0);
      input.dispatchEvent(_touchPointer('pointerup', pointerId: 72));

      input.focus();
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 73));
      // No pointerup/cancel is delivered for 73. A new primary pointer is a new
      // WebKit session and must release the stale owner instead of getting stuck.
      input.dispatchEvent(_touchPointer('pointerdown', pointerId: 74));
      expect(enginePrimaryPointerCount, 0);
    },
  );

  testWidgets(
    'body-target paste after protected blur updates focused EditableText once',
    (tester) async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final controller = TextEditingController(text: 'showroom-old')
        ..selection = const TextSelection(baseOffset: 9, extentOffset: 12);
      final focusNode = FocusNode();
      var changedCount = 0;
      addTearDown(() {
        focusNode.dispose();
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (_) => changedCount += 1,
            ),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      final editable = _activeFlutterDomEditable();
      _setDomSelection(editable, 9, 12);
      editable.dispatchEvent(_touchPointer('pointerdown', pointerId: 81));
      editable.dispatchEvent(_touchPointer('pointerup', pointerId: 81));
      _blurDomEditable(editable);

      final pasteEvent = _pasteEvent('CP01');
      web.document.body!.dispatchEvent(pasteEvent);
      final pairedBeforeInput = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: 'CP01',
          inputType: 'insertFromPaste',
        ),
      );
      web.document.body!.dispatchEvent(pairedBeforeInput);
      await tester.pump();

      expect(pasteEvent.defaultPrevented, isTrue);
      expect(pairedBeforeInput.defaultPrevented, isTrue);
      expect(controller.text, 'showroom-CP01');
      expect(controller.selection, const TextSelection.collapsed(offset: 13));
      expect(changedCount, 1);
    },
  );

  testWidgets(
    'empty paste only retains target for its immediate data-bearing pair',
    (tester) async {
      await recovery.initializeBrowserNativePasteRecovery(
        preserveRepeatedTapTarget: true,
      );
      final controller = TextEditingController(text: 'order-old')
        ..selection = const TextSelection.collapsed(offset: 9);
      final focusNode = FocusNode();
      addTearDown(() {
        focusNode.dispose();
        controller.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(controller: controller, focusNode: focusNode),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pumpAndSettle();
      final editable = _activeFlutterDomEditable();
      _setDomSelection(editable, 9, 9);
      editable.dispatchEvent(_touchPointer('pointerdown', pointerId: 91));
      editable.dispatchEvent(_touchPointer('pointerup', pointerId: 91));
      _blurDomEditable(editable);
      recovery.expireTransientCalloutTargetForTesting();

      final expiredPaste = _pasteEvent('CP01');
      web.document.body!.dispatchEvent(expiredPaste);
      await tester.pump();
      expect(expiredPaste.defaultPrevented, isFalse);
      expect(controller.text, 'order-old');

      _focusDomEditable(editable);
      editable.dispatchEvent(_touchPointer('pointerdown', pointerId: 92));
      editable.dispatchEvent(_touchPointer('pointerup', pointerId: 92));
      _blurDomEditable(editable);
      final emptyPaste = _pasteEvent('');
      web.document.body!.dispatchEvent(emptyPaste);
      final pairedBeforeInput = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: 'CP02',
          inputType: 'insertFromPaste',
        ),
      );
      web.document.body!.dispatchEvent(pairedBeforeInput);
      final laterPaste = _pasteEvent('CP03');
      web.document.body!.dispatchEvent(laterPaste);
      await tester.pump();

      expect(emptyPaste.defaultPrevented, isFalse);
      expect(pairedBeforeInput.defaultPrevented, isTrue);
      expect(laterPaste.defaultPrevented, isFalse);
      expect(controller.text, 'order-oldCP02');

      _focusDomEditable(editable);
      _setDomSelection(
        editable,
        controller.text.length,
        controller.text.length,
      );
      editable.dispatchEvent(_touchPointer('pointerdown', pointerId: 93));
      editable.dispatchEvent(_touchPointer('pointerup', pointerId: 93));
      _blurDomEditable(editable);
      final secondEmptyPaste = _pasteEvent('');
      web.document.body!.dispatchEvent(secondEmptyPaste);
      final emptyBeforeInput = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: '',
          inputType: 'insertFromPaste',
        ),
      );
      web.document.body!.dispatchEvent(emptyBeforeInput);
      final staleDataBeforeInput = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: 'CP04',
          inputType: 'insertFromPaste',
        ),
      );
      web.document.body!.dispatchEvent(staleDataBeforeInput);
      await tester.pump();

      expect(secondEmptyPaste.defaultPrevented, isFalse);
      expect(emptyBeforeInput.defaultPrevented, isFalse);
      expect(staleDataBeforeInput.defaultPrevented, isFalse);
      expect(controller.text, 'order-oldCP02');
    },
  );

  test(
    'handles iOS beforeinput paste delivery without a second insertion',
    () async {
      await recovery.initializeBrowserNativePasteRecovery();
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'order-old';
      web.document.body!.append(input);
      addTearDown(() => input.remove());

      input.focus();
      input.setSelectionRange(6, 9);
      final beforeInputEvent = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: 'CP02',
          inputType: 'insertFromPaste',
        ),
      );
      input.dispatchEvent(beforeInputEvent);

      expect(beforeInputEvent.defaultPrevented, isTrue);
      expect(input.value, 'order-CP02');
      expect(input.selectionStart, 10);
      expect(input.selectionEnd, 10);
    },
  );

  test(
    'deduplicates the paired event after an input formatter normalizes DOM text',
    () async {
      await recovery.initializeBrowserNativePasteRecovery();
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'amount-old';
      web.document.body!.append(input);
      addTearDown(() => input.remove());

      // Simulate a formatter/onChanged round-trip that changes the raw DOM
      // result before Safari emits the paired beforeinput event.
      final normalizeListener = ((web.Event _) {
        input.value = input.value.toUpperCase();
        final end = input.value.length;
        input.setSelectionRange(end, end);
      }).toJS;
      input.addEventListener('input', normalizeListener);
      addTearDown(() {
        input.removeEventListener('input', normalizeListener);
      });

      input.focus();
      input.setSelectionRange(7, 10);
      final pasteEvent = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clipboardData: web.DataTransfer()..setData('text/plain', 'CP03'),
        ),
      );
      input.dispatchEvent(pasteEvent);
      final normalizedValue = input.value;

      final pairedBeforeInput = web.InputEvent(
        'beforeinput',
        web.InputEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          data: 'CP03',
          inputType: 'insertFromPaste',
        ),
      );
      input.dispatchEvent(pairedBeforeInput);

      expect(normalizedValue, 'AMOUNT-CP03');
      expect(input.value, normalizedValue);
      expect(pairedBeforeInput.defaultPrevented, isTrue);

      // The paired marker is single-use. A new paste with the same clipboard
      // immediately afterwards must still be applied.
      input.setSelectionRange(input.value.length, input.value.length);
      final secondPaste = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clipboardData: web.DataTransfer()..setData('text/plain', 'CP03'),
        ),
      );
      input.dispatchEvent(secondPaste);
      expect(secondPaste.defaultPrevented, isTrue);
      expect(input.value, 'AMOUNT-CP03CP03');
    },
  );

  test(
    'does not redirect paste from a foreign editable to a cached field',
    () async {
      await recovery.initializeBrowserNativePasteRecovery();
      final flutterInput = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'flutter-old';
      final foreignInput = web.HTMLInputElement()
        ..className = 'application-input'
        ..value = 'foreign-old';
      web.document.body!
        ..append(flutterInput)
        ..append(foreignInput);
      addTearDown(() {
        flutterInput.remove();
        foreignInput.remove();
      });

      flutterInput.focus();
      flutterInput.setSelectionRange(0, flutterInput.value.length);
      foreignInput.focus();
      foreignInput.setSelectionRange(0, foreignInput.value.length);
      final pasteEvent = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clipboardData: web.DataTransfer()
            ..setData('text/plain', 'replacement'),
        ),
      );
      foreignInput.dispatchEvent(pasteEvent);

      expect(pasteEvent.defaultPrevented, isFalse);
      expect(flutterInput.value, 'flutter-old');
      expect(foreignInput.value, 'foreign-old');
    },
  );

  test(
    'does not paste into a cached Flutter field after ordinary blur',
    () async {
      await recovery.initializeBrowserNativePasteRecovery();
      final input = web.HTMLInputElement()
        ..className = 'flt-text-editing'
        ..value = 'blurred-old';
      web.document.body!.append(input);
      addTearDown(() => input.remove());

      input.focus();
      input.setSelectionRange(0, input.value.length);
      input.blur();
      final pasteEvent = web.ClipboardEvent(
        'paste',
        web.ClipboardEventInit(
          bubbles: true,
          cancelable: true,
          composed: true,
          clipboardData: web.DataTransfer()
            ..setData('text/plain', 'replacement'),
        ),
      );
      web.document.body!.dispatchEvent(pasteEvent);

      expect(pasteEvent.defaultPrevented, isFalse);
      expect(input.value, 'blurred-old');
    },
  );

  test('updates Flutter text-editing DOM input and emits one input event', () {
    final input = web.HTMLInputElement()
      ..className = 'flt-text-editing'
      ..value = 'showroom-old';
    web.document.body!.append(input);
    addTearDown(() => input.remove());

    input.focus();
    input.setSelectionRange(9, 12);
    var inputEventCount = 0;
    final listener = ((web.Event _) {
      inputEventCount += 1;
    }).toJS;
    input.addEventListener('input', listener);
    addTearDown(() => input.removeEventListener('input', listener));

    expect(recovery.applyBrowserPasteToDomForTesting(input, 'CP01'), isTrue);
    expect(input.value, 'showroom-CP01');
    expect(input.selectionStart, 13);
    expect(input.selectionEnd, 13);
    expect(inputEventCount, 1);
  });

  test('does not touch a non-Flutter DOM input', () {
    final input = web.HTMLInputElement()
      ..className = 'application-input'
      ..value = 'unchanged';
    web.document.body!.append(input);
    addTearDown(() => input.remove());
    input.focus();
    input.setSelectionRange(0, input.value.length);

    expect(
      recovery.applyBrowserPasteToDomForTesting(input, 'replacement'),
      isFalse,
    );
    expect(input.value, 'unchanged');
  });
}

web.PointerEvent _touchPointer(String type, {required int pointerId}) {
  return web.PointerEvent(
    type,
    web.PointerEventInit(
      bubbles: true,
      cancelable: true,
      composed: true,
      pointerId: pointerId,
      pointerType: 'touch',
      isPrimary: true,
    ),
  );
}

web.ClipboardEvent _pasteEvent(String text) {
  return web.ClipboardEvent(
    'paste',
    web.ClipboardEventInit(
      bubbles: true,
      cancelable: true,
      composed: true,
      clipboardData: web.DataTransfer()..setData('text/plain', text),
    ),
  );
}

web.HTMLElement _activeFlutterDomEditable() {
  final active = web.document.activeElement;
  expect(active, isA<web.HTMLElement>());
  final editable = active! as web.HTMLElement;
  expect(editable.classList.contains('flt-text-editing'), isTrue);
  expect(
    editable.isA<web.HTMLInputElement>() ||
        editable.isA<web.HTMLTextAreaElement>(),
    isTrue,
  );
  return editable;
}

void _setDomSelection(web.HTMLElement editable, int start, int end) {
  if (editable.isA<web.HTMLInputElement>()) {
    (editable as web.HTMLInputElement).setSelectionRange(start, end);
    return;
  }
  (editable as web.HTMLTextAreaElement).setSelectionRange(start, end);
}

void _focusDomEditable(web.HTMLElement editable) {
  if (editable.isA<web.HTMLInputElement>()) {
    (editable as web.HTMLInputElement).focus();
    return;
  }
  (editable as web.HTMLTextAreaElement).focus();
}

void _blurDomEditable(web.HTMLElement editable) {
  if (editable.isA<web.HTMLInputElement>()) {
    (editable as web.HTMLInputElement).blur();
    return;
  }
  (editable as web.HTMLTextAreaElement).blur();
}
