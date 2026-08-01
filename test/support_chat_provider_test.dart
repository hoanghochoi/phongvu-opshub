import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/support_chat/data/support_chat_repository.dart';
import 'package:phongvu_opshub/features/support_chat/domain/support_chat_models.dart';
import 'package:phongvu_opshub/features/support_chat/presentation/providers/support_chat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  const requester = User(
    id: 'requester-1',
    email: 'requester@phongvu.vn',
    assignmentPending: true,
  );
  const superAdmin = User(
    id: 'admin-1',
    email: 'admin@phongvu.vn',
    role: 'SUPER_ADMIN',
  );

  test(
    'keeps assignment-pending requester state memory-only until opened',
    () async {
      final repository = _FakeSupportChatRepository();
      final realtime = _FakeRealtimeClient();
      final provider = SupportChatProvider(
        repository,
        realtimeClient: realtime,
      );

      await provider.syncAuth(requester, enabled: true);
      expect(provider.enabled, isTrue);
      expect(repository.getMineCount, 0);

      await provider.setSurfaceActive(true);
      expect(repository.getMineCount, 1);
      expect(provider.thread?.conversation?.requesterId, 'requester-1');

      provider.dispose();
      await realtime.close();
    },
  );

  test(
    'realtime invalidation refreshes only while surface is active',
    () async {
      final repository = _FakeSupportChatRepository();
      final realtime = _FakeRealtimeClient();
      final provider = SupportChatProvider(
        repository,
        realtimeClient: realtime,
      );
      await provider.syncAuth(requester, enabled: true);

      realtime.addEvent(_supportEvent('event-1'));
      await Future<void>.delayed(Duration.zero);
      expect(repository.getMineCount, 0);

      await provider.setSurfaceActive(true);
      expect(repository.getMineCount, 1);

      realtime.addEvent(_supportEvent('event-2'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repository.getMineCount, 2);

      provider.dispose();
      await realtime.close();
    },
  );

  test('account switch clears prior conversation and unread state', () async {
    final repository = _FakeSupportChatRepository();
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(requester, enabled: true);
    await provider.setSurfaceActive(true);
    expect(provider.unreadCount, 2);

    await provider.syncAuth(
      const User(id: 'requester-2', email: 'other@phongvu.vn'),
      enabled: true,
    );
    expect(provider.thread, isNull);
    expect(provider.unreadCount, 0);

    provider.dispose();
    await realtime.close();
  });

  test('in-flight text send cannot restore a prior account thread', () async {
    final repository = _FakeSupportChatRepository()
      ..pendingSendMyText = Completer<SupportChatThread>()
      ..sendMyTextStarted = Completer<void>();
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(requester, enabled: true);
    await provider.setSurfaceActive(true);

    final send = provider.sendText('stale-text', 'Cần hỗ trợ');
    await repository.sendMyTextStarted!.future;
    await provider.syncAuth(
      const User(id: 'requester-2', email: 'other@phongvu.vn'),
      enabled: true,
    );
    repository.pendingSendMyText!.complete(_thread());

    expect(await send, isFalse);
    expect(provider.thread, isNull);
    expect(provider.isSending, isFalse);
    provider.dispose();
    await realtime.close();
  });

  test('disposed provider ignores an in-flight image completion', () async {
    final repository = _FakeSupportChatRepository()
      ..pendingSendMyImages = Completer<SupportChatThread>()
      ..sendMyImagesStarted = Completer<void>();
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(requester, enabled: true);
    await provider.setSurfaceActive(true);

    final send = provider.sendImages('stale-image', [
      SupportChatImageDraft(
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      ),
    ]);
    await repository.sendMyImagesStarted!.future;
    provider.dispose();
    repository.pendingSendMyImages!.complete(_thread());

    expect(await send, isFalse);
    await realtime.close();
  });

  test('in-flight admin mutation cannot restore state after logout', () async {
    final repository = _FakeSupportChatRepository();
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(superAdmin, enabled: true);
    await provider.setSurfaceActive(true);
    await provider.openAdminConversation('conversation-1');
    repository
      ..pendingAdminMutation = Completer<SupportChatThread>()
      ..adminMutationStarted = Completer<void>();

    final mutation = provider.mutateAdmin('claim');
    await repository.adminMutationStarted!.future;
    await provider.syncAuth(null, enabled: false);
    repository.pendingAdminMutation!.complete(_thread());

    expect(await mutation, isFalse);
    expect(provider.thread, isNull);
    expect(provider.enabled, isFalse);
    provider.dispose();
    await realtime.close();
  });

  test('failed send can retry with the same client message id', () async {
    final repository = _FakeSupportChatRepository()..failNextSend = true;
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(requester, enabled: true);
    await provider.setSurfaceActive(true);

    expect(await provider.sendText('stable-id', 'Cần hỗ trợ'), isFalse);
    expect(await provider.sendText('stable-id', 'Cần hỗ trợ'), isTrue);
    expect(repository.clientMessageIds, ['stable-id', 'stable-id']);

    provider.dispose();
    await realtime.close();
  });

  test('admin realtime refreshes both queue and selected thread', () async {
    final repository = _FakeSupportChatRepository();
    final realtime = _FakeRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(superAdmin, enabled: true);
    await provider.setSurfaceActive(true);
    await provider.openAdminConversation('conversation-1');
    final listBefore = repository.adminListCount;
    final threadBefore = repository.adminThreadCount;

    realtime.addEvent(_supportEvent('event-admin'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.adminListCount, greaterThan(listBefore));
    expect(repository.adminThreadCount, greaterThan(threadBefore));
    provider.dispose();
    await realtime.close();
  });

  test(
    'requester invalidation during a load queues a fresh snapshot',
    () async {
      final pendingLoad = Completer<SupportChatThread>();
      final repository = _FakeSupportChatRepository()
        ..pendingGetMine = pendingLoad
        ..getMineStarted = Completer<void>();
      final realtime = _FakeRealtimeClient();
      final provider = SupportChatProvider(
        repository,
        realtimeClient: realtime,
      );
      await provider.syncAuth(requester, enabled: true);

      final opening = provider.setSurfaceActive(true);
      await repository.getMineStarted!.future;
      realtime.addEvent(_supportEvent('event-during-requester-load'));
      await Future<void>.delayed(Duration.zero);
      pendingLoad.complete(_thread());
      await opening;

      expect(repository.getMineCount, 2);
      provider.dispose();
      await realtime.close();
    },
  );

  test(
    'admin invalidation during selected-thread load queues resync',
    () async {
      final repository = _FakeSupportChatRepository();
      final realtime = _FakeRealtimeClient();
      final provider = SupportChatProvider(
        repository,
        realtimeClient: realtime,
      );
      await provider.syncAuth(superAdmin, enabled: true);
      await provider.setSurfaceActive(true);
      await provider.openAdminConversation('conversation-1');
      final listBefore = repository.adminListCount;
      final threadBefore = repository.adminThreadCount;
      final pendingThread = Completer<SupportChatThread>();
      repository
        ..pendingAdminThread = pendingThread
        ..adminThreadStarted = Completer<void>();

      final refresh = provider.refresh();
      await repository.adminThreadStarted!.future;
      realtime.addEvent(_supportEvent('event-during-admin-load'));
      await Future<void>.delayed(Duration.zero);
      pendingThread.complete(_thread());
      await refresh;

      expect(repository.adminListCount, greaterThanOrEqualTo(listBefore + 2));
      expect(
        repository.adminThreadCount,
        greaterThanOrEqualTo(threadBefore + 2),
      );
      provider.dispose();
      await realtime.close();
    },
  );

  test('parses decimal sequences and optional private attachments', () {
    final thread = SupportChatThread.fromJson({
      'conversation': {
        'id': 'conversation-1',
        'requesterId': 'requester-1',
        'status': 'OPEN',
        'revision': '12',
        'lastMessageSequence': '9223372036854775806',
        'unreadCount': 1,
      },
      'messages': [
        {
          'id': 'message-1',
          'conversationId': 'conversation-1',
          'sequence': '9223372036854775806',
          'senderId': 'requester-1',
          'senderKind': 'USER',
          'type': 'IMAGE',
          'attachments': [
            {
              'id': 'media-1',
              'url': '/media/media-1',
              'contentType': 'image/jpeg',
              'sizeBytes': 100,
            },
          ],
          'createdAt': '2026-08-01T00:00:00.000Z',
        },
      ],
    });

    expect(thread.conversation?.lastMessageSequence, '9223372036854775806');
    expect(thread.messages.single.attachments.single.id, 'media-1');
  });
}

RealtimeEnvelope _supportEvent(String id) => RealtimeEnvelope(
  version: 2,
  kind: 'SUPPORT_CHAT_INVALIDATED',
  id: id,
  topic: 'support.chat',
  sequence: 1,
  timestamp: DateTime.utc(2026, 8, 1),
  data: const {'changeType': 'MESSAGE_CREATED'},
);

SupportChatThread _thread() => SupportChatThread(
  conversation: const SupportConversation(
    id: 'conversation-1',
    requesterId: 'requester-1',
    requesterDisplayName: 'Nhân viên',
    status: 'OPEN',
    assigneeId: null,
    revision: '1',
    lastMessageSequence: '1',
    unreadCount: 2,
    unassignedSince: null,
    lastMessageAt: null,
    resolvedAt: null,
  ),
  messages: const [],
  nextBeforeSequence: null,
  hasMore: false,
);

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _sync = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _sync.stream;

  void addEvent(RealtimeEnvelope event) => _events.add(event);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> close() async {
    await _events.close();
    await _sync.close();
  }
}

