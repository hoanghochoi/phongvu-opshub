import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('RealtimeEnvelope accepts only the versioned v2 contract', () {
    final envelope = RealtimeEnvelope.parse(
      jsonEncode({
        'v': 2,
        'kind': 'HOME_SUMMARY_UPDATED',
        'id': 'event-42',
        'topic': 'home.summary',
        'seq': 42,
        'ts': '2026-07-14T10:30:05Z',
        'data': {
          'affectedDates': ['2026-07-14'],
          'projectionVersion': 42,
        },
      }),
    );

    expect(envelope.version, 2);
    expect(envelope.sequence, 42);
    expect(envelope.data['projectionVersion'], 42);
    expect(() => RealtimeEnvelope.parse('{"v":1}'), throwsFormatException);
    expect(() => RealtimeEnvelope.parse([0xff]), throwsA(isA<Object>()));
  });

  testWidgets(
    'Realtime manager deduplicates events and requests HTTP resync after reconnect',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      var issuedUris = 0;
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async {
          issuedUris += 1;
          return Uri.parse('ws://localhost/ws/v2?ticket=test');
        },
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        reconnectDelays: const [Duration(milliseconds: 1)],
        stableConnectionWindow: Duration.zero,
        randomDouble: () => 1,
      );
      addTearDown(manager.shutdown);
      final events = <RealtimeEnvelope>[];
      final syncReasons = <RealtimeSyncReason>[];
      final eventSubscription = manager.events.listen(events.add);
      final syncSubscription = manager.syncRequests.listen(syncReasons.add);
      addTearDown(eventSubscription.cancel);
      addTearDown(syncSubscription.cancel);

      await manager.syncSession('session-1');
      await tester.pump();
      expect(connections, hasLength(1));
      expect(issuedUris, 1);
      expect(manager.isConnected, isTrue);

      final message = jsonEncode({
        'v': 2,
        'kind': 'HOME_SUMMARY_UPDATED',
        'id': 'event-42',
        'topic': 'home.summary',
        'seq': 42,
        'ts': '2026-07-14T10:30:05Z',
        'data': {
          'affectedDates': ['2026-07-14'],
          'projectionVersion': 42,
        },
      });
      connections.first.add(message);
      connections.first.add(message);
      connections.first.add(
        jsonEncode({
          'v': 2,
          'kind': 'HOME_SUMMARY_UPDATED',
          'id': 'event-41-late',
          'topic': 'home.summary',
          'seq': 41,
          'ts': '2026-07-14T10:30:04Z',
          'data': {
            'affectedDates': ['2026-07-14'],
            'projectionVersion': 41,
          },
        }),
      );
      await tester.pump();
      expect(events.map((event) => event.id), ['event-42']);

      for (final sequence in [50, 49]) {
        connections.first.add(
          jsonEncode({
            'v': 2,
            'kind': 'PAYMENT_NOTIFICATION',
            'id': 'payment-$sequence',
            'topic': 'payment.transactions',
            'seq': sequence,
            'ts': '2026-07-14T10:30:05Z',
            'data': {'storeCode': 'CP01'},
          }),
        );
      }
      await tester.pump();
      expect(events.map((event) => event.id), [
        'event-42',
        'payment-50',
        'payment-49',
      ]);

      await connections.first.closeFromServer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(connections, hasLength(2));
      expect(syncReasons, contains(RealtimeSyncReason.reconnected));

      manager.handleAppResumed();
      await tester.pump();
      expect(syncReasons.last, RealtimeSyncReason.appResumed);
    },
  );

  testWidgets(
    'session change while ticket is pending does not block the new connection',
    (tester) async {
      final firstTicket = Completer<Uri>();
      final connections = <_FakeRealtimeConnection>[];
      var issuedUris = 0;
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () {
          issuedUris += 1;
          if (issuedUris == 1) return firstTicket.future;
          return Future.value(
            Uri.parse('ws://localhost/ws/v2?ticket=session-2'),
          );
        },
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        stableConnectionWindow: Duration.zero,
      );
      addTearDown(manager.shutdown);

      await manager.syncSession('session-1');
      await tester.pump();
      expect(issuedUris, 1);

      await manager.syncSession(null);
      await manager.syncSession('session-2');
      await tester.pump();
      await tester.pump();

      expect(issuedUris, 2);
      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);

      firstTicket.complete(
        Uri.parse('ws://localhost/ws/v2?ticket=obsolete-session'),
      );
      await tester.pump();

      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);
    },
  );

  testWidgets(
    'authenticated socket pauses in background and reconnects once on resume',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      final syncReasons = <RealtimeSyncReason>[];
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async =>
            Uri.parse('ws://localhost/ws/v2?ticket=test'),
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        reconnectDelays: const [Duration(milliseconds: 1)],
        stableConnectionWindow: Duration.zero,
        randomDouble: () => 1,
      );
      addTearDown(manager.shutdown);
      final subscription = manager.syncRequests.listen(syncReasons.add);
      addTearDown(subscription.cancel);

      await manager.syncSession('session-1');
      await tester.pump();
      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(manager.isConnected, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(connections, hasLength(1));

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(connections, hasLength(2));
      expect(manager.isConnected, isTrue);
      expect(syncReasons, contains(RealtimeSyncReason.appResumed));
      expect(syncReasons, contains(RealtimeSyncReason.reconnected));
    },
  );

  testWidgets(
    'socket without a lease stays inactive-compatible but pauses when hidden',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async =>
            Uri.parse('ws://localhost/ws/v2?ticket=test'),
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        stableConnectionWindow: Duration.zero,
      );
      addTearDown(manager.shutdown);

      await manager.syncSession('session-1');
      await tester.pump();
      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(manager.isConnected, isTrue);
      expect(connections, hasLength(1));

      manager.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(manager.isConnected, isFalse);
      expect(connections, hasLength(1));

      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(manager.isConnected, isFalse);
      expect(connections, hasLength(1));

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(manager.isConnected, isTrue);
      expect(connections, hasLength(2));
    },
  );

  testWidgets(
    'speaker lease retains one socket through inactive and hidden reconnects',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      final syncReasons = <RealtimeSyncReason>[];
      final backgroundSyncReasons = <RealtimeSyncReason>[];
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async =>
            Uri.parse('ws://localhost/ws/v2?ticket=test'),
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        reconnectDelays: const [Duration(milliseconds: 1)],
        stableConnectionWindow: Duration.zero,
        randomDouble: () => 1,
      );
      final lease = manager.acquireBackgroundConnection('payment_speaker');
      addTearDown(lease.release);
      addTearDown(manager.shutdown);
      final subscription = manager.syncRequests.listen(syncReasons.add);
      final backgroundSyncSubscription = manager.backgroundSpeakerSyncRequests
          .listen(backgroundSyncReasons.add);
      addTearDown(subscription.cancel);
      addTearDown(backgroundSyncSubscription.cancel);

      await manager.syncSession('session-1');
      await tester.pump();
      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);
      expect(manager.backgroundConnectionRequirementCount, 1);

      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);

      manager.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(connections, hasLength(1));
      expect(manager.isConnected, isTrue);

      await connections.first.closeFromServer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(connections, hasLength(2));
      expect(manager.isConnected, isTrue);
      expect(syncReasons, isNot(contains(RealtimeSyncReason.reconnected)));
      expect(backgroundSyncReasons, contains(RealtimeSyncReason.reconnected));

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(connections, hasLength(2));
      expect(syncReasons, contains(RealtimeSyncReason.appResumed));
      expect(
        backgroundSyncReasons,
        isNot(contains(RealtimeSyncReason.appResumed)),
      );

      manager.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump();
      expect(manager.isConnected, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(connections, hasLength(2));
    },
  );

  testWidgets(
    'releasing the last speaker lease pauses a hidden socket until resume',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async =>
            Uri.parse('ws://localhost/ws/v2?ticket=test'),
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        reconnectDelays: const [Duration(milliseconds: 1)],
        stableConnectionWindow: Duration.zero,
        randomDouble: () => 1,
      );
      addTearDown(manager.shutdown);
      final lease = manager.acquireBackgroundConnection('payment_speaker');

      await manager.syncSession('session-1');
      await tester.pump();
      manager.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(manager.isConnected, isTrue);

      lease.release();
      await tester.pump();
      expect(manager.backgroundConnectionRequirementCount, 0);
      expect(manager.isConnected, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(connections, hasLength(1));

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(connections, hasLength(2));
      expect(manager.isConnected, isTrue);
    },
  );

  testWidgets(
    'background lease isolates speaker events and releases UI events once on resume',
    (tester) async {
      final connections = <_FakeRealtimeConnection>[];
      final foregroundEvents = <RealtimeEnvelope>[];
      final backgroundSpeakerEvents = <RealtimeEnvelope>[];
      final foregroundSyncReasons = <RealtimeSyncReason>[];
      final manager = RealtimeConnectionManager(
        issueConnectionUri: () async =>
            Uri.parse('ws://localhost/ws/v2?ticket=test'),
        connector: (uri) {
          final connection = _FakeRealtimeConnection();
          connections.add(connection);
          return connection;
        },
        stableConnectionWindow: Duration.zero,
      );
      final lease = manager.acquireBackgroundConnection('payment_speaker');
      addTearDown(lease.release);
      addTearDown(manager.shutdown);
      final foregroundEventSubscription = manager.events.listen(
        foregroundEvents.add,
      );
      final backgroundEventSubscription = manager.backgroundSpeakerEvents
          .listen(backgroundSpeakerEvents.add);
      final foregroundSyncSubscription = manager.syncRequests.listen(
        foregroundSyncReasons.add,
      );
      addTearDown(foregroundEventSubscription.cancel);
      addTearDown(backgroundEventSubscription.cancel);
      addTearDown(foregroundSyncSubscription.cancel);

      await manager.syncSession('session-1');
      await tester.pump();
      manager.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();

      final deferredEvents = <Map<String, Object>>[
        {
          'kind': 'QUICK_ACTION_LINKS_UPDATED',
          'id': 'quick-actions-hidden',
          'topic': 'quick-actions.links',
        },
        {
          'kind': 'PAYMENT_NOTIFICATION',
          'id': 'vietqr-hidden',
          'topic': 'payment.transactions',
        },
        {
          'kind': 'SALES_REPORT_ORDERS_UPDATED',
          'id': 'sales-report-hidden',
          'topic': 'sales-report.orders',
        },
        {
          'kind': 'STATEMENT_ORDER_TRANSFER_REQUEST',
          'id': 'bank-statement-hidden',
          'topic': 'notifications.statement-transfer',
        },
        {
          'kind': 'OFFSET_ADJUSTMENT_NOTIFICATION',
          'id': 'offset-adjustment-hidden',
          'topic': 'notifications.offset-adjustment',
        },
      ];
      for (var index = 0; index < deferredEvents.length; index += 1) {
        final event = deferredEvents[index];
        connections.single.add(
          _realtimeMessage(
            kind: event['kind']! as String,
            id: event['id']! as String,
            topic: event['topic']! as String,
            sequence: index + 1,
          ),
        );
      }
      connections.single.add(
        _realtimeMessage(
          kind: 'PAYMENT_SPEAKER_STREAM',
          id: 'speaker-hidden',
          topic: 'payment.speaker',
          sequence: 100,
        ),
      );
      await tester.pump();

      expect(foregroundEvents, isEmpty);
      expect(backgroundSpeakerEvents.map((event) => event.id), [
        'speaker-hidden',
      ]);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(
        foregroundEvents.map((event) => event.id),
        deferredEvents.map((event) => event['id']),
      );
      expect(
        foregroundSyncReasons
            .where((reason) => reason == RealtimeSyncReason.appResumed)
            .length,
        1,
      );
      expect(connections, hasLength(1));
    },
  );
}

String _realtimeMessage({
  required String kind,
  required String id,
  required String topic,
  required int sequence,
}) => jsonEncode({
  'v': 2,
  'kind': kind,
  'id': id,
  'topic': topic,
  'seq': sequence,
  'ts': '2026-07-24T10:30:05Z',
  'data': const <String, Object>{},
});

class _FakeRealtimeConnection implements RealtimeConnection {
  final StreamController<dynamic> _controller = StreamController<dynamic>();
  bool closed = false;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _controller.stream;

  void add(dynamic value) => _controller.add(value);

  Future<void> closeFromServer() => _controller.close();

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}
