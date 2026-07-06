import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/formatting/money_formatters.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/data/repositories/home_summary_repository.dart';
import 'package:phongvu_opshub/features/home/domain/home_summary.dart';
import 'package:phongvu_opshub/features/home/presentation/providers/home_summary_provider.dart';
import 'package:phongvu_opshub/features/home/presentation/screens/home_screen.dart';
import 'package:phongvu_opshub/features/home/presentation/widgets/home_summary_page.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Home summary parses sales target status and over-target progress', () {
    final summary = HomeSummary.fromJson({
      'date': '2026-07-05',
      'available': true,
      'scope': 'OWN',
      'scopeLabel': 'Phạm vi cá nhân',
      'coverageLabel': 'Tỉ lệ báo cáo',
      'salesProgress': {
        'status': 'PARTIAL',
        'scope': 'PERSONAL_SA',
        'missingStoreCodes': ['CP02'],
        'day': {'actual': 120, 'target': 100, 'percentage': 120},
        'week': {'actual': 500, 'target': null, 'percentage': null},
        'month': {'actual': 800, 'target': null, 'percentage': null},
      },
    });

    expect(summary.salesProgress.status, 'PARTIAL');
    expect(summary.salesProgress.missingStoreCodes, ['CP02']);
    expect(summary.salesProgress.day.percentage, 120);
    expect(summary.salesProgress.week.target, isNull);
  });

  test('Compact VND formatter keeps long dashboard amounts short', () {
    expect(formatCompactVndAmount(365741), '365.741 VND');
    expect(formatCompactVndAmount(125000000), '125M VND');
    expect(formatCompactVndAmount(1255935484), '1,3B VND');
  });

  test('Home summary provider defaults selected date range to today', () {
    final summaryProvider = HomeSummaryProvider(
      _FakeHomeSummaryRepository(summary: _homeSummary()),
      now: () => DateTime(2026, 7, 6, 14, 30),
    );
    addTearDown(summaryProvider.dispose);

    expect(summaryProvider.selectedStartDate, DateTime(2026, 7, 6));
    expect(summaryProvider.selectedEndDate, DateTime(2026, 7, 6));
    expect(summaryProvider.hasExplicitDateRange, isTrue);
    expect(summaryProvider.formattedSelectedStartDate, '2026-07-06');
    expect(summaryProvider.formattedSelectedEndDate, '2026-07-06');
  });

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'Home dashboard renders scoped summary cards and progress panel',
    (tester) async {
      final authProvider = _FakeAuthProvider(_staffUser());
      final summaryProvider = HomeSummaryProvider(
        _FakeHomeSummaryRepository(
          summary: HomeSummary(
            date: '2026-07-04',
            available: true,
            scope: 'OWN',
            scopeLabel: 'Phạm vi cá nhân',
            scopeDetail: '2 showroom: CP75, CP62',
            coverageLabel: 'Tỉ lệ báo cáo',
            totalRevenue: 125000000,
            totalOrders: 42,
            totalReports: 38,
            reportedOrders: 35,
            unreportedOrders: 7,
            coverageRate: 83.33,
            conversionRate: 110.53,
            financeAvailable: true,
            totalTransferredAmount: 98000000,
            totalStatements: 24,
            totalStatementsWithOrder: 18,
            totalStatementsWithoutOrder: 6,
            statementOrderRate: 75,
            salesProgress: const HomeSalesProgress(
              status: 'AVAILABLE',
              scope: 'PERSONAL_SA',
              missingStoreCodes: [],
              day: HomeSalesProgressPeriod(
                actual: 125000000,
                target: 100000000,
                percentage: 125,
              ),
              range: HomeSalesProgressPeriod(
                actual: 125000000,
                target: 100000000,
                percentage: 125,
              ),
              week: HomeSalesProgressPeriod(
                actual: 350000000,
                target: 700000000,
                percentage: 50,
              ),
              month: HomeSalesProgressPeriod(
                actual: 1200000000,
                target: 3000000000,
                percentage: 40,
              ),
            ),
            refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
          ),
        ),
      );
      addTearDown(summaryProvider.dispose);
      summaryProvider.syncAuth(authProvider.user, isInitialized: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<HomeSummaryProvider>.value(
              value: summaryProvider,
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-summary-page')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-header')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-toolbar')), findsNothing);
      expect(find.byKey(const Key('home-summary-grid')), findsOneWidget);
      expect(
        find.byKey(const Key('home-finance-summary-grid')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-summary-date-range')), findsOneWidget);
      expect(
        find.byKey(const Key('home-summary-refresh-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-progress-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-revenue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-totalOrders')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-conversionRate')),
          matching: find.text('110.5%'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-totalReports')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('home-summary-card-reportedOrders')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-unreportedOrders')),
        findsOneWidget,
      );
      final homeSummaryColumn = tester.widget<Column>(
        find.byKey(const Key('home-summary-page')),
      );
      final structuredChildren = homeSummaryColumn.children
          .where((child) => child is! SizedBox)
          .toList();
      expect(structuredChildren[0], isA<HomeSummaryHeader>());
      expect(find.text('Bán hàng'), findsOneWidget);
      expect(find.text('Tài chính'), findsOneWidget);
      expect(find.text('Tỉ lệ báo cáo'), findsWidgets);
      expect(find.text('Tỉ lệ chuyển đổi'), findsOneWidget);
      expect(find.text('Tổng số báo cáo hợp lệ'), findsNothing);
      expect(find.text('Tổng số tiền chuyển khoản'), findsOneWidget);
      expect(find.text('Tổng số sao kê'), findsOneWidget);
      expect(find.text('Tổng sao kê có đơn hàng'), findsOneWidget);
      expect(find.text('Tổng sao kê chưa có đơn hàng'), findsOneWidget);
      expect(find.text('Tỉ lệ sao kê có đơn hàng'), findsOneWidget);
      expect(find.text('98M VND'), findsOneWidget);
      expect(find.text('Trang chủ vận hành'), findsOneWidget);
      expect(find.text('Doanh số trong ngày'), findsOneWidget);
      expect(find.text('125M VND'), findsOneWidget);
      expect(
        find.byKey(const Key('home-summary-progress-donut')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-statement-progress-donut')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-sales-progress-range')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-sales-progress-week')), findsOneWidget);
      expect(
        find.byKey(const Key('home-sales-progress-month')),
        findsOneWidget,
      );
      expect(find.textContaining('Đã đạt:'), findsWidgets);
      expect(find.textContaining('Chỉ tiêu:'), findsWidgets);
      expect(find.text('Đã đạt: 1,2B VND'), findsOneWidget);
      expect(find.text('Chỉ tiêu: 3B VND'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Tổng quan'), findsOneWidget);
      expect(
        tester
            .getTopLeft(find.byKey(const Key('home-summary-progress-panel')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('home-sales-section-header')))
              .dy,
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-conversionRate')),
          matching: find.byIcon(Icons.swap_horiz_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-statementOrderRate')),
          matching: find.byIcon(Icons.percent_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-operations-shortcut')), findsOneWidget);
      expect(find.text('Công cụ nhanh'), findsOneWidget);
      expect(find.text('Đối soát'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-page')),
          matching: find.byKey(const Key('home-operations-shortcut')),
        ),
        findsNothing,
      );
    },
  );

  testWidgets('Quick tool icon and text block share the same vertical center', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1200,
              child: HomeOperationsShortcutCard(
                actions: [
                  HomeQuickToolAction(
                    id: 'reports',
                    title: 'Tổng hợp ngày',
                    description: 'Xem tổng hợp và chi tiết báo cáo',
                    icon: Icons.description_outlined,
                    color: Colors.teal,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final iconCenter = tester.getCenter(
      find.byKey(const Key('home-quick-tool-icon-reports')),
    );
    final contentCenter = tester.getCenter(
      find.byKey(const Key('home-quick-tool-content-reports')),
    );

    expect((iconCenter.dy - contentCenter.dy).abs(), lessThanOrEqualTo(0.5));
  });

  testWidgets('Home KPI grid keeps two cards per row on normal mobile width', (
    tester,
  ) async {
    const summary = HomeSummary(
      date: '2026-07-06',
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      scopeDetail: 'CP01',
      coverageLabel: 'Tỉ lệ báo cáo',
      totalRevenue: 1000000,
      totalOrders: 10,
      totalReports: 8,
      reportedOrders: 6,
      unreportedOrders: 4,
      coverageRate: 60,
      refreshedAt: null,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 390, child: SummaryCardGrid(summary: summary)),
        ),
      ),
    );

    final first = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-revenue')),
    );
    final second = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-totalOrders')),
    );
    final third = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-coverageRate')),
    );
    expect(first.dy, second.dy);
    expect(first.dx, lessThan(second.dx));
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets('Home KPI grid falls back to one card when extremely narrow', (
    tester,
  ) async {
    const summary = HomeSummary(
      date: '2026-07-06',
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      scopeDetail: 'CP01',
      coverageLabel: 'Tỉ lệ báo cáo',
      totalRevenue: 1000000,
      totalOrders: 10,
      totalReports: 8,
      reportedOrders: 6,
      unreportedOrders: 4,
      coverageRate: 60,
      refreshedAt: null,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: SummaryCardGrid(summary: summary)),
        ),
      ),
    );

    final first = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-revenue')),
    );
    final second = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-totalOrders')),
    );
    expect(second.dy, greaterThan(first.dy));
  });

  testWidgets('Home dashboard shows neutral unavailable state from scope API', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_staffUser());
    final summaryProvider = HomeSummaryProvider(
      _FakeHomeSummaryRepository(
        summary: HomeSummary(
          date: '2026-07-04',
          available: false,
          scope: 'UNAVAILABLE',
          scopeLabel: 'Chưa sẵn sàng',
          scopeDetail: '',
          coverageLabel: 'Tỉ lệ báo cáo',
          totalRevenue: 0,
          totalOrders: 0,
          totalReports: 0,
          reportedOrders: 0,
          unreportedOrders: 0,
          coverageRate: 0,
          refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
          unavailableMessage:
              'Tài khoản hiện chưa có quyền xem tổng quan báo cáo bán hàng.',
        ),
      ),
    );
    addTearDown(summaryProvider.dispose);
    summaryProvider.syncAuth(authProvider.user, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<HomeSummaryProvider>.value(
            value: summaryProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-summary-unavailable')), findsOneWidget);
    expect(
      find.text('Dashboard chưa khả dụng cho tài khoản này'),
      findsOneWidget,
    );
    expect(
      find.text('Tài khoản hiện chưa có quyền xem tổng quan báo cáo bán hàng.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-summary-grid')), findsNothing);
  });

  testWidgets('Home dashboard scope dropdown reloads with selected scope', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_superAdminUser());
    final repository = _FakeHomeSummaryRepository(
      summary: HomeSummary(
        date: '2026-07-04',
        available: true,
        scope: 'ALL',
        scopeLabel: 'Toàn hệ thống',
        scopeDetail: 'Tổng hợp toàn hệ thống',
        coverageLabel: 'Tỉ lệ báo cáo',
        totalRevenue: 125000000,
        totalOrders: 42,
        totalReports: 38,
        reportedOrders: 35,
        unreportedOrders: 7,
        coverageRate: 83.33,
        refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
      ),
      scopedSummaries: {
        'OWN': HomeSummary(
          date: '2026-07-04',
          available: true,
          scope: 'OWN',
          scopeLabel: 'Phạm vi cá nhân',
          scopeDetail: 'CP75',
          coverageLabel: 'Tỉ lệ báo cáo',
          totalRevenue: 5000000,
          totalOrders: 2,
          totalReports: 1,
          reportedOrders: 1,
          unreportedOrders: 1,
          coverageRate: 50,
          refreshedAt: DateTime.parse('2026-07-04T03:20:00.000Z'),
        ),
      },
    );
    final summaryProvider = HomeSummaryProvider(repository);
    addTearDown(summaryProvider.dispose);
    summaryProvider.syncAuth(authProvider.user, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<HomeSummaryProvider>.value(
            value: summaryProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Toàn hệ thống'), findsWidgets);
    expect(find.text('Tài chính'), findsNothing);
    expect(find.byKey(const Key('home-finance-summary-grid')), findsNothing);

    await tester.tap(find.byKey(const Key('home-summary-scope-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phạm vi cá nhân').last);
    await tester.pumpAndSettle();

    expect(summaryProvider.selectedScope, 'OWN');
    expect(repository.requestedScopes, contains('OWN'));
    expect(find.text('Phạm vi cá nhân'), findsWidgets);
    expect(find.text('5M VND'), findsOneWidget);
  });

  testWidgets('Home dashboard scope dropdown selects assigned child node', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_managerUser());
    final repository = _FakeHomeSummaryRepository(
      summary: HomeSummary(
        date: '2026-07-04',
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Vùng: Hồ Chí Minh',
        scopeDetail: '2 showroom được gán',
        coverageLabel: 'Tỉ lệ báo cáo',
        totalRevenue: 125000000,
        totalOrders: 42,
        totalReports: 38,
        reportedOrders: 35,
        unreportedOrders: 7,
        coverageRate: 83.33,
        refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
      ),
      scopeOptions: const [
        HomeSummaryScopeOptionDto(
          value: 'NODE:org-area-hcm',
          label: 'Vùng: Hồ Chí Minh',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'org-area-hcm',
          organizationNodeType: 'LV3_AREA',
          storeCount: 2,
          isDefault: true,
        ),
        HomeSummaryScopeOptionDto(
          value: 'NODE:org-store-cp75',
          label: 'Showroom: CP75',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'org-store-cp75',
          organizationNodeType: 'LV4_STORE',
          storeCount: 1,
        ),
      ],
      nodeSummaries: {
        'org-store-cp75': HomeSummary(
          date: '2026-07-04',
          available: true,
          scope: 'MANAGED_SCOPE',
          scopeLabel: 'Showroom: CP75',
          scopeDetail: 'CP75',
          coverageLabel: 'Tỉ lệ báo cáo',
          totalRevenue: 9000000,
          totalOrders: 3,
          totalReports: 2,
          reportedOrders: 2,
          unreportedOrders: 1,
          coverageRate: 66.67,
          refreshedAt: DateTime.parse('2026-07-04T03:20:00.000Z'),
        ),
      },
    );
    final summaryProvider = HomeSummaryProvider(repository);
    addTearDown(summaryProvider.dispose);
    summaryProvider.syncAuth(authProvider.user, isInitialized: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<HomeSummaryProvider>.value(
            value: summaryProvider,
          ),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedNodeIds, contains('org-area-hcm'));

    await tester.tap(find.byKey(const Key('home-summary-scope-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Showroom: CP75').last);
    await tester.pumpAndSettle();

    expect(summaryProvider.selectedScope, 'NODE:org-store-cp75');
    expect(repository.requestedScopes, contains('MANAGED_SCOPE'));
    expect(repository.requestedNodeIds, contains('org-store-cp75'));
    expect(find.text('9M VND'), findsOneWidget);
  });
}

