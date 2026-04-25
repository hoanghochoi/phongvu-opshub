import 'sku_item.dart';

class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final List<SKUItem>? skuItems;
  final List<SKUItem>? suggestedItems;

  const Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.skuItems,
    this.suggestedItems,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.toIso8601String(),
    if (skuItems != null) 'skuItems': skuItems!.map((e) => e.toJson()).toList(),
    if (suggestedItems != null) 'suggestedItems': suggestedItems!.map((e) => e.toJson()).toList(),
  };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: json['id'] ?? '',
    content: json['content'] ?? '',
    isUser: json['isUser'] ?? false,
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    skuItems: json['skuItems'] != null
        ? (json['skuItems'] as List).map((e) => SKUItem.fromJson(e as Map<String, dynamic>)).toList()
        : null,
    suggestedItems: json['suggestedItems'] != null
        ? (json['suggestedItems'] as List).map((e) => SKUItem.fromJson(e as Map<String, dynamic>)).toList()
        : null,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Message &&
        other.id == id &&
        other.content == content &&
        other.isUser == isUser &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        content.hashCode ^
        isUser.hashCode ^
        timestamp.hashCode;
  }

  @override
  String toString() {
    return 'Message(id: $id, content: $content, isUser: $isUser, timestamp: $timestamp)';
  }
}
