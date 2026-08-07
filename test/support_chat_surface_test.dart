import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/support_chat/data/support_chat_repository.dart';
import 'package:phongvu_opshub/features/support_chat/domain/support_chat_models.dart';
import 'package:phongvu_opshub/features/support_chat/presentation/providers/support_chat_provider.dart';
import 'package:phongvu_opshub/features/support_chat/presentation/support_chat_surface.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppLogger.instance.setUploadsEnabledForTesting(false));
  tearDown(() => AppLogger.instance.setUploadsEnabledForTesting(true));

  testWidgets('fallback support launcher preserves approved FAB geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportChatBubble(visibleWhenDisabled: true, onPressed: () {}),
        ),
      ),
    );

    final bubble = find.byType(SupportChatBubble);
    expect(tester.getSize(bubble), const Size.square(64));
    expect(find.byTooltip('Hỗ trợ'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.headset));
    expect(icon.size, 28);
  });

  testWidgets('compact admin can return to inbox and keeps requester context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SurfaceRepository();
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_admin, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      _surfaceHarness(
        auth: _SurfaceAuthProvider(_admin),
        support: provider,
        child: const SupportChatAdminScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.byTooltip('Quay lại hộp thư'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('support-reply-composer'))),
      const Size(343, 56),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('support-reply-send'))),
      const Size(88, 40),
    );
    expect(
      find.bySemanticsLabel('Tin nhắn từ nhân viên cần hỗ trợ'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Tin nhắn của bạn'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Quay lại hộp thư'), findsNothing);
    expect(find.text('Chưa tiếp nhận'), findsOneWidget);
  });

  testWidgets('wide admin exposes the selected requester in semantics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final repository = _SurfaceRepository();
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_admin, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      _surfaceHarness(
        auth: _SurfaceAuthProvider(_admin),
        support: provider,
        child: const SupportChatAdminScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nguyễn Văn A'));
    await tester.pumpAndSettle();

    final selected = find.bySemanticsLabel('Cuộc trò chuyện với Nguyễn Văn A');
    expect(selected, findsOneWidget);
    expect(
      tester.getSemantics(selected).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('wide support workspace follows approved Figma geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1190, 828);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SurfaceRepository();
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_admin, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      _surfaceHarness(
        auth: _SurfaceAuthProvider(_admin),
        support: provider,
        child: const SupportChatAdminScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('support-inbox-workspace'))),
      const Size(380, 780),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('support-conversation-workspace')),
      ),
      const Size(746, 780),
    );
    for (final label in [
      'Chưa tiếp nhận',
      'Của tôi',
      'Đang xử lý',
      'Đã xử lý',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey('support-filter-$label'))),
        const Size(170, 36),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('requester initial-load error offers an actionable retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SurfaceRepository()..failMineOnce = true;
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_requester, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      _surfaceHarness(
        auth: _SurfaceAuthProvider(_requester),
        support: provider,
        child: const SupportChatPanel(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa tải được cuộc trò chuyện'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(repository.mineCalls, 2);
    expect(find.text('Bắt đầu trò chuyện hỗ trợ'), findsOneWidget);
  });

  testWidgets('composer sends on Enter and keeps Shift+Enter as a newline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SurfaceRepository();
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_requester, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      _surfaceHarness(
        auth: _SurfaceAuthProvider(_requester),
        support: provider,
        child: const SupportChatPanel(),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'Tin nhan gui nhanh');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(repository.sendMyTextCalls, 1);
    expect(repository.lastSentText, 'Tin nhan gui nhanh');
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);

    await tester.enterText(field, 'Dong tiep');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(repository.sendMyTextCalls, 1);
    expect(tester.widget<TextField>(field).controller!.text, 'Dong tiep\n');
  });

  testWidgets('admin support-chat route hides the global bubble launcher', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _SurfaceRepository();
    final realtime = _SurfaceRealtimeClient();
    final provider = SupportChatProvider(repository, realtimeClient: realtime);
    await provider.syncAuth(_admin, enabled: true);
    addTearDown(() async {
      provider.dispose();
      await realtime.close();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _SurfaceAuthProvider(_admin),
          ),
          ChangeNotifierProvider<SupportChatProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          home: AppShell(
            location: '/admin/support-chats',
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SupportChatBubble), findsNothing);
  });
}

