class PaymentSpeakerResult {
  final String backend;
  final String extension;
  final int durationMs;
  final bool reportedSuccess;
  final bool audibleVerified;

  const PaymentSpeakerResult({
    required this.backend,
    required this.extension,
    required this.durationMs,
    required this.reportedSuccess,
    required this.audibleVerified,
  });
}

class PaymentSpeakerException implements Exception {
  final String message;
  final List<String> backendErrors;

  const PaymentSpeakerException(this.message, {this.backendErrors = const []});

  @override
  String toString() {
    if (backendErrors.isEmpty) {
      return message;
    }
    return '$message (${backendErrors.join(' | ')})';
  }
}
