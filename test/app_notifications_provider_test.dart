import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notification_read_store.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notifications_feed_repository.dart';
import 'package:phongvu_opshub/features/notifications/presentation/providers/app_notifications_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient().setAuthToken(null);
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  group('AppNotificationsProvider', () {
    test('combines statement and offset counts in the global bell', () async {
      final bankRepository = _FakeBankStatementRepository(
        requests: [_statementRequest()],
        total: 2,
        canReview: true,
      );
      final offsetRepository = _FakeOffsetAdjustmentRepository(
        items: [_offsetAdjustment()],
        total: 3,
        canReview: true,
      );
      final provider = AppNotificationsProvider(
        bankRepository,
        offsetAdjustmentRepository: offsetRepository,
        feedRepository: _feedRepository(bankRepository, offsetRepository),
      );

      await _activate(provider);
      await provider.syncAuth(_financeReviewer, isInitialized: true);

      expect(provider.isEnabled, isTrue);
      expect(provider.count, 2);
      expect(provider.totalCount, 5);
      expect(provider.statementOrderRequests, hasLength(1));
      expect(provider.offsetAdjustmentRequests, hasLength(1));
      expect(bankRepository.fetchOrderTransferRequestsCount, 0);
      expect(offsetRepository.fetchListCount, 0);

      provider.dispose();
    });

    test(
      'keeps the global badge off for rows read on another device',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [
            _statementRequest(notificationReadAt: '2026-06-26T03:00:00.000Z'),
          ],
          total: 1,
          canReview: true,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [
            _offsetAdjustment(notificationReadAt: '2026-06-26T03:05:00.000Z'),
          ],
          total: 1,
          canReview: true,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: _feedRepository(bankRepository, offsetRepository),
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);

        expect(provider.count, 0);
        expect(provider.totalCount, 2);

        provider.dispose();
      },
    );

    test(
      'shows offset notifications even without bank-statement access',
      () async {
        final bankRepository = _FakeBankStatementRepository();
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 4,
          canReview: true,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: _feedRepository(bankRepository, offsetRepository),
        );

        await _activate(provider);
        await provider.syncAuth(_offsetReviewer, isInitialized: true);

        expect(provider.isEnabled, isTrue);
        expect(provider.count, 1);
        expect(provider.totalCount, 4);
        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 0);

        provider.dispose();
      },
    );

    test('loads rejected offset notifications for requesters', () async {
      final bankRepository = _FakeBankStatementRepository();
      final offsetRepository = _FakeOffsetAdjustmentRepository(
        items: [
          _offsetAdjustment(
            status: OffsetAdjustmentStatus.rejected,
            rejectReason: 'Sai mã đơn',
          ),
        ],
        total: 1,
      );
      final provider = AppNotificationsProvider(
        bankRepository,
        offsetAdjustmentRepository: offsetRepository,
        feedRepository: _feedRepository(bankRepository, offsetRepository),
      );

      await _activate(provider);
      await provider.syncAuth(_storeUser, isInitialized: true);

      expect(provider.isEnabled, isTrue);
      expect(provider.count, 1);
      expect(
        provider.offsetAdjustmentRequests.single.status,
        OffsetAdjustmentStatus.rejected,
      );
      expect(bankRepository.fetchOrderTransferRequestsCount, 0);
      expect(offsetRepository.fetchListCount, 0);

      provider.dispose();
    });

    test(
      'marks visible global notifications as read for the signed-in user',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [_statementRequest()],
          total: 1,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 1,
        );
        final readStore = _FakeNotificationReadStore();
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: _feedRepository(bankRepository, offsetRepository),
          notificationReadStore: readStore,
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);
        expect(provider.count, 2);

        await provider.markVisibleNotificationsRead();
        expect(provider.count, 0);

        final reloadedProvider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: _feedRepository(bankRepository, offsetRepository),
          notificationReadStore: readStore,
        );
        await _activate(reloadedProvider);
        await reloadedProvider.syncAuth(_financeReviewer, isInitialized: true);

        expect(reloadedProvider.count, 0);
        expect(reloadedProvider.totalCount, 2);
        expect(readStore.markedReadIdsBySource['statement_order_transfer'], {
          'statement-request-1',
        });
        expect(readStore.markedReadIdsBySource['offset_adjustment'], {
          'offset-1',
        });

        provider.dispose();
        reloadedProvider.dispose();
      },
    );

    test('lights the global badge again for a new notification id', () async {
      SharedPreferences.setMockInitialValues({
        'opshub.production.notifications.seen.statement_order_transfer.fin_1': [
          'statement-request-1',
        ],
      });
      final bankRepository = _FakeBankStatementRepository(
        requests: [
          _statementRequest(),
          _statementRequest(id: 'statement-request-2'),
        ],
        total: 2,
      );
      final offsetRepository = _FakeOffsetAdjustmentRepository();
      final provider = AppNotificationsProvider(
        bankRepository,
        offsetAdjustmentRepository: offsetRepository,
        feedRepository: _feedRepository(bankRepository, offsetRepository),
      );

      await _activate(provider);
      await provider.syncAuth(_financeReviewer, isInitialized: true);

      expect(provider.count, 1);
      expect(provider.totalCount, 2);

      provider.dispose();
    });

    test(
      'coalesces inactive realtime events into one load on activation',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [_statementRequest()],
          total: 1,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 1,
        );
        final realtime = _FakeRealtimeClient();
        final feedRepository = _feedRepository(
          bankRepository,
          offsetRepository,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: feedRepository,
          realtimeClient: realtime,
        );

        await provider.syncAuth(_financeReviewer, isInitialized: true);
        realtime.addEvent(
          _envelope(
            kind: 'STATEMENT_ORDER_TRANSFER_REQUEST',
            topic: 'notifications.statement-transfer',
          ),
        );
        realtime.addEvent(
          _envelope(
            kind: 'OFFSET_ADJUSTMENT_NOTIFICATION',
            topic: 'notifications.offset-adjustment',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 0);
        expect(feedRepository.fetchCount, 0);

        await _activate(provider);

        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 0);
        expect(feedRepository.fetchCount, 1);

        realtime.addEvent(
          _envelope(
            kind: 'STATEMENT_ORDER_TRANSFER_REQUEST',
            topic: 'payment.transactions',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(feedRepository.fetchCount, 1);

        provider.dispose();
        await realtime.dispose();
      },
    );

    test(
      'loads both notification sections with one aggregate request',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [_statementRequest()],
          total: 2,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 3,
        );
        final feedRepository = _feedRepository(
          bankRepository,
          offsetRepository,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: feedRepository,
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);

        expect(feedRepository.fetchCount, 1);
        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 0);
        expect(provider.totalCount, 5);

        provider.dispose();
      },
    );

    test(
      'does not reload an empty feed on repeated auth/runtime sync',
      () async {
        final bankRepository = _FakeBankStatementRepository();
        final offsetRepository = _FakeOffsetAdjustmentRepository();
        final feedRepository = _feedRepository(
          bankRepository,
          offsetRepository,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: feedRepository,
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);
        expect(feedRepository.fetchCount, 1);
        expect(provider.totalCount, 0);

        for (var index = 0; index < 5; index += 1) {
          await provider.syncRuntime(isForeground: true, isSurfaceActive: true);
          await provider.syncAuth(_financeReviewer, isInitialized: true);
        }
        await provider.syncRuntime(isForeground: false, isSurfaceActive: true);
        await provider.syncRuntime(isForeground: true, isSurfaceActive: true);

        expect(feedRepository.fetchCount, 1);

        provider.dispose();
      },
    );

    test('coalesces an active realtime burst into one feed request', () async {
      final bankRepository = _FakeBankStatementRepository(
        requests: [_statementRequest()],
        total: 1,
      );
      final offsetRepository = _FakeOffsetAdjustmentRepository(
        items: [_offsetAdjustment()],
        total: 1,
      );
      final realtime = _FakeRealtimeClient();
      final feedRepository = _feedRepository(bankRepository, offsetRepository);
      final provider = AppNotificationsProvider(
        bankRepository,
        offsetAdjustmentRepository: offsetRepository,
        feedRepository: feedRepository,
        realtimeClient: realtime,
        realtimeRefreshDebounce: const Duration(milliseconds: 10),
        realtimeRefreshMaxWait: const Duration(milliseconds: 40),
      );

      await _activate(provider);
      await provider.syncAuth(_financeReviewer, isInitialized: true);
      expect(feedRepository.fetchCount, 1);

      for (var index = 0; index < 8; index += 1) {
        realtime.addEvent(
          _envelope(
            kind: 'STATEMENT_ORDER_TRANSFER_REQUEST',
            topic: 'notifications.statement-transfer',
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(feedRepository.fetchCount, 2);

      provider.dispose();
      await realtime.dispose();
    });

    test(
      'falls back to legacy endpoints only when feed is unsupported',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [_statementRequest()],
          total: 1,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 1,
        );
        final feedRepository = _feedRepository(bankRepository, offsetRepository)
          ..error = ApiException('Not implemented', 501);
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: feedRepository,
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);

        expect(feedRepository.fetchCount, 1);
        expect(bankRepository.fetchOrderTransferRequestsCount, 1);
        expect(offsetRepository.fetchListCount, 1);
        expect(provider.totalCount, 2);

        provider.dispose();
      },
    );

    test(
      'retains stale rows without fan-out on network and 5xx failures',
      () async {
        final bankRepository = _FakeBankStatementRepository(
          requests: [_statementRequest()],
          total: 2,
        );
        final offsetRepository = _FakeOffsetAdjustmentRepository(
          items: [_offsetAdjustment()],
          total: 3,
        );
        final feedRepository = _feedRepository(
          bankRepository,
          offsetRepository,
        );
        final provider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          feedRepository: feedRepository,
        );

        await _activate(provider);
        await provider.syncAuth(_financeReviewer, isInitialized: true);
        expect(provider.totalCount, 5);

        feedRepository.error = NetworkException();
        await provider.load(silent: true);
        feedRepository.error = ServerException('Server unavailable', 503);
        await provider.load(silent: true);

        expect(feedRepository.fetchCount, 3);
        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 0);
        expect(provider.totalCount, 5);
        expect(
          provider.statementOrderRequests.single.id,
          'statement-request-1',
        );
        expect(provider.offsetAdjustmentRequests.single.id, 'offset-1');

        provider.dispose();
      },
    );

    test(
      'same-user scope change clears old rows and reloads the aggregate feed',
      () async {
        final feedRepository = _DeferredAppNotificationsFeedRepository();
        final provider = AppNotificationsProvider(
          _FakeBankStatementRepository(),
          offsetAdjustmentRepository: _FakeOffsetAdjustmentRepository(),
          feedRepository: feedRepository,
        );
        await _activate(provider);

        final firstSync = provider.syncAuth(
          _statementUserForStore('CP01'),
          isInitialized: true,
        );
        await _waitForNotificationCondition(
          () => feedRepository.requests.length == 1,
        );
        feedRepository.requests[0].complete(
          _feedWithStatement(
            _statementRequest(id: 'cp01-request', storeCode: 'CP01'),
          ),
        );
        await firstSync;
        expect(provider.statementOrderRequests.single.storeCode, 'CP01');

        final secondSync = provider.syncAuth(
          _statementUserForStore('CP02'),
          isInitialized: true,
        );
        await _waitForNotificationCondition(
          () => feedRepository.requests.length == 2,
        );
        expect(provider.statementOrderRequests, isEmpty);

        feedRepository.requests[1].complete(
          _feedWithStatement(
            _statementRequest(id: 'cp02-request', storeCode: 'CP02'),
          ),
        );
        await secondSync;

        expect(provider.statementOrderRequests.single.storeCode, 'CP02');
        expect(feedRepository.fetchCount, 2);
        provider.dispose();
      },
    );
  });
}

