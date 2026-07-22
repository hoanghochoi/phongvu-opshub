class PaymentNotification {
  final String notificationId;
  final String transactionId;
  final String storeCode;
  final int amount;
  final String? audioUrl;
  final String? streamUrl;
  final String? currency;
  final String? assetPackVersion;
  final String? playbackMode;
  final String audioStatus;
  final DateTime? paidAt;
  final DateTime? firstSeenAt;
  final DateTime? createdAt;

  const PaymentNotification({
    required this.notificationId,
    required this.transactionId,
    required this.storeCode,
    required this.amount,
    required this.audioUrl,
    required this.streamUrl,
    this.currency,
    this.assetPackVersion,
    this.playbackMode,
    required this.audioStatus,
    required this.paidAt,
    required this.firstSeenAt,
    required this.createdAt,
  });

  factory PaymentNotification.fromJson(Map<String, dynamic> json) {
    return PaymentNotification(
      notificationId: json['notificationId']?.toString() ?? '',
      transactionId: json['transactionId']?.toString() ?? '',
      storeCode: json['storeCode']?.toString() ?? '',
      amount: _readAmount(json['amount']),
      audioUrl: json['audioUrl']?.toString(),
      streamUrl: json['streamUrl']?.toString(),
      currency: json['currency']?.toString(),
      assetPackVersion: json['assetPackVersion']?.toString(),
      playbackMode: json['playbackMode']?.toString(),
      audioStatus: json['audioStatus']?.toString() ?? 'FAILED',
      paidAt: DateTime.tryParse(json['paidAt']?.toString() ?? ''),
      firstSeenAt: DateTime.tryParse(json['firstSeenAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  bool get isValid =>
      notificationId.isNotEmpty && storeCode.isNotEmpty && amount > 0;

  bool get requestsLocalAssetPlayback =>
      currency?.trim().toUpperCase() == 'VND' &&
      playbackMode?.trim().toUpperCase() == 'LOCAL_ASSET' &&
      (assetPackVersion?.trim().isNotEmpty ?? false);

  static int _readAmount(Object? value) {
    if (value is num) return value.toInt();
    final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized == null || normalized.isEmpty) return 0;
    return int.tryParse(normalized) ?? 0;
  }
}
