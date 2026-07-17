const _unset = Object();

class ContractAppendixItem {
  final int position;
  final String sourceLineKey;
  final String sku;
  final String? sellerSku;
  final String productName;
  final int quantity;
  final String unit;
  final int finalSellPrice;
  final int? vatRateBps;
  final String? taxCode;
  final String? taxLabel;
  final String taxSource;
  final DateTime? taxFetchedAt;
  final int? unitPriceBeforeVat;
  final int? lineBeforeVat;
  final int? lineVatAmount;
  final int? lineAfterVat;

  const ContractAppendixItem({
    required this.position,
    required this.sourceLineKey,
    required this.sku,
    required this.sellerSku,
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.finalSellPrice,
    required this.vatRateBps,
    required this.taxCode,
    required this.taxLabel,
    required this.taxSource,
    required this.taxFetchedAt,
    required this.unitPriceBeforeVat,
    required this.lineBeforeVat,
    required this.lineVatAmount,
    required this.lineAfterVat,
  });

  factory ContractAppendixItem.fromJson(Map<String, dynamic> json) {
    return ContractAppendixItem(
      position: _int(json['position']) ?? 0,
      sourceLineKey: _text(json['sourceLineKey']),
      sku: _text(json['sku']),
      sellerSku: _optionalText(json['sellerSku']),
      productName: _text(json['productName']),
      quantity: _int(json['quantity']) ?? 0,
      unit: _text(json['unit'], fallback: 'Cái'),
      finalSellPrice: _int(json['finalSellPrice']) ?? 0,
      vatRateBps: _int(json['vatRateBps']),
      taxCode: _optionalText(json['taxCode']),
      taxLabel: _optionalText(json['taxLabel']),
      taxSource: _text(json['taxSource'], fallback: 'MISSING'),
      taxFetchedAt: _date(json['taxFetchedAt']),
      unitPriceBeforeVat: _int(json['unitPriceBeforeVat']),
      lineBeforeVat: _int(json['lineBeforeVat']),
      lineVatAmount: _int(json['lineVatAmount']),
      lineAfterVat: _int(json['lineAfterVat']),
    );
  }

  bool get canEnterManualTax => taxSource == 'MISSING' || taxSource == 'MANUAL';

  bool get isTaxMissing => vatRateBps == null || taxSource == 'MISSING';

  String get vatLabel {
    final rate = vatRateBps;
    if (rate == null) return 'Chưa xác định';
    final percent = rate / 100;
    final formatted = percent == percent.roundToDouble()
        ? percent.toInt().toString()
        : percent.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return '$formatted%';
  }

  ContractAppendixItem copyWith({
    String? productName,
    String? unit,
    Object? vatRateBps = _unset,
    Object? taxCode = _unset,
    Object? taxLabel = _unset,
    String? taxSource,
    Object? taxFetchedAt = _unset,
    Object? unitPriceBeforeVat = _unset,
    Object? lineBeforeVat = _unset,
    Object? lineVatAmount = _unset,
    Object? lineAfterVat = _unset,
  }) {
    return ContractAppendixItem(
      position: position,
      sourceLineKey: sourceLineKey,
      sku: sku,
      sellerSku: sellerSku,
      productName: productName ?? this.productName,
      quantity: quantity,
      unit: unit ?? this.unit,
      finalSellPrice: finalSellPrice,
      vatRateBps: identical(vatRateBps, _unset)
          ? this.vatRateBps
          : vatRateBps as int?,
      taxCode: identical(taxCode, _unset) ? this.taxCode : taxCode as String?,
      taxLabel: identical(taxLabel, _unset)
          ? this.taxLabel
          : taxLabel as String?,
      taxSource: taxSource ?? this.taxSource,
      taxFetchedAt: identical(taxFetchedAt, _unset)
          ? this.taxFetchedAt
          : taxFetchedAt as DateTime?,
      unitPriceBeforeVat: identical(unitPriceBeforeVat, _unset)
          ? this.unitPriceBeforeVat
          : unitPriceBeforeVat as int?,
      lineBeforeVat: identical(lineBeforeVat, _unset)
          ? this.lineBeforeVat
          : lineBeforeVat as int?,
      lineVatAmount: identical(lineVatAmount, _unset)
          ? this.lineVatAmount
          : lineVatAmount as int?,
      lineAfterVat: identical(lineAfterVat, _unset)
          ? this.lineAfterVat
          : lineAfterVat as int?,
    );
  }

  Map<String, dynamic> toOverrideJson() {
    return {
      'sourceLineKey': sourceLineKey,
      'productName': productName.trim(),
      'unit': unit.trim(),
      if (taxSource == 'MANUAL' && vatRateBps != null)
        'manualVatRateBps': vatRateBps,
    };
  }
}

