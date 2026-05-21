class PaymentNotification {
  final String notificationId;
  final String transactionId;
  final String storeCode;
  final int amount;
  final String? audioUrl;
  final String audioStatus;
  final DateTime? createdAt;

  const PaymentNotification({
    required this.notificationId,
    required this.transactionId,
    required this.storeCode,
    required this.amount,
    required this.audioUrl,
    required this.audioStatus,
    required this.createdAt,
  });

  factory PaymentNotification.fromJson(Map<String, dynamic> json) {
    return PaymentNotification(
      notificationId: json['notificationId']?.toString() ?? '',
      transactionId: json['transactionId']?.toString() ?? '',
      storeCode: json['storeCode']?.toString() ?? '',
      amount: _readAmount(json['amount']),
      audioUrl: json['audioUrl']?.toString(),
      audioStatus: json['audioStatus']?.toString() ?? 'FAILED',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  bool get isValid =>
      notificationId.isNotEmpty && storeCode.isNotEmpty && amount > 0;

  static int _readAmount(Object? value) {
    if (value is num) return value.toInt();
    final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized == null || normalized.isEmpty) return 0;
    return int.tryParse(normalized) ?? 0;
  }
}
