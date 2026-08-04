import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/core/platform/app_restart_service.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_amount_audio_composer.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/domain/map_payment_transaction.dart';
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

  test(
    'keeps transaction sync running without speaker polling when muted',
    () async {
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
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.isActive, isTrue);
      expect(provider.isSpeakerEnabled, isFalse);
      expect(repository.transactionFetchCount, greaterThan(0));
      expect(repository.readyFetchCount, 0);
      expect(repository.ackEvents, isEmpty);
      expect(speaker.playCount, 0);

      provider.dispose();
    },
  );

  test(
    'same-user monitor revoke rejects the in-flight poll response',
    () async {
      final pending = Completer<StoredPaymentTransactionsPage>();
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        pendingTransactionPage: pending,
      );
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(), isInitialized: true);
      await _waitUntil(() => repository.transactionFetchCount == 1);

      provider.syncAuth(_storeUser(canMonitor: false), isInitialized: true);
      pending.complete(
        StoredPaymentTransactionsPage(
          transactions: [_paymentTransaction(id: 'stale-transaction')],
          page: 0,
          limit: 10,
          total: 1,
          canReviewOrderTransfers: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasMonitorScope, isFalse);
      expect(provider.isActive, isFalse);
      expect(provider.latestTransactions, isEmpty);
      expect(provider.canReviewOrderTransfers, isFalse);
    },
  );

  test('does not create a speaker-ready fallback timer', () async {
    var periodicTimerCount = 0;
    final periodicDurations = <Duration>[];
    late PaymentMonitorProvider provider;
    final repository = _FakePaymentMonitorRepository(notifications: const []);

    await runZoned(
      () async {
        provider = PaymentMonitorProvider(
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
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          periodicTimerCount += 1;
          periodicDurations.add(duration);
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ),
    );

    expect(periodicTimerCount, 0);
    expect(periodicDurations, isEmpty);
    expect(repository.transactionFetchCount, 1);
    provider.dispose();
  });

  test('persists the selected speaker voice preset locally', () async {
    final firstProvider = PaymentMonitorProvider(
      _FakePaymentMonitorRepository(notifications: const []),
      _FakePaymentSpeaker(),
      null,
      retryDelay,
    );
    await Future<void>.delayed(Duration.zero);
    firstProvider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () =>
          firstProvider.canConfigurePaymentSpeaker && !firstProvider.isLoading,
    );

    await firstProvider.setSpeakerVoicePreset('mien-nam-phuong-ly');
    expect(firstProvider.speakerVoicePresetId, 'mien-nam-phuong-ly');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(AppStorageKeys.shared('payment_monitor_voice_preset')),
      'mien-nam-phuong-ly',
    );
    firstProvider.dispose();

    final secondProvider = PaymentMonitorProvider(
      _FakePaymentMonitorRepository(notifications: const []),
      _FakePaymentSpeaker(),
      null,
      retryDelay,
    );
    addTearDown(secondProvider.dispose);
    await _waitUntil(
      () => secondProvider.speakerVoicePresetId == 'mien-nam-phuong-ly',
    );
    expect(secondProvider.speakerVoicePreset.label, 'Miền Nam — Phương Ly');
  });

  test(
    'loads transactions but skips notification polling without speaker feature',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
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
    'explains speaker pause while viewing multiple assigned stores',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_multiStoreUser(), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.isActive, isTrue);
      expect(provider.canUsePaymentSpeaker, isFalse);
      expect(provider.isViewingMultipleStores, isTrue);
      expect(provider.speakerSelectionNotice, contains('chọn đúng 1 showroom'));
      expect(repository.readyFetchCount, 0);
      expect(repository.requestedStoreIds.last, 'CP62,CP75');

      provider.setSelectedStoreIds({'CP75'});
      await _waitUntil(
        () => repository.transactionFetchCount > 1 && !provider.isLoading,
      );

      expect(provider.canUsePaymentSpeaker, isTrue);
      expect(provider.isViewingMultipleStores, isFalse);
      expect(provider.speakerSelectionNotice, isNull);
      expect(repository.requestedStoreIds.last, 'CP75');

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
          () => repository.transactionFetchCount > 0 && !provider.isLoading,
        );

        expect(provider.canUsePaymentSpeaker, isTrue);
        expect(repository.readyFetchCount, 0);

        provider.dispose();
      }
    },
  );

  test(
    'plays realtime server audio on Android without local preset playback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.canUsePaymentSpeaker, isTrue);
      expect(provider.isActive, isTrue);
      expect(repository.transactionFetchCount, greaterThan(0));

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-android'),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('PLAYED'));

      expect(repository.streamDownloadCount, 1);
      expect(repository.downloadCount, 0);
      expect(repository.requestedIncludeCues, contains(true));
      expect(speaker.playCount, 1);
      expect(speaker.playLocalCueValues, [false]);
      expect(speaker.playLocalCuePrefixValues, [false]);

      provider.dispose();
    },
  );

  test(
    'plays realtime server audio on iOS/iPadOS without local preset playback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.canUsePaymentSpeaker, isTrue);
      expect(provider.isActive, isTrue);
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-ios'),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('PLAYED'));

      expect(repository.streamDownloadCount, 1);
      expect(repository.downloadCount, 0);
      expect(speaker.playCount, 1);
      expect(speaker.playLocalCueValues, [false]);
      expect(speaker.playLocalCuePrefixValues, [false]);
    },
  );

  test(
    'lets SUPER_ADMIN enable a speaker scope after choosing a store',
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
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_superAdmin(), isInitialized: true);

      expect(provider.canUsePaymentSpeaker, isFalse);
      expect(provider.hasMonitorScope, isFalse);
      expect(repository.readyFetchCount, 0);

      provider.setStoreOverride('cp62');
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      expect(provider.hasMonitorScope, isTrue);
      expect(repository.requestedRateLimitCooldownBypasses.last, isTrue);
      expect(repository.readyFetchCount, 0);
      expect(repository.downloadCount, 0);
      expect(repository.streamDownloadCount, 0);
      expect(repository.ackEvents, isEmpty);
      expect(speaker.playCount, 0);

      provider.dispose();
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

  test('loads payment order review state from stored transactions', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      canReviewOrderTransfers: true,
      transactions: [
        _paymentTransaction(
          id: 'txn-pending',
          orders: const ['26052112345678'],
          pendingRequestId: 'request-1',
          requestedOrders: const ['26052287654321'],
        ),
      ],
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

    expect(provider.canReviewOrderTransfers, isTrue);
    expect(
      provider.latestTransactions.single.hasPendingOrderTransferRequest,
      isTrue,
    );
    expect(provider.latestTransactions.single.orderTransferRequestedOrders, [
      '26052287654321',
    ]);

    provider.dispose();
  });

  test('saves payment monitor orders and replaces the visible row', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactions: [_paymentTransaction(id: 'txn-1')],
    );
    repository.updatedTransaction = _paymentTransaction(
      id: 'txn-1',
      orders: const ['26052287654321'],
      canEditOrders: true,
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

    await provider.updateOrders('txn-1', '26052287654321');

    expect(repository.savedOrderInputs.single, ['26052287654321']);
    expect(repository.savedOrderTransactionKeys.single, 'key-txn-1');
    expect(provider.latestTransactions.single.orders, ['26052287654321']);
    expect(provider.rowMessages['txn-1']?.text, 'Đã cập nhật mã đơn hàng.');

    provider.dispose();
  });

  test('rejects blank payment order input without an existing order', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactions: [_paymentTransaction(id: 'txn-blank')],
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

    final saved = await provider.updateOrders('txn-blank', '  ');

    expect(saved, isFalse);
    expect(repository.savedOrderInputs, isEmpty);
    expect(
      provider.rowMessages['txn-blank']?.text,
      'Mã đơn hàng phải gồm 14 chữ số, ngăn cách bằng dòng hoặc dấu phẩy.',
    );

    provider.dispose();
  });

  test('allows blank payment order input to remove existing orders', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactions: [
        _paymentTransaction(id: 'txn-delete', orders: const ['26052112345678']),
      ],
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

    final saved = await provider.updateOrders('txn-delete', '');

    expect(saved, isTrue);
    expect(repository.savedOrderInputs.single, isEmpty);
    expect(provider.latestTransactions.single.orders, isEmpty);

    provider.dispose();
  });

  test(
    'exposes payment ERP loading and keeps API failure in the row',
    () async {
      final pending = Completer<void>();
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        transactions: [_paymentTransaction(id: 'txn-error')],
        pendingOrderUpdate: pending,
        updateOrdersError: ApiException('ERP tạm thời chưa phản hồi', 503),
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

      final save = provider.updateOrders('txn-error', '26052287654321');
      await Future<void>.delayed(Duration.zero);
      expect(provider.isUpdatingOrders('txn-error'), isTrue);

      pending.complete();
      expect(await save, isFalse);
      expect(provider.isUpdatingOrders('txn-error'), isFalse);
      expect(
        provider.rowMessages['txn-error']?.text,
        'ERP tạm thời chưa phản hồi',
      );

      provider.dispose();
    },
  );

  test('updates payment tracking and replaces the visible row', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactions: [
        _paymentTransaction(
          id: 'txn-track',
          orders: const ['26052112345678'],
          canManageOrderTracking: true,
        ),
      ],
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

    final updated = await provider.updateOrderTracking(
      'txn-track',
      'UNFOLLOWED',
    );

    expect(updated, isTrue);
    expect(repository.updatedTrackingStatuses, ['UNFOLLOWED']);
    expect(repository.trackingCooldownBypasses, [isTrue]);
    expect(provider.latestTransactions.single.isFollowing, isFalse);
    expect(
      provider.rowMessages['txn-track']?.text,
      'Đã bỏ theo dõi giao dịch.',
    );

    provider.dispose();
  });

  test('blocks payment tracking update without permission', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      transactions: [_paymentTransaction(id: 'txn-no-track')],
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

    final updated = await provider.updateOrderTracking(
      'txn-no-track',
      'UNFOLLOWED',
    );

    expect(updated, isFalse);
    expect(repository.updatedTrackingStatuses, isEmpty);
    expect(
      provider.rowMessages['txn-no-track']?.text,
      'Không thể thay đổi trạng thái theo dõi giao dịch.',
    );

    provider.dispose();
  });

  test(
    'requests payment order transfer and refreshes the current page',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        transactions: [
          _paymentTransaction(id: 'txn-1', orders: const ['26052112345678']),
        ],
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
      final fetchCount = repository.transactionFetchCount;

      final ok = await provider.requestOrderTransfer('txn-1', '26052287654321');

      expect(ok, isTrue);
      expect(repository.requestedOrderTransfers.single, ['26052287654321']);
      expect(repository.requestedOrderTransferTransactionIds.single, 'txn-1');
      expect(
        repository.requestedOrderTransferTransactionKeys.single,
        'key-txn-1',
      );
      expect(repository.transactionFetchCount, greaterThan(fetchCount));
      expect(provider.rowMessages['txn-1']?.text, 'Đã cập nhật mã đơn hàng.');

      provider.dispose();
    },
  );

  test(
    'realtime payment event refreshes transactions without reading ready audio',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        notificationBatches: [
          const [],
          [
            _readyNotification(
              notificationId: 'note-1',
              transactionId: 'txn-1',
            ),
          ],
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
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      final initialFetchCount = repository.transactionFetchCount;

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: {
            'notificationId': 'note-1',
            'transactionId': 'txn-1',
            'storeCode': 'CP01',
            'amount': 1250000,
            'audioStatus': 'READY',
          },
        ),
      );
      await _waitUntil(
        () =>
            repository.transactionFetchCount > initialFetchCount &&
            !provider.isLoading,
      );

      expect(repository.requestedIncludeTotals.first, isTrue);
      expect(repository.requestedIncludeTotals.last, isFalse);
      expect(repository.readyFetchCount, 0);
      expect(speaker.playCount, 0);
      expect(repository.ackEvents, isEmpty);

      provider.dispose();
    },
  );

  test(
    'inactive payment route keeps cache and refreshes once for a matching realtime event',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): false,
      });
      final transactions = <MapPaymentTransaction>[
        _paymentTransaction(id: 'txn-existing'),
      ];
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        transactions: transactions,
      );
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount == 1 && !provider.isLoading,
      );

      provider.syncRuntime(isForeground: true, isListViewActive: false);
      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(provider.isActive, isTrue);
      expect(
        provider.latestTransactions.single.transactionNumber,
        'txn-existing',
      );
      expect(repository.transactionFetchCount, 1);

      transactions.add(_paymentTransaction(id: 'txn-new'));
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {
            'notificationId': 'note-new',
            'transactionId': 'txn-new',
            'storeCode': 'CP01',
            'amount': 750000,
          },
        ),
      );
      await _waitUntil(
        () => repository.transactionFetchCount == 2 && !provider.isLoading,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repository.transactionFetchCount, 2);
      expect(
        provider.latestTransactions.map((item) => item.transactionNumber),
        containsAll(<String>['txn-existing', 'txn-new']),
      );
      expect(repository.readyFetchCount, 0);
    },
  );

  test(
    'inactive payment route ignores other stores and refreshes assigned stores',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): false,
      });
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_multiStoreUser(), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount == 1 && !provider.isLoading,
      );
      provider.syncRuntime(isForeground: true, isListViewActive: false);

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {'storeCode': 'CP99'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(repository.transactionFetchCount, 1);

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {'storeCode': 'CP75'},
          sequence: 2,
        ),
      );
      await _waitUntil(
        () => repository.transactionFetchCount == 2 && !provider.isLoading,
      );

      expect(repository.transactionFetchCount, 2);
      expect(repository.requestedStoreIds, everyElement('CP62,CP75'));
      expect(repository.readyFetchCount, 0);
    },
  );

  test(
    'background runtime defers event refresh until foreground once',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): false,
      });
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        transactions: [_paymentTransaction(id: 'txn-existing')],
      );
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount == 1 && !provider.isLoading,
      );

      provider.syncRuntime(
        isForeground: false,
        isListViewActive: false,
        allowBackgroundSpeakerRuntime: true,
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {'storeCode': 'CP01'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(provider.isActive, isTrue);
      expect(
        provider.latestTransactions.single.transactionNumber,
        'txn-existing',
      );
      expect(repository.transactionFetchCount, 1);

      provider.syncRuntime(
        isForeground: true,
        isListViewActive: false,
        allowBackgroundSpeakerRuntime: true,
      );
      await _waitUntil(
        () => repository.transactionFetchCount == 2 && !provider.isLoading,
      );
      provider.syncRuntime(
        isForeground: true,
        isListViewActive: false,
        allowBackgroundSpeakerRuntime: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(repository.transactionFetchCount, 2);
    },
  );

  test(
    'background speaker event plays without refreshing the transaction list',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): true,
      });
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker();
      final realtime = _FakeRealtimeClient();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        realtime,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      provider.syncRuntime(
        isForeground: true,
        isListViewActive: true,
        allowBackgroundSpeakerRuntime: true,
      );
      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () =>
            repository.transactionFetchCount == 1 &&
            !provider.isLoading &&
            realtime.activeBackgroundLeaseCount == 1,
      );
      final initialTransactionFetchCount = repository.transactionFetchCount;

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {'storeCode': 'CP01'},
          sequence: 2,
        ),
      );
      provider.syncRuntime(
        isForeground: false,
        isListViewActive: false,
        allowBackgroundSpeakerRuntime: true,
      );
      realtime.addBackgroundSpeakerEvent(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-background', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('PLAYED'));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(speaker.playCount, 1);
      expect(repository.transactionFetchCount, initialTransactionFetchCount);
      expect(realtime.activeBackgroundLeaseCount, 1);

      provider.dispose();
      expect(realtime.activeBackgroundLeaseCount, 0);
      await realtime.dispose();
    },
  );

  test('background reconnect sync does not read a speaker backlog', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final realtime = _FakeRealtimeClient();
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      retryDelay,
      realtime,
      const Duration(hours: 1),
    );

    provider.syncRuntime(
      isForeground: true,
      isListViewActive: true,
      allowBackgroundSpeakerRuntime: true,
    );
    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount == 1 && !provider.isLoading,
    );
    final initialTransactionFetchCount = repository.transactionFetchCount;

    provider.syncRuntime(
      isForeground: false,
      isListViewActive: false,
      allowBackgroundSpeakerRuntime: true,
    );
    realtime.addBackgroundSpeakerSync(RealtimeSyncReason.reconnected);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repository.readyFetchCount, 0);
    expect(repository.ackEvents, isEmpty);
    expect(repository.transactionFetchCount, initialTransactionFetchCount);

    provider.dispose();
    await realtime.dispose();
  });

  test('speaker lease releases on mute detached logout and dispose', () async {
    final realtime = _FakeRealtimeClient();
    final provider = PaymentMonitorProvider(
      _FakePaymentMonitorRepository(notifications: const []),
      _FakePaymentSpeaker(),
      null,
      retryDelay,
      realtime,
    );

    provider.syncRuntime(
      isForeground: true,
      isListViewActive: false,
      allowBackgroundSpeakerRuntime: true,
    );
    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(() => realtime.activeBackgroundLeaseCount == 1);

    await provider.setSpeakerEnabled(false);
    expect(realtime.activeBackgroundLeaseCount, 0);

    await provider.setSpeakerEnabled(true);
    await _waitUntil(() => realtime.activeBackgroundLeaseCount == 1);

    provider.syncRuntime(
      isForeground: false,
      isListViewActive: false,
      allowBackgroundSpeakerRuntime: false,
    );
    expect(realtime.activeBackgroundLeaseCount, 0);

    provider.syncRuntime(
      isForeground: true,
      isListViewActive: false,
      allowBackgroundSpeakerRuntime: true,
    );
    await _waitUntil(() => realtime.activeBackgroundLeaseCount == 1);

    provider.syncAuth(null, isInitialized: true);
    expect(realtime.activeBackgroundLeaseCount, 0);

    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(() => realtime.activeBackgroundLeaseCount == 1);
    provider.dispose();

    expect(realtime.activeBackgroundLeaseCount, 0);
    expect(realtime.acquiredBackgroundLeaseCount, greaterThanOrEqualTo(4));
    await realtime.dispose();
  });

  test(
    'foreground resume on active payment route keeps cache without fetching',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): false,
      });
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        transactions: [_paymentTransaction(id: 'txn-existing')],
      );
      final provider = PaymentMonitorProvider(
        repository,
        _FakePaymentSpeaker(),
        null,
        retryDelay,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount == 1 && !provider.isLoading,
      );

      provider.syncRuntime(isForeground: false, isListViewActive: true);
      provider.syncRuntime(isForeground: true, isListViewActive: true);
      await Future<void>.delayed(const Duration(milliseconds: 650));

      expect(provider.isActive, isTrue);
      expect(
        provider.latestTransactions.single.transactionNumber,
        'txn-existing',
      );
      expect(repository.transactionFetchCount, 1);

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_NOTIFICATION',
          topic: 'payment.transactions',
          data: const {'storeCode': 'CP01'},
        ),
      );
      await _waitUntil(
        () => repository.transactionFetchCount == 2 && !provider.isLoading,
      );

      expect(repository.transactionFetchCount, 2);
    },
  );

  test('stream event skips without retry when speaker is disabled', () async {
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('payment_monitor_enabled'): false,
    });
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
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
      _realtimeEnvelope(
        kind: 'PAYMENT_SPEAKER_STREAM',
        topic: 'payment.speaker',
        data: _streamPayload('note-disabled'),
      ),
    );
    await _waitUntil(
      () =>
          repository.transactionFetchCount > initialFetchCount &&
          !provider.isLoading,
    );

    expect(provider.isSpeakerEnabled, isFalse);
    expect(repository.readyFetchCount, 0);
    expect(repository.streamDownloadCount, 0);
    expect(speaker.playCount, 0);
    expect(repository.ackEvents, contains('SILENCED'));
    expect(repository.ackErrors, contains('speaker_disabled'));

    provider.dispose();
  });

  test('local-asset stream composes and claims without audio HTTP', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final composer = _FakePaymentAmountAudioComposer(
      prefixBytes: const [1, 2, 3],
    );
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
      null,
      const Duration(seconds: 5),
      composer,
    );
    addTearDown(provider.dispose);

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );

    await provider.handleRealtimeMessageForTesting(
      _realtimeEnvelope(
        kind: 'PAYMENT_SPEAKER_STREAM',
        topic: 'payment.speaker',
        data: _streamPayload('note-local', localAsset: true),
      ),
    );
    await _waitUntil(() => repository.ackEvents.contains('PLAYED'));

    expect(composer.composeCount, 1);
    expect(repository.localClaimCount, 1);
    expect(repository.streamDownloadCount, 0);
    expect(repository.downloadCount, 0);
    expect(speaker.playCount, 1);
    expect(speaker.playLocalCuePrefixValues, [true]);
    expect(speaker.localPrefixBytesValues, [
      const [1, 2, 3],
    ]);
  });

  test(
    'missing local asset fails terminally without requesting stream audio',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker();
      final composer = _FakePaymentAmountAudioComposer(
        error: StateError('asset missing'),
      );
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        composer,
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-local-fallback', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('FAILED'));

      expect(repository.localClaimCount, 0);
      expect(repository.streamDownloadCount, 0);
      expect(repository.downloadCount, 0);
      expect(repository.requestedRawAmounts, isEmpty);
      expect(speaker.playCount, 0);
    },
  );

  test(
    'stream event retries local preset playback errors and logs them to server',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker(failuresBeforeSuccess: 1);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-retry', localAsset: true),
        ),
      );
      await _waitUntil(
        () => repository.ackEvents.contains('PLAYED') && speaker.playCount == 2,
      );

      expect(repository.downloadCount, 0);
      expect(repository.streamDownloadCount, 0);
      expect(repository.requestedRawAmounts, isEmpty);
      expect(repository.ackEvents, contains('STREAM_STARTED'));
      expect(repository.ackEvents, contains('PLAYBACK_FAILED'));
      expect(repository.ackEvents, contains('PLAYED'));
      expect(repository.ackErrors.single, contains('speaker failed'));

      provider.dispose();
    },
  );

  test(
    'stream event ignores duplicate local payloads without triggering extra ready drain',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker(
        playDelay: const Duration(milliseconds: 1000),
      );
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-race', localAsset: true),
        ),
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-race', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('PLAYED'));

      expect(repository.streamDownloadCount, 0);
      expect(repository.requestedStreamClientIds, isEmpty);
      expect(repository.downloadCount, 0);
      expect(repository.readyFetchCount, 0);
      expect(speaker.playCount, 1);
      expect(
        repository.ackEvents.where((event) => event == 'STREAM_STARTED'),
        hasLength(1),
      );
      expect(
        repository.ackEvents.where((event) => event == 'PLAYED'),
        hasLength(1),
      );

      provider.dispose();
    },
  );

  test(
    'stream duplicate-suppressed response is treated as a no-op without speaker error',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        localClaimError: ApiException(
          'Giao dịch này đang được xử lý trên máy hiện tại.',
          409,
        ),
      );
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-suppressed', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.localClaimCount == 1);

      expect(speaker.playCount, 0);
      expect(provider.speakerError, isNull);
      expect(repository.streamDownloadCount, 0);
      expect(repository.ackEvents, isNot(contains('FAILED')));
      expect(repository.ackEvents, isNot(contains('PLAYED')));
      expect(repository.ackEvents, isNot(contains('STREAM_STARTED')));

      provider.dispose();
    },
  );

  test(
    'expired stream response is treated as a no-op without retrying stale audio',
    () async {
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        localClaimError: ApiException('Thông báo đọc loa đã quá hạn.', 409),
      );
      final speaker = _FakePaymentSpeaker();
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );

      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-expired', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.localClaimCount == 1);

      expect(speaker.playCount, 0);
      expect(provider.speakerError, isNull);
      expect(repository.requestedRawAmounts, isEmpty);
      expect(repository.streamDownloadCount, 0);
      expect(repository.ackEvents, isNot(contains('FAILED')));
      expect(repository.ackEvents, isNot(contains('PLAYED')));
      expect(repository.ackEvents, isNot(contains('STREAM_STARTED')));

      provider.dispose();
    },
  );

  test('does not drain a ready notification backlog', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      notificationBatches: [
        [
          _readyNotification(notificationId: 'note-1', transactionId: 'txn-1'),
          _readyNotification(notificationId: 'note-2', transactionId: 'txn-2'),
          _readyNotification(notificationId: 'note-3', transactionId: 'txn-3'),
        ],
        [_readyNotification(notificationId: 'note-4', transactionId: 'txn-4')],
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
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );

    expect(repository.readyFetchCount, 0);
    expect(repository.downloadCount, 0);
    expect(repository.streamDownloadCount, 0);
    expect(speaker.playCount, 0);
    expect(repository.ackEvents, isEmpty);

    provider.dispose();
  });

  test('speaker-ready fallback is disabled without list refresh', () async {
    final repository = _FakePaymentMonitorRepository(
      notifications: const [],
      notificationBatches: [
        const [],
        [
          _readyNotification(
            notificationId: 'note-fallback',
            transactionId: 'txn-fallback',
          ),
        ],
      ],
    );
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount >= 1 && !provider.isLoading,
    );

    expect(repository.transactionFetchCount, 1);
    expect(repository.readyFetchCount, 0);
    expect(repository.streamDownloadCount, 0);
    expect(speaker.playCount, 0);

    provider.dispose();
  });

  test('shared realtime sync does not drain a speaker backlog', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final realtime = _FakeRealtimeClient();
    final provider = PaymentMonitorProvider(
      repository,
      _FakePaymentSpeaker(),
      null,
      retryDelay,
      realtime,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );
    final initialFetchCount = repository.transactionFetchCount;

    realtime.addEvent(
      _realtimeEnvelope(
        kind: 'PAYMENT_NOTIFICATION',
        topic: 'payment.speaker',
        data: const {'storeCode': 'CP01'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(repository.transactionFetchCount, initialFetchCount);

    realtime.addSync(RealtimeSyncReason.reconnected);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(provider.isActive, isTrue);
    expect(repository.transactionFetchCount, initialFetchCount);
    expect(repository.readyFetchCount, 0);

    realtime.addSync(RealtimeSyncReason.appResumed);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repository.transactionFetchCount, initialFetchCount);
    expect(repository.readyFetchCount, 0);

    realtime.addEvent(
      _realtimeEnvelope(
        kind: 'PAYMENT_NOTIFICATION',
        topic: 'payment.transactions',
        data: const {'storeCode': 'CP01'},
        sequence: 2,
      ),
    );
    await _waitUntil(
      () =>
          repository.transactionFetchCount == initialFetchCount + 1 &&
          !provider.isLoading,
    );

    expect(repository.requestedIncludeTotals.last, isFalse);
    expect(repository.requestedRateLimitCooldownBypasses.last, isFalse);

    provider.dispose();
    await realtime.dispose();
  });

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
    expect(repository.requestedRateLimitCooldownBypasses.last, isTrue);

    provider.dispose();
  });

  test(
    'queued manual refresh preserves its user-initiated bypass flag',
    () async {
      final pendingPage = Completer<StoredPaymentTransactionsPage>();
      final repository = _FakePaymentMonitorRepository(
        notifications: const [],
        pendingTransactionPage: pendingPage,
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
        () => repository.transactionFetchCount == 1 && provider.isLoading,
      );

      await provider.refreshNow();
      await provider.refreshNow();
      expect(repository.transactionFetchCount, 1);
      pendingPage.complete(
        const StoredPaymentTransactionsPage(
          transactions: [],
          page: 0,
          limit: 10,
          total: 0,
          canReviewOrderTransfers: false,
        ),
      );
      await _waitUntil(
        () => repository.transactionFetchCount == 2 && !provider.isLoading,
      );

      expect(repository.requestedRateLimitCooldownBypasses, [false, true]);
      provider.dispose();
    },
  );

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
      _realtimeEnvelope(
        kind: 'PAYMENT_NOTIFICATION',
        topic: 'payment.transactions',
        data: {
          'notificationId': 'note-throttled',
          'transactionId': 'txn-throttled',
          'storeCode': 'CP01',
          'amount': 1250000,
          'audioStatus': 'READY',
        },
      ),
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
    'retries local preset playback three times before acknowledging failed',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): true,
      });
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker(failuresBeforeSuccess: 99);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-retry-3', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('FAILED'));

      expect(repository.downloadCount, 0);
      expect(repository.streamDownloadCount, 0);
      expect(speaker.playCount, 3);
      expect(
        repository.ackEvents.where((event) => event == 'PLAYBACK_FAILED'),
        hasLength(2),
      );
      expect(
        repository.ackEvents.where((event) => event == 'STREAM_STARTED'),
        hasLength(1),
      );
      expect(repository.ackEvents, isNot(contains('PLAYED')));
      expect(provider.speakerError, isNotNull);

      provider.dispose();
    },
  );

  test('plays the selected local prefix with the composed amount', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
      null,
      const Duration(seconds: 5),
      _FakePaymentAmountAudioComposer(),
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );
    await provider.handleRealtimeMessageForTesting(
      _realtimeEnvelope(
        kind: 'PAYMENT_SPEAKER_STREAM',
        topic: 'payment.speaker',
        data: _streamPayload('note-local-prefix', localAsset: true),
      ),
    );
    await _waitUntil(() => repository.ackEvents.contains('PLAYED'));

    expect(repository.requestedRawAmounts, isEmpty);
    expect(repository.requestedIncludeCues, isEmpty);
    expect(repository.streamDownloadCount, 0);
    expect(repository.ackEvents, contains('STREAM_STARTED'));
    expect(
      repository.ackEvents.indexOf('STREAM_STARTED'),
      lessThan(repository.ackEvents.indexOf('PLAYED')),
    );
    expect(speaker.playLocalCueValues, [false]);
    expect(speaker.playLocalCuePrefixValues, [true]);
    expect(repository.downloadCount, 0);

    provider.dispose();
  });

  test('does not fall back to server-combined cue audio', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
      null,
      const Duration(seconds: 5),
      _FakePaymentAmountAudioComposer(error: StateError('asset missing')),
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );
    await provider.handleRealtimeMessageForTesting(
      _realtimeEnvelope(
        kind: 'PAYMENT_SPEAKER_STREAM',
        topic: 'payment.speaker',
        data: _streamPayload('note-no-combined-fallback', localAsset: true),
      ),
    );
    await _waitUntil(() => repository.ackEvents.contains('FAILED'));

    expect(repository.requestedRawAmounts, isEmpty);
    expect(repository.requestedIncludeCues, isEmpty);
    expect(speaker.playLocalCueValues, isEmpty);
    expect(speaker.playLocalCuePrefixValues, isEmpty);
    expect(repository.downloadCount, 0);
    expect(repository.streamDownloadCount, 0);

    provider.dispose();
  });

  test('rejects non-local speaker events without a TTS fallback', () async {
    final repository = _FakePaymentMonitorRepository(notifications: const []);
    final speaker = _FakePaymentSpeaker();
    final provider = PaymentMonitorProvider(
      repository,
      speaker,
      null,
      retryDelay,
    );

    await Future<void>.delayed(Duration.zero);
    provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
    await _waitUntil(
      () => repository.transactionFetchCount > 0 && !provider.isLoading,
    );
    await provider.handleRealtimeMessageForTesting(
      _realtimeEnvelope(
        kind: 'PAYMENT_SPEAKER_STREAM',
        topic: 'payment.speaker',
        data: _streamPayload('note-no-local-mode'),
      ),
    );
    await _waitUntil(() => repository.ackEvents.contains('FAILED'));

    expect(repository.requestedRawAmounts, isEmpty);
    expect(repository.requestedIncludeCues, isEmpty);
    expect(speaker.playLocalCueValues, isEmpty);
    expect(speaker.playLocalCuePrefixValues, isEmpty);
    expect(repository.downloadCount, 0);
    expect(repository.streamDownloadCount, 0);

    provider.dispose();
  });

  test(
    'final payment audio failure logs playback failures and acks failed',
    () async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('payment_monitor_enabled'): true,
      });
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker(failuresBeforeSuccess: 99);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-final-failure', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('FAILED'));

      expect(repository.downloadCount, 0);
      expect(repository.streamDownloadCount, 0);
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
      expect(provider.speakerError!.notificationId, 'note-final-failure');
      expect(provider.speakerError!.amount, 1250000);

      provider.dispose();
    },
  );

  test(
    'non-retryable payment audio failure acks failed without retries',
    () async {
      final repository = _FakePaymentMonitorRepository(notifications: const []);
      final speaker = _FakePaymentSpeaker(nonRetryableFailure: true);
      final provider = PaymentMonitorProvider(
        repository,
        speaker,
        null,
        retryDelay,
        null,
        const Duration(seconds: 5),
        _FakePaymentAmountAudioComposer(),
      );

      await Future<void>.delayed(Duration.zero);
      provider.syncAuth(_storeUser(storeId: 'CP01'), isInitialized: true);
      await _waitUntil(
        () => repository.transactionFetchCount > 0 && !provider.isLoading,
      );
      await provider.handleRealtimeMessageForTesting(
        _realtimeEnvelope(
          kind: 'PAYMENT_SPEAKER_STREAM',
          topic: 'payment.speaker',
          data: _streamPayload('note-nonretryable', localAsset: true),
        ),
      );
      await _waitUntil(() => repository.ackEvents.contains('FAILED'));

      expect(repository.downloadCount, 0);
      expect(repository.streamDownloadCount, 0);
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

User _multiStoreUser() {
  return const User(
    id: 'user-multi',
    email: 'multi@example.com',
    role: 'MANAGER',
    jobRoleCode: 'CASH',
    assignedStores: [
      StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
    ],
    featureAccess: {'PAYMENT_MONITOR': true, 'PAYMENT_SPEAKER': true},
  );
}

User _superAdmin() {
  return const User(
    id: 'super-1',
    email: 'admin@example.com',
    role: 'SUPER_ADMIN',
  );
}

PaymentNotification _readyNotification({
  String notificationId = 'note-1',
  String transactionId = 'txn-1',
}) {
  return PaymentNotification.fromJson({
    'notificationId': notificationId,
    'transactionId': transactionId,
    'storeCode': 'CP01',
    'amount': 1250000,
    'audioStatus': 'READY',
    'audioUrl': '/payment-notifications/$notificationId/audio',
    'streamUrl': '/payment-notifications/$notificationId/stream',
    'createdAt': '2026-05-21T10:00:00.000Z',
  });
}

MapPaymentTransaction _paymentTransaction({
  required String id,
  List<String> orders = const [],
  bool canEditOrders = true,
  bool canRequestOrderTransfer = true,
  String orderTrackingStatus = 'FOLLOWING',
  bool canManageOrderTracking = false,
  String? orderTrackingActionBlockedReason,
  String? pendingRequestId,
  List<String> requestedOrders = const [],
}) {
  return MapPaymentTransaction.fromJson({
    'transactionNumber': id,
    'transactionKey': 'key-$id',
    'amount': 1250000,
    'storeId': 'CP01',
    'status': '00',
    'orders': orders,
    'canEditOrders': canEditOrders,
    'canRequestOrderTransfer': canRequestOrderTransfer,
    'orderTrackingStatus': orderTrackingStatus,
    'canManageOrderTracking': canManageOrderTracking,
    if (orderTrackingActionBlockedReason != null)
      'orderTrackingActionBlockedReason': orderTrackingActionBlockedReason,
    if (pendingRequestId != null) ...{
      'orderTransferRequestId': pendingRequestId,
      'orderTransferStatus': 'PENDING',
      'orderTransferRequestedOrders': requestedOrders,
    },
  });
}

RealtimeEnvelope _realtimeEnvelope({
  required String kind,
  required String topic,
  required Map<String, dynamic> data,
  int sequence = 1,
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: kind,
    id: 'event-$kind-$sequence',
    topic: topic,
    sequence: sequence,
    timestamp: DateTime.utc(2026, 7, 15),
    data: data,
  );
}

Map<String, dynamic> _streamPayload(
  String notificationId, {
  bool localAsset = false,
}) {
  return {
    'notificationId': notificationId,
    'transactionId': 'txn-$notificationId',
    'storeCode': 'CP01',
    'amount': 1250000,
    'paidAt': '2026-06-27T01:00:00.000Z',
    'firstSeenAt': '2026-06-27T01:00:02.000Z',
    'streamUrl': '/payment-notifications/$notificationId/stream',
    'expiresAt': '2026-06-28T01:00:00.000Z',
    if (localAsset) ...{
      'currency': 'VND',
      'assetPackVersion': paymentAmountAudioPackVersion,
      'playbackMode': 'LOCAL_ASSET',
    },
  };
}

class _FakePaymentMonitorRepository extends PaymentMonitorRepository {
  final List<PaymentNotification> notifications;
  final List<List<PaymentNotification>> notificationBatches;
  final List<MapPaymentTransaction> transactions;
  final bool canReviewOrderTransfers;
  final Object? transactionError;
  final Object? localClaimError;
  final Object? updateOrdersError;
  final Completer<StoredPaymentTransactionsPage>? pendingTransactionPage;
  final Completer<void>? pendingOrderUpdate;
  final List<String> ackEvents = [];
  final List<String> ackErrors = [];
  final List<String?> requestedStartDates = [];
  final List<String?> requestedEndDates = [];
  final List<String?> requestedStoreIds = [];
  final List<bool> requestedIncludeTotals = [];
  final List<bool> requestedIncludeCues = [];
  final List<bool> requestedRawAmounts = [];
  final List<String?> requestedStreamClientIds = [];
  final List<List<String>> savedOrderInputs = [];
  final List<String?> savedOrderTransactionKeys = [];
  final List<String> updatedTrackingStatuses = [];
  final List<bool> trackingCooldownBypasses = [];
  final List<List<String>> requestedOrderTransfers = [];
  final List<String> requestedOrderTransferTransactionIds = [];
  final List<String?> requestedOrderTransferTransactionKeys = [];
  final List<bool> requestedRateLimitCooldownBypasses = [];
  final List<String> approvedRequestIds = [];
  final List<String> rejectedRequestIds = [];
  int transactionFetchCount = 0;
  int readyFetchCount = 0;
  int downloadCount = 0;
  int streamDownloadCount = 0;
  int localClaimCount = 0;
  int _notificationBatchIndex = 0;
  MapPaymentTransaction? updatedTransaction;

  _FakePaymentMonitorRepository({
    required this.notifications,
    this.notificationBatches = const [],
    this.transactions = const [],
    this.canReviewOrderTransfers = false,
    this.transactionError,
    this.localClaimError,
    this.updateOrdersError,
    this.pendingTransactionPage,
    this.pendingOrderUpdate,
  }) : super(ApiClient());

  @override
  Future<StoredPaymentTransactionsPage> fetchStoredTransactions({
    String? storeId,
    String? storeIds,
    bool allStores = false,
    String? date,
    String? startDate,
    String? endDate,
    int page = 0,
    int limit = 10,
    bool includeTotal = true,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    transactionFetchCount += 1;
    requestedRateLimitCooldownBypasses.add(allowRateLimitCooldownBypass);
    final pending = pendingTransactionPage;
    if (pending != null) return pending.future;
    final error = transactionError;
    if (error != null) throw error;
    requestedStoreIds.add(storeIds ?? storeId);
    requestedStartDates.add(startDate);
    requestedEndDates.add(endDate);
    requestedIncludeTotals.add(includeTotal);
    return StoredPaymentTransactionsPage(
      transactions: transactions,
      page: page,
      limit: limit,
      total: transactions.length,
      canReviewOrderTransfers: canReviewOrderTransfers,
    );
  }

  @override
  Future<MapPaymentTransaction> updateOrders(
    String transactionId,
    List<String> orders, {
    String? transactionKey,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    savedOrderInputs.add(orders);
    savedOrderTransactionKeys.add(transactionKey);
    await pendingOrderUpdate?.future;
    final error = updateOrdersError;
    if (error != null) throw error;
    return updatedTransaction ??
        MapPaymentTransaction.fromJson({
          'transactionNumber': transactionId,
          if (transactionKey != null) 'transactionKey': transactionKey,
          'amount': 1250000,
          'storeId': 'CP01',
          'status': '00',
          'orders': orders,
          'canEditOrders': true,
          'canRequestOrderTransfer': true,
        });
  }

  @override
  Future<MapPaymentTransaction> updateOrderTracking(
    String transactionId,
    String status, {
    bool allowRateLimitCooldownBypass = false,
  }) async {
    updatedTrackingStatuses.add(status);
    trackingCooldownBypasses.add(allowRateLimitCooldownBypass);
    final existing = transactions.firstWhere(
      (transaction) => transaction.id == transactionId,
    );
    return MapPaymentTransaction.fromJson({
      'id': existing.id,
      'transactionNumber': existing.transactionNumber,
      'transactionReference': existing.transactionReference,
      'transactionKey': existing.transactionKey,
      'amount': existing.amount,
      'content': existing.content,
      'storeId': existing.storeId,
      'status': existing.status,
      'orders': existing.orders,
      'orderTrackingStatus': status,
      'canManageOrderTracking': existing.canManageOrderTracking,
      'canEditOrders': status == 'FOLLOWING',
      'canRequestOrderTransfer': status == 'FOLLOWING',
    });
  }

  @override
  Future<void> createOrderTransferRequest(
    String transactionId,
    List<String> orders, {
    String? transactionKey,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    requestedOrderTransferTransactionIds.add(transactionId);
    requestedOrderTransferTransactionKeys.add(transactionKey);
    requestedOrderTransfers.add(orders);
  }

  @override
  Future<MapPaymentTransaction?> approveOrderTransferRequest(
    String requestId, {
    bool allowRateLimitCooldownBypass = false,
  }) async {
    approvedRequestIds.add(requestId);
    return updatedTransaction;
  }

  @override
  Future<MapPaymentTransaction?> rejectOrderTransferRequest(
    String requestId, {
    String? note,
    bool allowRateLimitCooldownBypass = false,
  }) async {
    rejectedRequestIds.add(requestId);
    return updatedTransaction;
  }

  @override
  Future<List<PaymentNotification>> fetchReadyNotifications({
    required String clientId,
    String? storeId,
    DateTime? afterCreatedAt,
    int limit = 10,
  }) async {
    readyFetchCount += 1;
    if (_notificationBatchIndex < notificationBatches.length) {
      final batch = notificationBatches[_notificationBatchIndex];
      _notificationBatchIndex += 1;
      return batch;
    }
    return notifications.take(limit).toList(growable: false);
  }

  @override
  Future<List<int>> downloadNotificationAudio(
    String notificationId, {
    bool includeCue = false,
    bool rawAmount = false,
  }) async {
    downloadCount += 1;
    requestedIncludeCues.add(includeCue);
    requestedRawAmounts.add(rawAmount);
    return const [0x52, 0x49, 0x46, 0x46, 0x00];
  }

  @override
  Future<List<int>> downloadNotificationStreamAudio(
    String notificationId, {
    bool includeCue = false,
    bool rawAmount = false,
    String? clientId,
  }) async {
    streamDownloadCount += 1;
    requestedStreamClientIds.add(clientId);
    requestedIncludeCues.add(includeCue);
    requestedRawAmounts.add(rawAmount);
    return const [0x52, 0x49, 0x46, 0x46, 0x00];
  }

  @override
  Future<void> claimNotificationForLocalPlayback(
    String notificationId, {
    required String clientId,
  }) async {
    localClaimCount += 1;
    final error = localClaimError;
    if (error != null) throw error;
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
  final Duration playDelay;
  final List<bool> playLocalCueValues = [];
  final List<bool> playLocalCuePrefixValues = [];
  final List<List<int>?> localPrefixBytesValues = [];
  int playCount = 0;

  _FakePaymentSpeaker({
    this.failuresBeforeSuccess = 0,
    this.nonRetryableFailure = false,
    this.playDelay = Duration.zero,
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
    List<int>? localPrefixBytes,
    bool playLocalCue = true,
    bool playLocalCuePrefix = false,
    Future<void> Function()? onPlaybackStarting,
  }) async {
    playCount += 1;
    playLocalCueValues.add(playLocalCue);
    playLocalCuePrefixValues.add(playLocalCuePrefix);
    localPrefixBytesValues.add(
      localPrefixBytes == null ? null : List<int>.from(localPrefixBytes),
    );
    if (onPlaybackStarting != null) {
      await onPlaybackStarting();
    }
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
    if (playDelay > Duration.zero) {
      await Future<void>.delayed(playDelay);
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

class _FakePaymentAmountAudioComposer implements PaymentAmountAudioComposer {
  final Object? error;
  final List<int> prefixBytes;
  int composeCount = 0;

  _FakePaymentAmountAudioComposer({
    this.error,
    this.prefixBytes = const [0x52],
  });

  @override
  Future<PaymentAmountAudioResult> compose({
    required int amount,
    required String assetPackVersion,
    required String voicePresetId,
  }) async {
    composeCount += 1;
    final failure = error;
    if (failure != null) throw failure;
    return PaymentAmountAudioResult(
      bytes: Uint8List.fromList(const [0x52, 0x49, 0x46, 0x46, 0x00]),
      prefixBytes: Uint8List.fromList(prefixBytes),
      voicePresetId: voicePresetId,
      assetIds: const ['chunk/leading/001', 'chunk/unit/đồng'],
      composeDurationMs: 1,
    );
  }
}

class _FakeRealtimeClient
    implements RealtimeClient, RealtimeBackgroundConnectionController {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();
  final _backgroundSpeakerEvents =
      StreamController<RealtimeEnvelope>.broadcast();
  final _backgroundSpeakerSyncRequests =
      StreamController<RealtimeSyncReason>.broadcast();
  int acquiredBackgroundLeaseCount = 0;
  int activeBackgroundLeaseCount = 0;

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  @override
  Stream<RealtimeEnvelope> get backgroundSpeakerEvents =>
      _backgroundSpeakerEvents.stream;

  @override
  Stream<RealtimeSyncReason> get backgroundSpeakerSyncRequests =>
      _backgroundSpeakerSyncRequests.stream;

  void addEvent(RealtimeEnvelope envelope) => _events.add(envelope);

  void addSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  void addBackgroundSpeakerEvent(RealtimeEnvelope envelope) =>
      _backgroundSpeakerEvents.add(envelope);

  void addBackgroundSpeakerSync(RealtimeSyncReason reason) =>
      _backgroundSpeakerSyncRequests.add(reason);

  @override
  RealtimeBackgroundConnectionLease acquireBackgroundConnection(String owner) {
    acquiredBackgroundLeaseCount += 1;
    activeBackgroundLeaseCount += 1;
    return _FakeRealtimeBackgroundConnectionLease(() {
      activeBackgroundLeaseCount -= 1;
    });
  }

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
    await _backgroundSpeakerEvents.close();
    await _backgroundSpeakerSyncRequests.close();
  }
}

class _FakeRealtimeBackgroundConnectionLease
    implements RealtimeBackgroundConnectionLease {
  _FakeRealtimeBackgroundConnectionLease(this._onRelease);

  void Function()? _onRelease;

  @override
  void release() {
    final onRelease = _onRelease;
    if (onRelease == null) return;
    _onRelease = null;
    onRelease();
  }
}

class _FakeAppRestartService extends AppRestartService {
  int restartCount = 0;

  @override
  Future<void> restart() async {
    restartCount += 1;
  }
}
