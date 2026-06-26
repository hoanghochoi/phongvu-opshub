class VietQrBrand {
  final String key;
  final String title;
  final String logoKey;
  final String logoAsset;

  const VietQrBrand({
    required this.key,
    required this.title,
    required this.logoKey,
    required this.logoAsset,
  });

  static const fallback = VietQrBrand(
    key: 'phongvu',
    title: 'Phong Vũ',
    logoKey: 'phongvu',
    logoAsset: 'assets/icon/source/app_icon_master.png',
  );

  factory VietQrBrand.fromJson(Object? value) {
    if (value is! Map) return fallback;
    return VietQrBrand(
      key: _readText(value['key'], fallback.key),
      title: _readText(value['title'], fallback.title),
      logoKey: _readText(value['logoKey'], fallback.logoKey),
      logoAsset: _readText(value['logoAsset'], fallback.logoAsset),
    );
  }

  static String _readText(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class VietQrTransfer {
  final String id;
  final String bankBin;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final int? amount;
  final String transferContent;
  final String qrPayload;
  final String status;
  final VietQrBrand qrBrand;

  const VietQrTransfer({
    required this.id,
    required this.bankBin,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.amount,
    required this.transferContent,
    required this.qrPayload,
    required this.status,
    this.qrBrand = VietQrBrand.fallback,
  });

  factory VietQrTransfer.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    return VietQrTransfer(
      id: json['id'] as String? ?? '',
      bankBin: json['bankBin'] as String? ?? '',
      bankName: json['bankName'] as String? ?? json['bankBin'] as String? ?? '',
      accountNumber: json['accountNumber'] as String? ?? '',
      accountName: json['accountName'] as String? ?? '',
      amount: rawAmount is num ? rawAmount.toInt() : null,
      transferContent: json['transferContent'] as String? ?? '',
      qrPayload: json['qrPayload'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      qrBrand: VietQrBrand.fromJson(json['qrBrand']),
    );
  }
}

class VietQrPaymentConfirmation {
  final String id;
  final String status;
  final bool confirmed;
  final String reason;
  final String? matchedTransactionNumber;
  final int? matchedAmount;
  final DateTime? matchedTranTime;
  final String? matchedPayerName;
  final String? matchedPayerAccount;
  final String? matchedTransactionContent;
  final DateTime? confirmedAt;

  const VietQrPaymentConfirmation({
    required this.id,
    required this.status,
    required this.confirmed,
    required this.reason,
    this.matchedTransactionNumber,
    this.matchedAmount,
    this.matchedTranTime,
    this.matchedPayerName,
    this.matchedPayerAccount,
    this.matchedTransactionContent,
    this.confirmedAt,
  });

  factory VietQrPaymentConfirmation.fromJson(Map<String, dynamic> json) {
    return VietQrPaymentConfirmation(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      confirmed: json['confirmed'] == true,
      reason: json['reason'] as String? ?? '',
      matchedTransactionNumber: json['matchedTransactionNumber'] as String?,
      matchedAmount: json['matchedAmount'] is num
          ? (json['matchedAmount'] as num).toInt()
          : null,
      matchedTranTime: _parseDateTime(json['matchedTranTime']),
      matchedPayerName: _parseString(json['matchedPayerName']),
      matchedPayerAccount: _parseString(json['matchedPayerAccount']),
      matchedTransactionContent: _parseString(
        json['matchedTransactionContent'],
      ),
      confirmedAt: _parseDateTime(json['confirmedAt']),
    );
  }

  String? get matchedStatementNumber => _parseString(matchedTransactionNumber);

  static String? _parseString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
