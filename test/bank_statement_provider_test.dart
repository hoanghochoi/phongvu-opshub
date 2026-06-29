import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/providers/bank_statement_provider.dart';
import 'package:phongvu_opshub/features/notifications/data/app_notification_read_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  group('BankStatementTransaction', () {
    test('parses order list and history rows', () {
      final transaction = BankStatementTransaction.fromJson({
        'id': 'tx-1',
        'storeId': 'CP01',
        'transactionKey': 'key-1',
        'transactionNumber': 'MAP-001',
        'transactionReference': '00020300000000004567',
        'amount': '1,250,000',
        'content': 'PAY 26052912345678 26052987654321',
        'orders': ['26052912345678', '26052987654321'],
        'orderSource': 'AUTO',
        'orderUpdatedAt': '2026-05-29T03:00:00.000Z',
        'orderUpdatedByEmail': 'manager@example.com',
        'status': '00',
        'paidAt': '2026-05-29T02:00:00.000Z',
        'firstSeenAt': '2026-05-29T02:00:05.000Z',
        'payerName': 'NGUYEN VAN A',
        'payerAccount': '9704361234567890',
      });
      final history = BankStatementOrderHistoryEntry.fromJson({
        'id': 'audit-1',
        'oldOrders': '26052912345678',
        'newOrders': ['26052987654321'],
        'changedByEmail': 'manager@example.com',
        'createdAt': '2026-05-29T03:01:00.000Z',
      });

      expect(transaction.amount, 1250000);
      expect(transaction.statementNumber, '00020300000000004567');
      expect(transaction.hasOrders, isTrue);
      expect(transaction.orders, ['26052912345678', '26052987654321']);
      expect(transaction.payerName, 'NGUYEN VAN A');
      expect(transaction.payerAccount, '9704361234567890');
      expect(transaction.payerLabel, 'NGUYEN VAN A • 9704361234567890');
      expect(history.oldOrders, ['26052912345678']);
      expect(history.newOrders, ['26052987654321']);
      expect(history.changedByEmail, 'manager@example.com');
    });

    test('reads VietinBank MAP request card payer fields', () {
      final transaction = BankStatementTransaction.fromJson({
        'id': 'tx-req-card',
        'storeId': 'CP01',
        'transactionKey': 'key-req-card',
        'transactionNumber': 'MAP-REQ-001',
        'amount': 1250000,
        'content': 'PAY 26052912345678',
        'orders': ['26052912345678'],
        'status': '00',
        'paidAt': '2026-05-29T02:00:00.000Z',
        'firstSeenAt': '2026-05-29T02:00:05.000Z',
        'reqCardName': 'NGUYEN VAN A',
        'reqCardNo': '9704361234567890',
      });

      expect(transaction.payerName, 'NGUYEN VAN A');
      expect(transaction.payerAccount, '9704361234567890');
      expect(transaction.payerLabel, 'NGUYEN VAN A • 9704361234567890');
    });
  });

  group('BankStatementProvider', () {
    test('loads stores but does not auto-load transactions', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);

      await provider.initialize(_nationalManager);

      expect(provider.stores.map((store) => store.storeId), ['CP01', 'CP02']);
      expect(provider.hasSearched, isFalse);
      expect(repository.fetchStatementsCount, 0);

      provider.dispose();
    });

    test('uses bank statement all-scope policy for all-store access', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);

      await provider.initialize(_financeAllScopeUser);

      expect(provider.canUseAllStores, isTrue);
      expect(provider.stores.map((store) => store.storeId), ['CP01', 'CP02']);

      provider.setStoreSelection(allStores: true, ids: const {});

      expect(provider.allStores, isTrue);

      provider.dispose();
    });

    test('limits a store-scoped manager to the assigned showroom', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);

      await provider.initialize(_storeScopedManager);

      expect(provider.canUseAllStores, isFalse);
      expect(provider.stores.map((store) => store.storeId), ['CP01']);

      provider.dispose();
    });

    test(
      'keeps every assigned showroom visible for multi-store users',
      () async {
        final repository = _FakeBankStatementRepository();
        final provider = BankStatementProvider(repository);

        await provider.initialize(_multiStoreScopedManager);

        expect(provider.canUseAllStores, isFalse);
        expect(provider.stores.map((store) => store.storeId), ['CP01', 'CP02']);

        provider.dispose();
      },
    );

    test('keeps primary filters mutually exclusive', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setStoreSelection(allStores: true, ids: const {});
      expect(provider.allStores, isTrue);
      provider.setStatementNumber('00020300000000004567');

      expect(provider.allStores, isFalse);
      expect(provider.selectedStoreIds, isEmpty);
      expect(provider.statementNumber, '00020300000000004567');

      provider.setAmount('1250000');

      expect(provider.allStores, isFalse);
      expect(provider.selectedStoreIds, isEmpty);
      expect(provider.statementNumber, isNull);
      expect(provider.amount, '1250000');

      provider.setContent('customer transfer');
      expect(provider.amount, isNull);
      expect(provider.content, 'customer transfer');

      provider.dispose();
    });

    test(
      'requires complete date ranges and defaults missing ranges to today',
      () async {
        final repository = _FakeBankStatementRepository();
        final provider = BankStatementProvider(
          repository,
          now: () => DateTime.utc(2026, 5, 31, 18),
        );
        await provider.initialize(_nationalManager);

        provider.setDateRange(DateTime(2026, 5, 29), null);
        expect(provider.startDate, isNull);
        expect(provider.endDate, isNull);

        provider.setDateRange(null, DateTime(2026, 5, 30));
        expect(provider.startDate, isNull);
        expect(provider.endDate, isNull);

        provider.setStatementNumber('00020300000000004567');
        await provider.search();

        expect(repository.lastQuery?.statementNumber, '00020300000000004567');
        expect(repository.lastQuery?.startDate, DateTime(2026, 6));
        expect(repository.lastQuery?.endDate, DateTime(2026, 6));

        provider.dispose();
      },
    );

    test(
      'searches on demand, ticks current page, and updates orders inline',
      () async {
        final repository = _FakeBankStatementRepository();
        final provider = BankStatementProvider(repository);
        await provider.initialize(_nationalManager);

        provider.setOrder('26052912345678');
        await provider.search();
        provider.toggleAllVisible(true);
        await provider.updateOrders(
          'tx-1',
          '26052987654321, 26052987654321 26052900000000',
        );

        expect(repository.fetchStatementsCount, 1);
        expect(repository.lastQuery?.order, '26052912345678');
        expect(provider.hasSearched, isTrue);
        expect(provider.selectedIds, {'tx-1', 'tx-2'});
        expect(repository.lastUpdatedOrders, [
          '26052987654321',
          '26052900000000',
        ]);
        expect(provider.transactions.first.orders, [
          '26052987654321',
          '26052900000000',
        ]);

        provider.dispose();
      },
    );

    test('keeps selected ids across server-side pages', () async {
      final repository = _FakeBankStatementRepository(
        pages: [
          [
            _transaction('tx-1', ['26052912345678']),
            _transaction('tx-2', const []),
          ],
          [_transaction('tx-3', const []), _transaction('tx-4', const [])],
        ],
      );
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setOrderStatus('MISSING_ORDER');
      provider.setLimit(2);
      await provider.search();
      provider.toggleAllVisible(true);
      expect(provider.page, 0);
      expect(provider.selectedIds, {'tx-1', 'tx-2'});
      expect(repository.fetchStatementsCount, 1);

      await provider.nextPage();
      expect(repository.fetchStatementsCount, 2);
      provider.toggleSelected('tx-3', true);

      expect(provider.page, 1);
      expect(provider.transactions.map((item) => item.id), ['tx-3', 'tx-4']);
      expect(provider.selectedIds, {'tx-1', 'tx-2', 'tx-3'});

      await provider.previousPage();
      expect(repository.fetchStatementsCount, 3);

      expect(provider.page, 0);
      expect(provider.transactions.map((item) => item.id), ['tx-1', 'tx-2']);
      expect(provider.selectedIds, {'tx-1', 'tx-2', 'tx-3'});

      provider.dispose();
    });

    test('loads only the current server page for broad SR searches', () async {
      final repository = _FakeBankStatementRepository(
        pages: [
          List.generate(
            125,
            (index) => _transaction('tx-${index + 1}', const []),
          ),
        ],
      );
      final provider = BankStatementProvider(
        repository,
        now: () => DateTime.utc(2026, 5, 31, 18),
      );
      await provider.initialize(_superAdmin);

      provider.setStoreSelection(allStores: false, ids: {'CP01'});
      await provider.search();

      expect(provider.hasSearched, isTrue);
      expect(provider.total, 125);
      expect(provider.transactions.length, 20);
      expect(repository.fetchStatementsCount, 1);
      expect(repository.seenQueries.single.limit, 20);
      expect(
        repository.seenQueries.every(
          (query) => query.storeIds.single == 'CP01',
        ),
        isTrue,
      );
      expect(
        repository.seenQueries.every(
          (query) =>
              query.startDate == DateTime(2026, 6) &&
              query.endDate == DateTime(2026, 6),
        ),
        isTrue,
      );

      provider.dispose();
    });

    test('exports selected ids kept across pages', () async {
      final repository = _FakeBankStatementRepository(
        pages: [
          [
            _transaction('tx-1', ['26052912345678']),
            _transaction('tx-2', const []),
          ],
          [_transaction('tx-3', const []), _transaction('tx-4', const [])],
        ],
      );
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setOrderStatus('MISSING_ORDER');
      provider.setLimit(2);
      await provider.search();
      provider.toggleSelected('tx-1', true);
      await provider.nextPage();
      provider.toggleSelected('tx-3', true);
      await provider.exportCsv();

      expect(repository.exportCsvCount, 1);
      expect(repository.lastExportTransactionIds, ['tx-1', 'tx-3']);

      provider.dispose();
    });

    test('blocks CSV export when the date range is over one month', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setStoreSelection(allStores: true, ids: const {});
      provider.setDateRange(DateTime(2026, 5), DateTime(2026, 6, 5));

      expect(provider.hasExportDateRangeLimitViolation, isTrue);

      await provider.exportCsv();

      expect(repository.exportCsvCount, 0);
      expect(provider.exportMessage, 'Không xuất file quá 1 tháng.');

      provider.dispose();
    });

    test('rejects invalid inline order dates before calling API', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);
      provider.setOrder('26052912345678');
      await provider.search();

      await provider.updateOrders('tx-1', '26023012345678');

      expect(repository.updateOrdersCount, 0);
      expect(provider.transactions.first.orders, ['26052912345678']);

      provider.dispose();
    });

    test('accepts newline separated inline order input', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);
      provider.setOrder('26052912345678');
      await provider.search();

      await provider.updateOrders(
        'tx-1',
        '26052912345678\n26053087654321, 26052912345678',
      );

      expect(repository.updateOrdersCount, 1);
      expect(repository.lastUpdatedOrders, [
        '26052912345678',
        '26053087654321',
      ]);
      expect(provider.transactions.first.orders, [
        '26052912345678',
        '26053087654321',
      ]);

      provider.dispose();
    });

    test('passes offset order status filters to statement query', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setOrderStatus('OFFSET_PENDING');
      await provider.search();
      expect(repository.lastQuery?.orderStatus, 'OFFSET_PENDING');

      provider.setOrderStatus('OFFSET_CONFIRMED');
      await provider.search();
      expect(repository.lastQuery?.orderStatus, 'OFFSET_CONFIRMED');

      provider.dispose();
    });

    test('creates pending order transfer request with newline input', () async {
      final repository = _FakeBankStatementRepository(
        canReviewOrderTransfers: true,
      );
      final provider = BankStatementProvider(repository);
      await provider.initialize(_accUser);
      provider.setOrder('26052912345678');
      await provider.search();

      final ok = await provider.requestOrderTransfer(
        'tx-1',
        '26052987654321\n26053000000000, 26052987654321',
      );

      expect(ok, isTrue);
      expect(repository.createOrderTransferRequestCount, 1);
      expect(repository.lastTransferRequestedOrders, [
        '26052987654321',
        '26053000000000',
      ]);
      expect(provider.canReviewOrderTransfers, isTrue);
      expect(provider.pendingOrderTransferTotal, 1);
      expect(provider.pendingOrderTransferUnreadCount, 1);
      expect(
        provider.transactions.first.hasPendingOrderTransferRequest,
        isTrue,
      );
      expect(provider.transactions.first.orderTransferRequestedOrders, [
        '26052987654321',
        '26053000000000',
      ]);

      provider.dispose();
    });

    test(
      'approves pending order transfer and marks offset transaction',
      () async {
        final repository = _FakeBankStatementRepository(
          canReviewOrderTransfers: true,
        );
        final readStore = _FakeNotificationReadStore();
        final provider = BankStatementProvider(
          repository,
          notificationReadStore: readStore,
        );
        await provider.initialize(_accUser);
        provider.setOrder('26052912345678');
        await provider.search();
        await provider.requestOrderTransfer('tx-1', '26052987654321');

        await provider.approveOrderTransferRequest('request-1');

        expect(repository.approveOrderTransferRequestCount, 1);
        expect(provider.pendingOrderTransferTotal, 0);
        expect(provider.pendingOrderTransferUnreadCount, 0);
        expect(provider.transactions.first.orders, ['26052987654321']);
        expect(provider.transactions.first.isOrderOffsetConfirmed, isTrue);

        provider.dispose();
      },
    );

    test(
      'marks statement bell notifications as read for the signed-in user',
      () async {
        final repository = _FakeBankStatementRepository(
          canReviewOrderTransfers: true,
        );
        final readStore = _FakeNotificationReadStore();
        final provider = BankStatementProvider(
          repository,
          notificationReadStore: readStore,
        );
        await provider.initialize(_accUser);
        provider.setOrder('26052912345678');
        await provider.search();
        await provider.requestOrderTransfer('tx-1', '26052987654321');

        expect(provider.pendingOrderTransferTotal, 1);
        expect(provider.pendingOrderTransferUnreadCount, 1);

        await provider.markPendingOrderTransferNotificationsRead();
        expect(provider.pendingOrderTransferTotal, 1);
        expect(provider.pendingOrderTransferUnreadCount, 0);
        expect(readStore.markedReadIdsBySource['statement_order_transfer'], {
          'request-1',
        });

        final reloadedProvider = BankStatementProvider(
          repository,
          notificationReadStore: readStore,
        );
        await reloadedProvider.initialize(_accUser);

        expect(reloadedProvider.pendingOrderTransferTotal, 1);
        expect(reloadedProvider.pendingOrderTransferUnreadCount, 0);

        provider.dispose();
        reloadedProvider.dispose();
      },
    );

    test(
      'does not count pending order transfers already read on another device',
      () async {
        final repository = _FakeBankStatementRepository(
          canReviewOrderTransfers: true,
          notificationReadAt: DateTime.utc(2026, 5, 29, 4),
        );
        final provider = BankStatementProvider(repository);
        await provider.initialize(_accUser);
        provider.setOrder('26052912345678');
        await provider.search();
        await provider.requestOrderTransfer('tx-1', '26052987654321');

        expect(provider.pendingOrderTransferTotal, 1);
        expect(provider.pendingOrderTransferUnreadCount, 0);

        provider.dispose();
      },
    );
  });

  test('export body sends selected ids when present', () {
    final query = BankStatementQuery(
      allStores: false,
      storeIds: const ['CP01'],
      statementNumber: null,
      order: null,
      amount: null,
      content: null,
      orderStatus: 'HAS_ORDER',
      startDate: DateTime(2026, 5, 29),
      endDate: DateTime(2026, 5, 30),
      page: 0,
      limit: 50,
    );

    expect(query.toExportBody(transactionIds: const ['tx-1']), {
      'storeIds': 'CP01',
      'orderStatus': 'HAS_ORDER',
      'startDate': '2026-05-29',
      'endDate': '2026-05-30',
      'page': '0',
      'limit': '50',
      'transactionIds': ['tx-1'],
    });
  });

  test('keeps UTF-8 BOM when saving CSV bytes', () {
    final withoutBom = ensureUtf8BomForCsv(Uint8List.fromList([0x63, 0x73]));
    expect(withoutBom, [0xef, 0xbb, 0xbf, 0x63, 0x73]);

    final withBom = Uint8List.fromList([0xef, 0xbb, 0xbf, 0x63, 0x73]);
    expect(ensureUtf8BomForCsv(withBom), withBom);
  });
}