class _FakeSupportChatRepository implements SupportChatDataSource {
  int getMineCount = 0;
  int adminListCount = 0;
  int adminThreadCount = 0;
  bool failNextSend = false;
  final clientMessageIds = <String>[];
  Completer<SupportChatThread>? pendingGetMine;
  Completer<void>? getMineStarted;
  Completer<SupportChatThread>? pendingSendMyText;
  Completer<void>? sendMyTextStarted;
  Completer<SupportChatThread>? pendingSendMyImages;
  Completer<void>? sendMyImagesStarted;
  Completer<SupportChatThread>? pendingAdminThread;
  Completer<void>? adminThreadStarted;
  Completer<SupportChatThread>? pendingAdminMutation;
  Completer<void>? adminMutationStarted;

  @override
  Future<SupportChatThread> getMine({
    String? beforeSequence,
    int limit = 50,
  }) async {
    getMineCount += 1;
    final pending = pendingGetMine;
    if (pending != null) {
      pendingGetMine = null;
      if (getMineStarted?.isCompleted == false) getMineStarted!.complete();
      return pending.future;
    }
    return _thread();
  }

  @override
  Future<SupportChatThread> sendMyText({
    required String clientMessageId,
    required String text,
  }) async {
    clientMessageIds.add(clientMessageId);
    final pending = pendingSendMyText;
    if (pending != null) {
      if (sendMyTextStarted?.isCompleted == false) {
        sendMyTextStarted!.complete();
      }
      return pending.future;
    }
    if (failNextSend) {
      failNextSend = false;
      throw StateError('offline');
    }
    return _thread();
  }

