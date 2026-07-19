import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:phongvu_opshub/core/platform/browser_native_paste_recovery_policy.dart';

void main() {
  test(
    'replaces the focused selection once and collapses after pasted text',
    () {
      final before = TextEditingValue(
        text: 'showroom-old',
        selection: const TextSelection(baseOffset: 9, extentOffset: 12),
      );

      final after = recoverBrowserPasteValue(
        before: before,
        pastedText: 'CP01',
      );

      expect(after?.text, 'showroom-CP01');
      expect(after?.selection, const TextSelection.collapsed(offset: 13));
      expect(after?.composing, TextRange.empty);
    },
  );

  test('rejects an invalid selection instead of guessing a paste target', () {
    final after = recoverBrowserPasteValue(
      before: const TextEditingValue(
        text: 'value',
        selection: TextSelection.collapsed(offset: -1),
      ),
      pastedText: 'paste',
    );

    expect(after, isNull);
  });

  test('normalizes a reversed DOM selection before replacing pasted text', () {
    final after = recoverBrowserPasteText(
      beforeText: 'abcdef',
      selectionStart: 5,
      selectionEnd: 2,
      pastedText: 'X',
    );

    expect(after?.text, 'abXf');
    expect(after?.selectionOffset, 3);
  });

  test('normalizes a reversed framework selection for the fallback path', () {
    final after = recoverBrowserPasteValue(
      before: const TextEditingValue(
        text: 'abcdef',
        selection: TextSelection(baseOffset: 5, extentOffset: 2),
      ),
      pastedText: 'X',
    );

    expect(after?.text, 'abXf');
    expect(after?.selection, const TextSelection.collapsed(offset: 3));
  });
}
