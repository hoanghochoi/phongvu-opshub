import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat vietnameseMoneyNumberFormat = NumberFormat.decimalPattern(
  'vi_VN',
);
final NumberFormat _compactMoneyNumberFormat = NumberFormat('#,##0.#', 'vi_VN');

int? parseMoneyAmount(Object? value) {
  if (value == null) return null;
  if (value is num) return value.round();
  final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

String formatVndAmount(Object? value) {
  final amount = parseMoneyAmount(value);
  if (amount == null) return '';
  return '${vietnameseMoneyNumberFormat.format(amount)} VND';
}

String formatCompactVndAmount(Object? value) {
  final amount = parseMoneyAmount(value);
  if (amount == null) return '';
  final absoluteAmount = amount.abs();
  if (absoluteAmount >= 999500000) {
    return '${_compactMoneyNumberFormat.format(amount / 1000000000)}B VND';
  }
  if (absoluteAmount >= 1000000) {
    return '${_compactMoneyNumberFormat.format(amount / 1000000)}M VND';
  }
  return formatVndAmount(amount);
}

class VietnameseThousandsSeparatorInputFormatter extends TextInputFormatter {
  VietnameseThousandsSeparatorInputFormatter({NumberFormat? formatter})
    : formatter = formatter ?? vietnameseMoneyNumberFormat;

  final NumberFormat formatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final cleanString = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanString.isEmpty) {
      return newValue.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    final intValue = int.tryParse(cleanString);
    if (intValue == null) return oldValue;

    final formatted = formatter.format(intValue);
    var digitCountBeforeCursor = 0;
    for (var i = 0; i < newValue.selection.end; i++) {
      if (RegExp(r'[0-9]').hasMatch(newValue.text[i])) {
        digitCountBeforeCursor++;
      }
    }

    var newOffset = 0;
    var digitCount = 0;
    while (newOffset < formatted.length &&
        digitCount < digitCountBeforeCursor) {
      if (RegExp(r'[0-9]').hasMatch(formatted[newOffset])) {
        digitCount++;
      }
      newOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
