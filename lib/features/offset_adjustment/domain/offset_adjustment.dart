class OffsetAdjustmentType {
  static const singleOrder = 'SINGLE_ORDER';
  static const vnpayQroff = 'VNPAY_QROFF';
  static const zaloPay = 'ZALOPAY';
  static const shopeePay = 'SHOPEEPAY';

  static const values = [singleOrder, vnpayQroff, zaloPay, shopeePay];

  static String label(String type) {
    return switch (type) {
      singleOrder => 'Cấn trừ đơn',
      vnpayQroff => 'VNPAY QROFF',
      zaloPay => 'Zalo Pay',
      shopeePay => 'Shopee Pay',
      _ => type,
    };
  }
}

class OffsetAdjustmentStatus {
  static const pending = 'PENDING_ACC';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED_NEEDS_FIX';

  static String label(String status) {
    return switch (status) {
      pending => 'Chờ Kế toán xác nhận',
      approved => 'Kế toán đã xác nhận',
      rejected => 'Kế toán từ chối chờ sửa',
      _ => status,
    };
  }
}

class OffsetEditContentKind {
  static const customer = 'CUSTOMER_OFFSET';
  static const technician = 'TECHNICIAN_OFFSET';

  static const values = [customer, technician];

  static String label(String kind) {
    return switch (kind) {
      customer => 'Cấn trừ KH',
      technician => 'Cấn trừ KTV',
      _ => kind,
    };
  }
}

class OffsetAdjustment {
  final String id;
  final String type;
  final String status;
  final String storeCode;
  final String? oldOrderCode;
  final String? newOrderCode;
  final String? orderCode;
  final String? scanDate;
  final String? editContentKind;
  final String? transactionCode;
  final int amount;
  final String? note;
  final String? ctCode;
  final String? rejectReason;
  final String? createdByEmail;
  final String? reviewedByEmail;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final int? singleOrderReuseCount;
  final bool canReview;
  final bool canResubmit;

  const OffsetAdjustment({
    required this.id,
    required this.type,
    required this.status,
    required this.storeCode,
    required this.oldOrderCode,
    required this.newOrderCode,
    required this.orderCode,
    required this.scanDate,
    required this.editContentKind,
    required this.transactionCode,
    required this.amount,
    required this.note,
    required this.ctCode,
    required this.rejectReason,
    required this.createdByEmail,
    required this.reviewedByEmail,
    required this.submittedAt,
    required this.reviewedAt,
    required this.singleOrderReuseCount,
    required this.canReview,
    required this.canResubmit,
  });

  factory OffsetAdjustment.fromJson(Map<String, dynamic> json) {
    return OffsetAdjustment(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      storeCode: json['storeCode']?.toString() ?? '',
      oldOrderCode: _text(json['oldOrderCode']),
      newOrderCode: _text(json['newOrderCode']),
      orderCode: _text(json['orderCode']),
      scanDate: _text(json['scanDate']),
      editContentKind: _text(json['editContentKind']),
      transactionCode: _text(json['transactionCode']),
      amount: _amount(json['amount']),
      note: _text(json['note']),
      ctCode: _text(json['ctCode']),
      rejectReason: _text(json['rejectReason']),
      createdByEmail: _text(json['createdByEmail']),
      reviewedByEmail: _text(json['reviewedByEmail']),
      submittedAt: _date(json['submittedAt']),
      reviewedAt: _date(json['reviewedAt']),
      singleOrderReuseCount: json['singleOrderReuseCount'] == null
          ? null
          : int.tryParse(json['singleOrderReuseCount'].toString()),
      canReview: json['canReview'] == true,
      canResubmit: json['canResubmit'] == true,
    );
  }

  bool get isSingleOrder => type == OffsetAdjustmentType.singleOrder;

  String get primaryOrderLabel {
    if (isSingleOrder) {
      return [
        oldOrderCode ?? '',
        newOrderCode ?? '',
      ].where((item) => item.isNotEmpty).join(' -> ');
    }
    return orderCode ?? '';
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _amount(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(
          value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '',
        ) ??
        0;
  }

  static DateTime? _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}

class OffsetAdjustmentInput {
  final String type;
  final int amount;
  final String? oldOrderCode;
  final String? newOrderCode;
  final String? orderCode;
  final String? scanDate;
  final String? editContentKind;
  final String? transactionCode;
  final String? note;

  const OffsetAdjustmentInput({
    required this.type,
    required this.amount,
    this.oldOrderCode,
    this.newOrderCode,
    this.orderCode,
    this.scanDate,
    this.editContentKind,
    this.transactionCode,
    this.note,
  });

  Map<String, dynamic> toJson({bool includeType = true}) {
    return {
      if (includeType) 'type': type,
      'amount': amount,
      if (_hasText(oldOrderCode)) 'oldOrderCode': oldOrderCode!.trim(),
      if (_hasText(newOrderCode)) 'newOrderCode': newOrderCode!.trim(),
      if (_hasText(orderCode)) 'orderCode': orderCode!.trim(),
      if (_hasText(scanDate)) 'scanDate': scanDate!.trim(),
      if (_hasText(editContentKind)) 'editContentKind': editContentKind!.trim(),
      if (_hasText(transactionCode)) 'transactionCode': transactionCode!.trim(),
      if (_hasText(note)) 'note': note!.trim(),
    };
  }

  static bool _hasText(String? value) => (value ?? '').trim().isNotEmpty;
}
