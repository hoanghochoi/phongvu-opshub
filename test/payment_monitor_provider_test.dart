import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_notification.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('keeps transaction sync running when speaker is muted', () async {
    SharedPreferences.setMockInitialValues({'payment_monitor_enabled': false});
    final repository = _FakePaymentMonitorRepository(
      notifications: [
        PaymentNotification.fromJson({
          'notificationId': 'note-1',
          'transactionId': 'txn-1',
          'storeCode': 'CP01',
          'amount': 1250000,
          'audioStatus': 'READY',
          'audioUrl': '/payment-notifications/note-1/audio',
          'createdAt': '2026-05-21T10:00:00.000Z',
        }),
      ],
    );
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(repository, speaker);

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(
      const User(
        id: 'user-1',
        email: 'staff@example.com',
        role: 'MANAGER',
        storeId: 'store-uuid-1',
      ),
      isInitialized: true,
    );
    await _waitUntil(
      () =>
          repository.transactionFetchCount > 0 &&
          repository.ackEvents.contains('SILENCED'),
    );

    expect(provider.isActive, isTrue);
    expect(provider.isSpeakerEnabled, isFalse);
    expect(repository.transactionFetchCount, greaterThan(0));
    expect(repository.ackEvents, contains('SILENCED'));
    expect(speaker.playCount, 0);

    provider.dispose();
  });

  test('requests stored transactions with the selected date range', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(repository, speaker);

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(
      const User(
        id: 'user-1',
        email: 'staff@example.com',
        role: 'MANAGER',
        storeId: 'store-uuid-1',
      ),
      isInitialized: true,
    );
    await _waitUntil(() => repository.transactionFetchCount > 0);

    repository.requestedStartDates.clear();
    repository.requestedEndDates.clear();
    provider.setDateRange(DateTime(2026, 5, 23), DateTime(2026, 5, 27));
    await _waitUntil(
      () => repository.requestedStartDates.contains('2026-05-23'),
    );

    expect(repository.requestedStartDates, contains('2026-05-23'));
    expect(repository.requestedEndDates, contains('2026-05-27'));

    provider.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 20; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakePaymentMonitorRepository extends PaymentMonitorRepository {
  final List<PaymentNotification> notifications;
  final List<String> ackEvents = [];
  final List<String?> requestedStartDates = [];
  final List<String?> requestedEndDates = [];
  int transactionFetchCount = 0;

  _FakePaymentMonitorRepository({required this.notifications})
    : super(ApiClient());

  @override
  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? date,
    String? startDate,
    String? endDate,
    int page = 0,
    int limit = 10,
  }) async {
    transactionFetchCount += 1;
    requestedStartDates.add(startDate);
    requestedEndDates.add(endDate);
    return StoredPaymentTransactionsPage(
      transactions: const [],
      page: page,
      limit: limit,
      total: 0,
    );
  }

  @override
  Future<List<PaymentNotification>> fetchReadyNotifications({
    required String clientId,
    String? storeId,
    DateTime? afterCreatedAt,
    int limit = 10,
  }) async {
    return notifications;
  }

  @override
  Future<List<int>> downloadNotificationAudio(String notificationId) async {
    throw StateError('Audio should not download while speaker is muted');
  }

  @override
  Future<void> acknowledgeNotification({
    required String notificationId,
    required String clientId,
    required String event,
    String? error,
  }) async {
    ackEvents.add(event);
  }
}

class _FakePaymentSpeaker extends PaymentSpeaker {
  int playCount = 0;

  @override
  Future<void> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
  }) async {
    playCount += 1;
  }
}
