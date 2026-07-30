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

    expect(find.byKey(const Key('offset-adjustment-header')), findsNothing);
    expect(
      find.byKey(const Key('offset-adjustment-filter-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offset-adjustment-toolbar')), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Yêu cầu xử lý'), findsNothing);
    expect(find.text('Trang 1 - 1 hồ sơ'), findsOneWidget);
    expect(find.text('Cấn trừ đơn'), findsWidgets);
    expect(find.text('CP01'), findsWidgets);
    expect(find.text('2607020001 -> 2607020002'), findsOneWidget);
    expect(find.text('2607020002: CP99'), findsOneWidget);
    expect(find.textContaining('1.250.000'), findsWidgets);
    expect(find.text('Chờ Kế toán xác nhận'), findsWidgets);

    await tester.tap(find.text('2607020001 -> 2607020002'));
    await tester.pumpAndSettle();
    expect(find.text('Cửa hàng bán'), findsOneWidget);
    expect(find.text('2607020002: CP99'), findsWidgets);

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

    expect(find.byKey(const Key('offset-adjustment-header')), findsNothing);
    expect(
      find.byKey(const Key('offset-adjustment-filter-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('offset-adjustment-toolbar')), findsNothing);
    expect(find.text('Bộ lọc cấn trừ'), findsOneWidget);
    expect(find.text('Trang 1 - 1 hồ sơ'), findsOneWidget);
    expect(find.text('Mã đơn'), findsNothing);
    expect(find.text('2607020001 -> 2607020002'), findsOneWidget);

    await tester.tap(find.text('Bộ lọc cấn trừ'));
    await tester.pumpAndSettle();

    expect(find.text('Mã đơn'), findsOneWidget);
    expect(find.text('Số tiền'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables batch selection for VNPAY QROFF rows', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _WidgetOffsetAdjustmentRepository(
      items: [_offsetAdjustment, _vnpayOffsetAdjustment],
    );
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    final blockedTooltip = find.byTooltip('Cần nhập Mã CT và xác nhận riêng.');
    expect(blockedTooltip, findsOneWidget);
    final checkbox = tester.widget<Checkbox>(
      find.descendant(of: blockedTooltip, matching: find.byType(Checkbox)),
    );
    expect(checkbox.onChanged, isNull);
    expect(find.textContaining('2 hồ sơ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirms selected offsets through the batch dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _WidgetOffsetAdjustmentRepository();
    await tester.pumpWidget(_buildApp(repository));
    await tester.pumpAndSettle();

    final selectable = find.byTooltip('Chọn hồ sơ để xác nhận hàng loạt');
    await tester.tap(
      find.descendant(of: selectable, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await tester.tap(find.text('Xác nhận đã chọn'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận hồ sơ đã chọn'), findsOneWidget);
    expect(find.textContaining('1 hồ sơ cấn trừ'), findsOneWidget);
    await tester.tap(find.text('Xác nhận'));
    await tester.pumpAndSettle();

    expect(repository.batchCompleteCount, 1);
    expect(repository.lastBatchIds, ['offset-1']);
    expect(find.text('0 hồ sơ đã chọn'), findsOneWidget);
    expect(find.text('Đã xác nhận 1 hồ sơ cấn trừ.'), findsOneWidget);
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
  final List<OffsetAdjustment> items;
  int fetchCount = 0;
  int batchCompleteCount = 0;
  List<String> lastBatchIds = const [];
  final List<OffsetAdjustmentQuery> seenQueries = [];

  _WidgetOffsetAdjustmentRepository({List<OffsetAdjustment>? items})
    : items = items ?? [_offsetAdjustment],
      super(ApiClient());

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
      items: items,
      page: query.page,
      limit: query.limit,
      total: items.length,
      canReview: true,
    );
  }

  @override
  Future<int> batchComplete(List<String> ids) async {
    batchCompleteCount += 1;
    lastBatchIds = List.of(ids);
    return ids.length;
  }
}

final _offsetAdjustment = OffsetAdjustment.fromJson({
  'id': 'offset-1',
  'type': OffsetAdjustmentType.singleOrder,
  'status': OffsetAdjustmentStatus.pending,
  'storeCode': 'CP01',
  'sellingStores': [
    {'orderCode': '2607020002', 'storeCode': 'CP99'},
  ],
  'creationChannel': 'Cấn trừ trên OpsHub',
  'oldOrderCode': '2607020001',
  'newOrderCode': '2607020002',
  'amount': 1250000,
  'singleOrderReuseCount': 2,
  'submittedAt': '2026-07-02T02:00:00.000Z',
  'canReview': true,
});

final _vnpayOffsetAdjustment = OffsetAdjustment.fromJson({
  'id': 'offset-vnpay',
  'type': OffsetAdjustmentType.vnpayQroff,
  'status': OffsetAdjustmentStatus.pending,
  'storeCode': 'CP01',
  'sellingStores': [
    {'orderCode': '2607020003', 'storeCode': 'CP88'},
  ],
  'creationChannel': 'Cấn trừ trên OpsHub',
  'orderCode': '2607020003',
  'amount': 750000,
  'submittedAt': '2026-07-02T02:05:00.000Z',
  'canReview': true,
});
