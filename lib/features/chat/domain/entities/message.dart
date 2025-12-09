class Message {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;

  const Message({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  });

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
