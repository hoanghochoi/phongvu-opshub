import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
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
  int transactionFetchCount = 0;

  _FakePaymentMonitorRepository({required this.notifications})
    : super(ApiClient());

  @override
  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? date,
    int page = 0,
    int limit = 10,
  }) async {
    transactionFetchCount += 1;
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
