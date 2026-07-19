import 'package:flutter/widgets.dart';

TextEditingValue? recoverBrowserPasteValue({
  required TextEditingValue before,
  required String pastedText,
}) {
  final selection = before.selection;
  if (!selection.isValid || !selection.isNormalized) return null;

  final nextText = before.text.replaceRange(
    selection.start,
    selection.end,
    pastedText,
  );
  final nextOffset = selection.start + pastedText.length;
  return before.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: TextRange.empty,
  );
}
