import '../../domain/entities/fifo_check_entry.dart';

class FifoCheckEntryModel extends FifoCheckEntry {
  const FifoCheckEntryModel({
    required super.id,
    required super.content,
    required super.isUserInput,
    required super.timestamp,
  });

  factory FifoCheckEntryModel.fromEntity(FifoCheckEntry entry) {
    return FifoCheckEntryModel(
      id: entry.id,
      content: entry.content,
      isUserInput: entry.isUserInput,
      timestamp: entry.timestamp,
    );
  }

  factory FifoCheckEntryModel.fromJson(Map<String, dynamic> json) {
    return FifoCheckEntryModel(
      id: json['id'] as String,
      content: json['content'] as String,
      isUserInput: (json['isUserInput'] ?? json['isUser'] ?? false) as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isUserInput': isUserInput,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
