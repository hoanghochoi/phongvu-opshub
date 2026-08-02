import 'payment_amount_audio_composer_types.dart';

PaymentAmountAudioComposer createPaymentAmountAudioComposer() =>
    const _UnsupportedPaymentAmountAudioComposer();

class _UnsupportedPaymentAmountAudioComposer
    implements PaymentAmountAudioComposer {
  const _UnsupportedPaymentAmountAudioComposer();

  @override
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
    required String voicePresetId,
  }) {
    throw UnsupportedError(
      'Offline payment audio is supported on Windows only',
    );
  }
}
