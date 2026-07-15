import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_delivery_metrics.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('loads delivery metrics for SUPER_ADMIN', () async {
    final repository = _FakePaymentMonitorRepository(_metrics(), _history());
    final provider = PaymentDeliveryMetricsProvider(
      repository,
      refreshInterval: Duration.zero,
    );

    await provider.syncAuth(_user(role: 'SUPER_ADMIN'), isInitialized: true);

    expect(repository.fetchCount, 1);
    expect(provider.metrics?.current.averageMs, 7242);
    expect(provider.shouldShow, isTrue);

    provider.dispose();
  });

  test('loads delivery history for SUPER_ADMIN', () async {
    final repository = _FakePaymentMonitorRepository(_metrics(), _history());
    final provider = PaymentDeliveryMetricsProvider(
      repository,
      refreshInterval: Duration.zero,
    );

    await provider.syncAuth(_user(role: 'SUPER_ADMIN'), isInitialized: true);
    await provider.loadHistory();

    expect(repository.historyFetchCount, 1);
    expect(provider.historyItems, hasLength(1));
    expect(provider.historyItems.single.storeCode, 'CP01');
    expect(provider.historyItems.single.bankToStreamStartLatencyMs, 7242);
    expect(provider.historyErrorMessage, isNull);

    provider.dispose();
  });

  test('does not load delivery metrics for non SUPER_ADMIN users', () async {
    final repository = _FakePaymentMonitorRepository(_metrics(), _history());
    final provider = PaymentDeliveryMetricsProvider(
      repository,
      refreshInterval: Duration.zero,
    );

    await provider.syncAuth(_user(role: 'USER'), isInitialized: true);

    expect(repository.fetchCount, 0);
    expect(repository.historyFetchCount, 0);
    expect(provider.metrics, isNull);
    expect(provider.shouldShow, isFalse);

    provider.dispose();
  });

  test('debounces only the typed delivery-metrics realtime topic', () async {
    final repository = _FakePaymentMonitorRepository(_metrics(), _history());
    final realtime = _FakeRealtimeClient();
    final provider = PaymentDeliveryMetricsProvider(
      repository,
      refreshInterval: Duration.zero,
      realtimeDebounce: const Duration(milliseconds: 20),
      realtimeClient: realtime,
    );

    await provider.syncAuth(_user(role: 'SUPER_ADMIN'), isInitialized: true);
    expect(repository.fetchCount, 1);

    realtime.addEvent(
      _envelope(
        kind: 'PAYMENT_DELIVERY_METRICS_UPDATED',
        topic: 'payment.transactions',
      ),
    );
    for (var index = 0; index < 3; index += 1) {
      realtime.addEvent(
        _envelope(
          kind: 'PAYMENT_DELIVERY_METRICS_UPDATED',
          topic: 'payment.delivery-metrics',
          sequence: index + 2,
        ),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repository.fetchCount, 2);

    realtime.addSync(RealtimeSyncReason.reconnected);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(repository.fetchCount, 3);

    await provider.syncRuntime(isForeground: false, isSurfaceActive: false);
    realtime.addEvent(
      _envelope(
        kind: 'PAYMENT_DELIVERY_METRICS_UPDATED',
        topic: 'payment.delivery-metrics',
        sequence: 10,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(repository.fetchCount, 3);

    provider.dispose();
    await realtime.dispose();
  });
}

RealtimeEnvelope _envelope({
  required String kind,
  required String topic,
  int sequence = 1,
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: kind,
    id: 'event-$sequence',
    topic: topic,
    sequence: sequence,
    timestamp: DateTime.utc(2026, 7, 15),
    data: const {},
  );
}

User _user({required String role}) {
  return User(id: 'user-$role', email: '$role@example.com', role: role);
}

PaymentDeliveryMetrics _metrics() {
  return PaymentDeliveryMetrics.fromJson({
    'sampledAt': '2026-06-27T02:00:00.000Z',
    'windowHours': 24,
    'current': {
      'count': 3,
      'averageMs': 7242,
      'from': '2026-06-26T02:00:00.000Z',
      'to': '2026-06-27T02:00:00.000Z',
    },
    'previous': {
      'count': 2,
      'averageMs': 8342,
      'from': '2026-06-25T02:00:00.000Z',
      'to': '2026-06-26T02:00:00.000Z',
    },
    'deltaMs': -1100,
    'deltaPercent': -13.2,
    'trend': 'down',
  });
}

PaymentDeliveryHistory _history() {
  return PaymentDeliveryHistory.fromJson({
    'sampledAt': '2026-06-27T02:00:00.000Z',
    'limit': 20,
    'list': [
      {
        'deliveryLogId': 'log-1',
        'notificationId': 'note-1',
        'transactionId': 'txn-1',
        'storeCode': 'CP01',
        'amount': 1250000,
        'paidAt': '2026-06-27T01:00:00.000Z',
        'firstSeenAt': '2026-06-27T01:00:02.003Z',
        'streamStartedAt': '2026-06-27T01:00:07.242Z',
        'playedAt': '2026-06-27T01:00:09.245Z',
        'status': 'PLAYED',
        'bankToStreamStartLatencyMs': 7242,
        'firstSeenToStreamStartLatencyMs': 5239,
        'playDurationMs': 2003,
        'firstSeenToPlayedMs': 7242,
      },
    ],
  });
}

class _FakePaymentMonitorRepository extends PaymentMonitorRepository {
  final PaymentDeliveryMetrics result;
  final PaymentDeliveryHistory historyResult;
  int fetchCount = 0;
  int historyFetchCount = 0;

  _FakePaymentMonitorRepository(this.result, this.historyResult)
    : super(ApiClient());

  @override
  Future<PaymentDeliveryMetrics> fetchDeliveryMetrics({
    int windowHours = 24,
  }) async {
    fetchCount += 1;
    return result;
  }

  @override
  Future<PaymentDeliveryHistory> fetchDeliveryHistory({int limit = 20}) async {
    historyFetchCount += 1;
    return historyResult;
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope envelope) => _events.add(envelope);

  void addSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
