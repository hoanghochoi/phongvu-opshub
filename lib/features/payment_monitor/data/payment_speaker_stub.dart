class PaymentSpeaker {
  Future<void> speakAmount(int amount) async {}

  Future<void> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
  }) async {}
}
