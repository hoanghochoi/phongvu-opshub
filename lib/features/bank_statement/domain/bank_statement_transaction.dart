const bankStatementMissingOrderText = 'Chưa có mã đơn';

String statementOrdersText(List<String> orders) =>
    orders.isEmpty ? bankStatementMissingOrderText : orders.join(', ');

class BankStatementTransaction {
  final String id;
  final String storeId;
  final String transactionKey;
  final String transactionNumber;
  final String? transactionReference;
  final int amount;
  final String content;
  final List<String> orders;
  final String? orderSource;
  final DateTime? orderUpdatedAt;
  final String? orderUpdatedByEmail;
  final String? status;
  final DateTime? paidAt;
  final DateTime? firstSeenAt;
  final String? payerName;
  final String? payerAccount;
  final String incomeType;
  final String? receivingAccount;
  final bool canEditOrders;
  final String? orderEditBlockedReason;
  final bool canRequestOrderTransfer;
  final String? orderTransferRequestBlockedReason;
  final bool hasPendingOrderTransferRequest;
  final String? orderTransferRequestId;
  final List<String> orderTransferRequestedOrders;
  final String? orderTransferRequestedByEmail;
  final DateTime? orderTransferRequestedAt;
  final String? orderTransferReviewNote;
  final String? orderTransferStatus;
  final bool isOrderOffsetConfirmed;

  const BankStatementTransaction({
    required this.id,
    required this.storeId,
    required this.transactionKey,
    required this.transactionNumber,
    this.transactionReference,
    required this.amount,
    required this.content,
    required this.orders,
    required this.orderSource,
    required this.orderUpdatedAt,
    required this.orderUpdatedByEmail,
    required this.status,
    required this.paidAt,
    required this.firstSeenAt,
    required this.payerName,
    required this.payerAccount,
    this.incomeType = 'SALES',
    this.receivingAccount,
    required this.canEditOrders,
    required this.orderEditBlockedReason,
    required this.canRequestOrderTransfer,
    required this.orderTransferRequestBlockedReason,
    required this.hasPendingOrderTransferRequest,
    required this.orderTransferRequestId,
    required this.orderTransferRequestedOrders,
    required this.orderTransferRequestedByEmail,
    required this.orderTransferRequestedAt,
    required this.orderTransferReviewNote,
    required this.orderTransferStatus,
    required this.isOrderOffsetConfirmed,
  });

  factory BankStatementTransaction.fromJson(Map<String, dynamic> json) {
    return BankStatementTransaction(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      transactionKey: json['transactionKey']?.toString() ?? '',
      transactionNumber: json['transactionNumber']?.toString() ?? '',
      transactionReference: _readFirstText(json, const [
        'transactionReference',
        'txnReference',
      ]),
      amount: _readAmount(json['amount']),
      content: json['content']?.toString() ?? '',
      orders: _readOrders(json['orders']),
      orderSource: json['orderSource']?.toString(),
      orderUpdatedAt: _readDate(json['orderUpdatedAt']),
      orderUpdatedByEmail: json['orderUpdatedByEmail']?.toString(),
      status: json['status']?.toString(),
      paidAt: _readDate(json['paidAt']),
      firstSeenAt: _readDate(json['firstSeenAt']),
      canEditOrders: json['canEditOrders'] != false,
      orderEditBlockedReason: json['orderEditBlockedReason']?.toString(),
      canRequestOrderTransfer: json['canRequestOrderTransfer'] == true,
      orderTransferRequestBlockedReason:
          json['orderTransferRequestBlockedReason']?.toString(),
      hasPendingOrderTransferRequest:
          json['hasPendingOrderTransferRequest'] == true,
      orderTransferRequestId: json['orderTransferRequestId']?.toString(),
      orderTransferRequestedOrders: _readOrders(
        json['orderTransferRequestedOrders'],
      ),
      orderTransferRequestedByEmail: json['orderTransferRequestedByEmail']
          ?.toString(),
      orderTransferRequestedAt: _readDate(json['orderTransferRequestedAt']),
      orderTransferReviewNote: json['orderTransferReviewNote']?.toString(),
      orderTransferStatus: json['orderTransferStatus']?.toString(),
      isOrderOffsetConfirmed: json['isOrderOffsetConfirmed'] == true,
      payerName: _readFirstText(json, const [
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
      ]),
      payerAccount: _readFirstText(json, const [
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
      ]),
      incomeType:
          json['incomeType']?.toString().trim().toUpperCase() ==
              'PARTNER_INTERNAL'
          ? 'PARTNER_INTERNAL'
          : 'SALES',
      receivingAccount: _readFirstText(json, const [
        'receivingAccount',
        'receiveAccount',
        'receiveAccountNo',
      ]),
    );
  }

  bool get hasOrders => orders.isNotEmpty;
  bool get isPartnerInternal => incomeType == 'PARTNER_INTERNAL';
  String get incomeTypeLabel =>
      isPartnerInternal ? 'Đối tác/Nội bộ' : 'Bán hàng';
  String get statementNumber {
    final reference = transactionReference?.trim() ?? '';
    if (reference.isNotEmpty) return reference;
    return transactionNumber.trim();
  }

