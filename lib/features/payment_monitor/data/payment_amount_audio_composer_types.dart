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
