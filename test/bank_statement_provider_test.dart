import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/bank_statement/presentation/providers/bank_statement_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
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
      expect(transaction.hasOrders, isTrue);
      expect(transaction.orders, ['26052912345678', '26052987654321']);
      expect(transaction.payerName, 'NGUYEN VAN A');
      expect(transaction.payerAccount, '9704361234567890');
      expect(transaction.payerLabel, 'NGUYEN VAN A • 9704361234567890');
      expect(history.oldOrders, ['26052912345678']);
      expect(history.newOrders, ['26052987654321']);
      expect(history.changedByEmail, 'manager@example.com');
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

    test('keeps primary filters mutually exclusive', () async {
      final repository = _FakeBankStatementRepository();
      final provider = BankStatementProvider(repository);
      await provider.initialize(_nationalManager);

      provider.setStoreSelection(allStores: true, ids: const {});
      expect(provider.allStores, isTrue);
      provider.setAmount('1250000');

      expect(provider.allStores, isFalse);
      expect(provider.selectedStoreIds, isEmpty);
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

        provider.setOrder('26060112345678');
        await provider.search();

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
      final callsAfterSearch = repository.fetchStatementsCount;

      expect(provider.page, 0);
      expect(provider.selectedIds, {'tx-1', 'tx-2'});

      await provider.nextPage();
      expect(repository.fetchStatementsCount, callsAfterSearch);
      provider.toggleSelected('tx-3', true);

      expect(provider.page, 1);
      expect(provider.transactions.map((item) => item.id), ['tx-3', 'tx-4']);
      expect(provider.selectedIds, {'tx-1', 'tx-2', 'tx-3'});

      await provider.previousPage();
      expect(repository.fetchStatementsCount, callsAfterSearch);

      expect(provider.page, 0);
      expect(provider.transactions.map((item) => item.id), ['tx-1', 'tx-2']);
      expect(provider.selectedIds, {'tx-1', 'tx-2', 'tx-3'});

      provider.dispose();
    });

    test('keeps SR snapshot fetches under backend page limit', () async {
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
      expect(repository.fetchStatementsCount, 3);
      expect(repository.seenQueries.map((query) => query.limit), [
        20,
        100,
        100,
      ]);
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
  });

  test('export body sends selected ids when present', () {
    final query = BankStatementQuery(
      allStores: false,
      storeIds: const ['CP01'],
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

class _FakeBankStatementRepository extends BankStatementRepository {
  int fetchStatementsCount = 0;
  int updateOrdersCount = 0;
  BankStatementQuery? lastQuery;
  final List<BankStatementQuery> seenQueries = [];
  List<String> lastUpdatedOrders = const [];

  final List<List<BankStatementTransaction>> _pages;

  _FakeBankStatementRepository({List<List<BankStatementTransaction>>? pages})
    : _pages =
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
    return Uint8List.fromList([0xef, 0xbb, 0xbf, 0x63, 0x73, 0x76]);
  }
}

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
  );
}