Widget _surfaceHarness({
  required AuthProvider auth,
  required SupportChatProvider support,
  required Widget child,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ChangeNotifierProvider<SupportChatProvider>.value(value: support),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

const _requester = User(id: 'requester-1', email: 'requester@phongvu.vn');
const _admin = User(
  id: 'admin-1',
  email: 'admin@phongvu.vn',
  role: 'SUPER_ADMIN',
);

SupportConversation get _conversation => const SupportConversation(
  id: 'conversation-1',
  requesterId: 'requester-1',
  requesterDisplayName: 'Nguyễn Văn A',
  status: 'OPEN',
  assigneeId: 'admin-1',
  revision: '2',
  lastMessageSequence: '2',
  unreadCount: 1,
  unassignedSince: null,
  lastMessageAt: null,
  resolvedAt: null,
);

SupportChatThread get _adminThread => SupportChatThread(
  conversation: _conversation,
  messages: [
    SupportChatMessage(
      id: 'message-1',
      conversationId: 'conversation-1',
      sequence: '1',
      senderId: 'requester-1',
      senderKind: 'REQUESTER',
      type: 'TEXT',
      text: 'Em cần hỗ trợ',
      attachments: const [],
      createdAt: DateTime.utc(2026, 8, 1, 1),
    ),
    SupportChatMessage(
      id: 'message-2',
      conversationId: 'conversation-1',
      sequence: '2',
      senderId: 'admin-1',
      senderKind: 'SUPER_ADMIN',
      type: 'TEXT',
      text: 'Đã tiếp nhận',
      attachments: const [],
      createdAt: DateTime.utc(2026, 8, 1, 1, 1),
    ),
  ],
  nextBeforeSequence: null,
  hasMore: false,
);

class _SurfaceAuthProvider extends AuthProvider {
  final User currentUser;

  _SurfaceAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _SurfaceRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _sync = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _sync.stream;

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> close() async {
    await _events.close();
    await _sync.close();
  }
}

class _SurfaceRepository implements SupportChatDataSource {
  bool failMineOnce = false;
  int mineCalls = 0;
  int sendMyTextCalls = 0;
  String? lastSentText;

  @override
  Future<SupportChatThread> getMine({
    String? beforeSequence,
    int limit = 50,
  }) async {
    mineCalls += 1;
    if (failMineOnce) {
      failMineOnce = false;
      throw StateError('offline');
    }
    return const SupportChatThread(
      conversation: null,
      messages: [],
      nextBeforeSequence: null,
      hasMore: false,
    );
  }

  @override
  Future<SupportChatAdminPage> listAdmin({
    required String bucket,
    String? query,
    String? cursor,
    int limit = 50,
  }) async => SupportChatAdminPage(items: [_conversation], nextCursor: null);

  @override
  Future<SupportChatThread> getAdminConversation(
    String conversationId, {
    String? beforeSequence,
  }) async => _adminThread;

  @override
  Future<void> markAdminRead(
    String conversationId,
    String lastReadSequence,
  ) async {}

  @override
  Future<void> markMineRead(String lastReadSequence) async {}

  @override
  Future<SupportChatThread> mutateAdmin(
    String conversationId,
    String action, {
    Map<String, dynamic> body = const {},
  }) async => _adminThread;

  @override
  Future<SupportChatThread> sendAdminImages({
    required String conversationId,
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async => _adminThread;

  @override
  Future<SupportChatThread> sendAdminText({
    required String conversationId,
    required String clientMessageId,
    required String text,
  }) async => _adminThread;

  @override
  Future<SupportChatThread> sendMyImages({
    required String clientMessageId,
    required List<SupportChatImageDraft> images,
  }) async => _adminThread;

  @override
  Future<SupportChatThread> sendMyText({
    required String clientMessageId,
    required String text,
  }) async {
    sendMyTextCalls += 1;
    lastSentText = text;
    return _adminThread;
  }

  @override
  Future<Uint8List> loadPrivateImage(String url) async => Uint8List(0);
}
