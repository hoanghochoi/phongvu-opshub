import 'sku_item.dart';

class FifoCheckEntry {
  final String id;
  final String content;
  final bool isUserInput;
  final DateTime timestamp;
  final List<SKUItem>? skuItems;
  final List<SKUItem>? suggestedItems;

  const FifoCheckEntry({
    required this.id,
    required this.content,
    required this.isUserInput,
    required this.timestamp,
    this.skuItems,
    this.suggestedItems,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'isUserInput': isUserInput,
    'timestamp': timestamp.toIso8601String(),
    if (skuItems != null) 'skuItems': skuItems!.map((e) => e.toJson()).toList(),
    if (suggestedItems != null)
      'suggestedItems': suggestedItems!.map((e) => e.toJson()).toList(),
  };

  factory FifoCheckEntry.fromJson(Map<String, dynamic> json) => FifoCheckEntry(
    id: json['id'] ?? '',
    content: json['content'] ?? '',
    isUserInput: json['isUserInput'] ?? json['isUser'] ?? false,
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    skuItems: json['skuItems'] != null
        ? (json['skuItems'] as List)
              .map((e) => SKUItem.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
    suggestedItems: json['suggestedItems'] != null
        ? (json['suggestedItems'] as List)
              .map((e) => SKUItem.fromJson(e as Map<String, dynamic>))
              .toList()
        : null,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FifoCheckEntry &&
        other.id == id &&
        other.content == content &&
        other.isUserInput == isUserInput &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        content.hashCode ^
        isUserInput.hashCode ^
        timestamp.hashCode;
  }

  @override
  String toString() {
    return 'FifoCheckEntry(id: $id, content: $content, isUserInput: $isUserInput, timestamp: $timestamp)';
  }
}
