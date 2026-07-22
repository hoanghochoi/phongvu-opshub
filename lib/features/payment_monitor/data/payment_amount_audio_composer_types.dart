import 'dart:typed_data';

const paymentAmountAudioPackVersion = 'ngoc-linh-chunk-v4';

class PaymentAmountAudioResult {
  final Uint8List bytes;
  final List<String> assetIds;
  final int composeDurationMs;

  const PaymentAmountAudioResult({
    required this.bytes,
    required this.assetIds,
    required this.composeDurationMs,
  });
}

abstract class PaymentAmountAudioComposer {
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
  });
}

List<String> paymentAmountChunkAssetIds(int amount) {
  if (amount <= 0 || amount > 999999999999999999) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Amount is outside the supported VND range',
    );
  }
  const units = ['', 'nghìn', 'triệu', 'tỷ', 'nghìn tỷ', 'triệu tỷ'];
  final groups = <int>[];
  var remaining = amount;
  while (remaining > 0) {
    groups.add(remaining % 1000);
    remaining ~/= 1000;
  }
  if (groups.length > units.length) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Amount has too many three-digit groups',
    );
  }

  final highest = groups.length - 1;
  final ids = <String>[];
  for (var index = highest; index >= 0; index -= 1) {
    final value = groups[index];
    if (value == 0) continue;
    final role = index < highest && value < 100 ? 'forced' : 'leading';
    ids.add('chunk/$role/${value.toString().padLeft(3, '0')}');
    final unit = units[index];
    if (unit.isNotEmpty) {
      ids.addAll(unit.split(' ').map((part) => 'chunk/unit/$part'));
    }
  }
  ids.add('chunk/unit/đồng');
  return List.unmodifiable(ids);
}
