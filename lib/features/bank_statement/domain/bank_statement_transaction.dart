class BankStatementTransaction {
  final String id;
  final String storeId;
  final String transactionKey;
  final String transactionNumber;
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

  const BankStatementTransaction({
    required this.id,
    required this.storeId,
    required this.transactionKey,
    required this.transactionNumber,
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
  });

  factory BankStatementTransaction.fromJson(Map<String, dynamic> json) {
    return BankStatementTransaction(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      transactionKey: json['transactionKey']?.toString() ?? '',
      transactionNumber: json['transactionNumber']?.toString() ?? '',
      amount: _readAmount(json['amount']),
      content: json['content']?.toString() ?? '',
      orders: _readOrders(json['orders']),
      orderSource: json['orderSource']?.toString(),
      orderUpdatedAt: _readDate(json['orderUpdatedAt']),
      orderUpdatedByEmail: json['orderUpdatedByEmail']?.toString(),
      status: json['status']?.toString(),
      paidAt: _readDate(json['paidAt']),
      firstSeenAt: _readDate(json['firstSeenAt']),
      payerName: json['payerName']?.toString(),
      payerAccount: json['payerAccount']?.toString(),
    );
  }

  bool get hasOrders => orders.isNotEmpty;
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
    );
  }

  static int _readAmount(Object? value) {
    if (value is num) return value.toInt();
    final normalized = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(normalized ?? '') ?? 0;
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
