import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';
import 'package:phongvu_opshub/features/offset_adjustment/presentation/providers/offset_adjustment_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  group('OffsetAdjustment', () {
    test('parses amount and single-order count', () {
      final item = OffsetAdjustment.fromJson({
        'id': 'offset-1',
        'type': OffsetAdjustmentType.singleOrder,
        'status': OffsetAdjustmentStatus.pending,
        'storeCode': 'CP01',
        'oldOrderCode': '26062500000001',
        'newOrderCode': '26062500000002',
        'amount': '1,500,000',
        'singleOrderReuseCount': 3,
      });

      expect(item.amount, 1500000);
      expect(item.primaryOrderLabel, '26062500000001 -> 26062500000002');
      expect(item.singleOrderReuseCount, 3);
    });
  });

  group('OffsetAdjustmentProvider', () {
    test('loads all-day list for store-scoped SR on initialize', () async {
      final repository = _FakeOffsetAdjustmentRepository();
      final provider = OffsetAdjustmentProvider(
        repository,
        now: () => DateTime(2026, 6, 25, 10),
      );

      await provider.initialize(_srUser);

      expect(provider.stores.map((store) => store.storeId), ['CP01']);
      expect(provider.items, hasLength(1));
      expect(repository.lastQuery?.allStores, isFalse);
      expect(repository.lastQuery?.startDate, isNull);
      expect(repository.lastQuery?.endDate, isNull);

      provider.dispose();
    });

    test('store-scoped SR can filter among assigned stores', () async {
      final repository = _FakeOffsetAdjustmentRepository();
      final provider = OffsetAdjustmentProvider(
        repository,
        now: () => DateTime(2026, 6, 25, 10),
      );

      await provider.initialize(_multiStoreSrUser);

      expect(provider.stores.map((store) => store.storeId), ['CP01', 'CP02']);
      expect(repository.lastQuery?.allStores, isFalse);
      expect(repository.lastQuery?.storeIds, isEmpty);

      provider.setStoreSelection(allStores: false, ids: {'CP02'});
      await provider.search();

      expect(repository.lastQuery?.storeIds, ['CP02']);

      provider.dispose();
    });

    test('reviewer queries all stores and loads pending count', () async {
      final repository = _FakeOffsetAdjustmentRepository(canReview: true);
      final provider = OffsetAdjustmentProvider(
        repository,
        now: () => DateTime(2026, 6, 25, 10),
      );

      await provider.initialize(_accUser);

      expect(provider.canReview, isTrue);
      expect(provider.stores.map((store) => store.storeId), ['CP01', 'CP02']);
      expect(repository.seenQueries.first.allStores, isTrue);
      expect(
        repository.seenQueries.last.status,
        OffsetAdjustmentStatus.pending,
      );
      expect(repository.seenQueries.last.startDate, isNull);
      expect(repository.seenQueries.last.endDate, isNull);

      provider.dispose();
    });

    test(
      'loads pending notification items without changing main filter',
      () async {
        final repository = _FakeOffsetAdjustmentRepository(canReview: true);
        final provider = OffsetAdjustmentProvider(
          repository,
          now: () => DateTime(2026, 6, 25, 10),
        );
        await provider.initialize(_accUser);
        provider.setStatus(OffsetAdjustmentStatus.approved);

        await provider.loadPendingItems();

        expect(provider.status, OffsetAdjustmentStatus.approved);
        expect(provider.pendingItems, hasLength(1));
        expect(repository.lastQuery?.status, OffsetAdjustmentStatus.pending);
        expect(repository.lastQuery?.type, 'ALL');
        expect(repository.lastQuery?.startDate, isNull);
        expect(repository.lastQuery?.endDate, isNull);

        provider.dispose();
      },
    );

    test('create sends payload then refreshes current list', () async {
      final repository = _FakeOffsetAdjustmentRepository();
      final provider = OffsetAdjustmentProvider(
        repository,
        now: () => DateTime(2026, 6, 25, 10),
      );
      await provider.initialize(_srUser);

      final error = await provider.create(
        const OffsetAdjustmentInput(
          type: OffsetAdjustmentType.singleOrder,
          oldOrderCode: '26062500000001',
          newOrderCode: '26062500000002',
          amount: 1500000,
        ),
      );

      expect(error, isNull);
      expect(repository.createCount, 1);
      expect(repository.fetchListCount, greaterThanOrEqualTo(2));

      provider.dispose();
    });
  });
}

const _srUser = User(
  id: 'sr-1',
  email: 'sr@phongvu.vn',
  role: 'USER',
  storeId: 'CP01',
  departmentCode: 'SALES',
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

const _multiStoreSrUser = User(
  id: 'sr-2',
  email: 'sr2@phongvu.vn',
  role: 'USER',
  storeId: 'CP01',
  departmentCode: 'SALES',
  assignedStores: [
    StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'CP01'),
    StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'CP02'),
  ],
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

const _accUser = User(
  id: 'acc-1',
  email: 'acc@phongvu.vn',
  role: 'USER',
  departmentCode: 'ACC',
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

class _FakeOffsetAdjustmentRepository extends OffsetAdjustmentRepository {
  final bool canReview;
  int fetchListCount = 0;
  int createCount = 0;
  OffsetAdjustmentQuery? lastQuery;
  final List<OffsetAdjustmentQuery> seenQueries = [];

  _FakeOffsetAdjustmentRepository({this.canReview = false})
    : super(ApiClient());

  @override
  Future<List<StoreBranch>> fetchStores() async {
    return const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'CP01'),
      StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'CP02'),
    ];
  }

  @override
  Future<OffsetAdjustmentPage> fetchList(OffsetAdjustmentQuery query) async {
    fetchListCount += 1;
    lastQuery = query;
    seenQueries.add(query);
    return OffsetAdjustmentPage(
      items: [_offset()],
      page: query.page,
      limit: query.limit,
      total: query.status == OffsetAdjustmentStatus.pending ? 7 : 1,
      canReview: canReview,
    );
  }

  @override
  Future<OffsetAdjustment> create(OffsetAdjustmentInput input) async {
    createCount += 1;
    return _offset(type: input.type, amount: input.amount);
  }
}

OffsetAdjustment _offset({
  String type = OffsetAdjustmentType.singleOrder,
  int amount = 1500000,
}) {
  return OffsetAdjustment.fromJson({
    'id': 'offset-1',
    'type': type,
    'status': OffsetAdjustmentStatus.pending,
    'storeCode': 'CP01',
    'oldOrderCode': '26062500000001',
    'newOrderCode': '26062500000002',
    'amount': amount,
    'singleOrderReuseCount': 1,
    'submittedAt': '2026-06-25T03:00:00.000Z',
  });
}
