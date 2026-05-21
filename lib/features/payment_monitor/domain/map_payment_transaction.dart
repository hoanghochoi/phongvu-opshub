class MapPaymentTransaction {
  final String id;
  final int amount;
  final String content;
  final String transactionNumber;
  final DateTime? paidAt;
  final DateTime? firstSeenAt;
  final bool successful;

  const MapPaymentTransaction({
    required this.id,
    required this.amount,
    required this.content,
    required this.transactionNumber,
    required this.paidAt,
    required this.firstSeenAt,
    required this.successful,
  });

  factory MapPaymentTransaction.fromJson(Map<String, dynamic> json) {
    final amount = _readAmount(json);
    final transactionNumber = _readFirstText(json, const [
      'transactionNumber',
      'txnNumber',
      'tranNumber',
      'transactionNo',
      'txnNo',
      'id',
    ]);
    final content = _readFirstText(json, const [
      'transactionDescription',
      'description',
      'content',
      'transferContent',
      'addInfo',
      'additionalInfo',
      'remark',
      'remarks',
      'txnDesc',
      'txnRemark',
      'transactionContent',
      'paymentContent',
    ]);
    final paidAt = _readDate(json);
    final firstSeenAt = _readDate(json, keys: const ['firstSeenAt']);
    final fallbackId = [
      transactionNumber,
      amount?.toString() ?? '',
      paidAt?.toIso8601String() ?? '',
      content,
    ].join('|');

    return MapPaymentTransaction(
      id: transactionNumber.isNotEmpty ? transactionNumber : fallbackId,
      amount: amount ?? 0,
      content: content,
      transactionNumber: transactionNumber,
      paidAt: paidAt,
      firstSeenAt: firstSeenAt,
      successful: _readSuccessful(json),
    );
  }

  bool get isValidIncoming => amount > 0 && successful;

  static int? _readAmount(Map<String, dynamic> json) {
    for (final key in const [
      'amount',
      'txnAmount',
      'transactionAmount',
      'paymentAmount',
      'paidAmount',
      'totalAmount',
      'transAmount',
      'txnAmt',
    ]) {
      final value = json[key];
      if (value is num) return value.toInt();
      final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (normalized != null && normalized.isNotEmpty) {
        return int.tryParse(normalized);
      }
    }
    return null;
  }

  static DateTime? _readDate(
    Map<String, dynamic> json, {
    List<String> keys = const [
      'tranTime',
      'txnDate',
      'transactionDate',
      'transactionTime',
      'paymentDate',
      'createdDate',
      'paidAt',
    ],
  }) {
    final raw = _readFirstText(json, keys);
    if (raw.isEmpty) return null;
    final match = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(raw);
    if (match == null) return DateTime.tryParse(raw);
    return DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
      int.parse(match.group(4) ?? '0'),
      int.parse(match.group(5) ?? '0'),
      int.parse(match.group(6) ?? '0'),
    );
  }

  static bool _readSuccessful(Map<String, dynamic> json) {
    final rawText = [
      'statusText',
      'status',
      'statusName',
      'transactionStatus',
      'transactionStatusName',
      'txnStatus',
      'txnStatusName',
      'paymentStatus',
      'paymentStatusName',
    ].map((key) => json[key]?.toString() ?? '').join(' ');
    final text = _normalize(rawText);
    final upperRawText = rawText.toUpperCase();
    final rawCodes = [
      'status',
      'transactionStatus',
      'txnStatus',
      'paymentStatus',
    ].map((key) => json[key]?.toString().trim().toUpperCase()).toSet();
    return text.contains('THANH CONG') ||
        upperRawText.contains('THÀNH CÔNG') ||
        text.contains('SUCCESS') ||
        text.contains('DA THANH TOAN') ||
        upperRawText.contains('ĐÃ THANH TOÁN') ||
        text.contains('HOAN THANH') ||
        upperRawText.contains('HOÀN THÀNH') ||
        text.contains('COMPLETED') ||
        text.contains('APPROVED') ||
        rawCodes.contains('00');
  }

  static String _normalize(String value) {
    return value
        .toUpperCase()
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll('Đ', 'D')
        .replaceAll(RegExp(r'[^A-Z0-9]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _readFirstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
