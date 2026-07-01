import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/providers/sales_report_provider.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_admin_screen.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_screen.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Báo cáo opens a two-column order cockpit', (tester) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SalesReportScreen(),
        ),
        GoRoute(
          path: '/sales-reports/purchased',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Purchased form'))),
        ),
        GoRoute(
          path: '/sales-reports/not-purchased',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Not purchased form'))),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchOrdersCount, 1);
    expect(find.text('Báo cáo chưa mua'), findsOneWidget);
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);
    expect(find.text('2607010001'), findsOneWidget);
    expect(find.text('2607010002'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await tester.tap(find.text('Báo cáo chưa mua'));
    await tester.pumpAndSettle();

    expect(find.text('Not purchased form'), findsOneWidget);
  });

  testWidgets('Báo cáo app route provides the sales report provider', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          home: AppRouter.buildSalesReportHubRoute(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.fetchOrdersCount, 1);
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);
  });

  testWidgets('Báo cáo opens purchased dialog from unreported order', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: SalesReportScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2607010002'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.checkOrderCount, 1);
    expect(find.text('Báo cáo mua hàng'), findsOneWidget);
    expect(find.text('Đơn hàng đã kiểm tra'), findsOneWidget);
  });

  testWidgets('Báo cáo hub shows export and list actions with admin feature', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SalesReportScreen(),
        ),
        GoRoute(
          path: '/admin/sales-reports',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('Admin reports'))),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Báo cáo chưa mua'), findsNothing);
    expect(find.text('Xuất HVTC'), findsOneWidget);
    expect(find.text('Xuất Doanh số'), findsOneWidget);
    expect(find.text('Xuất Trả góp'), findsOneWidget);
    expect(find.text('Danh sách'), findsOneWidget);
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('Chưa báo cáo'), findsOneWidget);

    await tester.tap(find.text('Danh sách'));
    await tester.pumpAndSettle();

    expect(find.text('Admin reports'), findsOneWidget);
  });

  testWidgets('Báo cáo form requires explicit behavior answers', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: SalesReportFormScreen.notPurchased()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.text('Loại khách hàng'), findsOneWidget);
    expect(find.text('Tên khách hàng'), findsOneWidget);

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập tên khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng nhập nhu cầu khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn loại khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn Tư vấn 3 giải pháp'), findsOneWidget);
    expect(repository.createCalled, isFalse);
  });

  testWidgets('Báo cáo form scrolls to top after successful submit', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    await _tapVisible(
      tester,
      _checkboxTileByKey('sales-report-customer-type-PERSONAL'),
    );
    await tester.ensureVisible(
      _textFormFieldByParentKey('sales-report-customer-name-field'),
    );
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-customer-name-field'),
      'Nguyễn Văn A',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-category-NH08')),
    );
    await tester.ensureVisible(
      _textFormFieldByParentKey('sales-report-customer-need-field'),
    );
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-customer-need-field'),
      'Laptop văn phòng',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-Tư vấn 3 giải pháp-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('sales-report-answer-KH đã được trải nghiệm-YES'),
      ),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-KH quét Zalo-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('sales-report-answer-KH tải App PV-YES')),
    );
    await _tapVisible(
      tester,
      find.byKey(
        const ValueKey('sales-report-not-purchased-reason-PRICE_HESITATION'),
      ),
    );

    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.createCalled, isTrue);
    expect(repository.lastInput?.customerName, 'Nguyễn Văn A');
    expect(position.pixels, 0);
  });

  testWidgets('Học sinh - Sinh viên is a child option of Cá nhân', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    final businessFinder = _checkboxTileByKey(
      'sales-report-customer-type-BUSINESS',
    );
    final personalFinder = _checkboxTileByKey(
      'sales-report-customer-type-PERSONAL',
    );
    final studentFinder = _checkboxTileByKey('sales-report-customer-student');

    await tester.ensureVisible(studentFinder);
    await tester.tap(studentFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(personalFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(studentFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(businessFinder).value, isFalse);

    await tester.ensureVisible(businessFinder);
    await tester.tap(businessFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(businessFinder).value, isTrue);
    expect(tester.widget<CheckboxListTile>(personalFinder).value, isFalse);
    expect(tester.widget<CheckboxListTile>(studentFinder).value, isFalse);
    expect(tester.widget<CheckboxListTile>(personalFinder).onChanged, isNull);
    expect(tester.widget<CheckboxListTile>(studentFinder).onChanged, isNull);
  });

  testWidgets('Số tiền vay formats thousand separators while typing', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository();
    await _pumpNotPurchasedForm(tester, repository);

    await tester.ensureVisible(
      find.byKey(const ValueKey('sales-report-installment-checkbox')),
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-report-installment-checkbox')),
    );
    await tester.pumpAndSettle();

    final loanField = find.descendant(
      of: find.byKey(const ValueKey('sales-report-installment-loan-amount')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(loanField, '5000000');
    await tester.pump();

    expect(find.text('5.000.000'), findsOneWidget);
  });

  testWidgets(
    'Báo cáo chưa mua opens installment approval and no-installment reason',
    (tester) async {
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'user-1',
          email: 'sale@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-store-cp01',
          featureAccess: {'SALES_REPORT': true},
        ),
      );
      final repository = _FakeSalesReportRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SalesReportProvider>(
              create: (_) => SalesReportProvider(repository),
            ),
          ],
          child: const MaterialApp(home: SalesReportFormScreen.notPurchased()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('sales-report-installment-checkbox')),
      );
      await tester.tap(
        find.byKey(const ValueKey('sales-report-installment-checkbox')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đối tác trả góp'), findsOneWidget);
      expect(find.text('Hồ sơ được duyệt không'), findsOneWidget);
      expect(find.text('Lý do không trả góp'), findsOneWidget);
      expect(find.text('VNPAY - POS'), findsOneWidget);
      expect(find.text('Mirae Asset'), findsOneWidget);
      expect(find.text('MPOS'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('sales-report-installment-VNPAY_POS')),
      );
      await tester.ensureVisible(find.text('Gửi báo cáo'));
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pumpAndSettle();

      expect(
        find.text('Vui lòng chọn hồ sơ được duyệt hay chưa'),
        findsOneWidget,
      );
      expect(find.text('Vui lòng chọn lý do không trả góp'), findsOneWidget);
      expect(repository.createCalled, isFalse);
    },
  );

  testWidgets('Báo cáo sale admin filters list by selected date range', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: SalesReportAdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 1);
    expect(find.text('Ngày: Tất cả ngày'), findsOneWidget);
    expect(find.text('Xuất Trả góp'), findsOneWidget);

    await tester.tap(find.text('Ngày: Tất cả ngày'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hôm nay'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(repository.fetchListCount, 2);
    expect(repository.lastListQuery?.startDate, today);
    expect(repository.lastListQuery?.endDate, today);
  });

  test('SalesReportOrderCheck parses multiple category groups', () {
    final check = SalesReportOrderCheck.fromJson({
      'orderCode': '2606290001',
      'customerType': 'BUSINESS',
      'customerTypeLabel': 'Doanh nghiệp',
      'paymentMethods': ['cash', 'bank_transfer'],
      'categoryGroups': [
        {
          'id': 'NH03',
          'catGroupName': 'Computer components',
          'catGroupNameVi': 'Linh kiện máy tính',
        },
        {
          'id': 'NH08',
          'catGroupName': 'Network and Security equipment',
          'catGroupNameVi': 'Thiết bị mạng và an ninh',
        },
      ],
    });

    expect(check.categoryGroups.map((category) => category.id), [
      'NH03',
      'NH08',
    ]);
    expect(check.categoryGroup?.id, isNull);
    expect(check.customerType, 'BUSINESS');
    expect(check.paymentMethods, ['cash', 'bank_transfer']);
  });

  test('SalesReportQuery serializes admin date filters and export type', () {
    final query = SalesReportQuery(
      reportType: 'PURCHASED',
      exportType: 'REVENUE',
      startDate: DateTime(2026, 6, 1, 15, 30),
      endDate: DateTime(2026, 6, 30, 23, 59),
      page: 2,
      limit: 50,
    );

    expect(query.toQueryParameters(), {
      'reportType': 'PURCHASED',
      'exportType': 'REVENUE',
      'startDate': '2026-06-01',
      'endDate': '2026-06-30',
      'page': '2',
      'limit': '50',
    });
  });

  test('SalesReportOrdersQuery serializes report date and limit', () {
    final query = SalesReportOrdersQuery(
      date: DateTime(2026, 7, 1, 9, 30),
      limit: 75,
    );

    expect(query.toQueryParameters(), {'date': '2026-07-01', 'limit': '75'});
  });

  test('SalesReportOrderCockpit parses reported and unreported orders', () {
    final cockpit = SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': 'MANAGED_SCOPE',
      'reportedOrders': [
        {'status': 'REPORTED', 'orderCode': '2607010001'},
      ],
      'unreportedOrders': [
        {'status': 'UNREPORTED', 'orderCode': '2607010002'},
      ],
    });

    expect(cockpit.scope, 'MANAGED_SCOPE');
    expect(cockpit.reportedOrders.single.isReported, isTrue);
    expect(cockpit.unreportedOrders.single.orderCode, '2607010002');
  });
}

