import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_delivery_metrics.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('opens recent speaker delivery history from chip', (
    tester,
  ) async {
    final repository = _FakePaymentMonitorRepository(_metrics(), _history());
    final provider = PaymentDeliveryMetricsProvider(
      repository,
      refreshInterval: Duration.zero,
    );
    await provider.syncAuth(_user(), isInitialized: true);

    await tester.pumpWidget(
      ChangeNotifierProvider<PaymentDeliveryMetricsProvider>.value(
        value: provider,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: PaymentDeliveryMetricsChip())),
        ),
      ),
    );

    expect(find.text('TB 7.2s'), findsOneWidget);

    await tester.tap(find.byType(PaymentDeliveryMetricsChip));
    await tester.pumpAndSettle();

    expect(repository.historyFetchCount, 1);
    expect(find.text('Lịch sử đọc loa'), findsOneWidget);
    expect(find.text('SR CP01'), findsOneWidget);
    expect(find.text('Ack PLAYED: 08:00:09 27/06/2026'), findsOneWidget);
    expect(find.textContaining('Trạng thái lỗi: Lỗi tạm thời'), findsOneWidget);

    provider.dispose();
  });
}

User _user() {
  return const User(
    id: 'super-1',
    email: 'super@example.com',
    role: 'SUPER_ADMIN',
  );
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
        'firstSeenAt': '2026-06-27T08:00:02.003',
        'playedAt': '2026-06-27T08:00:09.245',
        'status': 'PLAYED',
        'errorStatus': 'PLAYBACK_FAILED',
        'errorMessage': 'speaker failed attempt 1',
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