  String get payerLabel => [
    payerName?.trim() ?? '',
    payerAccount?.trim() ?? '',
  ].where((value) => value.isNotEmpty).join(' • ');

  BankStatementTransaction copyWith({List<String>? orders}) {
    return BankStatementTransaction(
      id: id,
      storeId: storeId,
      transactionKey: transactionKey,
      transactionNumber: transactionNumber,
      transactionReference: transactionReference,
      amount: amount,
      content: content,
      orders: orders ?? this.orders,
      orderSource: orderSource,
      orderUpdatedAt: orderUpdatedAt,
      orderUpdatedByEmail: orderUpdatedByEmail,
      status: status,
      paidAt: paidAt,
      firstSeenAt: firstSeenAt,
      payerName: payerName,
      payerAccount: payerAccount,
      incomeType: incomeType,
      receivingAccount: receivingAccount,
      canEditOrders: canEditOrders,
      orderEditBlockedReason: orderEditBlockedReason,
      canRequestOrderTransfer: canRequestOrderTransfer,
      orderTransferRequestBlockedReason: orderTransferRequestBlockedReason,
      hasPendingOrderTransferRequest: hasPendingOrderTransferRequest,
      orderTransferRequestId: orderTransferRequestId,
      orderTransferRequestedOrders: orderTransferRequestedOrders,
      orderTransferRequestedByEmail: orderTransferRequestedByEmail,
      orderTransferRequestedAt: orderTransferRequestedAt,
      orderTransferReviewNote: orderTransferReviewNote,
      orderTransferStatus: orderTransferStatus,
      isOrderOffsetConfirmed: isOrderOffsetConfirmed,
    );
  }

  static int _readAmount(Object? value) {
    if (value is num) return value.toInt();
    final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(normalized ?? '') ?? 0;
  }

  static String? _readFirstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final text = json[key]?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static DateTime? _readDate(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
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

class BankStatementOrderHistoryEntry {
  final String id;
  final List<String> oldOrders;
  final List<String> newOrders;
  final String? changedByEmail;
  final DateTime? createdAt;

  const BankStatementOrderHistoryEntry({
    required this.id,
    required this.oldOrders,
    required this.newOrders,
    required this.changedByEmail,
    required this.createdAt,
  });

  factory BankStatementOrderHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BankStatementOrderHistoryEntry(
      id: json['id']?.toString() ?? '',
      oldOrders: BankStatementTransaction._readOrders(json['oldOrders']),
      newOrders: BankStatementTransaction._readOrders(json['newOrders']),
      changedByEmail: json['changedByEmail']?.toString(),
      createdAt: BankStatementTransaction._readDate(json['createdAt']),
    );
  }
}

class BankStatementOrderTransferRequest {
  final String id;
  final String transactionId;
  final String storeCode;
  final List<String> oldOrders;
  final List<String> requestedOrders;
  final String status;
  final String? requestedByEmail;
  final String? reviewedByEmail;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final String? transactionNumber;
  final String? transactionReference;
  final int amount;
  final String content;
  final DateTime? paidAt;
  final DateTime? firstSeenAt;
  final DateTime? notificationReadAt;

  const BankStatementOrderTransferRequest({
    required this.id,
    required this.transactionId,
    required this.storeCode,
    required this.oldOrders,
    required this.requestedOrders,
    required this.status,
    required this.requestedByEmail,
    required this.reviewedByEmail,
    required this.reviewNote,
    required this.reviewedAt,
    required this.createdAt,
    required this.transactionNumber,
    required this.transactionReference,
    required this.amount,
    required this.content,
    required this.paidAt,
    required this.firstSeenAt,
    this.notificationReadAt,
  });

  factory BankStatementOrderTransferRequest.fromJson(
    Map<String, dynamic> json,
  ) {
    return BankStatementOrderTransferRequest(
      id: json['id']?.toString() ?? '',
      transactionId: json['transactionId']?.toString() ?? '',
      storeCode: json['storeCode']?.toString() ?? '',
      oldOrders: BankStatementTransaction._readOrders(json['oldOrders']),
      requestedOrders: BankStatementTransaction._readOrders(
        json['requestedOrders'],
      ),
      status: json['status']?.toString() ?? '',
      requestedByEmail: json['requestedByEmail']?.toString(),
      reviewedByEmail: json['reviewedByEmail']?.toString(),
      reviewNote: json['reviewNote']?.toString(),
      reviewedAt: BankStatementTransaction._readDate(json['reviewedAt']),
      createdAt: BankStatementTransaction._readDate(json['createdAt']),
      transactionNumber: json['transactionNumber']?.toString(),
      transactionReference: BankStatementTransaction._readFirstText(
        json,
        const ['transactionReference', 'txnReference'],
      ),
      amount: BankStatementTransaction._readAmount(json['amount']),
      content: json['content']?.toString() ?? '',
      paidAt: BankStatementTransaction._readDate(json['paidAt']),
      firstSeenAt: BankStatementTransaction._readDate(json['firstSeenAt']),
      notificationReadAt: BankStatementTransaction._readDate(
        json['notificationReadAt'],
      ),
    );
  }

  String get statementNumber {
    final reference = transactionReference?.trim() ?? '';
    if (reference.isNotEmpty) return reference;
    return transactionNumber?.trim() ?? '';
  }
}