Future<void> _activate(AppNotificationsProvider provider) {
  return provider.syncRuntime(isForeground: true, isSurfaceActive: true);
}

RealtimeEnvelope _envelope({required String kind, required String topic}) {
  return RealtimeEnvelope(
    version: 2,
    kind: kind,
    id: 'event-$kind',
    topic: topic,
    sequence: 1,
    timestamp: DateTime.utc(2026, 7, 15),
    data: const {},
  );
}

const _financeReviewer = User(
  id: 'fin-1',
  email: 'fin@phongvu.vn',
  role: 'USER',
  departmentCode: 'FIN_ACC',
  featureAccess: {'BANK_STATEMENTS': true, 'OFFSET_ADJUSTMENTS': true},
);

const _offsetReviewer = User(
  id: 'acc-1',
  email: 'acc@phongvu.vn',
  role: 'USER',
  departmentCode: 'ACC',
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

const _storeUser = User(
  id: 'sr-1',
  email: 'sr@phongvu.vn',
  role: 'USER',
  storeId: 'CP01',
  departmentCode: 'SALES',
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

User _statementUserForStore(String storeCode) {
  return User(
    id: 'statement-user',
    email: 'statement@phongvu.vn',
    role: 'USER',
    storeId: storeCode,
    featureAccess: const {'BANK_STATEMENTS': true},
  );
}

_FakeAppNotificationsFeedRepository _feedRepository(
  _FakeBankStatementRepository statements,
  _FakeOffsetAdjustmentRepository offsets,
) {
  return _FakeAppNotificationsFeedRepository(statements, offsets);
}

class _FakeAppNotificationsFeedRepository
    extends AppNotificationsFeedRepository {
  final _FakeBankStatementRepository statements;
  final _FakeOffsetAdjustmentRepository offsets;
  int fetchCount = 0;
  Object? error;

  _FakeAppNotificationsFeedRepository(this.statements, this.offsets)
    : super(ApiClient());

  @override
  Future<AppNotificationsFeed> fetchFeed() async {
    fetchCount += 1;
    final currentError = error;
    if (currentError != null) throw currentError;
    return AppNotificationsFeed(
      schemaVersion: 1,
      generatedAt: DateTime.utc(2026, 7, 15),
      statementOrderTransfersEnabled: true,
      offsetAdjustmentsEnabled: true,
      statementOrderTransfers: BankStatementOrderTransferRequestPage(
        requests: statements.requests,
        page: 0,
        limit: 20,
        total: statements.total,
        canReview: statements.canReview,
      ),
      offsetAdjustments: OffsetAdjustmentPage(
        items: offsets.items,
        page: 0,
        limit: 20,
        total: offsets.total,
        canReview: offsets.canReview,
      ),
    );
  }
}

class _DeferredAppNotificationsFeedRepository
    extends AppNotificationsFeedRepository {
  final List<Completer<AppNotificationsFeed>> requests = [];
  int fetchCount = 0;

  _DeferredAppNotificationsFeedRepository() : super(ApiClient());

  @override
  Future<AppNotificationsFeed> fetchFeed() {
    fetchCount += 1;
    final request = Completer<AppNotificationsFeed>();
    requests.add(request);
    return request.future;
  }
}

AppNotificationsFeed _feedWithStatement(
  BankStatementOrderTransferRequest request,
) {
  return AppNotificationsFeed(
    schemaVersion: 1,
    generatedAt: DateTime.utc(2026, 7, 15),
    statementOrderTransfersEnabled: true,
    offsetAdjustmentsEnabled: false,
    statementOrderTransfers: BankStatementOrderTransferRequestPage(
      requests: [request],
      page: 0,
      limit: 20,
      total: 1,
      canReview: false,
    ),
    offsetAdjustments: const OffsetAdjustmentPage(
      items: [],
      page: 0,
      limit: 20,
      total: 0,
      canReview: false,
    ),
  );
}

Future<void> _waitForNotificationCondition(bool Function() condition) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition was not reached before timeout.');
}

class _FakeBankStatementRepository extends BankStatementRepository {
  final List<BankStatementOrderTransferRequest> requests;
  final int total;
  final bool canReview;
  int fetchOrderTransferRequestsCount = 0;

  _FakeBankStatementRepository({
    this.requests = const [],
    this.total = 0,
    this.canReview = false,
  }) : super(ApiClient());

  @override
  Future<BankStatementOrderTransferRequestPage> fetchOrderTransferRequests({
    String status = 'PENDING',
    bool allStores = false,
    List<String> storeIds = const [],
    int page = 0,
    int limit = 50,
  }) async {
    fetchOrderTransferRequestsCount += 1;
    return BankStatementOrderTransferRequestPage(
      requests: requests,
      page: page,
      limit: limit,
      total: total,
      canReview: canReview,
    );
  }
}

class _FakeOffsetAdjustmentRepository extends OffsetAdjustmentRepository {
  final List<OffsetAdjustment> items;
  final int total;
  final bool canReview;
  int fetchListCount = 0;
  OffsetAdjustmentQuery? lastQuery;

  _FakeOffsetAdjustmentRepository({
    this.items = const [],
    this.total = 0,
    this.canReview = false,
  }) : super(ApiClient());

  @override
  Future<OffsetAdjustmentPage> fetchList(OffsetAdjustmentQuery query) async {
    fetchListCount += 1;
    lastQuery = query;
    return OffsetAdjustmentPage(
      items: items,
      page: query.page,
      limit: query.limit,
      total: total,
      canReview: canReview,
    );
  }
}

class _FakeNotificationReadStore extends AppNotificationReadStore {
  final Map<String, Set<String>> _seenIdsByKey = {};
  final Map<String, Set<String>> markedReadIdsBySource = {};

  @override
  Future<Set<String>> loadSeenIds({
    required String userKey,
    required String source,
  }) async {
    return Set<String>.of(_seenIdsByKey[_key(userKey, source)] ?? const {});
  }

  @override
  Future<void> saveSeenIds({
    required String userKey,
    required String source,
    required Set<String> ids,
  }) async {
    _seenIdsByKey[_key(userKey, source)] = Set<String>.of(ids);
  }

  @override
  Future<void> markRead({
    required String source,
    required Set<String> ids,
  }) async {
    markedReadIdsBySource.update(
      source,
      (value) => value..addAll(ids),
      ifAbsent: () => Set<String>.of(ids),
    );
  }

  String _key(String userKey, String source) => '$userKey::$source';
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope envelope) => _events.add(envelope);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}

