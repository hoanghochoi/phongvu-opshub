class SupportChatAttachment {
  final String id;
  final String url;
  final String contentType;
  final int sizeBytes;

  const SupportChatAttachment({
    required this.id,
    required this.url,
    required this.contentType,
    required this.sizeBytes,
  });

  factory SupportChatAttachment.fromJson(Map<String, dynamic> json) {
    return SupportChatAttachment(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      contentType: json['contentType']?.toString() ?? 'image/jpeg',
      sizeBytes: _intOf(json['sizeBytes']),
    );
  }
}

class SupportChatMessage {
  final String id;
  final String conversationId;
  final String sequence;
  final String? senderId;
  final String senderKind;
  final String type;
  final String? text;
  final List<SupportChatAttachment> attachments;
  final DateTime createdAt;

  const SupportChatMessage({
    required this.id,
    required this.conversationId,
    required this.sequence,
    required this.senderId,
    required this.senderKind,
    required this.type,
    required this.text,
    required this.attachments,
    required this.createdAt,
  });

  bool sentBy(String? userId) => userId != null && senderId == userId;

  factory SupportChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAttachments =
        json['attachments'] ?? json['media'] ?? json['images'];
    return SupportChatMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      sequence: json['sequence']?.toString() ?? '0',
      senderId: json['senderId']?.toString(),
      senderKind:
          json['senderKind']?.toString() ??
          json['senderRole']?.toString() ??
          'REQUESTER',
      type:
          json['type']?.toString() ?? json['contentType']?.toString() ?? 'TEXT',
      text: json['text']?.toString(),
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map>()
                .map(
                  (value) => SupportChatAttachment.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SupportConversation {
  final String id;
  final String? requesterId;
  final String? requesterDisplayName;
  final String status;
  final String? assigneeId;
  final String revision;
  final String lastMessageSequence;
  final int unreadCount;
  final DateTime? unassignedSince;
  final DateTime? lastMessageAt;
  final DateTime? resolvedAt;

  const SupportConversation({
    required this.id,
    required this.requesterId,
    required this.requesterDisplayName,
    required this.status,
    required this.assigneeId,
    required this.revision,
    required this.lastMessageSequence,
    required this.unreadCount,
    required this.unassignedSince,
    required this.lastMessageAt,
    required this.resolvedAt,
  });

  bool get isResolved => status == 'RESOLVED';
  bool isAssignedTo(String? userId) => userId != null && assigneeId == userId;

  factory SupportConversation.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'] is Map
        ? Map<String, dynamic>.from(json['requester'] as Map)
        : const <String, dynamic>{};
    final assignee = json['assignee'] is Map
        ? Map<String, dynamic>.from(json['assignee'] as Map)
        : const <String, dynamic>{};
    final lastMessageSequence = json['lastMessageSequence']?.toString() ?? '0';
    final lastReadSequence = json['myLastReadSequence']?.toString() ?? '0';
    final inferredUnread = _nonNegativeBigIntDifference(
      lastMessageSequence,
      lastReadSequence,
    );
    return SupportConversation(
      id: json['id']?.toString() ?? '',
      requesterId:
          json['requesterId']?.toString() ?? requester['id']?.toString(),
      requesterDisplayName:
          json['requesterDisplayName']?.toString() ??
          json['requesterName']?.toString() ??
          requester['displayName']?.toString(),
      status: json['status']?.toString() ?? 'OPEN',
      assigneeId: json['assigneeId']?.toString() ?? assignee['id']?.toString(),
      revision: json['revision']?.toString() ?? '0',
      lastMessageSequence: lastMessageSequence,
      unreadCount: json.containsKey('unreadCount')
          ? _intOf(json['unreadCount'])
          : inferredUnread,
      unassignedSince: _dateOf(json['unassignedSince']),
      lastMessageAt: _dateOf(json['lastMessageAt']),
      resolvedAt: _dateOf(json['resolvedAt']),
    );
  }
}

class SupportChatThread {
  final SupportConversation? conversation;
  final List<SupportChatMessage> messages;
  final String? nextBeforeSequence;
  final bool hasMore;

  const SupportChatThread({
    required this.conversation,
    required this.messages,
    required this.nextBeforeSequence,
    required this.hasMore,
  });

  factory SupportChatThread.fromJson(Map<String, dynamic> json) {
    final rawConversation = json['conversation'];
    final rawMessages = json['messages'];
    final page = json['page'] is Map
        ? Map<String, dynamic>.from(json['page'] as Map)
        : json;
    return SupportChatThread(
      conversation: rawConversation is Map
          ? SupportConversation.fromJson(
              Map<String, dynamic>.from(rawConversation),
            )
          : null,
      messages: rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map(
                  (value) => SupportChatMessage.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
      nextBeforeSequence:
          page['nextBeforeSequence']?.toString() ??
          page['nextCursor']?.toString(),
      hasMore: page['hasMore'] == true,
    );
  }
}

class SupportChatAdminPage {
  final List<SupportConversation> items;
  final String? nextCursor;

  const SupportChatAdminPage({required this.items, required this.nextCursor});

  factory SupportChatAdminPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] ?? json['conversations'];
    return SupportChatAdminPage(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (value) => SupportConversation.fromJson(
                    Map<String, dynamic>.from(value),
                  ),
                )
                .toList(growable: false)
          : const [],
      nextCursor: json['nextCursor']?.toString(),
    );
  }
}

int _intOf(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _dateOf(Object? value) => DateTime.tryParse(value?.toString() ?? '');

int _nonNegativeBigIntDifference(String upper, String lower) {
  final upperValue = BigInt.tryParse(upper) ?? BigInt.zero;
  final lowerValue = BigInt.tryParse(lower) ?? BigInt.zero;
  final difference = upperValue - lowerValue;
  if (difference <= BigInt.zero) return 0;
  return difference > BigInt.from(2147483647) ? 2147483647 : difference.toInt();
}