class ContractAppendixDocument {
  final String? id;
  final String orderCode;
  final String quoteVersion;
  final String terminalCode;
  final DateTime? sourceOrderFetchedAt;
  final List<ContractAppendixItem> items;
  final int? totalBeforeVat;
  final int? totalVatAmount;
  final int? totalAfterVat;
  final String? amountInWords;
  final int manualTaxItemCount;
  final int unresolvedTaxCount;
  final bool canSave;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const ContractAppendixDocument({
    required this.id,
    required this.orderCode,
    required this.quoteVersion,
    required this.terminalCode,
    required this.sourceOrderFetchedAt,
    required this.items,
    required this.totalBeforeVat,
    required this.totalVatAmount,
    required this.totalAfterVat,
    required this.amountInWords,
    required this.manualTaxItemCount,
    required this.unresolvedTaxCount,
    required this.canSave,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ContractAppendixDocument.fromJson(Map<String, dynamic> json) {
    final rows = json['items'] is List ? json['items'] as List : const [];
    final items = rows
        .whereType<Map>()
        .map(
          (row) => ContractAppendixItem.fromJson(
            row.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
    final unresolved =
        _int(json['unresolvedTaxCount']) ??
        items.where((item) => item.isTaxMissing).length;
    return ContractAppendixDocument(
      id: _optionalText(json['id']),
      orderCode: _text(json['orderCode']),
      quoteVersion: _text(json['quoteVersion']),
      terminalCode: _text(json['terminalCode']),
      sourceOrderFetchedAt: _date(json['sourceOrderFetchedAt']),
      items: items,
      totalBeforeVat: _int(json['totalBeforeVat']),
      totalVatAmount: _int(json['totalVatAmount']),
      totalAfterVat: _int(json['totalAfterVat']),
      amountInWords: _optionalText(json['amountInWords']),
      manualTaxItemCount: _int(json['manualTaxItemCount']) ?? 0,
      unresolvedTaxCount: unresolved,
      canSave: json['canSave'] == true,
      createdAt: _date(json['createdAt']),
      expiresAt: _date(json['expiresAt']),
    );
  }

  bool get isFinalized => id != null && createdAt != null;

  ContractAppendixDocument copyWith({
    List<ContractAppendixItem>? items,
    String? quoteVersion,
    Object? totalBeforeVat = _unset,
    Object? totalVatAmount = _unset,
    Object? totalAfterVat = _unset,
    Object? amountInWords = _unset,
    int? manualTaxItemCount,
    int? unresolvedTaxCount,
    bool? canSave,
  }) {
    return ContractAppendixDocument(
      id: id,
      orderCode: orderCode,
      quoteVersion: quoteVersion ?? this.quoteVersion,
      terminalCode: terminalCode,
      sourceOrderFetchedAt: sourceOrderFetchedAt,
      items: items ?? this.items,
      totalBeforeVat: identical(totalBeforeVat, _unset)
          ? this.totalBeforeVat
          : totalBeforeVat as int?,
      totalVatAmount: identical(totalVatAmount, _unset)
          ? this.totalVatAmount
          : totalVatAmount as int?,
      totalAfterVat: identical(totalAfterVat, _unset)
          ? this.totalAfterVat
          : totalAfterVat as int?,
      amountInWords: identical(amountInWords, _unset)
          ? this.amountInWords
          : amountInWords as String?,
      manualTaxItemCount: manualTaxItemCount ?? this.manualTaxItemCount,
      unresolvedTaxCount: unresolvedTaxCount ?? this.unresolvedTaxCount,
      canSave: canSave ?? this.canSave,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  List<Map<String, dynamic>> buildOverrides() =>
      items.map((item) => item.toOverrideJson()).toList(growable: false);
}

class ContractAppendixHistoryItem {
  final String id;
  final String orderCode;
  final int itemCount;
  final int totalBeforeVat;
  final int totalVatAmount;
  final int totalAfterVat;
  final String amountInWords;
  final int manualTaxItemCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const ContractAppendixHistoryItem({
    required this.id,
    required this.orderCode,
    required this.itemCount,
    required this.totalBeforeVat,
    required this.totalVatAmount,
    required this.totalAfterVat,
    required this.amountInWords,
    required this.manualTaxItemCount,
    required this.createdAt,
    required this.expiresAt,
  });

  factory ContractAppendixHistoryItem.fromJson(Map<String, dynamic> json) {
    return ContractAppendixHistoryItem(
      id: _text(json['id']),
      orderCode: _text(json['orderCode']),
      itemCount: _int(json['itemCount']) ?? 0,
      totalBeforeVat: _int(json['totalBeforeVat']) ?? 0,
      totalVatAmount: _int(json['totalVatAmount']) ?? 0,
      totalAfterVat: _int(json['totalAfterVat']) ?? 0,
      amountInWords: _text(json['amountInWords']),
      manualTaxItemCount: _int(json['manualTaxItemCount']) ?? 0,
      createdAt: _date(json['createdAt']),
      expiresAt: _date(json['expiresAt']),
    );
  }
}

class ContractAppendixHistoryPage {
  final List<ContractAppendixHistoryItem> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  const ContractAppendixHistoryPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  factory ContractAppendixHistoryPage.fromJson(Map<String, dynamic> json) {
    final rows = json['items'] is List ? json['items'] as List : const [];
    return ContractAppendixHistoryPage(
      items: rows
          .whereType<Map>()
          .map(
            (row) => ContractAppendixHistoryItem.fromJson(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false),
      page: _int(json['page']) ?? 0,
      limit: _int(json['limit']) ?? 20,
      total: _int(json['total']) ?? 0,
      hasMore: json['hasMore'] == true,
    );
  }
}

int? _int(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return int.tryParse(value.toString().trim());
}

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _optionalText(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? value) {
  final text = _text(value);
  return text.isEmpty ? null : DateTime.tryParse(text);
}
