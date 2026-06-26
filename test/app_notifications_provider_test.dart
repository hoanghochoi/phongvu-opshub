import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/notifications/presentation/providers/app_notifications_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient().setAuthToken(null);
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
      expect(provider.count, 5);
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
        expect(provider.count, 4);
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

BankStatementOrderTransferRequest _statementRequest() {
  return BankStatementOrderTransferRequest.fromJson({
    'id': 'statement-request-1',
    'transactionId': 'transaction-1',
    'storeCode': 'CP01',
    'oldOrders': ['26062600000001'],
    'requestedOrders': ['26062600000002'],
    'status': 'PENDING',
    'amount': 1200000,
    'createdAt': '2026-06-26T02:00:00.000Z',
  });
}

OffsetAdjustment _offsetAdjustment({
  String status = OffsetAdjustmentStatus.pending,
  String? rejectReason,
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
  });
}
