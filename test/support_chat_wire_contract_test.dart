import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/support_chat/data/support_chat_repository.dart';
import 'package:phongvu_opshub/features/support_chat/domain/support_chat_models.dart';

void main() {
  test(
    'parses the canonical Nest thread response without losing identity or media',
    () {
      final thread = SupportChatThread.fromJson({
        'conversation': {
          'id': 'conversation-1',
          'requester': {'id': 'requester-1', 'displayName': 'Nguyễn An'},
          'assignee': {'id': 'admin-1', 'displayName': 'Quản trị viên'},
          'status': 'OPEN',
          'revision': '4',
          'lastMessageSequence': '9',
          'unassignedSince': null,
          'lastMessageAt': '2026-08-01T01:02:03.000Z',
          'resolvedAt': null,
          'readReceipts': [],
        },
        'messages': [
          {
            'id': 'message-9',
            'conversationId': 'conversation-1',
            'senderId': 'requester-1',
            'senderRole': 'REQUESTER',
            'sequence': '9',
            'contentType': 'IMAGE',
            'text': null,
            'media': [
              {'id': 'media-1', 'url': '/media/media-1'},
            ],
            'createdAt': '2026-08-01T01:02:03.000Z',
          },
        ],
        'hasMore': false,
        'nextBeforeSequence': null,
      });

      expect(thread.conversation?.requesterId, 'requester-1');
      expect(thread.conversation?.requesterDisplayName, 'Nguyễn An');
      expect(thread.conversation?.assigneeId, 'admin-1');
      expect(thread.messages.single.senderKind, 'REQUESTER');
      expect(thread.messages.single.type, 'IMAGE');
      expect(thread.messages.single.attachments.single.url, '/media/media-1');
    },
  );

  test(
    'multipart images retain an accepted MIME without original filename',
    () {
      final files = buildSupportChatMultipartImages([
        SupportChatImageDraft(
          bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]),
          contentType: 'image/jpeg',
        ),
      ]);

      expect(files.single.contentType.toString(), 'image/jpeg');
      expect(files.single.filename, 'support-image-1.jpg');
    },
  );
}
