class PaymentSpeakerResult {
  final String backend;
  final String extension;
  final int durationMs;
  final bool reportedSuccess;
  final bool audibleVerified;
  final bool normalized;
  final int? sampleRateHz;
  final int? channels;
  final int? bitsPerSample;
  final String? audioPreflightStatus;

  const PaymentSpeakerResult({
    required this.backend,
    required this.extension,
    required this.durationMs,
    required this.reportedSuccess,
    required this.audibleVerified,
    this.normalized = false,
    this.sampleRateHz,
    this.channels,
    this.bitsPerSample,
    this.audioPreflightStatus,
  });

  PaymentSpeakerResult copyWith({
    String? backend,
    String? extension,
    int? durationMs,
    bool? reportedSuccess,
    bool? audibleVerified,
    bool? normalized,
    int? sampleRateHz,
    int? channels,
    int? bitsPerSample,
    String? audioPreflightStatus,
  }) {
    return PaymentSpeakerResult(
      backend: backend ?? this.backend,
      extension: extension ?? this.extension,
      durationMs: durationMs ?? this.durationMs,
      reportedSuccess: reportedSuccess ?? this.reportedSuccess,
      audibleVerified: audibleVerified ?? this.audibleVerified,
      normalized: normalized ?? this.normalized,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      channels: channels ?? this.channels,
      bitsPerSample: bitsPerSample ?? this.bitsPerSample,
      audioPreflightStatus: audioPreflightStatus ?? this.audioPreflightStatus,
    );
  }
}

class PaymentSpeakerException implements Exception {
  final String message;
  final List<String> backendErrors;
  final bool retryable;

  const PaymentSpeakerException(
    this.message, {
    this.backendErrors = const [],
    this.retryable = true,
  });

  @override
  String toString() {
    if (backendErrors.isEmpty) {
      return message;
    }
    return '$message (${backendErrors.join(' | ')})';
  }
}
