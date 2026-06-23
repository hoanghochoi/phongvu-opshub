class MapPaymentTransaction {
  final String id;
  final String storeId;
  final int amount;
  final String content;
  final String transactionNumber;
  final List<String> orders;
  final String status;
  final DateTime? paidAt;
  final DateTime? firstSeenAt;
  final String payerName;
  final String payerAccount;
  final bool successful;

  const MapPaymentTransaction({
    required this.id,
    required this.storeId,
    required this.amount,
    required this.content,
    required this.transactionNumber,
    required this.orders,
    required this.status,
    required this.paidAt,
    required this.firstSeenAt,
    required this.payerName,
    required this.payerAccount,
    required this.successful,
  });

  factory MapPaymentTransaction.fromJson(Map<String, dynamic> json) {
    final amount = _readAmount(json);
    final storeId = _readFirstText(json, const ['storeId', 'storeCode']);
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
    final status = _readFirstText(json, const [
      'statusText',
      'status',
      'statusName',
      'transactionStatus',
      'transactionStatusName',
      'txnStatus',
      'txnStatusName',
      'paymentStatus',
      'paymentStatusName',
    ]);
    final payerName = _readFirstText(json, const [
      'payerName',
      'payerFullName',
      'reqCardName',
      'requestCardName',
      'senderName',
      'senderFullName',
      'fromAccountName',
      'debitAccountName',
      'customerName',
      'buyerName',
    ]);
    final payerAccount = _readFirstText(json, const [
      'payerAccount',
      'payerAccountNo',
      'reqCardNo',
      'requestCardNo',
      'senderAccount',
      'senderAccountNo',
      'fromAccount',
      'fromAccountNo',
      'debitAccount',
      'debitAccountNo',
    ]);
    final paidAt = _readDate(json);
    final firstSeenAt = _readDate(json, keys: const ['firstSeenAt']);
    final orders = _readOrders(json['orders']);
    final fallbackId = [
      transactionNumber,
      amount?.toString() ?? '',
      paidAt?.toIso8601String() ?? '',
      content,
    ].join('|');

    return MapPaymentTransaction(
      id: transactionNumber.isNotEmpty ? transactionNumber : fallbackId,
      storeId: storeId,
      amount: amount ?? 0,
      content: content,
      transactionNumber: transactionNumber,
      orders: orders,
      status: status,
      paidAt: paidAt,
      firstSeenAt: firstSeenAt,
      payerName: payerName,
      payerAccount: payerAccount,
      successful: _readSuccessful(json),
    );
  }

  bool get isValidIncoming => amount > 0 && successful;
  bool get hasOrders => orders.isNotEmpty;
  String get payerLabel =>
      [payerName, payerAccount].where((value) => value.isNotEmpty).join(' • ');

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

  static List<String> _readOrders(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'[\s,;]+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
