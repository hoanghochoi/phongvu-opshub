import 'fifo_inventory_item.dart';

class FifoCheckResult {
  final String mode;
  final String query;
  final String srCode;
  final bool includeExported;
  final String? status;
  final String? message;
  final List<FifoInventoryItem> items;
  final FifoInventoryItem? item;
  final FifoInventoryItem? suggestedItem;

  const FifoCheckResult({
    required this.mode,
    required this.query,
    required this.srCode,
    required this.includeExported,
    required this.items,
    this.status,
    this.message,
    this.item,
    this.suggestedItem,
  });

  bool get isSkuMode => mode == 'sku';
  bool get isSerialMode => mode == 'serial';

  factory FifoCheckResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return FifoCheckResult(
      mode: json['mode']?.toString() ?? '',
      query: json['query']?.toString() ?? '',
      srCode: json['srCode']?.toString() ?? json['sr_code']?.toString() ?? '',
      includeExported:
          json['includeExported'] == true || json['includeExported'] == 'true',
      status: json['status']?.toString(),
      message: json['message']?.toString(),
      items: rawItems is List
          ? rawItems
                .whereType<Map<String, dynamic>>()
                .map(FifoInventoryItem.fromJson)
                .toList()
          : const [],
      item: json['item'] is Map<String, dynamic>
          ? FifoInventoryItem.fromJson(json['item'] as Map<String, dynamic>)
          : null,
      suggestedItem: json['suggestedItem'] is Map<String, dynamic>
          ? FifoInventoryItem.fromJson(
              json['suggestedItem'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}