Future<void> _pumpNotPurchasedForm(
  WidgetTester tester,
  _FakeSalesReportRepository repository,
) async {
  final authProvider = _FakeAuthProvider(
    const User(
      id: 'user-1',
      email: 'sale@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store-cp01',
      featureAccess: {'SALES_REPORT': true},
    ),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<SalesReportProvider>(
          create: (_) => SalesReportProvider(repository),
        ),
      ],
      child: const MaterialApp(home: SalesReportFormScreen.notPurchased()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _checkboxTileByKey(String key) {
  return find.byWidgetPredicate(
    (widget) => widget is CheckboxListTile && widget.key == ValueKey(key),
  );
}

Finder _textFormFieldByParentKey(String key) {
  return find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextFormField),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _FakeSalesReportRepository extends SalesReportRepository {
  bool createCalled = false;
  int fetchListCount = 0;
  int fetchOrdersCount = 0;
  int checkOrderCount = 0;
  SalesReportInput? lastInput;
  SalesReportQuery? lastListQuery;

  _FakeSalesReportRepository() : super(ApiClient());

  @override
  Future<List<SalesReportCategoryGroup>> fetchCategories({
    bool admin = false,
  }) async {
    return const [
      SalesReportCategoryGroup(
        id: 'NH08',
        catGroupName: 'Network and Security equipment',
        catGroupNameVi: 'Thiết bị mạng và an ninh',
      ),
    ];
  }

  @override
  Future<Map<String, dynamic>> create(SalesReportInput input) async {
    createCalled = true;
    lastInput = input;
    return const {};
  }

  @override
  Future<Map<String, dynamic>> fetchList(SalesReportQuery query) async {
    fetchListCount += 1;
    lastListQuery = query;
    return {
      'items': const [],
      'page': query.page,
      'limit': query.limit,
      'total': 0,
    };
  }

  @override
  Future<SalesReportOrderCheck> checkOrder(String orderCode) async {
    checkOrderCount += 1;
    return SalesReportOrderCheck.fromJson({
      'orderCode': orderCode,
      'isCancelled': false,
      'customerName': 'Trần Thị B',
      'customerNeed': 'Laptop trả góp',
      'customerType': 'PERSONAL',
      'categoryGroups': [
        {
          'id': 'NH08',
          'catGroupName': 'Network and Security equipment',
          'catGroupNameVi': 'Thiết bị mạng và an ninh',
        },
      ],
      'items': [
        {'sku': 'SKU-1', 'name': 'Laptop', 'quantity': 1},
      ],
      'payments': [
        {'method': 'cash'},
      ],
      'order': {
        'orderCode': orderCode,
        'grandTotal': 2500000,
        'paymentStatus': 'PAID',
        'terminalName': 'CP62',
      },
    });
  }

  @override
  Future<SalesReportOrderCockpit> fetchOrders(
    SalesReportOrdersQuery query,
  ) async {
    fetchOrdersCount += 1;
    return SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'refreshedAt': '2026-07-01T09:03:00.000Z',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': 'OWN',
      'reportedOrders': [
        {
          'status': 'REPORTED',
          'orderCode': '2607010001',
          'customerName': 'Nguyễn Văn A',
          'grandTotal': 1200000,
          'storeCode': 'CP62',
          'reportedAt': '2026-07-01T02:30:00.000Z',
        },
      ],
      'unreportedOrders': [
        {
          'status': 'UNREPORTED',
          'orderCode': '2607010002',
          'customerName': 'Trần Thị B',
          'grandTotal': 2500000,
          'storeCode': 'CP62',
          'consultantName': 'Sale CP62',
        },
      ],
    });
  }
}
