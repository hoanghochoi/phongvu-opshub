import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
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
