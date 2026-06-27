import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notification_read_store.dart';
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
      );

      await provider.syncAuth(_financeReviewer, isInitialized: true);

      expect(provider.isEnabled, isTrue);
      expect(provider.count, 2);
      expect(provider.totalCount, 5);
      expect(provider.statementOrderRequests, hasLength(1));
      expect(provider.offsetAdjustmentRequests, hasLength(1));
      expect(bankRepository.fetchOrderTransferRequestsCount, 1);
      expect(offsetRepository.fetchListCount, 1);
      expect(
        offsetRepository.lastQuery?.status,
        OffsetAdjustmentStatus.notification,
      );
      expect(offsetRepository.lastQuery?.allStores, isTrue);

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
        );

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
        );

        await provider.syncAuth(_offsetReviewer, isInitialized: true);

        expect(provider.isEnabled, isTrue);
        expect(provider.count, 1);
        expect(provider.totalCount, 4);
        expect(bankRepository.fetchOrderTransferRequestsCount, 0);
        expect(offsetRepository.fetchListCount, 1);

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
      );

      await provider.syncAuth(_storeUser, isInitialized: true);

      expect(provider.isEnabled, isTrue);
      expect(provider.count, 1);
      expect(
        provider.offsetAdjustmentRequests.single.status,
        OffsetAdjustmentStatus.rejected,
      );
      expect(bankRepository.fetchOrderTransferRequestsCount, 0);
      expect(offsetRepository.fetchListCount, 1);
      expect(
        offsetRepository.lastQuery?.status,
        OffsetAdjustmentStatus.notification,
      );
      expect(offsetRepository.lastQuery?.allStores, isFalse);

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
          notificationReadStore: readStore,
        );

        await provider.syncAuth(_financeReviewer, isInitialized: true);
        expect(provider.count, 2);

        await provider.markVisibleNotificationsRead();
        expect(provider.count, 0);

        final reloadedProvider = AppNotificationsProvider(
          bankRepository,
          offsetAdjustmentRepository: offsetRepository,
          notificationReadStore: readStore,
        );
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
      final provider = AppNotificationsProvider(
        bankRepository,
        offsetAdjustmentRepository: _FakeOffsetAdjustmentRepository(),
      );

      await provider.syncAuth(_financeReviewer, isInitialized: true);

      expect(provider.count, 1);
      expect(provider.totalCount, 2);

      provider.dispose();
    });
  });
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

BankStatementOrderTransferRequest _statementRequest({
  String id = 'statement-request-1',
  String? notificationReadAt,
}) {
  return BankStatementOrderTransferRequest.fromJson({
    'id': id,
    'transactionId': 'transaction-1',
    'storeCode': 'CP01',
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
