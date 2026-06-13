import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/platform/app_restart_service.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/payment_notification.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const retryDelay = Duration(milliseconds: 1);

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
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('payment_monitor_enabled'): false,
    });
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
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () =>
          repository.transactionFetchCount > 0 &&
          repository.ackEvents.contains('SILENCED') &&
          !provider.isLoading,
    );

    expect(provider.isActive, isTrue);
    expect(provider.isSpeakerEnabled, isFalse);
    expect(repository.transactionFetchCount, greaterThan(0));
    expect(repository.ackEvents, contains('SILENCED'));
    expect(speaker.playCount, 0);

    provider.dispose();
  });

  test(
    'loads transactions but skips notification polling for ineligible job role',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: [_readyNotification()],
      );
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(jobRoleCode: 'SA'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.canUsePaymentSpeaker, isFalse);
      expect(provider.isActive, isFalse);
      expect(repository.transactionFetchCount, greaterThan(0));
      expect(repository.readyFetchCount, 0);
      expect(repository.downloadCount, 0);
      expect(repository.ackEvents, isEmpty);
      expect(speaker.playCount, 0);

      provider.dispose();
    },
  );

  test(
    'normalizes STORE_MANAGER and CASH job role codes for speaker polling',
    () async {
      for (final roleCode in ['store_manager', ' cash ']) {
        final repository = _FakePaymentMonitorRepository(
          notifications: const [],
        );
        final provider = PaymentMonitorProvider(
          repository,
          _FakePaymentSpeaker(),
          null,
          retryDelay,
        );

        await Future<void>.delayed(Duration.zero);
        provider.syncAuth(
          _storeUser(jobRoleCode: roleCode),
          isInitialized: true,
        );
        await _waitUntil(
          () => repository.readyFetchCount > 0 && !provider.isLoading,
        );

        expect(provider.canUsePaymentSpeaker, isTrue);
        expect(repository.readyFetchCount, greaterThan(0));

        provider.dispose();
      }
    },
  );

  test('requests stored transactions with the selected date range', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );

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

  test('stops monitor when polling returns an auth failure', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactionError: ApiException(
        'Phiên làm việc đã hết hạn. Vui lòng đăng nhập lại.',
        401,
      ),
    );
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );

    expect(provider.isActive, isFalse);
    expect(provider.errorMessage, contains('Phiên làm việc đã hết hạn'));
    expect(speaker.playCount, 0);

    provider.dispose();
  });

  test(
    'retries payment audio with cached bytes before acknowledging played',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: [_readyNotification()],
      );
      final speaker = _FakePaymentSpeaker(failuresBeforeSuccess: 1);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(), isInitialized: true);
      await _waitUntil(
        () => repository.ackEvents.contains('PLAYED') && !provider.isLoading,
      );

      expect(repository.downloadCount, 1);
      expect(speaker.playCount, 2);
      expect(
        repository.ackEvents.where((event) => event == 'PLAYBACK_FAILED'),
        hasLength(1),
      );
      expect(repository.ackEvents, contains('PLAYED'));
      expect(repository.ackEvents, isNot(contains('FAILED')));
      expect(provider.speakerError, isNull);

      provider.dispose();
    },
  );

  test(
    'final payment audio failure logs playback failures and acks failed',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: [_readyNotification()],
      );
      final speaker = _FakePaymentSpeaker(failuresBeforeSuccess: 99);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(), isInitialized: true);
      await _waitUntil(
        () => repository.ackEvents.contains('FAILED') && !provider.isLoading,
      );

      expect(repository.downloadCount, 1);
      expect(speaker.playCount, 3);
      expect(
        repository.ackEvents.where((event) => event == 'PLAYBACK_FAILED'),
        hasLength(2),
      );
      expect(
        repository.ackEvents.where((event) => event == 'FAILED'),
        hasLength(1),
      );
      expect(repository.ackErrors.last, contains('speaker failed 3'));
      expect(provider.speakerError, isNotNull);
      expect(provider.speakerError!.notificationId, 'note-1');
      expect(provider.speakerError!.amount, 1250000);

      provider.dispose();
    },
  );

  test(
    'non-retryable payment audio failure acks failed without retries',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: [_readyNotification()],
      );
      final speaker = _FakePaymentSpeaker(nonRetryableFailure: true);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(), isInitialized: true);
      await _waitUntil(
        () => repository.ackEvents.contains('FAILED') && !provider.isLoading,
      );

      expect(repository.downloadCount, 1);
      expect(speaker.playCount, 1);
      expect(repository.ackEvents, isNot(contains('PLAYBACK_FAILED')));
      expect(
        repository.ackEvents.where((event) => event == 'FAILED'),
        hasLength(1),
      );
      expect(repository.ackErrors.last, contains('audio output device'));
      expect(provider.speakerError, isNotNull);
      expect(
        provider.speakerError!.message,
        contains('Windows không nhận thiết bị âm thanh'),
      );

      provider.dispose();
    },
  );

  test('restartApp delegates to restart service', () async {
    final restartService = _FakeAppRestartService();
    final provider = PaymentMonitorProvider(
      _FakePaymentMonitorRepository(notifications: const []),
      _FakePaymentSpeaker(),
      restartService,
      retryDelay,
    );

    await provider.restartApp();

    expect(restartService.restartCount, 1);

    provider.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var i = 0; i < 200; i += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

User _storeUser({String? jobRoleCode = 'CASH'}) {
  return User(
    id: 'user-1',
    email: 'staff@example.com',
    role: 'MANAGER',
    storeId: 'store-uuid-1',
    jobRoleCode: jobRoleCode,
  );
}

PaymentNotification _readyNotification() {
  return PaymentNotification.fromJson({
    'notificationId': 'note-1',
    'transactionId': 'txn-1',
    'storeCode': 'CP01',
    'amount': 1250000,
    'audioStatus': 'READY',
    'audioUrl': '/payment-notifications/note-1/audio',
    'createdAt': '2026-05-21T10:00:00.000Z',
  });
}

class _FakePaymentMonitorRepository extends PaymentMonitorRepository {
  final List<PaymentNotification> notifications;
  final Object? transactionError;
  final List<String> ackEvents = [];
  final List<String> ackErrors = [];
  final List<String?> requestedStartDates = [];
  final List<String?> requestedEndDates = [];
  int transactionFetchCount = 0;
  int readyFetchCount = 0;
  int downloadCount = 0;

  _FakePaymentMonitorRepository({
    required this.notifications,
    this.transactionError,
  }) : super(ApiClient());

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
    final error = transactionError;
    if (error != null) throw error;
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
    readyFetchCount += 1;
    return notifications;
  }

  @override
  Future<List<int>> downloadNotificationAudio(String notificationId) async {
    downloadCount += 1;
    return const [0x52, 0x49, 0x46, 0x46, 0x00];
  }

  @override
  Future<void> acknowledgeNotification({
    required String notificationId,
    required String clientId,
    required String event,
    String? error,
  }) async {
    ackEvents.add(event);
    if (error != null) ackErrors.add(error);
  }
}

class _FakePaymentSpeaker extends PaymentSpeaker {
  final int failuresBeforeSuccess;
  final bool nonRetryableFailure;
  int playCount = 0;

  _FakePaymentSpeaker({
    this.failuresBeforeSuccess = 0,
    this.nonRetryableFailure = false,
  });

  @override
  Future<PaymentSpeakerResult> playServerAudio({
    required int amount,
    required List<int>? audioBytes,
    required String notificationId,
    required String transactionId,
    required String storeCode,
    required String clientId,
    required int attempt,
  }) async {
    playCount += 1;
    if (nonRetryableFailure) {
      throw const PaymentSpeakerException(
        'Windows does not report any audio output device',
        backendErrors: ['waveOutDevices=0'],
        retryable: false,
      );
    }
    if (playCount <= failuresBeforeSuccess) {
      throw StateError('speaker failed $playCount');
    }
    return const PaymentSpeakerResult(
      backend: 'fake',
      extension: 'wav',
      durationMs: 5,
      reportedSuccess: true,
      audibleVerified: false,
    );
  }
}

class _FakeAppRestartService extends AppRestartService {
  int restartCount = 0;

  @override
  Future<void> restart() async {
    restartCount += 1;
  }
}