HomeSummary _homeSummary() {
  return HomeSummary(
    date: '2026-07-06',
    available: true,
    scope: 'OWN',
    scopeLabel: 'Phạm vi cá nhân',
    scopeDetail: 'CP01',
    coverageLabel: 'Tỉ lệ báo cáo',
    totalRevenue: 0,
    totalOrders: 0,
    totalReports: 0,
    reportedOrders: 0,
    unreportedOrders: 0,
    coverageRate: 0,
    refreshedAt: DateTime.parse('2026-07-06T03:15:00.000Z'),
  );
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}

class _FakeHomeSummaryRepository extends HomeSummaryRepository {
  final HomeSummary summary;
  final Map<String, HomeSummary> scopedSummaries;
  final Map<String, HomeSummary> nodeSummaries;
  final List<HomeSummaryScopeOptionDto> scopeOptions;
  final List<String?> requestedScopes = [];
  final List<String?> requestedNodeIds = [];

  _FakeHomeSummaryRepository({
    required this.summary,
    this.scopedSummaries = const {},
    this.nodeSummaries = const {},
    this.scopeOptions = const [],
  }) : super(ApiClient());

  @override
  Future<HomeSummary> fetchSummary({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
  }) async {
    requestedScopes.add(scope);
    requestedNodeIds.add(organizationNodeId);
    if (organizationNodeId != null &&
        nodeSummaries.containsKey(organizationNodeId)) {
      return nodeSummaries[organizationNodeId]!;
    }
    return scopedSummaries[scope] ?? summary;
  }

  @override
  Future<List<HomeSummaryScopeOptionDto>> fetchScopeOptions() async {
    return scopeOptions;
  }
}

User _staffUser() {
  return const User(
    id: 'user-1',
    email: 'staff@phongvu.vn',
    name: 'Dashboard Staff',
    role: 'USER',
    organizationNodeId: 'org-store-cp75',
    assignedStores: [
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
      StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
    ],
    featureAccess: {'FIFO': true, 'WARRANTY': true, 'FEEDBACK': true},
  );
}

User _superAdminUser() {
  return const User(
    id: 'super-1',
    email: 'super@phongvu.vn',
    name: 'Super Admin',
    role: 'SUPER_ADMIN',
    organizationNodeId: 'org-hq',
    assignedStores: [
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
      StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
    ],
    featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
  );
}

User _managerUser() {
  return const User(
    id: 'manager-1',
    email: 'manager@phongvu.vn',
    name: 'Area Manager',
    role: 'USER',
    organizationNodeId: 'org-area-hcm',
    organizationNodeIds: ['org-area-hcm'],
    assignedStores: [
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
      StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
    ],
    featureAccess: {'ADMIN_SALES_REPORTS': true},
  );
}