const _nationalManager = User(
  id: 'user-1',
  email: 'manager@example.com',
  role: 'MANAGER',
  workScopeType: 'NATIONAL',
  policyAccess: {'BANK_STATEMENT_ALL_SCOPE': true},
);

const _superAdmin = User(
  id: 'admin-1',
  email: 'super@example.com',
  role: 'SUPER_ADMIN',
);

const _financeAllScopeUser = User(
  id: 'finance-1',
  email: 'finance@phongvu.vn',
  role: 'USER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  policyAccess: {'BANK_STATEMENT_ALL_SCOPE': true},
);

const _storeScopedManager = User(
  id: 'manager-1',
  email: 'manager@phongvu.vn',
  role: 'MANAGER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  featureAccess: {'BANK_STATEMENTS': true},
  policyAccess: {'BANK_STATEMENT_ALL_SCOPE': false},
);

const _multiStoreScopedManager = User(
  id: 'manager-2',
  email: 'manager2@phongvu.vn',
  role: 'MANAGER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  assignedStores: [
    StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
    StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'Showroom 2'),
  ],
  featureAccess: {'BANK_STATEMENTS': true},
  policyAccess: {'BANK_STATEMENT_ALL_SCOPE': false},
);

const _accUser = User(
  id: 'acc-1',
  email: 'acc@example.com',
  role: 'USER',
  storeId: 'CP01',
  workScopeType: 'STORE',
  departmentCode: 'ACC',
  featureAccess: {'BANK_STATEMENTS': true},
);

