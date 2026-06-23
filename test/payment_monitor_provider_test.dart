import 'dart:convert';

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
    'loads transactions but skips notification polling without speaker feature',
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
      provider.syncAuth(_storeUser(canReadSpeaker: false), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.canUsePaymentSpeaker, isFalse);
      expect(provider.isActive, isTrue);
      expect(repository.transactionFetchCount, greaterThan(0));
      expect(repository.readyFetchCount, 0);
      expect(repository.downloadCount, 0);
      expect(repository.ackEvents, isEmpty);
      expect(speaker.playCount, 0);

      provider.dispose();
    },
  );

  test(
    'uses PAYMENT_SPEAKER feature instead of job role for speaker polling',
    () async {
      for (final roleCode in ['SA', 'warehouse']) {
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

  test('loads transactions on Android but does not enable speaker', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final repository = _FakePaymentMonitorRepository(
      notifications: [_readyNotification()],
    );
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );

    expect(provider.canUsePaymentSpeaker, isFalse);
    expect(provider.isActive, isTrue);
    expect(repository.transactionFetchCount, greaterThan(0));
    expect(repository.readyFetchCount, 0);
    expect(repository.downloadCount, 0);

    provider.dispose();
  });

  test('lets SUPER_ADMIN use speaker polling after choosing a store', () async {
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
    provider.syncAuth(_superAdmin(), isInitialized: true);

    expect(provider.canUsePaymentSpeaker, isTrue);
    expect(provider.hasMonitorScope, isFalse);
    expect(repository.readyFetchCount, 0);

    provider.setStoreOverride('cp62');
    await _waitUntil(
      () => repository.readyFetchCount > 0 && !provider.isLoading,
    );

    expect(provider.hasMonitorScope, isTrue);
    expect(repository.readyFetchCount, greaterThan(0));
    expect(repository.downloadCount, 1);
    expect(repository.ackEvents, contains('PLAYED'));
    expect(speaker.playCount, 1);

    provider.dispose();
  });

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

  test(
    'realtime payment event triggers lightweight transaction refresh',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      final initialFetchCount = repository.transactionFetchCount;

      await provider.handleRealtimeMessageForTesting(
        jsonEncode({
          'type': 'PAYMENT_NOTIFICATION',
          'payload': {
            'notificationId': 'note-1',
            'transactionId': 'txn-1',
            'storeCode': 'CP01',
            'amount': 1250000,
            'audioStatus': 'READY',
          },
        }),
      );
      await _waitUntil(
        () =>
            repository.transactionFetchCount > initialFetchCount &&
            !provider.isLoading,
      );

      expect(repository.requestedIncludeTotals.first, isTrue);
      expect(repository.requestedIncludeTotals.last, isFalse);

      provider.dispose();
    },
  );

  test('manual refresh requests total count for pagination', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );
    repository.requestedIncludeTotals.clear();

    await provider.refreshNow();
    await _waitUntil(() => !provider.isLoading);

    expect(repository.requestedIncludeTotals, contains(true));

    provider.dispose();
  });

  test('realtime refresh respects poll backoff after throttling', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactionError: ApiException('Too Many Requests', 429),
    );
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount == 1 && !provider.isLoading,
    );

    await provider.handleRealtimeMessageForTesting(
      jsonEncode({
        'type': 'PAYMENT_NOTIFICATION',
        'payload': {
          'notificationId': 'note-throttled',
          'transactionId': 'txn-throttled',
          'storeCode': 'CP01',
          'amount': 1250000,
          'audioStatus': 'READY',
        },
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(repository.transactionFetchCount, 1);

    await provider.refreshNow();
    expect(repository.transactionFetchCount, 2);

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
    'plays server-combined cue audio without local cue when available',
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
      provider.syncAuth(_storeUser(), isInitialized: true);
      await _waitUntil(
        () => repository.ackEvents.contains('PLAYED') && !provider.isLoading,
      );

      expect(repository.requestedIncludeCues, [true]);
      expect(speaker.playLocalCueValues, [false]);
      expect(repository.downloadCount, 1);

      provider.dispose();
    },
  );

  test(
    'falls back to TTS-only download with local cue when combined audio fails',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: [_readyNotification()],
        combinedAudioError: ApiException('Combined audio unavailable', 400),
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
        () => repository.ackEvents.contains('PLAYED') && !provider.isLoading,
      );

      expect(repository.requestedIncludeCues, [true, false]);
      expect(speaker.playLocalCueValues, [true]);
      expect(repository.downloadCount, 2);

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

User _storeUser({
  String? jobRoleCode = 'CASH',
  String storeId = 'store-uuid-1',
  bool canReadSpeaker = true,
  bool canMonitor = true,
}) {
  return User(
    id: 'user-1',
    email: 'staff@example.com',
    role: 'MANAGER',
    storeId: storeId,
    jobRoleCode: jobRoleCode,
    featureAccess: {
      if (canMonitor) 'PAYMENT_MONITOR': true,
      if (canReadSpeaker) 'PAYMENT_SPEAKER': true,
    },
  );
}

User _superAdmin() {
  return const User(
    id: 'super-1',
    email: 'admin@example.com',
    role: 'SUPER_ADMIN',
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
  final Object? combinedAudioError;
  final List<String> ackEvents = [];
  final List<String> ackErrors = [];
  final List<String?> requestedStartDates = [];
  final List<String?> requestedEndDates = [];
  final List<bool> requestedIncludeTotals = [];
  final List<bool> requestedIncludeCues = [];
  int transactionFetchCount = 0;
  int readyFetchCount = 0;
  int downloadCount = 0;

  _FakePaymentMonitorRepository({
    required this.notifications,
    this.transactionError,
    this.combinedAudioError,
  }) : super(ApiClient());

  @override
  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? date,
    String? startDate,
    String? endDate,
    int page = 0,
    int limit = 10,
    bool includeTotal = true,
  }) async {
    transactionFetchCount += 1;
    final error = transactionError;
    if (error != null) throw error;
    requestedStartDates.add(startDate);
    requestedEndDates.add(endDate);
    requestedIncludeTotals.add(includeTotal);
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
  Future<List<int>> downloadNotificationAudio(
    String notificationId, {
    bool includeCue = false,
  }) async {
    downloadCount += 1;
    requestedIncludeCues.add(includeCue);
    final error = combinedAudioError;
    if (includeCue && error != null) throw error;
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
  final List<bool> playLocalCueValues = [];
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
    bool playLocalCue = true,
  }) async {
    playCount += 1;
    playLocalCueValues.add(playLocalCue);
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
