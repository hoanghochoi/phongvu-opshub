import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/app/widgets/app_cards.dart';
import 'package:phongvu_opshub/app/widgets/app_combobox.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:go_router/go_router.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/core/network/realtime_connection_manager.dart';
import 'package:phongvu_opshub/core/platform/app_platform_capabilities.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/sales_report/data/sales_report_repository.dart';
import 'package:phongvu_opshub/features/sales_report/domain/sales_report.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/providers/sales_report_provider.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_admin_screen.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_history_import_dialog.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/screens/sales_report_screen.dart';
import 'package:phongvu_opshub/features/sales_report/presentation/widgets/sales_report_export_menu.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('Sales history import supports only Web and Windows', () {
    expect(
      AppPlatformCapabilities.isSalesHistoryImportSupported(
        isWeb: true,
        platform: TargetPlatform.linux,
      ),
      isTrue,
    );
    expect(
      AppPlatformCapabilities.isSalesHistoryImportSupported(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      isTrue,
    );
    expect(
      AppPlatformCapabilities.isSalesHistoryImportSupported(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      isFalse,
    );
    expect(
      AppPlatformCapabilities.isSalesHistoryImportSupported(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
  });

  test(
    'Sales history import provider completes ready/activate/rollback flow',
    () async {
      final readyJob = SalesHistoryImportJob.fromJson({
        'id': 'job-1',
        'status': 'READY',
        'uploadedBytes': 128,
        'totalRows': 10,
        'cleanRows': 8,
        'quarantinedRows': 2,
        'cleanGrains': 1,
        'quarantinedGrains': 1,
        'cancelRequested': false,
        'versionId': 'version-1',
        'coverage': [
          {
            'date': '2025-08-10',
            'storeCode': 'CP01',
            'status': 'CLEAN',
            'rowCount': 8,
            'quarantinedRows': 0,
            'reasonCodes': <String>[],
          },
        ],
      });
      final repository = _FakeHistorySalesReportRepository(readyJob);
      final provider = SalesReportProvider(
        repository,
        isWeb: false,
        platform: TargetPlatform.windows,
        historyPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(provider.dispose);

      final started = await provider.startHistoryImport(
        SalesReportImportFile(
          name: 'history.csv',
          size: 128,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(started, isTrue);
      expect(repository.enqueueHistoryCount, 1);
      expect(provider.historyImportJob?.canActivate, isTrue);
      expect(provider.historyImportJob?.coverage.single.storeCode, 'CP01');
      expect(provider.isHistoryImportBusy, isFalse);
      expect(provider.historyVersions.single.id, 'version-1');
      expect(
        provider.historyImportMessage,
        'Đã kiểm tra xong. Xem phạm vi rồi kích hoạt phiên bản.',
      );

      expect(await provider.activateHistoryVersion('version-1'), isTrue);
      expect(repository.activatedVersionIds, ['version-1']);
      expect(
        provider.historyImportMessage,
        'Đã kích hoạt phiên bản dữ liệu lịch sử.',
      );

      expect(await provider.rollbackHistoryVersion('version-1'), isTrue);
      expect(repository.rolledBackVersionIds, ['version-1']);
      expect(
        provider.historyImportMessage,
        'Đã hoàn tác phiên bản dữ liệu lịch sử.',
      );
    },
  );

  test(
    'Sales history provider blocks Android and Linux before repository calls',
    () async {
      final readyJob = SalesHistoryImportJob.fromJson({
        'id': 'job-1',
        'status': 'READY',
        'uploadedBytes': 1,
        'versionId': 'version-1',
      });
      for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
        final repository = _FakeHistorySalesReportRepository(readyJob);
        final provider = SalesReportProvider(
          repository,
          isWeb: false,
          platform: platform,
        );
        addTearDown(provider.dispose);

        expect(
          await provider.startHistoryImport(
            SalesReportImportFile(
              name: 'history.csv',
              size: 1,
              bytes: Uint8List.fromList([1]),
            ),
          ),
          isFalse,
        );
        await provider.loadHistoryVersions();
        expect(await provider.activateHistoryVersion('version-1'), isFalse);
        expect(await provider.rollbackHistoryVersion('version-1'), isFalse);

        expect(repository.enqueueHistoryCount, 0);
        expect(repository.fetchHistoryVersionsCount, 0);
        expect(repository.activatedVersionIds, isEmpty);
        expect(repository.rolledBackVersionIds, isEmpty);
      }
    },
  );

  testWidgets(
    'Sales history 500 admission failure is Vietnamese and does not blame a file before a job exists',
    (tester) async {
      final provider = SalesReportProvider(
        _ServerRejectedHistorySalesReportRepository(),
        isWeb: false,
        platform: TargetPlatform.windows,
      );
      addTearDown(provider.dispose);

      expect(
        await provider.startHistoryImport(
          SalesReportImportFile(
            name: 'history.csv',
            size: 1,
            bytes: Uint8List.fromList([1]),
          ),
        ),
        isFalse,
      );
      expect(provider.historyImportJob, isNull);
      expect(
        provider.historyImportError,
        'Máy chủ đang bận xử lý tác vụ nhập dữ liệu. Vui lòng thử lại sau ít phút.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSalesHistoryImportDialog(
                context: context,
                provider: provider,
              ),
              child: const Text('Mở nhập lịch sử'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở nhập lịch sử'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Chưa tạo được tác vụ nhập dữ liệu. Vui lòng chờ ít phút rồi thử lại.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sửa tệp'), findsNothing);
      expect(find.textContaining('Internal Server Error'), findsNothing);
    },
  );

  testWidgets(
    'Sales history 500 after job creation keeps operation guidance and does not blame the file',
    (tester) async {
      final provider = SalesReportProvider(
        _ServerRejectedHistoryAfterJobRepository(),
        isWeb: false,
        platform: TargetPlatform.windows,
      );
      addTearDown(provider.dispose);

      expect(
        await provider.startHistoryImport(
          SalesReportImportFile(
            name: 'history.csv',
            size: 1,
            bytes: Uint8List.fromList([1]),
          ),
        ),
        isFalse,
      );
      expect(provider.historyImportJob, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSalesHistoryImportDialog(
                context: context,
                provider: provider,
              ),
              child: const Text('Mở nhập lịch sử'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở nhập lịch sử'));
      await tester.pumpAndSettle();

      expect(
        find.text('Kiểm tra thông báo phía trên rồi thử lại.'),
        findsOneWidget,
      );
      expect(find.textContaining('Sửa tệp'), findsNothing);
    },
  );

  test(
    'Sales history polling retries a transient failure and then completes',
    () async {
      final queued = SalesHistoryImportJob.fromJson({
        'id': 'job-1',
        'status': 'QUEUED',
        'uploadedBytes': 10,
      });
      final ready = SalesHistoryImportJob.fromJson({
        'id': 'job-1',
        'status': 'READY',
        'uploadedBytes': 10,
        'versionId': 'version-1',
        'cleanRows': 1,
        'cleanGrains': 1,
      });
      final repository = _RetryingHistorySalesReportRepository(queued, ready);
      final provider = SalesReportProvider(
        repository,
        isWeb: false,
        platform: TargetPlatform.windows,
        historyPollInterval: const Duration(milliseconds: 1),
      );
      addTearDown(provider.dispose);

      expect(
        await provider.startHistoryImport(
          SalesReportImportFile(
            name: 'history.csv',
            size: 10,
            bytes: Uint8List.fromList([1]),
          ),
        ),
        isTrue,
      );
      for (
        var attempt = 0;
        attempt < 100 && repository.fetchJobCount < 2;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(repository.fetchJobCount, 2);
      expect(provider.historyImportJob?.status, 'READY');
      expect(provider.historyImportError, isNull);
      expect(provider.isHistoryImportBusy, isFalse);
    },
  );

  test(
    'Sales history polling can explicitly reattach after retry exhaustion',
    () async {
      final queued = SalesHistoryImportJob.fromJson({
        'id': 'job-reattach',
        'status': 'QUEUED',
        'uploadedBytes': 10,
      });
      final ready = SalesHistoryImportJob.fromJson({
        'id': 'job-reattach',
        'status': 'READY',
        'uploadedBytes': 10,
        'versionId': 'version-reattach',
        'cleanRows': 1,
        'cleanGrains': 1,
      });
      final repository = _ReattachHistorySalesReportRepository(queued, ready);
      final provider = SalesReportProvider(
        repository,
        isWeb: false,
        platform: TargetPlatform.windows,
        historyPollInterval: const Duration(milliseconds: 1),
        historyPollMaxTransientFailures: 1,
      );
      addTearDown(provider.dispose);

      expect(
        await provider.startHistoryImport(
          SalesReportImportFile(
            name: 'history.csv',
            size: 10,
            bytes: Uint8List.fromList([1]),
          ),
        ),
        isTrue,
      );
      for (
        var attempt = 0;
        attempt < 100 && provider.isHistoryImportBusy;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      expect(provider.canRetryHistoryImportPolling, isTrue);
      expect(provider.canDismissHistoryImport, isFalse);
      expect(provider.historyImportError, contains('“Kiểm tra lại”'));

      await provider.retryHistoryImportPolling();

      expect(repository.fetchJobCount, 2);
      expect(provider.historyImportJob?.status, 'READY');
      expect(provider.historyImportError, isNull);
      expect(provider.canDismissHistoryImport, isTrue);
    },
  );

  testWidgets(
    'Sales history upload exposes progress, blocks Escape, and cancels in flight',
    (tester) async {
      final repository = _DeferredUploadSalesReportRepository();
      final provider = SalesReportProvider(
        repository,
        isWeb: false,
        platform: TargetPlatform.windows,
      );
      addTearDown(provider.dispose);
      final upload = provider.startHistoryImport(
        SalesReportImportFile(
          name: 'history.csv',
          size: 100,
          bytes: Uint8List.fromList(List.filled(100, 1)),
        ),
      );
      await repository.uploadStarted.future;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSalesHistoryImportDialog(
                context: context,
                provider: provider,
              ),
              child: const Text('Mở nhập lịch sử'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở nhập lịch sử'));
      await tester.pumpAndSettle();

      expect(provider.historyImportUploadProgress, 0.5);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byType(LinearProgressIndicator))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      final cancelButton = find.widgetWithText(AppPrimaryButton, 'Hủy tải');
      expect(tester.getSize(cancelButton).height, greaterThanOrEqualTo(48));

      await tester.tap(find.byTooltip('Đóng'));
      await tester.pump();
      expect(
        find.text(
          'Tác vụ chưa hoàn tất. Hãy tiếp tục theo dõi hoặc hủy tác vụ trước khi đóng.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Sửa tệp'), findsNothing);

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(
        find.byKey(const Key('sales-history-import-dialog')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const Key('sales-history-import-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('Sửa tệp'), findsNothing);

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(await upload, isFalse);
      expect(provider.isHistoryImportBusy, isFalse);
      expect(provider.historyImportMessage, 'Đã hủy tải tệp.');
      expect(
        find.text(
          'Tác vụ chưa hoàn tất. Hãy tiếp tục theo dõi hoặc hủy tác vụ trước khi đóng.',
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Sales history parsing and finalizing explain that the dialog cannot close',
    (tester) async {
      for (final status in const ['PARSING', 'FINALIZING']) {
        final activeJob = SalesHistoryImportJob.fromJson({
          'id': 'job-${status.toLowerCase()}',
          'status': status,
          'uploadedBytes': 10,
          'totalRows': 4,
        });
        final repository = _DeferredPollingHistorySalesReportRepository(
          activeJob,
        );
        final provider = SalesReportProvider(
          repository,
          isWeb: false,
          platform: TargetPlatform.windows,
          historyPollInterval: Duration.zero,
        );

        expect(
          await provider.startHistoryImport(
            SalesReportImportFile(
              name: 'history.csv',
              size: 10,
              bytes: Uint8List.fromList([1]),
            ),
          ),
          isTrue,
        );
        expect(provider.canDismissHistoryImport, isFalse);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSalesHistoryImportDialog(
                  context: context,
                  provider: provider,
                ),
                child: const Text('Mở nhập lịch sử'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Mở nhập lịch sử'));
        await tester.pump();

        final expected = status == 'PARSING'
            ? 'Chưa thể đóng cửa sổ khi OpsHub đang kiểm tra dữ liệu. Hãy chờ hoàn tất hoặc chọn Hủy tải.'
            : 'Chưa thể đóng cửa sổ khi OpsHub đang tạo phiên bản. Hãy chờ hoàn tất hoặc chọn Hủy tải.';
        expect(find.text(expected), findsOneWidget);

        repository.finishPolling();
        await tester.pump();
        provider.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Sales history clean dialog dismisses from outside tap', (
    tester,
  ) async {
    final provider = SalesReportProvider(
      _FakeSalesReportRepository(),
      isWeb: false,
      platform: TargetPlatform.windows,
    );
    addTearDown(provider.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSalesHistoryImportDialog(
              context: context,
              provider: provider,
            ),
            child: const Text('Mở nhập lịch sử'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở nhập lịch sử'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sales-history-import-dialog')), findsNothing);
  });

  testWidgets(
    'Sales history import action is hidden on Linux and opens on Windows',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'admin-1',
          email: 'lead@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-area-hcm',
          featureAccess: {'ADMIN_SALES_REPORTS': true},
        ),
      );
      final linuxProvider = SalesReportProvider(
        _FakeSalesReportRepository(),
        now: () => DateTime(2026, 8, 10, 9),
      );
      addTearDown(linuxProvider.dispose);

      Widget appFor(SalesReportProvider provider) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalesReportAdminScreen()),
        ),
      );

      await tester.pumpWidget(appFor(linuxProvider));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sales-history-import-action')),
        findsNothing,
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final windowsProvider = SalesReportProvider(
        _FakeSalesReportRepository(),
        now: () => DateTime(2026, 8, 10, 9),
      );
      addTearDown(windowsProvider.dispose);
      await tester.pumpWidget(appFor(windowsProvider));
      await tester.pumpAndSettle();

      final action = find.byKey(const Key('sales-history-import-action'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sales-history-import-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('sales-history-import-header')),
        findsOneWidget,
      );
      expect(find.text('Nhập dữ liệu bán hàng lịch sử'), findsOneWidget);
      expect(find.text('Chọn tệp'), findsOneWidget);
      expect(find.text('Xem lịch sử'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Báo cáo opens a two-column order cockpit', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository(unreportedTotal: 7998);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: SalesReportScreen()),
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
    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(find.text('Báo cáo bán hàng'), findsNothing);
    expect(find.text('Mua thủ công'), findsOneWidget);
    expect(find.text('Chưa mua'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mua thủ công')).dy,
      tester.getTopLeft(find.text('Chưa mua')).dy,
    );
    expect(find.text('Đã báo cáo • 1'), findsOneWidget);
    expect(find.text('Chưa báo cáo • 7.998'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Chưa báo cáo • 7.998')).dx,
      lessThan(tester.getTopLeft(find.text('Đã báo cáo • 1')).dx),
    );
    expect(find.text('2607010001'), findsOneWidget);
    expect(find.text('2607010002'), findsOneWidget);
    expect(find.text('Báo cáo'), findsNothing);
    expect(
      tester.getSize(
        find.byKey(const Key('sales-report-order-2607010001')),
      ).height,
      102,
    );
    expect(
      tester.getSize(
        find.byKey(const Key('sales-report-order-2607010002')),
      ).height,
      102,
    );
    expect(find.text('CP62 • Sale CP62'), findsOneWidget);
    expect(find.text('sale.cp62@phongvu.vn'), findsOneWidget);
    expect(find.textContaining('ĐỊA ĐIỂM KINH DOANH'), findsNothing);
    expect(find.text('Trang 1/400'), findsOneWidget);
    expect(find.text('Trước'), findsNothing);
    expect(find.text('Sau'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await tester.tap(find.text('2607010001'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);

    await tester.ensureVisible(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.pumpAndSettle();

    expect(repository.fetchOrdersCount, 2);
    expect(repository.lastOrdersQuery?.reportedPage, 0);
    expect(repository.lastOrdersQuery?.unreportedPage, 1);
    expect(repository.lastOrdersQuery?.limit, 20);

    await tester.ensureVisible(find.text('Mua thủ công'));
    await tester.tap(find.text('Mua thủ công'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Báo cáo mua hàng'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Chưa mua'));
    await tester.tap(find.text('Chưa mua'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Báo cáo chưa mua hàng'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('Báo cáo mobile stacks the approved direct controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(find.text('Chờ báo cáo'), findsNothing);
    expect(find.text('Hoàn tất'), findsNothing);
    expect(find.text('Mua thủ công'), findsOneWidget);
    expect(find.text('Chưa mua'), findsOneWidget);
    final purchasedAction = find.widgetWithText(
      AppPrimaryButton,
      'Mua thủ công',
    );
    final notPurchasedAction = find.widgetWithText(
      AppPrimaryButton,
      'Chưa mua',
    );
    final controls = find.byKey(const Key('sales-report-controls'));
    final dateFilter = find.byKey(const Key('sales-report-orders-date-range'));
    final storeFilter = find.byKey(const Key('sales-report-orders-store'));
    final userFilter = find.byKey(const Key('sales-report-orders-user'));
    final reloadAction = find.byKey(const Key('sales-report-reload-action'));
    for (final control in [
      dateFilter,
      storeFilter,
      userFilter,
      purchasedAction,
      notPurchasedAction,
      reloadAction,
    ]) {
      expect(tester.getSize(control), const Size(311, 48));
    }
    expect(tester.getSize(controls), const Size(343, 380));
    expect(tester.getRect(dateFilter).left - tester.getRect(controls).left, 16);
    expect(tester.getRect(dateFilter).top - tester.getRect(controls).top, 16);
    final compactLane = [
      dateFilter,
      storeFilter,
      userFilter,
      purchasedAction,
      notPurchasedAction,
      reloadAction,
    ];
    for (var index = 1; index < compactLane.length; index += 1) {
      expect(
        tester.getRect(compactLane[index]).top -
            tester.getRect(compactLane[index - 1]).bottom,
        12,
      );
    }
    expect(
      tester.widget<AppPrimaryButton>(purchasedAction).padding,
      const EdgeInsets.symmetric(horizontal: 12),
    );
    expect(
      tester.widget<AppPrimaryButton>(notPurchasedAction).padding,
      const EdgeInsets.symmetric(horizontal: 12),
    );
    expect(
      tester.getTopLeft(notPurchasedAction).dy,
      greaterThan(tester.getBottomLeft(purchasedAction).dy),
    );
    expect(find.text('Chưa báo cáo • 21'), findsOneWidget);
    expect(find.text('Đã báo cáo • 1'), findsOneWidget);
    expect(find.text('2607010002'), findsOneWidget);
    expect(find.text('2607010001'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Đã báo cáo • 1'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2607010001'), findsOneWidget);

    expect(find.text('Lọc'), findsNothing);

    for (final width in const [360.0, 320.0]) {
      tester.view.physicalSize = Size(width, 812);
      await tester.pumpAndSettle();
      expect(tester.getSize(purchasedAction).width, width - 64);
      expect(tester.getSize(notPurchasedAction).width, width - 64);
      final firstRect = tester.getRect(purchasedAction);
      final secondRect = tester.getRect(notPurchasedAction);
      expect(secondRect.top - firstRect.bottom, 12);
      expect(secondRect.right, lessThanOrEqualTo(width - 16));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Báo cáo app route provides the sales report provider', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
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
    expect(find.text('Đã báo cáo • 1'), findsOneWidget);
    expect(find.text('Chưa báo cáo • 21'), findsOneWidget);
  });

  testWidgets('manager cockpit filters orders by date, showroom and user', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'manager-1',
        email: 'manager@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository(managedScope: true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 1),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ngày: 01/07/2026'), findsOneWidget);
    expect(
      find.text(
        'Không chọn khoảng ngày: hệ thống mặc định lấy 30 ngày gần nhất.',
      ),
      findsNothing,
    );
    expect(find.text('Tất cả showroom'), findsOneWidget);
    expect(find.text('Tất cả nhân viên'), findsOneWidget);
    final showroomFilter = tester.widget<AppCombobox<String>>(
      find.byType(AppCombobox<String>).first,
    );
    final employeeFilter = tester.widget<AppCombobox<String>>(
      find.byType(AppCombobox<String>).at(1),
    );
    expect(showroomFilter.menuWidth, 180);
    expect(employeeFilter.menuWidth, 220);
    expect(showroomFilter.showLabel, isFalse);
    expect(employeeFilter.showLabel, isFalse);
    expect(showroomFilter.fixedHeight, 48);
    expect(employeeFilter.fixedHeight, 48);
    expect(showroomFilter.closedIcon, PhosphorIconsRegular.caretDown);
    expect(employeeFilter.closedIcon, PhosphorIconsRegular.caretDown);
    final searchFields = find.byType(TextField);
    expect(searchFields, findsNWidgets(2));
    expect(tester.getSize(searchFields.first).height, 48);
    expect(tester.getSize(searchFields.at(1)).height, 48);
    expect(
      tester.getTopLeft(searchFields.first).dy,
      tester.getTopLeft(searchFields.at(1)).dy,
    );
    final reloadButton = find.widgetWithText(AppSecondaryButton, 'Tải lại');
    expect(
      tester.getTopLeft(reloadButton).dy,
      greaterThan(tester.getBottomLeft(searchFields.first).dy),
    );
    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 7, 1));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));

    await tester.tap(find.byKey(const Key('open-date-range-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 ngày gần nhất'));
    await tester.tap(find.byKey(const Key('date-range-apply')));
    await tester.pumpAndSettle();

    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 6, 25));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));

    await tester.tap(find.byType(AppCombobox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP01 - Phong Vu CP01'));
    await tester.pumpAndSettle();

    expect(repository.lastOrdersQuery?.storeCode, 'CP01');
    expect(repository.lastOrdersQuery?.startDate, DateTime(2026, 6, 25));
    expect(repository.lastOrdersQuery?.endDate, DateTime(2026, 7, 1));
    expect(repository.lastOrdersQuery?.reportedPage, 0);
    expect(repository.lastOrdersQuery?.unreportedPage, 0);

    await tester.tap(find.byType(AppCombobox<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sale CP01 - sale.cp01@phongvu.vn'));
    await tester.pumpAndSettle();

    expect(repository.lastOrdersQuery?.storeCode, 'CP01');
    expect(repository.lastOrdersQuery?.userEmail, 'sale.cp01@phongvu.vn');
  });

  testWidgets(
    'managed compact filters stay direct and preserve provider state',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'manager-1',
          email: 'manager@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-store-cp01',
          featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
        ),
      );
      final repository = _FakeSalesReportRepository(managedScope: true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SalesReportProvider>(
              create: (_) => SalesReportProvider(repository),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sales-report-managed-filter')),
        findsNothing,
      );
      expect(find.textContaining('Bộ lọc nâng cao'), findsNothing);
      expect(find.textContaining(RegExp(r'^Lọc(?: \(\d+\))?$')), findsNothing);
      final controls = find.byKey(const Key('sales-report-controls'));
      final dateFilter = find.byKey(
        const Key('sales-report-orders-date-range'),
      );
      final storeFilter = find.byKey(const Key('sales-report-orders-store'));
      final userFilter = find.byKey(const Key('sales-report-orders-user'));
      final purchased = find.byKey(const Key('sales-report-purchased-action'));
      final notPurchased = find.byKey(
        const Key('sales-report-not-purchased-action'),
      );
      final reload = find.byKey(const Key('sales-report-reload-action'));
      final compactLane = [
        dateFilter,
        storeFilter,
        userFilter,
        purchased,
        notPurchased,
        reload,
      ];
      expect(tester.getSize(controls), const Size(358, 380));
      for (final control in compactLane) {
        expect(tester.getSize(control), const Size(326, 48));
      }
      for (var index = 1; index < compactLane.length; index += 1) {
        expect(
          tester.getRect(compactLane[index]).top -
              tester.getRect(compactLane[index - 1]).bottom,
          12,
        );
      }

      await tester.tap(storeFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CP01 - Phong Vu CP01'));
      await tester.pumpAndSettle();
      expect(repository.lastOrdersQuery?.storeCode, 'CP01');

      await tester.tap(userFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sale CP01 - sale.cp01@phongvu.vn'));
      await tester.pumpAndSettle();
      expect(repository.lastOrdersQuery?.userEmail, 'sale.cp01@phongvu.vn');
    },
  );

  testWidgets(
    'desktop command bar uses available content width instead of window width',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'manager-1',
          email: 'manager@phongvu.vn',
          role: 'USER',
          organizationNodeId: 'org-store-cp01',
          featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SalesReportProvider>(
              create: (_) => SalesReportProvider(
                _FakeSalesReportRepository(managedScope: true),
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 1000, child: SalesReportScreen()),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('sales-report-controls'))).height,
        140,
      );
      expect(
        find.byKey(const Key('sales-report-managed-filter')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Báo cáo follows the Figma loaded geometry matrix', (
    tester,
  ) async {
    final viewports = const [
      Size(1440, 900),
      Size(920, 900),
      Size(768, 900),
      Size(375, 812),
    ];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      for (final viewport in viewports) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        final authProvider = _FakeAuthProvider(
          const User(
            id: 'geometry-user',
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
                create: (_) =>
                    SalesReportProvider(_FakeSalesReportRepository()),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              home: const Scaffold(body: SalesReportScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final controls = tester.getSize(
          find.byKey(const Key('sales-report-controls')),
        );
        final compact = viewport.width < 600;
        final horizontalPadding = viewport.width >= 1200
            ? 64
            : compact
            ? 32
            : 48;
        final expectedWidth =
            (viewport.width >= 1200 ? 1190 : viewport.width) -
            horizontalPadding;
        expect(controls.width, expectedWidth);
        expect(controls.height, compact ? 380 : 140);
        expect(
          find.byKey(const Key('sales-report-workspace-header')),
          findsNothing,
        );
        final purchased = tester.getRect(
          find.widgetWithText(AppPrimaryButton, 'Mua thủ công'),
        );
        final notPurchased = tester.getRect(
          find.widgetWithText(AppPrimaryButton, 'Chưa mua'),
        );
        final reload = tester.getRect(
          find.widgetWithText(AppSecondaryButton, 'Tải lại'),
        );
        final dateFilter = tester.getRect(
          find.byKey(const Key('sales-report-orders-date-range')),
        );
        final storeFilter = tester.getRect(
          find.byKey(const Key('sales-report-orders-store')),
        );
        final userFilter = tester.getRect(
          find.byKey(const Key('sales-report-orders-user')),
        );
        expect(dateFilter.height, 48);
        expect(storeFilter.height, 48);
        expect(userFilter.height, 48);
        expect(purchased.height, 48);
        expect(notPurchased.height, 48);
        expect(reload.height, 48);
        if (compact) {
          expect(dateFilter.width, controls.width - 32);
          expect(storeFilter.width, controls.width - 32);
          expect(userFilter.width, controls.width - 32);
          expect(storeFilter.top - dateFilter.bottom, 12);
          expect(userFilter.top - storeFilter.bottom, 12);
          expect(purchased.width, controls.width - 32);
          expect(notPurchased.width, controls.width - 32);
          expect(reload.width, controls.width - 32);
          expect(notPurchased.top - purchased.bottom, 12);
          expect(reload.top, greaterThan(purchased.bottom));
        } else {
          expect(storeFilter.left - dateFilter.right, closeTo(12, 0.001));
          expect(userFilter.left - storeFilter.right, closeTo(12, 0.001));
          expect(storeFilter.top, dateFilter.top);
          expect(userFilter.top, dateFilter.top);
          expect(notPurchased.left - purchased.right, 12);
          expect(reload.left - notPurchased.right, 12);
          expect(reload.left, greaterThan(notPurchased.right));
          expect(reload.top, purchased.top);
        }
        expect(tester.takeException(), isNull);

        final unreported = find.byKey(
          const Key('sales-report-unreported-column'),
        );
        expect(unreported, findsOneWidget);
        expect(
          tester.getSize(unreported).height,
          viewport.width >= 1200 ? 514 : 360,
        );
        if (viewport.width < 900) {
          await tester.scrollUntilVisible(
            find.text('Đã báo cáo • 1'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
        }
        expect(
          find.byKey(const Key('sales-report-reported-column')),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('Báo cáo opens purchased dialog from unreported order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'sale@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'SALES_REPORT': true},
      ),
    );
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {
        'customerType': 'PERSONAL',
        'customerIsStudent': true,
        'promotionCodes': ['EXAM_SCORE_EXCHANGE', 'STUDENT'],
        'installmentNeed': true,
        'installmentLoanAmount': 5000000,
      },
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(repository),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SalesReportScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2607010002'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repository.checkOrderCount, 1);
    expect(find.text('Báo cáo mua hàng'), findsOneWidget);
    expect(find.text('Đơn hàng đã kiểm tra'), findsOneWidget);
    expect(find.textContaining('Tổng tiền (đã bao gồm VAT):'), findsWidgets);
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-customer-type-PERSONAL'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-customer-student'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-promotion-EXAM_SCORE_EXCHANGE'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-promotion-STUDENT'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            _checkboxTileByKey('sales-report-installment-checkbox'),
          )
          .value,
      isTrue,
    );
    expect(find.text('5.000.000'), findsOneWidget);

    final customerNeedField = _textFormFieldByParentKey(
      'sales-report-customer-need-field',
    );
    await tester.enterText(customerNeedField, List.filled(1001, 'N').join());
    expect(
      tester.widget<TextFormField>(customerNeedField).controller?.text.length,
      1000,
    );

    final header = find.byKey(const Key('sales-report-form-header'));
    final headerTop = tester.getTopLeft(header).dy;
    final dialogScroll = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(dialogScroll, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, headerTop);
  });

  testWidgets('Báo cáo blocks unpaid order submission and returns modal to top', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {
        'order': {'paymentStatus': 'pending_payment'},
      },
    );

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
        child: const MaterialApp(
          home: Scaffold(body: SalesReportFormScreen.purchased()),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-order-code-field'),
      '2607010002',
    );
    final scrollable = find.byType(Scrollable).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);

    final checkButton = tester.widget<AppIconAction>(
      find.byKey(const ValueKey('sales-report-order-check-action')),
    );
    checkButton.onPressed!.call();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text(
        'Đơn chưa thanh toán, vui lòng vào spos bấm Thanh toán lại hoặc Hủy đơn.',
      ),
      findsOneWidget,
    );
    expect(position.pixels, 0);
    expect(
      tester
          .widget<AppPrimaryButton>(
            find.widgetWithText(AppPrimaryButton, 'Gửi báo cáo'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.createCalled, isFalse);
  });

  testWidgets('Chăm sóc lại warns before converting a synced report', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {'willConvertSyncedReport': true},
    );
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
        child: const MaterialApp(
          home: Scaffold(
            body: SalesReportFormScreen.purchased(
              entrySource: 'COMEBACK',
              followUpCaseId: 'case-purchase',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-order-code-field'),
      '2607010002',
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-report-order-check-action')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text(
        'Đơn hàng này đã có trong danh sách đồng bộ. Nếu lưu mua hàng, hệ thống sẽ chuyển báo cáo sang Khách quay lại.',
      ),
      findsOneWidget,
    );
    expect(repository.checkOrderCount, 1);
  });

  testWidgets('Chăm sóc lại warns before converting a legacy report', (
    tester,
  ) async {
    final repository = _FakeSalesReportRepository(
      orderCheckOverrides: const {'willConvertLegacyReport': true},
    );
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
        child: const MaterialApp(
          home: Scaffold(
            body: SalesReportFormScreen.purchased(
              entrySource: 'COMEBACK',
              followUpCaseId: 'case-purchase',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-order-code-field'),
      '2607010002',
    );
    await tester.tap(
      find.byKey(const ValueKey('sales-report-order-check-action')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      find.text(
        'Đơn hàng này thuộc dữ liệu báo cáo cũ. Nếu lưu mua hàng, hệ thống sẽ chuyển báo cáo sang Khách quay lại.',
      ),
      findsOneWidget,
    );
    expect(repository.checkOrderCount, 1);
  });

  testWidgets('Báo cáo hub omits duplicate export and list actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: SalesReportScreen()),
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

    expect(
      find.byKey(const Key('sales-report-workspace-header')),
      findsNothing,
    );
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Chưa mua'), findsOneWidget);
    expect(find.text('Xuất file'), findsNothing);
    expect(find.text('Danh sách'), findsNothing);
    expect(find.text('Đã báo cáo • 1'), findsOneWidget);
    expect(find.text('Chưa báo cáo • 21'), findsOneWidget);
  });

  testWidgets('Sales report order command keeps scan and check on one row', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final viewport in const [Size(375, 812), Size(1024, 768)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'order-command-user',
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
              create: (_) => SalesReportProvider(_FakeSalesReportRepository()),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SalesReportFormScreen.purchased()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('sales-report-order-command-row'));
      final card = find.byKey(
        const ValueKey('sales-report-order-command-card'),
      );
      expect(row, findsOneWidget);
      expect(tester.getSize(row).width, lessThanOrEqualTo(720));
      final rowRect = tester.getRect(row);
      final cardRect = tester.getRect(card);
      expect(rowRect.left - cardRect.left, closeTo(16, 0.1));
      expect(cardRect.right - rowRect.right, closeTo(16, 0.1));
      expect(tester.widget<AppSurfaceCard>(card).radius, 14);
      final checkAction = tester.getSize(
        find.byKey(const ValueKey('sales-report-order-check-action')),
      );
      expect(checkAction.width, viewport.width < 600 ? 48 : 48);
      expect(
        tester.getSize(find.byType(AppIconAction).first).width,
        viewport.width < 600 ? 48 : 48,
      );
      if (viewport.width >= 600) {
        await tester.enterText(
          find.byKey(const ValueKey('sales-report-order-code-field')),
          '2607010001',
        );
        await tester.tap(
          find.byKey(const ValueKey('sales-report-order-check-action')),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('sales-report-order-check-action')),
              )
              .width,
          48,
        );
        expect(find.text('Đã kiểm tra'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Sales report order command uses dark semantic controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'order-command-dark-user',
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
            create: (_) => SalesReportProvider(_FakeSalesReportRepository()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: SalesReportFormScreen.purchased()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('sales-report-order-command-row')),
      findsOneWidget,
    );
    final input = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).first,
        matching: find.byType(EditableText),
      ),
    );
    expect(input.style.color, AppColors.darkTextSecondary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Sales report order command follows iOS/iPadOS geometry', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    for (final viewport in const [Size(390, 844), Size(834, 1112)]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'order-command-ios-user',
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
              create: (_) => SalesReportProvider(_FakeSalesReportRepository()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme.copyWith(platform: TargetPlatform.iOS),
            home: const Scaffold(body: SalesReportFormScreen.purchased()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('sales-report-order-command-row'));
      final card = find.byKey(
        const ValueKey('sales-report-order-command-card'),
      );
      expect(row, findsOneWidget);
      expect(tester.getSize(find.byType(AppIconAction).first).width, 44);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('sales-report-order-check-action')),
            )
            .width,
        44,
      );
      final rowRect = tester.getRect(row);
      final cardRect = tester.getRect(card);
      expect(rowRect.left - cardRect.left, closeTo(16, 0.1));
      expect(cardRect.right - rowRect.right, closeTo(16, 0.1));
      final searchIcon = find.descendant(
        of: find.byKey(const ValueKey('sales-report-order-check-action')),
        matching: find.byIcon(PhosphorIconsRegular.magnifyingGlass),
      );
      expect(searchIcon, findsOneWidget);
      expect(IconTheme.of(tester.element(searchIcon)).color, AppColors.surface);
      expect(tester.widget<AppSurfaceCard>(card).radius, 14);
      expect(
        tester
            .widgetList<AppIconAction>(find.byType(AppIconAction))
            .first
            .radius,
        16,
      );

      expect(tester.takeException(), isNull);
    }
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
        child: const MaterialApp(
          home: Scaffold(body: SalesReportFormScreen.notPurchased()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CheckboxListTile), findsWidgets);
    expect(find.text('Loại khách hàng'), findsOneWidget);
    expect(find.text('Tên khách hàng'), findsOneWidget);
    expect(find.text('Zalo cá nhân của khách hàng'), findsNothing);
    expect(
      _checkboxTileByKey('sales-report-contact-channel-ZALO_PERSONAL'),
      findsOneWidget,
    );
    expect(
      _checkboxTileByKey('sales-report-contact-channel-ZALO_OA'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập tên khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng nhập nhu cầu khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn loại khách hàng'), findsOneWidget);
    expect(find.text('Vui lòng chọn Tư vấn 3 giải pháp'), findsOneWidget);
    expect(
      find.text('Số điện thoại phải gồm 10 chữ số và bắt đầu bằng 0'),
      findsNothing,
    );
    expect(repository.createCalled, isFalse);
  });

  testWidgets(
    'Số điện thoại chưa mua chỉ nhận tối đa 10 chữ số bắt đầu bằng 0',
    (tester) async {
      final repository = _FakeSalesReportRepository();
      await _pumpNotPurchasedForm(tester, repository);
      final phoneField = _textFormFieldByParentKey(
        'sales-report-customer-phone-field',
      );

      await tester.ensureVisible(phoneField);
      await tester.enterText(phoneField, 'abc0912-345-6789');
      await tester.pump();

      expect(
        tester.widget<TextFormField>(phoneField).controller?.text,
        '0912345678',
      );

      await tester.enterText(phoneField, '1912345678');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(phoneField).controller?.text,
        '0912345678',
      );

      await tester.enterText(phoneField, '');
      await tester.enterText(phoneField, '1912345678');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(phoneField).controller?.text,
        isEmpty,
      );
    },
  );

  testWidgets('Báo cáo mua hàng requires CTKM áp dụng', (tester) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: SalesReportFormScreen.purchased(
              initialOrderCode: '2607010002',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Gửi báo cáo'));
    await tester.tap(find.text('Gửi báo cáo'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng chọn CTKM áp dụng'), findsOneWidget);
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
    await tester.ensureVisible(
      _textFormFieldByParentKey('sales-report-customer-phone-field'),
    );
    await tester.enterText(
      _textFormFieldByParentKey('sales-report-customer-phone-field'),
      '0901234567',
    );
    await _tapVisible(
      tester,
      _checkboxTileByKey('sales-report-contact-channel-ZALO_PERSONAL'),
    );
    await _tapVisible(
      tester,
      _checkboxTileByKey('sales-report-contact-channel-ZALO_OA'),
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
      find.byKey(const ValueKey('sales-report-answer-KH tải ứng dụng PV-YES')),
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
    expect(repository.lastInput?.customerPhone, '0901234567');
    expect(repository.lastInput?.customerContactChannels, [
      salesReportContactChannelPhone,
      salesReportContactChannelZaloPersonal,
      salesReportContactChannelZaloOa,
    ]);
    expect(repository.lastInput?.entrySource, isNull);
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
          child: const MaterialApp(
            home: Scaffold(body: SalesReportFormScreen.notPurchased()),
          ),
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

  testWidgets('Báo cáo bán hàng admin filters list by selected date range', (
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
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalesReportAdminScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 1);
    expect(
      find.byKey(const Key('sales-report-admin-workspace-header')),
      findsOneWidget,
    );
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Ngày: 04/07/2026'), findsOneWidget);
    expect(
      find.text(
        'Không chọn khoảng ngày: hệ thống mặc định lấy 30 ngày gần nhất.',
      ),
      findsNothing,
    );
    expect(find.text('Loại'), findsOneWidget);
    expect(find.text('Tất cả'), findsWidgets);
    expect(find.text('Xuất file'), findsOneWidget);
    expect(repository.lastListQuery?.startDate, DateTime(2026, 7, 4));
    expect(repository.lastListQuery?.endDate, DateTime(2026, 7, 4));

    await tester.tap(find.text('Xuất file'));
    await tester.pumpAndSettle();
    expect(find.text('HVTC'), findsOneWidget);
    expect(find.text('Doanh số'), findsOneWidget);
    expect(find.text('Trả góp'), findsOneWidget);

    await tester.tap(find.text('Ngày: 04/07/2026'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('date-range-desktop')), findsOneWidget);
    expect(find.byKey(const Key('from-calendar')), findsOneWidget);
    expect(find.byKey(const Key('to-calendar')), findsOneWidget);
  });

  testWidgets('Báo cáo bán hàng admin filters by assigned SR', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'admin-1',
        email: 'lead@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-area-hcm',
        assignedStores: [
          StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'PV CP01'),
          StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'PV CP02'),
        ],
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SalesReportAdminScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.lastListQuery?.storeIds, isEmpty);
    expect(find.text('Showroom'), findsWidgets);
    expect(find.text('Tất cả showroom'), findsWidgets);

    final storeFilter = find.byType(AppCombobox<String>).at(1);
    await tester.tap(storeFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP02 - PV CP02').last);
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 2);
    expect(repository.lastListQuery?.storeIds, ['CP02']);
    expect(find.text('CP02 - PV CP02'), findsWidgets);
  });

  testWidgets('Báo cáo bán hàng admin loads SR filter for super admin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'super-admin-1',
        email: 'admin@phongvu.vn',
        role: 'SUPER_ADMIN',
        featureAccess: {'ADMIN_SALES_REPORTS': true},
      ),
    );
    final repository = _FakeSalesReportRepository();
    final authRepository = _FakeStoreAuthRepository(const [
      StoreBranch(id: 'store-1', storeId: 'CP01', storeName: 'PV CP01'),
      StoreBranch(id: 'store-2', storeId: 'CP02', storeName: 'PV CP02'),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<SalesReportProvider>(
            create: (_) => SalesReportProvider(
              repository,
              now: () => DateTime(2026, 7, 4, 9),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SalesReportAdminScreen(authRepository: authRepository),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(authRepository.getStoresCount, 1);
    expect(repository.lastListQuery?.storeIds, isEmpty);
    expect(find.text('Showroom'), findsWidgets);
    expect(find.text('Tất cả showroom'), findsWidgets);

    final storeFilter = find.byType(AppCombobox<String>).at(1);
    await tester.tap(storeFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CP02 - PV CP02').last);
    await tester.pumpAndSettle();

    expect(repository.fetchListCount, 2);
    expect(repository.lastListQuery?.storeIds, ['CP02']);
  });

  testWidgets('Sales report export menu emits selected export type', (
    tester,
  ) async {
    String? selectedType;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              child: SalesReportExportMenuButton(
                isExporting: false,
                onExport: (type) => selectedType = type,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Xuất file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doanh số'));
    await tester.pumpAndSettle();

    expect(selectedType, 'REVENUE');
  });

  test('SalesReportOrderCheck parses multiple category groups', () {
    final check = SalesReportOrderCheck.fromJson({
      'orderCode': '2606290001',
      'customerPhone': '0901234567',
      'customerType': 'BUSINESS',
      'customerTypeLabel': 'Doanh nghiệp',
      'willConvertSyncedReport': true,
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
    expect(check.customerPhone, '0901234567');
    expect(check.paymentMethods, ['cash', 'bank_transfer']);
    expect(check.willConvertSyncedReport, isTrue);
  });

  test('SalesReportOrderCheck parses legacy conversion hint', () {
    final check = SalesReportOrderCheck.fromJson({
      'orderCode': '26070734972030',
      'willConvertLegacyReport': true,
    });

    expect(check.willConvertSyncedReport, isFalse);
    expect(check.willConvertLegacyReport, isTrue);
  });

  test('SalesReportProvider exposes converted-report success copy', () async {
    final repository = _FakeSalesReportRepository(
      createResponse: const {'convertedExistingReport': true},
    );
    final provider = SalesReportProvider(repository);
    addTearDown(provider.dispose);

    final result = await provider.submit(
      _purchasedReportInput(),
      const User(id: 'user-1', email: 'sale@phongvu.vn', role: 'USER'),
      followUpCaseId: 'case-purchase',
    );

    expect(result, isTrue);
    expect(
      provider.successMessage,
      'Đã ghi nhận khách quay lại và chuyển nguồn báo cáo.',
    );
  });

  test('SalesReportQuery serializes admin date filters and export type', () {
    final query = SalesReportQuery(
      reportType: 'PURCHASED',
      exportType: 'REVENUE',
      startDate: DateTime(2026, 6, 1, 15, 30),
      endDate: DateTime(2026, 6, 30, 23, 59),
      reporter: 'sale.cp01@phongvu.vn',
      storeIds: const ['CP01'],
      page: 2,
      limit: 50,
    );

    expect(query.toQueryParameters(), {
      'reportType': 'PURCHASED',
      'exportType': 'REVENUE',
      'startDate': '2026-06-01',
      'endDate': '2026-06-30',
      'reporter': 'sale.cp01@phongvu.vn',
      'storeIds': 'CP01',
      'page': '2',
      'limit': '50',
    });
  });

  test(
    'SalesReportOrdersQuery serializes report date range, pages and limit',
    () {
      final query = SalesReportOrdersQuery(
        startDate: DateTime(2026, 6, 25, 9, 30),
        endDate: DateTime(2026, 7, 1, 23, 59),
        reportedPage: 2,
        unreportedPage: 3,
        limit: 75,
        storeCode: 'CP01',
        userEmail: 'sale.cp01@phongvu.vn',
      );

      expect(query.toQueryParameters(), {
        'startDate': '2026-06-25',
        'endDate': '2026-07-01',
        'storeCode': 'CP01',
        'userEmail': 'sale.cp01@phongvu.vn',
        'reportedPage': '2',
        'unreportedPage': '3',
        'limit': '75',
      });
    },
  );

  test('SalesReportOrderCockpit parses reported and unreported orders', () {
    final cockpit = SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'startDate': '2026-06-25',
      'endDate': '2026-07-01',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': 'MANAGED_SCOPE',
      'selectedStoreCode': 'CP01',
      'selectedUserEmail': 'sale.cp01@phongvu.vn',
      'storeOptions': [
        {'value': 'CP01', 'label': 'CP01 - Phong Vu CP01'},
      ],
      'userOptions': [
        {
          'value': 'sale.cp01@phongvu.vn',
          'label': 'Sale CP01 - sale.cp01@phongvu.vn',
        },
      ],
      'limit': 20,
      'reportedPage': 1,
      'reportedTotal': 21,
      'unreportedPage': 2,
      'unreportedTotal': 42,
      'reportedOrders': [
        {'status': 'REPORTED', 'orderCode': '2607010001'},
      ],
      'unreportedOrders': [
        {'status': 'UNREPORTED', 'orderCode': '2607010002'},
      ],
    });

    expect(cockpit.startDate, '2026-06-25');
    expect(cockpit.endDate, '2026-07-01');

    expect(cockpit.scope, 'MANAGED_SCOPE');
    expect(cockpit.selectedStoreCode, 'CP01');
    expect(cockpit.selectedUserEmail, 'sale.cp01@phongvu.vn');
    expect(cockpit.storeOptions.single.value, 'CP01');
    expect(cockpit.userOptions.single.value, 'sale.cp01@phongvu.vn');
    expect(cockpit.limit, 20);
    expect(cockpit.reportedPage, 1);
    expect(cockpit.reportedTotal, 21);
    expect(cockpit.unreportedPage, 2);
    expect(cockpit.unreportedTotal, 42);
    expect(cockpit.reportedOrders.single.isReported, isTrue);
    expect(cockpit.unreportedOrders.single.orderCode, '2607010002');
  });

  test(
    'SalesReportProvider filters and coalesces shared realtime v2 events',
    () async {
      final repository = _FakeSalesReportRepository(managedScope: true);
      final realtime = _FakeRealtimeClient();
      final provider = SalesReportProvider(
        repository,
        now: () => DateTime(2026, 7, 1, 9),
        realtimeClient: realtime,
        realtimeDebounce: const Duration(milliseconds: 15),
        realtimeMaxWait: const Duration(milliseconds: 80),
      );

      await provider.initialize(
        const User(
          id: 'manager-1',
          email: 'manager.cp01@phongvu.vn',
          role: 'USER',
          jobRoleCode: 'STORE_MANAGER',
          storeId: 'CP01',
          featureAccess: {'SALES_REPORT': true, 'ADMIN_SALES_REPORTS': true},
        ),
        orders: true,
        categories: false,
      );
      expect(repository.fetchOrdersCount, 1);

      realtime.addEvent(
        _salesReportEnvelope(
          id: 'wrong-topic',
          topic: 'home.summary',
          dates: const ['2026-07-01'],
        ),
      );
      realtime.addEvent(
        _salesReportEnvelope(id: 'relevant-1', dates: const ['2026-07-01']),
      );
      realtime.addEvent(
        _salesReportEnvelope(id: 'relevant-2', dates: const ['2026-07-01']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(repository.fetchOrdersCount, 1);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.fetchOrdersCount, 2);

      realtime.addEvent(
        _salesReportEnvelope(id: 'outside-date', dates: const ['2026-07-02']),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(repository.fetchOrdersCount, 2);

      realtime.requestSync(RealtimeSyncReason.reconnected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repository.fetchOrdersCount, 3);

      provider.dispose();
      await realtime.dispose();
    },
  );
}

RealtimeEnvelope _salesReportEnvelope({
  required String id,
  String topic = 'sales-report.orders',
  List<String> dates = const [],
}) {
  return RealtimeEnvelope(
    version: 2,
    kind: 'SALES_REPORT_ORDERS_UPDATED',
    id: id,
    topic: topic,
    sequence: id.hashCode.abs(),
    timestamp: DateTime(2026, 7, 1, 9),
    data: {
      'dates': dates,
      'newOrderCount': 1,
      'mappedOrderCount': 0,
      'storeCodes': ['CP01'],
      'recipientUserIds': ['manager-1'],
    },
  );
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
      child: const MaterialApp(
        home: Scaffold(body: SalesReportFormScreen.notPurchased()),
      ),
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

class _FakeStoreAuthRepository extends AuthRepository {
  final List<StoreBranch> stores;
  int getStoresCount = 0;

  _FakeStoreAuthRepository(this.stores) : super(ApiClient());

  @override
  Future<List<StoreBranch>> getStores({String? query}) async {
    getStoresCount += 1;
    return stores;
  }
}

SalesReportInput _purchasedReportInput() {
  return const SalesReportInput(
    reportType: 'PURCHASED',
    orderCode: '2606290001',
    entrySource: 'COMEBACK',
    customerName: 'Nguyễn Văn A',
    customerPhone: '0900000000',
    customerContactChannels: [salesReportContactChannelPhone],
    customerZaloContact: null,
    categoryGroupId: 'NH08',
    categoryGroupIds: ['NH08'],
    customerNeed: 'Laptop',
    consultedSolutionAnswer: 'YES',
    consultedSolutionOtherReason: null,
    experiencedAnswer: 'YES',
    experiencedOtherReason: null,
    zaloAnswer: 'YES',
    zaloOtherReason: null,
    appDownloadAnswer: 'YES',
    appDownloadOtherReason: null,
    notPurchasedReason: null,
    notPurchasedOtherReason: null,
    customerType: 'PERSONAL',
    customerIsStudent: false,
    promotionCodes: ['OTHER'],
    installmentNeed: false,
    installmentApproved: null,
    installmentLoanAmount: null,
    installmentNoInstallmentReason: null,
    installmentStatus: null,
    installmentFailureReason: null,
    installmentPartnerCodes: [],
  );
}

class _FakeSalesReportRepository extends SalesReportRepository {
  final bool managedScope;
  final int unreportedTotal;
  final Map<String, dynamic> orderCheckOverrides;
  final Map<String, dynamic> createResponse;
  bool createCalled = false;
  int fetchListCount = 0;
  int fetchOrdersCount = 0;
  int checkOrderCount = 0;
  SalesReportInput? lastInput;
  SalesReportQuery? lastListQuery;
  SalesReportOrdersQuery? lastOrdersQuery;

  _FakeSalesReportRepository({
    this.managedScope = false,
    this.unreportedTotal = 21,
    this.orderCheckOverrides = const {},
    this.createResponse = const {},
  }) : super(ApiClient());

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
  Future<Map<String, dynamic>> create(
    SalesReportInput input, {
    String? followUpCaseId,
  }) async {
    createCalled = true;
    lastInput = input;
    return createResponse;
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
  Future<SalesReportOrderCheck> checkOrder(
    String orderCode, {
    String? followUpCaseId,
  }) async {
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
      ...orderCheckOverrides,
    });
  }

  @override
  Future<SalesReportOrderCockpit> fetchOrders(
    SalesReportOrdersQuery query,
  ) async {
    fetchOrdersCount += 1;
    lastOrdersQuery = query;
    return SalesReportOrderCockpit.fromJson({
      'date': '2026-07-01',
      'refreshedAt': '2026-07-01T09:03:00.000Z',
      'syncSucceeded': true,
      'syncCount': 2,
      'scope': managedScope ? 'MANAGED_SCOPE' : 'OWN',
      'selectedStoreCode': query.storeCode,
      'selectedUserEmail': query.userEmail,
      'storeOptions': managedScope
          ? [
              {'value': 'CP01', 'label': 'CP01 - Phong Vu CP01'},
            ]
          : const [],
      'userOptions': managedScope
          ? [
              {
                'value': 'sale.cp01@phongvu.vn',
                'label': 'Sale CP01 - sale.cp01@phongvu.vn',
              },
            ]
          : const [],
      'limit': query.limit,
      'reportedPage': query.reportedPage,
      'reportedTotal': 1,
      'unreportedPage': query.unreportedPage,
      'unreportedTotal': unreportedTotal,
      'reportedOrders': [
        {
          'status': 'REPORTED',
          'orderCode': '2607010001',
          'customerName': 'Nguyễn Văn A',
          'grandTotal': 1200000,
          'storeCode': 'CP62',
          'terminalName':
              'CP62 - ĐỊA ĐIỂM KINH DOANH 62 - CÔNG TY CỔ PHẦN THƯƠNG MẠI',
          'reportedAt': '2026-07-01T02:30:00.000Z',
          'employeeEmail': 'reported@phongvu.vn',
          'report': {'type': 'PURCHASED', 'createdByName': 'Người báo cáo'},
        },
      ],
      'unreportedOrders': [
        {
          'status': 'UNREPORTED',
          'orderCode': '2607010002',
          'customerName': 'Trần Thị B',
          'grandTotal': 2500000,
          'storeCode': 'CP62',
          'terminalName':
              'CP62 - ĐỊA ĐIỂM KINH DOANH 62 - CÔNG TY CỔ PHẦN THƯƠNG MẠI',
          'consultantName': 'Tư vấn CP62',
          'sellerName': 'Sale CP62',
          'employeeEmail': 'sale.cp62@phongvu.vn',
        },
      ],
    });
  }
}

class _FakeHistorySalesReportRepository extends _FakeSalesReportRepository {
  _FakeHistorySalesReportRepository(this.readyJob);

  final SalesHistoryImportJob readyJob;
  int enqueueHistoryCount = 0;
  int fetchHistoryVersionsCount = 0;
  final List<String> activatedVersionIds = [];
  final List<String> rolledBackVersionIds = [];

  @override
  Future<SalesHistoryImportJob> enqueueHistoryImport(
    SalesReportImportFile file, {
    void Function(SalesHistoryImportJob job)? onJobChanged,
    bool Function()? isCancelled,
  }) async {
    enqueueHistoryCount += 1;
    onJobChanged?.call(readyJob);
    return readyJob;
  }

  @override
  Future<List<SalesHistoryVersion>> fetchHistoryVersions() async {
    fetchHistoryVersionsCount += 1;
    return [
      SalesHistoryVersion(
        id: readyJob.versionId!,
        rowCount: readyJob.totalRows,
        cleanRowCount: readyJob.cleanRows,
        quarantinedRows: readyJob.quarantinedRows,
        cleanGrainCount: readyJob.cleanGrains,
        quarantineCount: readyJob.quarantinedGrains,
        rangeStart: '2025-08-10',
        rangeEnd: '2025-08-10',
        activeGrainCount: 1,
        lastAction: 'ACTIVATE',
      ),
    ];
  }

  @override
  Future<void> activateHistoryVersion(String id) async {
    activatedVersionIds.add(id);
  }

  @override
  Future<void> rollbackHistoryVersion(String id) async {
    rolledBackVersionIds.add(id);
  }
}

class _ServerRejectedHistorySalesReportRepository
    extends _FakeSalesReportRepository {
  @override
  Future<SalesHistoryImportJob> enqueueHistoryImport(
    SalesReportImportFile file, {
    void Function(SalesHistoryImportJob job)? onJobChanged,
    bool Function()? isCancelled,
  }) {
    throw ApiException('Internal Server Error', 500);
  }
}

class _ServerRejectedHistoryAfterJobRepository
    extends _FakeSalesReportRepository {
  @override
  Future<SalesHistoryImportJob> enqueueHistoryImport(
    SalesReportImportFile file, {
    void Function(SalesHistoryImportJob job)? onJobChanged,
    bool Function()? isCancelled,
  }) {
    onJobChanged?.call(
      SalesHistoryImportJob.fromJson({
        'id': 'job-before-500',
        'status': 'FAILED',
        'uploadedBytes': 1,
        'expectedBytes': 1,
        'totalRows': 0,
        'cleanRows': 0,
        'quarantinedRows': 0,
        'cleanGrains': 0,
        'quarantinedGrains': 0,
        'cancelRequested': false,
        'coverage': const [],
      }),
    );
    throw ApiException('Internal Server Error', 500);
  }
}

class _RetryingHistorySalesReportRepository
    extends _FakeHistorySalesReportRepository {
  _RetryingHistorySalesReportRepository(super.queuedJob, this.completedJob);

  final SalesHistoryImportJob completedJob;
  int fetchJobCount = 0;

  @override
  Future<SalesHistoryImportJob> fetchHistoryImportJob(String id) async {
    fetchJobCount += 1;
    if (fetchJobCount == 1) throw StateError('temporary');
    return completedJob;
  }

  @override
  Future<List<SalesHistoryVersion>> fetchHistoryVersions() async => [
    SalesHistoryVersion(
      id: completedJob.versionId!,
      rowCount: completedJob.totalRows,
      cleanRowCount: completedJob.cleanRows,
      quarantinedRows: completedJob.quarantinedRows,
      cleanGrainCount: completedJob.cleanGrains,
      quarantineCount: completedJob.quarantinedGrains,
      rangeStart: '2025-08-10',
      rangeEnd: '2025-08-10',
      activeGrainCount: 0,
    ),
  ];
}

class _ReattachHistorySalesReportRepository
    extends _FakeHistorySalesReportRepository {
  _ReattachHistorySalesReportRepository(super.queuedJob, this.completedJob);

  final SalesHistoryImportJob completedJob;
  int fetchJobCount = 0;

  @override
  Future<SalesHistoryImportJob> fetchHistoryImportJob(String id) async {
    fetchJobCount += 1;
    if (fetchJobCount == 1) throw StateError('poll exhausted');
    return completedJob;
  }

  @override
  Future<List<SalesHistoryVersion>> fetchHistoryVersions() async => [
    SalesHistoryVersion(
      id: completedJob.versionId!,
      rowCount: completedJob.totalRows,
      cleanRowCount: completedJob.cleanRows,
      quarantinedRows: completedJob.quarantinedRows,
      cleanGrainCount: completedJob.cleanGrains,
      quarantineCount: completedJob.quarantinedGrains,
      rangeStart: '2025-08-10',
      rangeEnd: '2025-08-10',
      activeGrainCount: 0,
    ),
  ];
}

class _DeferredPollingHistorySalesReportRepository
    extends _FakeHistorySalesReportRepository {
  _DeferredPollingHistorySalesReportRepository(super.activeJob);

  final Completer<SalesHistoryImportJob> _polling = Completer();

  @override
  Future<SalesHistoryImportJob> fetchHistoryImportJob(String id) =>
      _polling.future;

  void finishPolling() {
    if (_polling.isCompleted) return;
    _polling.complete(
      SalesHistoryImportJob.fromJson({
        'id': readyJob.id,
        'status': 'CANCELLED',
        'uploadedBytes': readyJob.uploadedBytes,
      }),
    );
  }
}

class _DeferredUploadSalesReportRepository
    extends _FakeHistorySalesReportRepository {
  _DeferredUploadSalesReportRepository()
    : super(
        SalesHistoryImportJob.fromJson({
          'id': 'job-uploading',
          'status': 'UPLOADING',
          'uploadedBytes': 50,
          'expectedBytes': 100,
        }),
      );

  final uploadStarted = Completer<void>();
  final uploadCancelled = Completer<void>();

  @override
  Future<SalesHistoryImportJob> enqueueHistoryImport(
    SalesReportImportFile file, {
    void Function(SalesHistoryImportJob job)? onJobChanged,
    bool Function()? isCancelled,
  }) async {
    onJobChanged?.call(readyJob);
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    await uploadCancelled.future;
    throw const SalesHistoryUploadCancelled();
  }

  @override
  Future<SalesHistoryImportJob> cancelHistoryImport(String id) async {
    if (!uploadCancelled.isCompleted) uploadCancelled.complete();
    return SalesHistoryImportJob.fromJson({
      'id': id,
      'status': 'CANCELLED',
      'uploadedBytes': 50,
      'expectedBytes': 100,
      'cancelRequested': true,
    });
  }
}

class _FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEnvelope>.broadcast();
  final _syncRequests = StreamController<RealtimeSyncReason>.broadcast();

  @override
  Stream<RealtimeEnvelope> get events => _events.stream;

  @override
  Stream<RealtimeSyncReason> get syncRequests => _syncRequests.stream;

  void addEvent(RealtimeEnvelope event) => _events.add(event);

  void requestSync(RealtimeSyncReason reason) => _syncRequests.add(reason);

  @override
  Future<void> syncSession(String? sessionKey) async {}

  Future<void> dispose() async {
    await _events.close();
    await _syncRequests.close();
  }
}