class _FakeBankStatementRepository extends BankStatementRepository {
  int fetchStatementsCount = 0;
  int updateOrdersCount = 0;
  int createOrderTransferRequestCount = 0;
  int fetchOrderTransferRequestsCount = 0;
  int approveOrderTransferRequestCount = 0;
  int rejectOrderTransferRequestCount = 0;
  int exportCsvCount = 0;
  BankStatementQuery? lastQuery;
  BankStatementQuery? lastExportQuery;
  final List<BankStatementQuery> seenQueries = [];
  List<String> lastUpdatedOrders = const [];
  List<String> lastTransferRequestedOrders = const [];
  List<String> lastExportTransactionIds = const [];
  final bool canReviewOrderTransfers;
  final DateTime? notificationReadAt;
  final List<BankStatementOrderTransferRequest> _pendingRequests = [];

  final List<List<BankStatementTransaction>> _pages;

  _FakeBankStatementRepository({
    List<List<BankStatementTransaction>>? pages,
    this.canReviewOrderTransfers = false,
    this.notificationReadAt,
  }) : _pages =
           pages ??
           [
             [
               _transaction('tx-1', ['26052912345678']),
               _transaction('tx-2', const []),
             ],
           ],
       super(ApiClient());

  @override
  Future<List<StoreBranch>> fetchStores() async {
    return const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
      StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'Showroom 2'),
    ];
  }

  @override
  Future<BankStatementPage> fetchStatements(BankStatementQuery query) async {
    fetchStatementsCount += 1;
    lastQuery = query;
    seenQueries.add(query);
    final allRows = _pages.expand((page) => page).toList(growable: false);
    final start = query.page * query.limit;
    final end = start + query.limit > allRows.length
        ? allRows.length
        : start + query.limit;
    final rows = start >= allRows.length
        ? const <BankStatementTransaction>[]
        : allRows.sublist(start, end);
    return BankStatementPage(
      transactions: List.of(rows),
      page: query.page,
      limit: query.limit,
      total: allRows.length,
    );
  }

  @override
  Future<BankStatementTransaction> updateOrders(
    String transactionId,
    List<String> orders,
  ) async {
    updateOrdersCount += 1;
    lastUpdatedOrders = List.of(orders);
    for (var pageIndex = 0; pageIndex < _pages.length; pageIndex += 1) {
      final index = _pages[pageIndex].indexWhere(
        (row) => row.id == transactionId,
      );
      if (index < 0) continue;
      final updated = _pages[pageIndex][index].copyWith(orders: orders);
      _pages[pageIndex][index] = updated;
      return updated;
    }
    throw StateError('Missing fake transaction $transactionId');
  }

  @override
  Future<BankStatementOrderTransferRequest> createOrderTransferRequest(
    String transactionId,
    List<String> orders,
  ) async {
    createOrderTransferRequestCount += 1;
    lastTransferRequestedOrders = List.of(orders);
    final transaction = _findTransaction(transactionId);
    final request = _transferRequest(
      id: 'request-${_pendingRequests.length + 1}',
      transaction: transaction,
      requestedOrders: orders,
      status: 'PENDING',
      notificationReadAt: notificationReadAt,
    );
    _pendingRequests.add(request);
    _replaceTransaction(
      _copyTransaction(
        transaction,
        canEditOrders: false,
        orderEditBlockedReason: 'Giao dịch đang chờ Kế toán xác nhận',
        canRequestOrderTransfer: false,
        orderTransferRequestBlockedReason:
            'Giao dịch đang chờ Kế toán xác nhận',
        hasPendingOrderTransferRequest: true,
        orderTransferRequestId: request.id,
        orderTransferRequestedOrders: orders,
        orderTransferStatus: 'PENDING',
      ),
    );
    return request;
  }

  @override
  Future<BankStatementOrderTransferRequestPage> fetchOrderTransferRequests({
    String status = 'PENDING',
    bool allStores = false,
    List<String> storeIds = const [],
    int page = 0,
    int limit = 50,
  }) async {
    fetchOrderTransferRequestsCount += 1;
    final matching = _pendingRequests
        .where(
          (request) => status == 'NOTIFICATION'
              ? request.status == 'PENDING' || request.status == 'REJECTED'
              : request.status == status,
        )
        .toList(growable: false);
    return BankStatementOrderTransferRequestPage(
      requests: matching,
      page: page,
      limit: limit,
      total: matching.length,
      canReview: canReviewOrderTransfers,
    );
  }

  @override
  Future<BankStatementOrderTransferReviewResult> approveOrderTransferRequest(
    String requestId,
  ) async {
    approveOrderTransferRequestCount += 1;
    final request = _removePendingRequest(requestId);
    final transaction = _findTransaction(request.transactionId);
    final updatedTransaction = _copyTransaction(
      transaction,
      orders: request.requestedOrders,
      orderSource: 'OFFSET',
      canEditOrders: true,
      orderEditBlockedReason: null,
      canRequestOrderTransfer: true,
      orderTransferRequestBlockedReason: null,
      hasPendingOrderTransferRequest: false,
      orderTransferRequestId: null,
      orderTransferRequestedOrders: const [],
      orderTransferStatus: 'APPROVED',
      isOrderOffsetConfirmed: true,
    );
    _replaceTransaction(updatedTransaction);
    return BankStatementOrderTransferReviewResult(
      request: _transferRequest(
        id: request.id,
        transaction: updatedTransaction,
        requestedOrders: request.requestedOrders,
        status: 'APPROVED',
      ),
      transaction: updatedTransaction,
    );
  }

  @override
  Future<BankStatementOrderTransferReviewResult> rejectOrderTransferRequest(
    String requestId, {
    String? note,
  }) async {
    rejectOrderTransferRequestCount += 1;
    final request = _removePendingRequest(requestId);
    final transaction = _findTransaction(request.transactionId);
    _replaceTransaction(
      _copyTransaction(
        transaction,
        canEditOrders: true,
        orderEditBlockedReason: null,
        canRequestOrderTransfer: true,
        orderTransferRequestBlockedReason: null,
        hasPendingOrderTransferRequest: false,
        orderTransferRequestId: null,
        orderTransferRequestedOrders: const [],
        orderTransferStatus: 'REJECTED',
      ),
    );
    return BankStatementOrderTransferReviewResult(
      request: _transferRequest(
        id: request.id,
        transaction: transaction,
        requestedOrders: request.requestedOrders,
        status: 'REJECTED',
        reviewNote: note,
      ),
      transaction: null,
    );
  }

  @override
  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId,
  ) async {
    return const [];
  }

  @override
  Future<Uint8List> exportCsv(
    BankStatementQuery query, {
    List<String> transactionIds = const [],
  }) async {
    exportCsvCount += 1;
    lastExportQuery = query;
    lastExportTransactionIds = List.of(transactionIds);
    return Uint8List.fromList([0xef, 0xbb, 0xbf, 0x63, 0x73, 0x76]);
  }

  BankStatementTransaction _findTransaction(String transactionId) {
    for (final page in _pages) {
      for (final transaction in page) {
        if (transaction.id == transactionId) return transaction;
      }
    }
    throw StateError('Missing fake transaction $transactionId');
  }

  void _replaceTransaction(BankStatementTransaction transaction) {
    for (var pageIndex = 0; pageIndex < _pages.length; pageIndex += 1) {
      final index = _pages[pageIndex].indexWhere(
        (row) => row.id == transaction.id,
      );
      if (index < 0) continue;
      _pages[pageIndex][index] = transaction;
      return;
    }
    throw StateError('Missing fake transaction ${transaction.id}');
  }

  BankStatementOrderTransferRequest _removePendingRequest(String requestId) {
    final index = _pendingRequests.indexWhere(
      (request) => request.id == requestId,
    );
    if (index < 0) throw StateError('Missing fake request $requestId');
    return _pendingRequests.removeAt(index);
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

const Object _unchanged = Object();

BankStatementTransaction _transaction(String id, List<String> orders) {
  return BankStatementTransaction(
    id: id,
    storeId: 'CP01',
    transactionKey: 'key-$id',
    transactionNumber: 'MAP-$id',
    amount: 1250000,
    content: 'Customer transfer',
    orders: orders,
    orderSource: orders.isEmpty ? null : 'AUTO',
    orderUpdatedAt: null,
    orderUpdatedByEmail: null,
    status: '00',
    paidAt: DateTime.utc(2026, 5, 29, 2),
    firstSeenAt: DateTime.utc(2026, 5, 29, 2, 0, 5),
    payerName: null,
    payerAccount: null,
    canEditOrders: true,
    orderEditBlockedReason: null,
    canRequestOrderTransfer: true,
    orderTransferRequestBlockedReason: null,
    hasPendingOrderTransferRequest: false,
    orderTransferRequestId: null,
    orderTransferRequestedOrders: const [],
    orderTransferRequestedByEmail: null,
    orderTransferRequestedAt: null,
    orderTransferReviewNote: null,
    orderTransferStatus: null,
    isOrderOffsetConfirmed: false,
  );
}

BankStatementTransaction _copyTransaction(
  BankStatementTransaction transaction, {
  List<String>? orders,
  String? orderSource,
  bool? canEditOrders,
  Object? orderEditBlockedReason = _unchanged,
  bool? canRequestOrderTransfer,
  Object? orderTransferRequestBlockedReason = _unchanged,
  bool? hasPendingOrderTransferRequest,
  Object? orderTransferRequestId = _unchanged,
  List<String>? orderTransferRequestedOrders,
  Object? orderTransferRequestedByEmail = _unchanged,
  Object? orderTransferRequestedAt = _unchanged,
  Object? orderTransferReviewNote = _unchanged,
  String? orderTransferStatus,
  bool? isOrderOffsetConfirmed,
}) {
  return BankStatementTransaction(
    id: transaction.id,
    storeId: transaction.storeId,
    transactionKey: transaction.transactionKey,
    transactionNumber: transaction.transactionNumber,
    transactionReference: transaction.transactionReference,
    amount: transaction.amount,
    content: transaction.content,
    orders: orders ?? transaction.orders,
    orderSource: orderSource ?? transaction.orderSource,
    orderUpdatedAt: transaction.orderUpdatedAt,
    orderUpdatedByEmail: transaction.orderUpdatedByEmail,
    status: transaction.status,
    paidAt: transaction.paidAt,
    firstSeenAt: transaction.firstSeenAt,
    payerName: transaction.payerName,
    payerAccount: transaction.payerAccount,
    canEditOrders: canEditOrders ?? transaction.canEditOrders,
    orderEditBlockedReason: identical(orderEditBlockedReason, _unchanged)
        ? transaction.orderEditBlockedReason
        : orderEditBlockedReason as String?,
    canRequestOrderTransfer:
        canRequestOrderTransfer ?? transaction.canRequestOrderTransfer,
    orderTransferRequestBlockedReason:
        identical(orderTransferRequestBlockedReason, _unchanged)
        ? transaction.orderTransferRequestBlockedReason
        : orderTransferRequestBlockedReason as String?,
    hasPendingOrderTransferRequest:
        hasPendingOrderTransferRequest ??
        transaction.hasPendingOrderTransferRequest,
    orderTransferRequestId: identical(orderTransferRequestId, _unchanged)
        ? transaction.orderTransferRequestId
        : orderTransferRequestId as String?,
    orderTransferRequestedOrders:
        orderTransferRequestedOrders ??
        transaction.orderTransferRequestedOrders,
    orderTransferRequestedByEmail:
        identical(orderTransferRequestedByEmail, _unchanged)
        ? transaction.orderTransferRequestedByEmail
        : orderTransferRequestedByEmail as String?,
    orderTransferRequestedAt: identical(orderTransferRequestedAt, _unchanged)
        ? transaction.orderTransferRequestedAt
        : orderTransferRequestedAt as DateTime?,
    orderTransferReviewNote: identical(orderTransferReviewNote, _unchanged)
        ? transaction.orderTransferReviewNote
        : orderTransferReviewNote as String?,
    orderTransferStatus: orderTransferStatus ?? transaction.orderTransferStatus,
    isOrderOffsetConfirmed:
        isOrderOffsetConfirmed ?? transaction.isOrderOffsetConfirmed,
  );
}

BankStatementOrderTransferRequest _transferRequest({
  required String id,
  required BankStatementTransaction transaction,
  required List<String> requestedOrders,
  required String status,
  String? reviewNote,
  DateTime? notificationReadAt,
}) {
  return BankStatementOrderTransferRequest(
    id: id,
    transactionId: transaction.id,
    storeCode: transaction.storeId,
    oldOrders: transaction.orders,
    requestedOrders: requestedOrders,
    status: status,
    requestedByEmail: 'staff@example.com',
    reviewedByEmail: null,
    reviewNote: reviewNote,
    reviewedAt: null,
    createdAt: DateTime.utc(2026, 5, 29, 3),
    transactionNumber: transaction.transactionNumber,
    transactionReference: transaction.transactionReference,
    amount: transaction.amount,
    content: transaction.content,
    paidAt: transaction.paidAt,
    firstSeenAt: transaction.firstSeenAt,
    notificationReadAt: notificationReadAt,
  );
}
