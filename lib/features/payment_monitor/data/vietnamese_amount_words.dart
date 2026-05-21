const _smallNumbers = [
  '',
  'một',
  'hai',
  'ba',
  'bốn',
  'năm',
  'sáu',
  'bảy',
  'tám',
  'chín',
];

const _groupUnits = ['', 'nghìn', 'triệu', 'tỷ', 'nghìn tỷ', 'triệu tỷ'];

String vietnameseAmountWords(int amount) {
  if (amount <= 0) return amount.toString();

  final groups = <int>[];
  var remaining = amount;
  while (remaining > 0) {
    groups.add(remaining % 1000);
    remaining ~/= 1000;
  }

  final highestGroupIndex = groups.lastIndexWhere((group) => group > 0);
  final parts = <String>[];
  for (var index = highestGroupIndex; index >= 0; index -= 1) {
    final group = groups[index];
    if (group == 0) continue;
    final words = _readThreeDigits(
      group,
      forceHundreds: index < highestGroupIndex,
    );
    final unit = index < _groupUnits.length ? _groupUnits[index] : '';
    parts.add([words, unit].where((part) => part.isNotEmpty).join(' '));
  }

  return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _readThreeDigits(int value, {required bool forceHundreds}) {
  final hundred = value ~/ 100;
  final ten = (value % 100) ~/ 10;
  final unit = value % 10;
  final parts = <String>[];

  if (hundred > 0) {
    parts.add('${_smallNumbers[hundred]} trăm');
  } else if (forceHundreds && (ten > 0 || unit > 0)) {
    parts.add('không trăm');
  }

  if (ten > 1) {
    parts.add('${_smallNumbers[ten]} mươi');
    if (unit > 0) parts.add(_readUnitAfterTen(unit));
  } else if (ten == 1) {
    parts.add('mười');
    if (unit > 0) parts.add(unit == 5 ? 'lăm' : _smallNumbers[unit]);
  } else if (unit > 0) {
    if (hundred > 0 || forceHundreds) parts.add('lẻ');
    parts.add(_smallNumbers[unit]);
  }

  return parts.join(' ');
}

String _readUnitAfterTen(int unit) {
  if (unit == 1) return 'mốt';
  if (unit == 4) return 'tư';
  if (unit == 5) return 'lăm';
  return _smallNumbers[unit];
}
