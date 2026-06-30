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
  final DateTime createdAt;
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
    required this.createdAt,
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
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      qrBrand: VietQrBrand.fromJson(json['qrBrand']),
    );
  }

  DateTime get expiresAt => createdAt.add(const Duration(minutes: 15));

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bankBin': bankBin,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountName': accountName,
      'amount': amount,
      'transferContent': transferContent,
      'qrPayload': qrPayload,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'qrBrand': {
        'key': qrBrand.key,
        'title': qrBrand.title,
        'logoKey': qrBrand.logoKey,
        'logoAsset': qrBrand.logoAsset,
      },
    };
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'confirmed': confirmed,
      'reason': reason,
      'matchedTransactionNumber': matchedTransactionNumber,
      'matchedAmount': matchedAmount,
      'matchedTranTime': matchedTranTime?.toIso8601String(),
      'matchedPayerName': matchedPayerName,
      'matchedPayerAccount': matchedPayerAccount,
      'matchedTransactionContent': matchedTransactionContent,
      'confirmedAt': confirmedAt?.toIso8601String(),
    };
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

class VietQrHistoryEntry {
  final String storeCode;
  final VietQrTransfer transfer;
  final VietQrPaymentConfirmation? confirmation;

  const VietQrHistoryEntry({
    required this.storeCode,
    required this.transfer,
    this.confirmation,
  });

  String get paymentId => transfer.id;

  VietQrHistoryEntry copyWith({
    String? storeCode,
    VietQrTransfer? transfer,
    VietQrPaymentConfirmation? confirmation,
  }) {
    return VietQrHistoryEntry(
      storeCode: storeCode ?? this.storeCode,
      transfer: transfer ?? this.transfer,
      confirmation: confirmation ?? this.confirmation,
    );
  }

  DateTime get createdAt => transfer.createdAt;

  DateTime get expiresAt => transfer.expiresAt;

  bool isExpired(DateTime now) {
    return !now.isBefore(expiresAt);
  }

  bool get hasConfirmation => confirmation != null;

  bool get isConfirmed => confirmation?.confirmed == true;

  bool canOpenQr(DateTime now) {
    return !isExpired(now);
  }

  VietQrTransfer asTransfer() => transfer;

  VietQrPaymentConfirmation? asConfirmation(DateTime now) {
    if (confirmation != null) return confirmation;
    if (!isExpired(now)) return null;
    return VietQrPaymentConfirmation(
      id: transfer.id,
      status: 'FAILED',
      confirmed: false,
      reason: 'EXPIRED_VIETNAM_15M',
      confirmedAt: null,
    );
  }

  String statusCode(DateTime now) {
    final currentConfirmation = confirmation;
    if (currentConfirmation != null) {
      if (currentConfirmation.confirmed) return 'PAID';
      final reason = currentConfirmation.reason.toUpperCase();
      if (reason == 'EXPIRED_VIETNAM_15M' || reason == 'EXPIRED_VIETNAM_DAY') {
        return 'EXPIRED';
      }
      return currentConfirmation.status.toUpperCase();
    }
    if (isExpired(now)) return 'EXPIRED';
    return transfer.status.trim().isEmpty
        ? 'PENDING'
        : transfer.status.trim().toUpperCase();
  }

  String statusReason(DateTime now) {
    final currentConfirmation = confirmation;
    if (currentConfirmation != null) {
      return currentConfirmation.reason.trim().toUpperCase();
    }
    if (isExpired(now)) return 'EXPIRED_VIETNAM_15M';
    return transfer.status.trim().toUpperCase();
  }

  Map<String, dynamic> toJson() {
    return {
      'storeCode': storeCode,
      'transfer': transfer.toJson(),
      if (confirmation != null) 'confirmation': confirmation!.toJson(),
    };
  }

  factory VietQrHistoryEntry.fromJson(Map<String, dynamic> json) {
    return VietQrHistoryEntry(
      storeCode: (json['storeCode']?.toString().trim().isNotEmpty ?? false)
          ? json['storeCode'].toString().trim().toUpperCase()
          : '',
      transfer: VietQrTransfer.fromJson(
        Map<String, dynamic>.from(json['transfer'] as Map? ?? const {}),
      ),
      confirmation: json['confirmation'] is Map
          ? VietQrPaymentConfirmation.fromJson(
              Map<String, dynamic>.from(json['confirmation'] as Map),
            )
          : null,
    );
  }
}
