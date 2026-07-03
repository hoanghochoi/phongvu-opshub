import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';
import 'package:phongvu_opshub/features/offset_adjustment/presentation/providers/offset_adjustment_provider.dart';
import 'package:phongvu_opshub/features/offset_adjustment/presentation/screens/offset_adjustment_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('renders content-only offset adjustment workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _WidgetOffsetAdjustmentRepository();
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('offset-adjustment-header'));
    expect(header, findsOneWidget);
    expect(tester.getSize(header).height, lessThan(120));
    expect(
      find.byKey(const Key('offset-adjustment-filter-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offset-adjustment-toolbar')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Cấn trừ'), findsOneWidget);
    expect(find.text('Cấn trừ đơn'), findsWidgets);
    expect(find.text('CP01'), findsWidgets);
    expect(find.text('2607020001 -> 2607020002'), findsOneWidget);
    expect(find.textContaining('1.250.000'), findsWidgets);
    expect(find.text('Chờ Kế toán xác nhận'), findsWidgets);
    expect(repository.fetchCount, greaterThanOrEqualTo(2));
    expect(repository.seenQueries.first.allStores, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps mobile loaded state compact with expandable filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _WidgetOffsetAdjustmentRepository();
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offset-adjustment-header')), findsOneWidget);
    expect(
      find.byKey(const Key('offset-adjustment-filter-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offset-adjustment-toolbar')), findsOneWidget);
    expect(find.text('Bộ lọc cấn trừ'), findsOneWidget);
    expect(find.text('Mã đơn'), findsNothing);
    expect(find.text('2607020001 -> 2607020002'), findsOneWidget);

    await tester.tap(find.text('Bộ lọc cấn trừ'));
    await tester.pumpAndSettle();

    expect(find.text('Mã đơn'), findsOneWidget);
    expect(find.text('Số tiền'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _buildApp(_WidgetOffsetAdjustmentRepository repository) {
  final provider = OffsetAdjustmentProvider(
    repository,
    now: () => DateTime(2026, 7, 2, 9),
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_offsetUser),
      ),
      ChangeNotifierProvider<OffsetAdjustmentProvider>(create: (_) => provider),
    ],
    child: const MaterialApp(home: OffsetAdjustmentScreen()),
  );
}

const _offsetUser = User(
  id: 'offset-user-1',
  email: 'offset@example.com',
  role: 'USER',
  storeId: 'CP01',
  storeName: 'Showroom 1',
  departmentCode: 'ACC',
  assignedStores: [
    StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
  ],
  featureAccess: {'OFFSET_ADJUSTMENTS': true},
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}

class _WidgetOffsetAdjustmentRepository extends OffsetAdjustmentRepository {
  int fetchCount = 0;
  final List<OffsetAdjustmentQuery> seenQueries = [];

  _WidgetOffsetAdjustmentRepository() : super(ApiClient());

  @override
  Future<List<StoreBranch>> fetchStores() async {
    return const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'Showroom 1'),
      StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'Showroom 2'),
    ];
  }

  @override
  Future<OffsetAdjustmentPage> fetchList(OffsetAdjustmentQuery query) async {
    fetchCount += 1;
    seenQueries.add(query);
    return OffsetAdjustmentPage(
      items: [_offsetAdjustment],
      page: query.page,
      limit: query.limit,
      total: 1,
      canReview: true,
    );
  }
}

final _offsetAdjustment = OffsetAdjustment.fromJson({
  'id': 'offset-1',
  'type': OffsetAdjustmentType.singleOrder,
  'status': OffsetAdjustmentStatus.pending,
  'storeCode': 'CP01',
  'oldOrderCode': '2607020001',
  'newOrderCode': '2607020002',
  'amount': 1250000,
  'singleOrderReuseCount': 2,
  'submittedAt': '2026-07-02T02:00:00.000Z',
  'canReview': true,
});
