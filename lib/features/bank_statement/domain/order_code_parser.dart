enum StatementOrderInputErrorReason { invalidFormat, invalidDatePrefix }

class StatementOrderInputFormatException extends FormatException {
  final StatementOrderInputErrorReason reason;

  const StatementOrderInputFormatException(this.reason)
    : super('Invalid statement order input');
}

List<String> parseStatementOrderInput(String input) {
  final seen = <String>{};
  final output = <String>[];
  for (final token in input.split(RegExp(r'[\s,;]+'))) {
    final value = token.trim();
    if (value.isEmpty || seen.contains(value)) continue;
    if (!RegExp(r'^\d{14}$').hasMatch(value)) {
      throw const StatementOrderInputFormatException(
        StatementOrderInputErrorReason.invalidFormat,
      );
    }
    if (!_hasValidStatementOrderDatePrefix(value)) {
      throw const StatementOrderInputFormatException(
        StatementOrderInputErrorReason.invalidDatePrefix,
      );
    }
    seen.add(value);
    output.add(value);
  }
  return output;
}

bool isValidStatementOrderCode(String value) {
  if (!RegExp(r'^\d{14}$').hasMatch(value)) return false;
  return _hasValidStatementOrderDatePrefix(value);
}

bool _hasValidStatementOrderDatePrefix(String value) {
  final year = 2000 + int.parse(value.substring(0, 2));
  final month = int.parse(value.substring(2, 4));
  final day = int.parse(value.substring(4, 6));
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
