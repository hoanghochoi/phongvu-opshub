import 'payment_speaker_types.dart';

class PaymentSpeaker {
  Future<PaymentSpeakerResult> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
    required String notificationId,
    required String transactionId,
    required String storeCode,
    required String clientId,
    required int attempt,
    bool playLocalCue = true,
    bool playLocalCuePrefix = false,
    Future<void> Function()? onPlaybackStarting,
  }) async {
    if (onPlaybackStarting != null) {
      await onPlaybackStarting();
    }
    return const PaymentSpeakerResult(
      backend: 'stub',
      extension: 'wav',
      durationMs: 0,
      reportedSuccess: true,
      audibleVerified: false,
    );
  }
}