  @override
  Future<SupportChatThread> sendMyImages({
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async {
    final pending = pendingSendMyImages;
    if (pending != null) {
      if (sendMyImagesStarted?.isCompleted == false) {
        sendMyImagesStarted!.complete();
      }
      return pending.future;
    }
    return _thread();
  }

  @override
  Future<void> markMineRead(String lastReadSequence) async {}

  @override
  Future<SupportChatAdminPage> listAdmin({
    required String bucket,
    String? query,
    String? cursor,
    int limit = 50,
  }) async {
    adminListCount += 1;
    return SupportChatAdminPage(
      items: [_thread().conversation!],
      nextCursor: null,
    );
  }

  @override
  Future<SupportChatThread> getAdminConversation(
    String conversationId, {
    String? beforeSequence,
  }) async {
    adminThreadCount += 1;
    final pending = pendingAdminThread;
    if (pending != null) {
      pendingAdminThread = null;
      if (adminThreadStarted?.isCompleted == false) {
        adminThreadStarted!.complete();
      }
      return pending.future;
    }
    return _thread();
  }

  @override
  Future<SupportChatThread> mutateAdmin(
    String conversationId,
    String action, {
    Map<String, dynamic> body = const {},
  }) async {
    final pending = pendingAdminMutation;
    if (pending != null) {
      if (adminMutationStarted?.isCompleted == false) {
        adminMutationStarted!.complete();
      }
      return pending.future;
    }
    return _thread();
  }

  @override
  Future<SupportChatThread> sendAdminText({
    required String conversationId,
    required String clientMessageId,
    required String text,
  }) async => _thread();

  @override
  Future<SupportChatThread> sendAdminImages({
    required String conversationId,
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async => _thread();

  @override
  Future<void> markAdminRead(
    String conversationId,
    String lastReadSequence,
  ) async {}

  @override
  Future<Uint8List> loadPrivateImage(String url) async => Uint8List(0);
}
