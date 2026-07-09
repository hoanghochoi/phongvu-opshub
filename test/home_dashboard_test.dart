import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
      'scopeSalesProgress': {
        'status': 'AVAILABLE',
        'scope': 'MANAGED',
        'missingStoreCodes': [],
        'day': {'actual': 200, 'target': 400, 'percentage': 50},
        'week': {'actual': 500, 'target': 1000, 'percentage': 50},
        'month': {'actual': 800, 'target': 1600, 'percentage': 50},
      },
      'salesProgressAssignees': [
        {
          'userId': 'sa-1',
          'label': 'SA Một',
          'email': 'sa1@phongvu.vn',
          'storeCodes': ['CP75'],
          'isSelected': true,
          'isCurrentUser': false,
        },
      ],
      'selectedSalesProgressUserId': 'sa-1',
      'notPurchasedReports': 12,
      'averageOrderValue': 2500000,
      'completedRevenue': 90000000,
      'pendingRevenue': 35000000,
      'businessCustomerRevenue': 60000000,
      'personalCustomerRevenue': 65000000,
      'examScorePromotionCount': 3,
      'studentPromotionCount': 4,
      'installmentNeedCount': 5,
      'successfulInstallmentCount': 2,
      'extendedInsuranceQuantity': 7,
      'laptopQuantity': 8,
      'pcQuantity': 9,
      'assembledPcQuantity': 1,
      'appleQuantity': 6,
      'monitorQuantity': 10,
      'printerQuantity': 11,
      'accessoriesQuantity': 12,
      'consultedSolutionRate': 75,
      'experiencedRate': 50,
      'zaloRate': 25,
      'appDownloadRate': 100,
    });

    expect(summary.salesProgress.status, 'PARTIAL');
    expect(summary.personalSalesProgress.status, 'PARTIAL');
    expect(summary.scopeSalesProgress.scope, 'MANAGED');
    expect(summary.salesProgressAssignees.single.label, 'SA Một');
    expect(summary.selectedSalesProgressUserId, 'sa-1');
    expect(summary.salesProgress.missingStoreCodes, ['CP02']);
    expect(summary.salesProgress.day.percentage, 120);
    expect(summary.salesProgress.week.target, isNull);
    expect(summary.notPurchasedReports, 12);
    expect(summary.averageOrderValue, 2500000);
    expect(summary.completedRevenue, 90000000);
    expect(summary.pendingRevenue, 35000000);
    expect(summary.businessCustomerRevenue, 60000000);
    expect(summary.personalCustomerRevenue, 65000000);
    expect(summary.examScorePromotionCount, 3);
    expect(summary.studentPromotionCount, 4);
    expect(summary.installmentNeedCount, 5);
    expect(summary.successfulInstallmentCount, 2);
    expect(summary.extendedInsuranceQuantity, 7);
    expect(summary.laptopQuantity, 8);
    expect(summary.pcQuantity, 9);
    expect(summary.assembledPcQuantity, 1);
    expect(summary.appleQuantity, 6);
    expect(summary.monitorQuantity, 10);
    expect(summary.printerQuantity, 11);
    expect(summary.accessoriesQuantity, 12);
    expect(summary.consultedSolutionRate, 75);
    expect(summary.experiencedRate, 50);
    expect(summary.zaloRate, 25);
    expect(summary.appDownloadRate, 100);
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
            notPurchasedReports: 12,
            unreportedOrders: 7,
            averageOrderValue: 2500000,
            completedRevenue: 100000000,
            pendingRevenue: 25000000,
            businessCustomerRevenue: 60000000,
            personalCustomerRevenue: 65000000,
            examScorePromotionCount: 3,
            studentPromotionCount: 4,
            installmentNeedCount: 5,
            successfulInstallmentCount: 2,
            extendedInsuranceQuantity: 7,
            laptopQuantity: 8,
            pcQuantity: 9,
            assembledPcQuantity: 1,
            appleQuantity: 6,
            monitorQuantity: 10,
            printerQuantity: 11,
            accessoriesQuantity: 12,
            coverageRate: 83.33,
            conversionRate: 110.53,
            consultedSolutionRate: 75,
            experiencedRate: 50,
            zaloRate: 25,
            appDownloadRate: 100,
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
            scopeSalesProgress: const HomeSalesProgress(
              status: 'AVAILABLE',
              scope: 'MANAGED',
              missingStoreCodes: [],
              day: HomeSalesProgressPeriod(
                actual: 200000000,
                target: 300000000,
                percentage: 66.67,
              ),
              range: HomeSalesProgressPeriod(
                actual: 200000000,
                target: 300000000,
                percentage: 66.67,
              ),
              week: HomeSalesProgressPeriod(
                actual: 900000000,
                target: 1400000000,
                percentage: 64.29,
              ),
              month: HomeSalesProgressPeriod(
                actual: 2400000000,
                target: 6000000000,
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
      expect(
        find.byKey(const Key('home-summary-pull-refresh')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-summary-header')), findsOneWidget);
      expect(find.byKey(const Key('home-summary-toolbar')), findsNothing);
      expect(find.byKey(const Key('home-summary-grid')), findsOneWidget);
      expect(
        find.byKey(const Key('home-finance-summary-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-sales-behavior-summary-grid')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-main-kpi-summary-grid')),
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
        find.byKey(const Key('home-summary-card-averageOrderValue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-completedRevenue')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-summary-card-pendingRevenue')),
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
        find.byKey(const Key('home-summary-card-notPurchasedReports')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('home-summary-card-notPurchasedReports-detail-icon'),
        ),
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
      expect(find.text('Doanh số'), findsOneWidget);
      expect(find.text('KPI chính'), findsOneWidget);
      expect(find.text('Hành vi then chốt'), findsOneWidget);
      expect(find.text('Tài chính'), findsOneWidget);
      expect(find.text('Tỉ lệ báo cáo'), findsWidgets);
      expect(find.text('Tỉ lệ chuyển đổi'), findsOneWidget);
      expect(find.text('Doanh số tổng'), findsOneWidget);
      expect(find.text('Số đơn bán'), findsOneWidget);
      expect(find.text('Trung bình đơn hàng'), findsOneWidget);
      expect(find.text('Doanh số hoàn thành'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Doanh số khách hàng doanh nghiệp'), findsOneWidget);
      expect(find.text('Doanh số khách hàng cá nhân'), findsOneWidget);
      expect(find.text('Số lượng CTKM đổi điểm thi'), findsOneWidget);
      expect(find.text('Số lượng CTKM HSSV'), findsOneWidget);
      expect(find.text('Số lượng nhu cầu trả góp'), findsOneWidget);
      expect(find.text('Số lượng trả góp thành công'), findsOneWidget);
      expect(find.text('Số lượng bảo hiểm mở rộng'), findsOneWidget);
      expect(find.text('Số lượng laptop'), findsOneWidget);
      expect(find.text('Số lượng PC bộ'), findsOneWidget);
      expect(find.text('Số lượng PC ráp'), findsOneWidget);
      expect(find.text('Số lượng Apple'), findsOneWidget);
      expect(find.text('Số lượng màn hình'), findsOneWidget);
      expect(find.text('Số lượng máy in'), findsOneWidget);
      expect(find.text('Số lượng phụ kiện'), findsOneWidget);
      expect(find.text('Số khách chưa mua'), findsOneWidget);
      expect(find.text('Báo cáo đã mua'), findsOneWidget);
      expect(find.text('Tỉ lệ 3 giải pháp'), findsOneWidget);
      expect(find.text('Tỉ lệ trải nghiệm'), findsOneWidget);
      expect(find.text('Tỉ lệ Zalo OA'), findsOneWidget);
      expect(find.text('Tỉ lệ tải App'), findsOneWidget);
      expect(find.text('Báo cáo chưa mua'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-notPurchasedReports')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      expect(find.text('Tổng số báo cáo hợp lệ'), findsNothing);
      expect(find.text('Tổng số tiền chuyển khoản'), findsOneWidget);
      expect(find.text('Tổng số sao kê'), findsOneWidget);
      expect(find.text('Tổng sao kê có đơn hàng'), findsOneWidget);
      expect(find.text('Tổng sao kê chưa có đơn hàng'), findsOneWidget);
      expect(find.text('Tỉ lệ sao kê có đơn hàng'), findsOneWidget);
      expect(find.text('98M VND'), findsOneWidget);
      expect(find.text('Trang chủ vận hành'), findsOneWidget);
      expect(find.text('Doanh số trong ngày'), findsNothing);
      expect(find.text('125M VND'), findsOneWidget);
      expect(find.text('100M VND'), findsOneWidget);
      expect(find.text('25M VND'), findsWidgets);
      expect(find.text('2,5M VND'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const Key('home-summary-card-businessCustomerRevenue'),
          ),
          matching: find.text('60M VND'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key('home-summary-card-personalCustomerRevenue'),
          ),
          matching: find.text('65M VND'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-appleQuantity')),
          matching: find.text('6'),
        ),
        findsOneWidget,
      );
      final salesGrid = tester.widget<Wrap>(
        find.byKey(const Key('home-summary-grid')),
      );
      final salesMetricKeys = salesGrid.children
          .map((child) => ((child as SizedBox).child! as SummaryCard).metricKey)
          .toList();
      expect(
        salesMetricKeys,
        containsAllInOrder([
          'revenue',
          'totalOrders',
          'averageOrderValue',
          'completedRevenue',
          'pendingRevenue',
          'conversionRate',
        ]),
      );
      final behaviorGrid = tester.widget<Wrap>(
        find.byKey(const Key('home-sales-behavior-summary-grid')),
      );
      final behaviorMetricKeys = behaviorGrid.children
          .map((child) => ((child as SizedBox).child! as SummaryCard).metricKey)
          .toList();
      expect(
        behaviorMetricKeys,
        containsAllInOrder([
          'notPurchasedReports',
          'unreportedOrders',
          'reportedOrders',
          'coverageRate',
          'consultedSolutionRate',
          'experiencedRate',
          'zaloRate',
          'appDownloadRate',
        ]),
      );
      final mainKpiGrid = tester.widget<Wrap>(
        find.byKey(const Key('home-main-kpi-summary-grid')),
      );
      final mainKpiMetricKeys = mainKpiGrid.children
          .map((child) => ((child as SizedBox).child! as SummaryCard).metricKey)
          .toList();
      expect(
        mainKpiMetricKeys,
        containsAllInOrder([
          'businessCustomerRevenue',
          'personalCustomerRevenue',
          'examScorePromotionCount',
          'studentPromotionCount',
          'installmentNeedCount',
          'successfulInstallmentCount',
          'extendedInsuranceQuantity',
          'laptopQuantity',
          'pcQuantity',
          'assembledPcQuantity',
          'appleQuantity',
          'monitorQuantity',
          'printerQuantity',
          'accessoriesQuantity',
        ]),
      );
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
      expect(find.text('Tổng quan cá nhân'), findsOneWidget);
      expect(find.text('Tổng quan Cửa hàng'), findsOneWidget);
      expect(find.byKey(const Key('home-sales-progress-week')), findsOneWidget);
      expect(
        find.byKey(const Key('home-sales-progress-month')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('home-scope-sales-progress-range')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const Key('home-sales-progress-range-donut')),
        ),
        const Size.square(68),
      );
      expect(find.textContaining('Đã đạt:'), findsWidgets);
      expect(find.textContaining('Chỉ tiêu:'), findsWidgets);
      expect(find.text('Đã đạt: 1,2B VND'), findsOneWidget);
      expect(find.text('Chỉ tiêu: 3B VND'), findsOneWidget);
      expect(find.text('Đã đạt: 2,4B VND'), findsOneWidget);
      expect(find.text('Chỉ tiêu: 6B VND'), findsOneWidget);
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

  testWidgets('Home behavior cards open detail tables in modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = HomeSummary(
      date: '2026-07-04',
      available: true,
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      scopeDetail: 'CP75',
      coverageLabel: 'Tỉ lệ báo cáo',
      totalRevenue: 1000000,
      totalOrders: 2,
      totalReports: 2,
      reportedOrders: 1,
      notPurchasedReports: 1,
      unreportedOrders: 1,
      coverageRate: 50,
      refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
    );
    final details = HomeSalesBehaviorDetails(
      startDate: '2026-07-04',
      endDate: '2026-07-04',
      scope: 'OWN',
      scopeLabel: 'Phạm vi cá nhân',
      selectedSalesProgressUserId: null,
      limit: 200,
      notPurchasedTotal: 1,
      unreportedTotal: 1,
      installmentNeedTotal: 2,
      notPurchasedReports: [
        HomeNotPurchasedReportDetail(
          id: 'report-2',
          submittedAt: DateTime(2026, 7, 4, 9),
          salesName: 'SA Một',
          customerName: 'Nguyễn Văn A',
          customerTypeLabel: 'Doanh nghiệp',
          categoryName: 'Linh kiện máy tính',
          notPurchasedReasonLabel: 'Phân vân giá',
        ),
      ],
      unreportedOrders: [
        HomeUnreportedOrderDetail(
          orderCode: '2607040002',
          soldAt: DateTime(2026, 7, 4, 10, 30),
          salesName: 'SA Hai',
        ),
      ],
      installmentNeedReports: [
        HomeInstallmentNeedDetail(
          id: 'report-3',
          submittedAt: DateTime(2026, 7, 4, 11),
          storeCode: 'CP75',
          salesName: 'SA Ba',
          orderCode: '2607040003',
          installmentPartnerLabels: const ['Mirae Asset'],
          successful: true,
          note: '2607040003',
        ),
        HomeInstallmentNeedDetail(
          id: 'report-4',
          submittedAt: DateTime(2026, 7, 4, 12),
          storeCode: 'CP62',
          salesName: 'SA Bốn',
          orderCode: null,
          installmentPartnerLabels: const ['MPOS'],
          successful: false,
          note: 'Khách từ chối: Lãi suất/Phí trả góp cao',
        ),
      ],
    );
    final repository = _FakeHomeSummaryRepository(
      summary: summary,
      salesBehaviorDetails: details,
    );
    final summaryProvider = HomeSummaryProvider(repository);
    addTearDown(summaryProvider.dispose);
    summaryProvider.syncAuth(_staffUser(), isInitialized: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 920,
              child: HomeSummaryPage(provider: summaryProvider),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notPurchasedTitle = find.byKey(
      const Key('home-summary-card-notPurchasedReports-title-action'),
    );
    await tester.ensureVisible(notPurchasedTitle);
    await tester.pumpAndSettle();
    await tester.tap(notPurchasedTitle);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-sales-behavior-details-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-not-purchased-details-table')),
      findsOneWidget,
    );
    expect(find.text('Tên SA'), findsOneWidget);
    expect(find.text('Tên khách hàng'), findsOneWidget);
    expect(find.text('Loại khách hàng'), findsOneWidget);
    expect(find.text('Ngành hàng'), findsOneWidget);
    expect(find.text('Lý do không mua'), findsOneWidget);
    expect(find.text('SA Một'), findsOneWidget);
    expect(find.text('Nguyễn Văn A'), findsOneWidget);
    expect(find.text('Doanh nghiệp'), findsOneWidget);
    expect(find.text('Linh kiện máy tính'), findsOneWidget);
    expect(find.text('Phân vân giá'), findsOneWidget);

    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    final unreportedValue = find.byKey(
      const Key('home-summary-card-unreportedOrders-value-action'),
    );
    await tester.ensureVisible(unreportedValue);
    await tester.pumpAndSettle();
    await tester.tap(unreportedValue);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-unreported-orders-details-table')),
      findsOneWidget,
    );
    expect(find.text('Mã đơn hàng'), findsOneWidget);
    expect(find.text('Thời gian bán'), findsOneWidget);
    expect(find.text('SA Hai'), findsOneWidget);
    expect(find.text('2607040002'), findsOneWidget);
    expect(find.text('04/07/2026 10:30'), findsOneWidget);

    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    final installmentNeedTitle = find.byKey(
      const Key('home-summary-card-installmentNeedCount-title-action'),
    );
    await tester.ensureVisible(installmentNeedTitle);
    await tester.pumpAndSettle();
    await tester.tap(installmentNeedTitle);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-installment-need-details-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-installment-need-details-table')),
      findsOneWidget,
    );
    expect(find.text('SR'), findsOneWidget);
    expect(find.text('Đối tác trả góp'), findsOneWidget);
    expect(find.text('Thành công'), findsOneWidget);
    expect(find.text('Ghi chú'), findsOneWidget);
    expect(find.text('CP75'), findsOneWidget);
    expect(find.text('SA Ba'), findsOneWidget);
    expect(find.text('Mirae Asset'), findsOneWidget);
    expect(find.text('2607040003'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('CP62'), findsOneWidget);
    expect(find.text('SA Bốn'), findsOneWidget);
    expect(find.text('MPOS'), findsOneWidget);
    expect(find.text('Không'), findsOneWidget);
    expect(
      find.text('Khách từ chối: Lãi suất/Phí trả góp cao'),
      findsOneWidget,
    );
    expect(repository.requestedDetailLimits, [200, 200, 200]);
  });

  testWidgets(
    'Home route cards open admin sales and missing-order statements',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final summaryProvider = HomeSummaryProvider(
        _FakeHomeSummaryRepository(
          summary: HomeSummary(
            date: '2026-07-04',
            available: true,
            scope: 'MANAGED_SCOPE',
            scopeLabel: 'Showroom: CP75',
            scopeDetail: 'CP75',
            coverageLabel: 'Tỉ lệ báo cáo',
            totalRevenue: 1000000,
            totalOrders: 3,
            totalReports: 3,
            reportedOrders: 2,
            notPurchasedReports: 1,
            unreportedOrders: 1,
            installmentNeedCount: 1,
            coverageRate: 66.67,
            financeAvailable: true,
            totalTransferredAmount: 3000000,
            totalStatements: 4,
            totalStatementsWithOrder: 2,
            totalStatementsWithoutOrder: 2,
            statementOrderRate: 50,
            refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
          ),
        ),
      );
      addTearDown(summaryProvider.dispose);
      summaryProvider.syncAuth(_managerFinanceUser(), isInitialized: true);

      late final GoRouter router;
      router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 1120,
                  child: HomeSummaryPage(provider: summaryProvider),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/admin/sales-reports',
            builder: (context, state) =>
                const Scaffold(body: Text('Admin Sales Reports Route')),
          ),
          GoRoute(
            path: '/bank-statement',
            builder: (context, state) => Scaffold(
              body: Text(
                'Bank Statement ${state.uri.queryParameters['orderStatus']} '
                '${state.uri.queryParameters['autoSearch']}',
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final reportedAction = find.byKey(
        const Key('home-summary-card-reportedOrders-title-action'),
      );
      await tester.ensureVisible(reportedAction);
      await tester.pumpAndSettle();
      await tester.tap(reportedAction);
      await tester.pumpAndSettle();

      expect(find.text('Admin Sales Reports Route'), findsOneWidget);

      router.go('/');
      await tester.pumpAndSettle();

      final statementAction = find.byKey(
        const Key('home-summary-card-totalStatementsWithoutOrder-title-action'),
      );
      await tester.ensureVisible(statementAction);
      await tester.pumpAndSettle();
      await tester.tap(statementAction);
      await tester.pumpAndSettle();

      expect(find.text('Bank Statement MISSING_ORDER true'), findsOneWidget);

      router.dispose();
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
      find.byKey(const Key('home-summary-card-averageOrderValue')),
    );
    expect(first.dy, second.dy);
    expect(first.dx, lessThan(second.dx));
    expect(third.dy, greaterThan(first.dy));
  });

  testWidgets('Home overview gives sales progress cards readable width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summary = _managerSalesProgressSummary('sa-1', includeFinance: true);
    final summaryProvider = HomeSummaryProvider(
      _FakeHomeSummaryRepository(summary: summary),
    );
    addTearDown(summaryProvider.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1180,
            child: ReportProgressPanel(
              summary: summary,
              provider: summaryProvider,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reportPanel = find.byKey(const Key('home-report-progress-panel'));
    final statementPanel = find.byKey(
      const Key('home-statement-progress-panel'),
    );
    final personalPanel = find.byKey(const Key('home-sales-progress-panel'));
    final scopePanel = find.byKey(const Key('home-scope-sales-progress-panel'));
    final reportTopLeft = tester.getTopLeft(reportPanel);
    final statementTopLeft = tester.getTopLeft(statementPanel);
    final personalTopLeft = tester.getTopLeft(personalPanel);
    final scopeTopLeft = tester.getTopLeft(scopePanel);
    expect(statementTopLeft.dy, reportTopLeft.dy);
    expect(personalTopLeft.dy, reportTopLeft.dy);
    expect(scopeTopLeft.dy, reportTopLeft.dy);
    expect(reportTopLeft.dx, lessThan(statementTopLeft.dx));
    expect(statementTopLeft.dx, lessThan(personalTopLeft.dx));
    expect(personalTopLeft.dx, lessThan(scopeTopLeft.dx));
    final combinedSmallWidth =
        tester.getSize(reportPanel).width +
        tester.getSize(statementPanel).width +
        16;
    expect(combinedSmallWidth, closeTo(tester.getSize(personalPanel).width, 1));
    expect(
      tester.getSize(personalPanel).width,
      closeTo(tester.getSize(scopePanel).width, 1),
    );
    final scopeMonthActual = tester.widget<Text>(
      find.byKey(const Key('home-scope-sales-progress-month-actual-label')),
    );
    final scopeMonthTarget = tester.widget<Text>(
      find.byKey(const Key('home-scope-sales-progress-month-target-label')),
    );
    expect(scopeMonthActual.overflow, isNot(TextOverflow.ellipsis));
    expect(scopeMonthTarget.overflow, isNot(TextOverflow.ellipsis));
    expect(scopeMonthActual.maxLines, 2);
    expect(scopeMonthTarget.maxLines, 2);
    expect(find.text('Đã đạt: 60M VND'), findsOneWidget);
    expect(find.text('Chỉ tiêu: 120M VND'), findsOneWidget);
  });

  testWidgets('Home KPI grid keeps revenue cards on one wide row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      notPurchasedReports: 3,
      unreportedOrders: 4,
      coverageRate: 60,
      refreshedAt: null,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 1200, child: SummaryCardGrid(summary: summary)),
        ),
      ),
    );

    final first = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-revenue')),
    );
    final notPurchased = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-completedRevenue')),
    );
    final last = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-conversionRate')),
    );
    expect(notPurchased.dy, first.dy);
    expect(last.dy, first.dy);
    expect(notPurchased.dx, lessThan(last.dx));
  });

  testWidgets('Home main KPI grid keeps requested two desktop rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
      businessCustomerRevenue: 600000,
      personalCustomerRevenue: 400000,
      examScorePromotionCount: 1,
      studentPromotionCount: 2,
      installmentNeedCount: 3,
      successfulInstallmentCount: 4,
      extendedInsuranceQuantity: 5,
      laptopQuantity: 6,
      pcQuantity: 7,
      assembledPcQuantity: 1,
      appleQuantity: 8,
      monitorQuantity: 9,
      printerQuantity: 10,
      accessoriesQuantity: 11,
      coverageRate: 60,
      refreshedAt: null,
    );

    final repository = _FakeHomeSummaryRepository(summary: summary);
    final provider = HomeSummaryProvider(repository);
    addTearDown(provider.dispose);
    provider.syncAuth(_staffUser(), isInitialized: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            child: MainKpiSummaryCardGrid(summary: summary, provider: provider),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('home-main-kpi-summary-grid-row-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-main-kpi-summary-grid-row-2')),
      findsOneWidget,
    );

    final business = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-businessCustomerRevenue')),
    );
    final successfulInstallment = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-successfulInstallmentCount')),
    );
    final insurance = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-extendedInsuranceQuantity')),
    );
    final accessories = tester.getTopLeft(
      find.byKey(const Key('home-summary-card-accessoriesQuantity')),
    );

    expect(successfulInstallment.dy, business.dy);
    expect(successfulInstallment.dx, greaterThan(business.dx));
    expect(insurance.dy, greaterThan(business.dy));
    expect(accessories.dy, insurance.dy);
    expect(accessories.dx, greaterThan(insurance.dx));
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

  testWidgets(
    'Home dashboard lets super admin select organization node scope',
    (tester) async {
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
        scopeOptions: const [
          HomeSummaryScopeOptionDto(
            value: 'ALL',
            label: 'Toàn hệ thống',
            scope: 'ALL',
            isDefault: true,
          ),
          HomeSummaryScopeOptionDto(
            value: 'NODE:org-area-hcm',
            label: 'Vùng: Hồ Chí Minh',
            scope: 'MANAGED_SCOPE',
            organizationNodeId: 'org-area-hcm',
            organizationNodeType: 'LV3_AREA',
            storeCount: 2,
          ),
          HomeSummaryScopeOptionDto(
            value: 'NODE:org-store-cp75',
            label: 'Showroom: CP75',
            scope: 'MANAGED_SCOPE',
            organizationNodeId: 'org-store-cp75',
            organizationNodeType: 'LV4_STORE',
            storeCount: 1,
          ),
          HomeSummaryScopeOptionDto(
            value: 'OWN',
            label: 'Phạm vi cá nhân',
            scope: 'OWN',
          ),
        ],
        nodeSummaries: {
          'org-area-hcm': HomeSummary(
            date: '2026-07-04',
            available: true,
            scope: 'MANAGED_SCOPE',
            scopeLabel: 'Vùng: Hồ Chí Minh',
            scopeDetail: '2 showroom được chọn',
            coverageLabel: 'Tỉ lệ báo cáo',
            totalRevenue: 15000000,
            totalOrders: 5,
            totalReports: 4,
            reportedOrders: 4,
            unreportedOrders: 1,
            coverageRate: 80,
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

      expect(summaryProvider.selectedScope, 'ALL');
      expect(find.text('Toàn hệ thống'), findsWidgets);

      await tester.tap(find.byKey(const Key('home-summary-scope-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vùng: Hồ Chí Minh').last);
      await tester.pumpAndSettle();

      expect(summaryProvider.selectedScope, 'NODE:org-area-hcm');
      expect(repository.requestedScopes, contains('MANAGED_SCOPE'));
      expect(repository.requestedNodeIds, contains('org-area-hcm'));
      expect(find.text('Vùng: Hồ Chí Minh'), findsWidgets);
      expect(find.text('15M VND'), findsOneWidget);
    },
  );

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

  testWidgets('Home dashboard defaults to aggregate assigned showroom scope', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_managerUser());
    final repository = _FakeHomeSummaryRepository(
      summary: HomeSummary(
        date: '2026-07-04',
        available: true,
        scope: 'MANAGED_SCOPE',
        scopeLabel: 'Tất cả SR được gán',
        scopeDetail: 'CP75, CP62',
        coverageLabel: 'Tỉ lệ báo cáo',
        totalRevenue: 22000000,
        totalOrders: 8,
        totalReports: 7,
        reportedOrders: 7,
        unreportedOrders: 1,
        coverageRate: 87.5,
        refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
      ),
      scopeOptions: const [
        HomeSummaryScopeOptionDto(
          value: 'MANAGED_SCOPE',
          label: 'Tất cả SR được gán',
          scope: 'MANAGED_SCOPE',
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
        HomeSummaryScopeOptionDto(
          value: 'NODE:org-store-cp62',
          label: 'Showroom: CP62',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'org-store-cp62',
          organizationNodeType: 'LV4_STORE',
          storeCount: 1,
        ),
        HomeSummaryScopeOptionDto(
          value: 'OWN',
          label: 'Phạm vi cá nhân',
          scope: 'OWN',
        ),
      ],
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

    expect(summaryProvider.selectedScope, 'MANAGED_SCOPE');
    expect(repository.requestedScopes, contains('MANAGED_SCOPE'));
    expect(repository.requestedNodeIds, contains(null));
    expect(find.text('Tất cả SR được gán'), findsWidgets);
    expect(find.text('22M VND'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-summary-scope-pill')));
    await tester.pumpAndSettle();

    expect(find.text('Showroom: CP75'), findsWidgets);
    expect(find.text('Showroom: CP62'), findsWidgets);
    expect(find.text('Phạm vi cá nhân'), findsWidgets);
  });

  testWidgets(
    'Home dashboard reloads sales KPIs for selected SA but keeps store overview',
    (tester) async {
      final authProvider = _FakeAuthProvider(_managerUser());
      final repository = _FakeHomeSummaryRepository(
        summary: _managerSalesProgressSummary(null, includeFinance: true),
        salesProgressUserSummaries: {
          'sa-2': _managerSalesProgressSummary('sa-2', includeFinance: true),
        },
        scopeOptions: const [
          HomeSummaryScopeOptionDto(
            value: 'NODE:org-store-cp75',
            label: 'Showroom: CP75',
            scope: 'MANAGED_SCOPE',
            organizationNodeId: 'org-store-cp75',
            organizationNodeType: 'LV4_STORE',
            storeCount: 1,
            isDefault: true,
          ),
        ],
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

      expect(
        find.byKey(const Key('home-sales-progress-assignee-dropdown')),
        findsOneWidget,
      );
      expect(summaryProvider.selectedSalesProgressUserId, isNull);
      expect(repository.requestedSalesProgressUserIds, contains(null));
      expect(find.text('Chưa chọn SA'), findsOneWidget);
      expect(find.text('Chọn SA để hiển thị chỉ số'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-revenue')),
          matching: find.text('171M VND'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-totalTransferredAmount')),
          matching: find.text('98M VND'),
        ),
        findsOneWidget,
      );
      expect(find.text('Đã đạt: 60M VND'), findsOneWidget);
      expect(find.text('Chỉ tiêu: 120M VND'), findsOneWidget);

      final assigneeDropdown = find.byKey(
        const Key('home-sales-progress-assignee-dropdown'),
      );
      await tester.ensureVisible(assigneeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(assigneeDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SA Hai - CP75').last);
      await tester.pumpAndSettle();

      expect(repository.requestedSalesProgressUserIds, contains('sa-2'));
      expect(summaryProvider.selectedSalesProgressUserId, 'sa-2');
      expect(find.text('SA Hai - CP75'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-revenue')),
          matching: find.text('80M VND'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-totalOrders')),
          matching: find.text('18'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('home-summary-card-totalTransferredAmount')),
          matching: find.text('98M VND'),
        ),
        findsOneWidget,
      );
      expect(find.text('Đã đạt: 60M VND'), findsOneWidget);
      expect(find.text('Chỉ tiêu: 120M VND'), findsOneWidget);
    },
  );

  testWidgets('Home dashboard uses searchable SA picker for long lists', (
    tester,
  ) async {
    final authProvider = _FakeAuthProvider(_managerUser());
    final repository = _FakeHomeSummaryRepository(
      summary: _managerLongSalesProgressSummary(null),
      salesProgressUserSummaries: {
        'sa-12': _managerLongSalesProgressSummary('sa-12'),
      },
      scopeOptions: const [
        HomeSummaryScopeOptionDto(
          value: 'NODE:org-store-cp75',
          label: 'Showroom: CP75',
          scope: 'MANAGED_SCOPE',
          organizationNodeId: 'org-store-cp75',
          organizationNodeType: 'LV4_STORE',
          storeCount: 1,
          isDefault: true,
        ),
      ],
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

    expect(find.text('Chưa chọn SA'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('home-sales-progress-assignee-dropdown')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-sales-progress-assignee-search-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('home-sales-progress-assignee-search-input')),
      '12',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('home-sales-progress-assignee-option-sa-12')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('home-sales-progress-assignee-option-sa-01')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('home-sales-progress-assignee-option-sa-12')),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedSalesProgressUserIds, contains('sa-12'));
    expect(summaryProvider.selectedSalesProgressUserId, 'sa-12');
    expect(find.text('SA 12 - CP75'), findsOneWidget);
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
  final Map<String, HomeSummary> salesProgressUserSummaries;
  final List<HomeSummaryScopeOptionDto> scopeOptions;
  final HomeSalesBehaviorDetails? salesBehaviorDetails;
  final List<String?> requestedScopes = [];
  final List<String?> requestedNodeIds = [];
  final List<String?> requestedSalesProgressUserIds = [];
  final List<int?> requestedDetailLimits = [];

  _FakeHomeSummaryRepository({
    required this.summary,
    this.scopedSummaries = const {},
    this.nodeSummaries = const {},
    this.salesProgressUserSummaries = const {},
    this.scopeOptions = const [],
    this.salesBehaviorDetails,
  }) : super(ApiClient());

  @override
  Future<HomeSummary> fetchSummary({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
  }) async {
    requestedScopes.add(scope);
    requestedNodeIds.add(organizationNodeId);
    requestedSalesProgressUserIds.add(salesProgressUserId);
    if (salesProgressUserId != null &&
        salesProgressUserSummaries.containsKey(salesProgressUserId)) {
      return salesProgressUserSummaries[salesProgressUserId]!;
    }
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

  @override
  Future<HomeSalesBehaviorDetails> fetchSalesBehaviorDetails({
    String? date,
    String? startDate,
    String? endDate,
    String? scope,
    String? organizationNodeId,
    String? salesProgressUserId,
    int? limit,
  }) async {
    requestedScopes.add(scope);
    requestedNodeIds.add(organizationNodeId);
    requestedSalesProgressUserIds.add(salesProgressUserId);
    requestedDetailLimits.add(limit);
    return salesBehaviorDetails ??
        HomeSalesBehaviorDetails(
          startDate: startDate ?? date ?? summary.startDate,
          endDate: endDate ?? date ?? summary.endDate,
          scope: scope ?? summary.scope,
          scopeLabel: summary.resolvedScopeLabel,
          selectedSalesProgressUserId: salesProgressUserId,
          limit: limit ?? 200,
          notPurchasedTotal: 0,
          unreportedTotal: 0,
          installmentNeedTotal: 0,
          notPurchasedReports: const [],
          unreportedOrders: const [],
          installmentNeedReports: const [],
        );
  }
}

HomeSummary _managerSalesProgressSummary(
  String? selectedUserId, {
  List<HomeSalesProgressAssignee>? assignees,
  bool includeFinance = false,
}) {
  final resolvedAssignees =
      assignees ??
      [
        HomeSalesProgressAssignee(
          userId: 'sa-1',
          label: 'SA Một',
          storeCodes: const ['CP75'],
          isSelected: selectedUserId == 'sa-1',
        ),
        HomeSalesProgressAssignee(
          userId: 'sa-2',
          label: 'SA Hai',
          storeCodes: const ['CP75'],
          isSelected: selectedUserId == 'sa-2',
        ),
      ];
  final isUnselected = selectedUserId == null;
  final isFirstSa = selectedUserId == 'sa-1';
  final personalProgress = isUnselected
      ? const HomeSalesProgress.notApplicable()
      : HomeSalesProgress(
          status: 'AVAILABLE',
          scope: 'PERSONAL_SA',
          missingStoreCodes: const [],
          day: const HomeSalesProgressPeriod(
            actual: 1000000,
            target: 2000000,
            percentage: 50,
          ),
          range: HomeSalesProgressPeriod(
            actual: selectedUserId == 'sa-1' ? 1000000 : 2000000,
            target: 2000000,
            percentage: selectedUserId == 'sa-1' ? 50 : 100,
          ),
          week: const HomeSalesProgressPeriod(
            actual: 5000000,
            target: 10000000,
            percentage: 50,
          ),
          month: const HomeSalesProgressPeriod(
            actual: 20000000,
            target: 40000000,
            percentage: 50,
          ),
        );
  return HomeSummary(
    date: '2026-07-04',
    available: true,
    scope: 'MANAGED_SCOPE',
    scopeLabel: 'Showroom: CP75',
    scopeDetail: 'CP75',
    coverageLabel: 'Tỉ lệ báo cáo',
    totalRevenue: isUnselected ? 171000000 : (isFirstSa ? 125000000 : 80000000),
    totalOrders: isUnselected ? 60 : (isFirstSa ? 42 : 18),
    totalReports: isUnselected ? 53 : (isFirstSa ? 38 : 15),
    reportedOrders: isUnselected ? 47 : (isFirstSa ? 35 : 12),
    notPurchasedReports: isUnselected ? 4 : (isFirstSa ? 3 : 1),
    unreportedOrders: isUnselected ? 13 : (isFirstSa ? 7 : 6),
    averageOrderValue: isUnselected ? 2850000 : (isFirstSa ? 2976190 : 4444444),
    completedRevenue: isUnselected
        ? 170000000
        : (isFirstSa ? 100000000 : 70000000),
    pendingRevenue: isUnselected ? 1000000 : (isFirstSa ? 25000000 : 10000000),
    coverageRate: isUnselected ? 78.33 : (isFirstSa ? 83.33 : 66.67),
    conversionRate: isUnselected ? 113.21 : (isFirstSa ? 110.53 : 120),
    consultedSolutionRate: isUnselected ? 74 : (isFirstSa ? 80 : 60),
    experiencedRate: isUnselected ? 68 : (isFirstSa ? 75 : 55),
    zaloRate: isUnselected ? 48 : (isFirstSa ? 50 : 45),
    appDownloadRate: isUnselected ? 38 : (isFirstSa ? 40 : 35),
    financeAvailable: includeFinance,
    totalTransferredAmount: includeFinance ? 98000000 : 0,
    totalStatements: includeFinance ? 40 : 0,
    totalStatementsWithOrder: includeFinance ? 32 : 0,
    totalStatementsWithoutOrder: includeFinance ? 8 : 0,
    statementOrderRate: includeFinance ? 80 : 0,
    salesProgress: personalProgress,
    personalSalesProgress: personalProgress,
    scopeSalesProgress: const HomeSalesProgress(
      status: 'AVAILABLE',
      scope: 'MANAGED',
      missingStoreCodes: [],
      day: HomeSalesProgressPeriod(
        actual: 3000000,
        target: 6000000,
        percentage: 50,
      ),
      range: HomeSalesProgressPeriod(
        actual: 3000000,
        target: 6000000,
        percentage: 50,
      ),
      week: HomeSalesProgressPeriod(
        actual: 15000000,
        target: 30000000,
        percentage: 50,
      ),
      month: HomeSalesProgressPeriod(
        actual: 60000000,
        target: 120000000,
        percentage: 50,
      ),
    ),
    salesProgressAssignees: resolvedAssignees,
    selectedSalesProgressUserId: selectedUserId,
    refreshedAt: DateTime.parse('2026-07-04T03:15:00.000Z'),
  );
}

HomeSummary _managerLongSalesProgressSummary(String? selectedUserId) {
  return _managerSalesProgressSummary(
    selectedUserId,
    assignees: [
      for (var index = 1; index <= 12; index += 1)
        HomeSalesProgressAssignee(
          userId: 'sa-${index.toString().padLeft(2, '0')}',
          label: 'SA ${index.toString().padLeft(2, '0')}',
          storeCodes: const ['CP75'],
          isSelected:
              selectedUserId == 'sa-${index.toString().padLeft(2, '0')}',
        ),
    ],
  );
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

User _managerFinanceUser() {
  return const User(
    id: 'manager-finance-1',
    email: 'manager-finance@phongvu.vn',
    name: 'Store Manager',
    role: 'USER',
    organizationNodeId: 'org-store-cp75',
    assignedStores: [
      StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
    ],
    featureAccess: {'ADMIN_SALES_REPORTS': true, 'BANK_STATEMENTS': true},
  );
}