BankStatementOrderTransferRequest _statementRequest({
  String id = 'statement-request-1',
  String storeCode = 'CP01',
  String? notificationReadAt,
}) {
  return BankStatementOrderTransferRequest.fromJson({
    'id': id,
    'transactionId': 'transaction-1',
    'storeCode': storeCode,
    'oldOrders': ['26062600000001'],
    'requestedOrders': ['26062600000002'],
    'status': 'PENDING',
    'amount': 1200000,
    'createdAt': '2026-06-26T02:00:00.000Z',
    if (notificationReadAt != null) 'notificationReadAt': notificationReadAt,
  });
}

OffsetAdjustment _offsetAdjustment({
  String status = OffsetAdjustmentStatus.pending,
  String? rejectReason,
  String? notificationReadAt,
}) {
  return OffsetAdjustment.fromJson({
    'id': 'offset-1',
    'type': OffsetAdjustmentType.singleOrder,
    'status': status,
    'storeCode': 'CP01',
    'oldOrderCode': '26062600000001',
    'newOrderCode': '26062600000002',
    'amount': 1500000,
    if (rejectReason != null) 'rejectReason': rejectReason,
    'submittedAt': '2026-06-26T02:30:00.000Z',
    if (notificationReadAt != null) 'notificationReadAt': notificationReadAt,
  });
}
