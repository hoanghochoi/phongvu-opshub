import 'package:flutter/widgets.dart';

class BrowserPasteTextReplacement {
  final String text;
  final int selectionOffset;

  const BrowserPasteTextReplacement({
    required this.text,
    required this.selectionOffset,
  });
}

BrowserPasteTextReplacement? recoverBrowserPasteText({
  required String beforeText,
  required int selectionStart,
  required int selectionEnd,
  required String pastedText,
}) {
  if (selectionStart < 0 ||
      selectionEnd < 0 ||
      selectionStart > beforeText.length ||
      selectionEnd > beforeText.length) {
    return null;
  }

  final start = selectionStart <= selectionEnd ? selectionStart : selectionEnd;
  final end = selectionStart <= selectionEnd ? selectionEnd : selectionStart;
  final nextText = beforeText.replaceRange(start, end, pastedText);
  return BrowserPasteTextReplacement(
    text: nextText,
    selectionOffset: start + pastedText.length,
  );
}

TextEditingValue? recoverBrowserPasteValue({
  required TextEditingValue before,
  required String pastedText,
}) {
  final selection = before.selection;
  if (!selection.isValid) return null;

  final replacement = recoverBrowserPasteText(
    beforeText: before.text,
    selectionStart: selection.start,
    selectionEnd: selection.end,
    pastedText: pastedText,
  );
  if (replacement == null) return null;

  return before.copyWith(
    text: replacement.text,
    selection: TextSelection.collapsed(offset: replacement.selectionOffset),
    composing: TextRange.empty,
  );
}
