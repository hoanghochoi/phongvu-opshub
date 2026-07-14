import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/widgets/app_layout.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/bank_statement/data/bank_statement_repository.dart';
import 'package:phongvu_opshub/features/bank_statement/domain/bank_statement_transaction.dart';
import 'package:phongvu_opshub/features/notifications/presentation/providers/app_notifications_provider.dart';
import 'package:phongvu_opshub/features/notifications/presentation/widgets/app_notifications_bell.dart';
import 'package:phongvu_opshub/features/offset_adjustment/data/offset_adjustment_repository.dart';
import 'package:phongvu_opshub/features/offset_adjustment/domain/offset_adjustment.dart';
import 'package:phongvu_opshub/features/quick_actions/data/quick_actions_repository.dart';
import 'package:phongvu_opshub/features/quick_actions/presentation/quick_actions_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '2026.07.03.87',
      buildNumber: '200087',
      buildSignature: '',
    );
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('AppShell replaces the route viewport when location changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);
    expect(find.text('home-route-marker'), findsOneWidget);
    expect(find.text('operations-route-marker'), findsNothing);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/operations',
            child: _RouteMarker(label: 'operations-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-/home')), findsNothing);
    expect(find.byKey(const ValueKey('route-/operations')), findsOneWidget);
    expect(find.text('home-route-marker'), findsNothing);
    expect(find.text('operations-route-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy tasks route redirects to home', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/tasks');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/home');
    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);
    expect(find.textContaining('Chào buổi'), findsOneWidget);
    expect(find.text('Tác vụ của bạn'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public /help stays reachable when the user is logged out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _LoggedOutAuthProvider();
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const _RouteMarker(label: 'help-route-marker'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/help');
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.text('help-route-marker'), findsOneWidget);
    expect(find.text('Email check'), findsNothing);
  });

  testWidgets('login screen exposes a help entry that opens /help', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _LoggedOutAuthProvider();
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const _RouteMarker(label: 'help-route-marker'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(find.text('Hướng dẫn'), findsOneWidget);

    await tester.tap(find.text('Hướng dẫn'));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.text('help-route-marker'), findsOneWidget);
  });

  testWidgets(
    'mobile shell routes to /operations and opens notifications as a route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = _FakeAuthProvider(_shellUser);
      final notificationsProvider = _FakeAppNotificationsProvider();
      final router = AppRouter.createRouter(authProvider);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<AppNotificationsProvider>.value(
              value: notificationsProvider,
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trang chủ'), findsWidgets);
      expect(find.text('Vận hành'), findsOneWidget);
      expect(find.text('Thông báo'), findsOneWidget);
      expect(find.text('Tài khoản'), findsOneWidget);

      await tester.tap(find.text('Vận hành'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/operations');
      expect(find.byKey(const ValueKey('route-/operations')), findsOneWidget);
      expect(
        find.byKey(const Key('operations-feature-section')),
        findsOneWidget,
      );
      expect(find.text('Công cụ theo quyền'), findsNothing);

      await tester.tap(find.text('Thông báo'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/notifications');
      expect(
        find.byKey(const ValueKey('route-/notifications')),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(notificationsProvider.loadCalls, 1);
      expect(notificationsProvider.markReadCalls, 1);
      expect(find.text('Chưa có thông báo.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile navbar gives quick actions its own compact fifth slot', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final authProvider = _FakeAuthProvider(_quickActionsUser);
      final quickActionsProvider = _FakeQuickActionsProvider(
        _quickActionsPayload,
      );
      Widget buildShell(String location) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<QuickActionsProvider>.value(
            value: quickActionsProvider,
          ),
        ],
        child: MaterialApp(
          home: AppMobileTypographyDensity(
            child: AppShell(
              location: location,
              child: const _RouteMarker(label: 'home-route-marker'),
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildShell('/home'));
      await tester.pumpAndSettle();

      final navFinder = find.byKey(const Key('mobile-bottom-navigation'));
      final destinationFinder = find.descendant(
        of: navFinder,
        matching: find.byType(NavigationDestination),
      );
      final quickActionsFinder = find.byKey(
        const Key('quick-actions-launcher'),
      );

      expect(destinationFinder, findsNWidgets(5));
      expect(tester.getSize(navFinder).height, 68);
      expect(quickActionsFinder, findsOneWidget);
      expect(tester.widget<NavigationBar>(navFinder).selectedIndex, 0);

      final navRect = tester.getRect(navFinder);
      final quickActionsRect = tester.getRect(quickActionsFinder);
      expect(navRect.contains(quickActionsRect.topLeft), isTrue);
      expect(navRect.contains(quickActionsRect.bottomRight), isTrue);
      expect(quickActionsRect.size, const Size.square(46));

      final destinationCenters = tester
          .widgetList<NavigationDestination>(destinationFinder)
          .map((destination) => tester.getCenter(find.byWidget(destination)).dx)
          .toList();
      for (var index = 1; index < destinationCenters.length; index++) {
        expect(
          destinationCenters[index] - destinationCenters[index - 1],
          closeTo(390 / 5, 0.5),
        );
      }

      final routeContext = tester.element(find.text('home-route-marker'));
      expect(
        MediaQuery.textScalerOf(routeContext).scale(16),
        closeTo(16 * AppMobileTypographyDensity.scale, 0.01),
      );

      await tester.pumpWidget(buildShell('/notifications'));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navFinder).selectedIndex, 3);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile drawer shows app metadata footer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mở menu'));
    await tester.pumpAndSettle();

    expect(find.text('Version 2026.07.03.87'), findsOneWidget);
    expect(find.text('Dev: Hoàng Học Hỏi'), findsOneWidget);
    expect(find.textContaining('© '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android system back returns to the previous shell route', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      final authProvider = _FakeAuthProvider(_shellUser);
      final router = AppRouter.createRouter(authProvider);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vận hành'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/operations');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('account logout waits for confirmation', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsOneWidget);
    expect(authProvider.logoutCalls, 0);

    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsNothing);
    expect(authProvider.logoutCalls, 0);

    await tester.tap(find.byTooltip('Tài khoản'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();

    expect(authProvider.logoutCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/login');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar help entry opens the in-app help route', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(
      authProvider,
      helpScreen: const _RouteMarker(label: 'help-route-marker'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sidebar-item-help')),
      300,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('desktop-sidebar-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('sidebar-item-help')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/help');
    expect(find.byKey(const ValueKey('route-/help')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-item-help')), findsOneWidget);
    expect(find.text('help-route-marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell routes do not keep the previous page for a transition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final router = AppRouter.createRouter(authProvider);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Chào buổi'), findsOneWidget);
    expect(find.byKey(const ValueKey('route-/home')), findsOneWidget);

    router.go('/warranty-main');
    await tester.pump();

    expect(find.byKey(const ValueKey('route-/home')), findsNothing);
    expect(find.textContaining('Chào buổi'), findsNothing);
    expect(find.byKey(const ValueKey('route-/warranty-main')), findsOneWidget);
    expect(find.byKey(const Key('warranty-main-header')), findsNothing);
    expect(find.text('Tác vụ bảo hành'), findsOneWidget);
    expect(find.text('Lưu hình ảnh'), findsOneWidget);
    expect(find.text('Xem lại hình ảnh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shell omits the header notification bell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final notificationsProvider = _FakeAppNotificationsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: notificationsProvider,
          ),
        ],
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thông báo'), findsOneWidget);
    expect(find.byType(AppNotificationsBell), findsNothing);
    expect(notificationsProvider.loadCalls, 0);
    expect(notificationsProvider.markReadCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shell keeps the notification bell quick menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);
    final notificationsProvider = _FakeAppNotificationsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: notificationsProvider,
          ),
        ],
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppNotificationsBell), findsOneWidget);

    await tester.tap(find.byTooltip('Thông báo'));
    await tester.pumpAndSettle();

    expect(notificationsProvider.loadCalls, 1);
    expect(notificationsProvider.markReadCalls, 1);
    expect(find.text('Chưa có thông báo.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar uses a left indicator for selected route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = _FakeAuthProvider(_shellUser);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(
          home: AppShell(
            location: '/home',
            child: _RouteMarker(label: 'home-route-marker'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedIndicatorFinder = find.byKey(
      const ValueKey('sidebar-selected-indicator-home'),
    );
    final selectedItem = tester.widget<Material>(
      find.byKey(const ValueKey('sidebar-item-home')),
    );
    final selectedIndicator = _sidebarIndicator(tester, 'home');
    final unselectedIndicator = _sidebarIndicator(tester, 'fifoCheck');
    final overviewGroup = find.byKey(const ValueKey('sidebar-group-overview'));
    final salesGroup = find.byKey(const ValueKey('sidebar-group-sales'));
    final warehouseGroup = find.byKey(
      const ValueKey('sidebar-group-warehouse'),
    );
    final financeGroup = find.byKey(const ValueKey('sidebar-group-finance'));
    final technicalGroup = find.byKey(
      const ValueKey('sidebar-group-technical'),
    );
    final configurationGroup = find.byKey(
      const ValueKey('sidebar-group-configuration'),
    );

    expect(find.text('Tổng quan'), findsOneWidget);
    expect(find.text('Bán hàng'), findsOneWidget);
    expect(find.text('Kho'), findsOneWidget);
    expect(find.text('Tài chính'), findsOneWidget);
    expect(find.text('Kỹ thuật'), findsOneWidget);
    expect(find.text('Cấu hình'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sidebar-item-operations')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sidebar-item-feedback')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-item-help')), findsOneWidget);
    expect(find.text('Kết nối nguồn lực. Đồng bộ vận hành.'), findsOneWidget);
    expect(find.text('Dev: Hoàng Học Hỏi'), findsOneWidget);
    expect(find.textContaining('© '), findsOneWidget);
    expect(
      tester.getTopLeft(overviewGroup).dy,
      lessThan(tester.getTopLeft(salesGroup).dy),
    );
    expect(
      tester.getTopLeft(salesGroup).dy,
      lessThan(tester.getTopLeft(warehouseGroup).dy),
    );
    expect(
      tester.getTopLeft(warehouseGroup).dy,
      lessThan(tester.getTopLeft(financeGroup).dy),
    );
    expect(
      tester.getTopLeft(financeGroup).dy,
      lessThan(tester.getTopLeft(technicalGroup).dy),
    );
    expect(
      tester.getTopLeft(technicalGroup).dy,
      lessThan(tester.getTopLeft(configurationGroup).dy),
    );
    expect(selectedItem.color, AppColors.transparent);
    expect(tester.getSize(selectedIndicatorFinder), const Size(4, 28));
    expect(_indicatorColor(selectedIndicator), isNot(AppColors.transparent));
    expect(_indicatorColor(unselectedIndicator), AppColors.transparent);
  });
}

class _RouteMarker extends StatelessWidget {
  final String label;

  const _RouteMarker({required this.label});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(child: Text(label)),
    );
  }
}

Container _sidebarIndicator(WidgetTester tester, String id) {
  return tester.widget<Container>(
    find.byKey(ValueKey('sidebar-selected-indicator-$id')),
  );
}

Color? _indicatorColor(Container indicator) {
  final decoration = indicator.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

const _shellUser = User(
  id: 'shell-user-1',
  email: 'shell@example.com',
  role: 'USER',
  organizationNodeId: 'org-store-cp01',
  featureAccess: {
    'FIFO': true,
    'WARRANTY': true,
    'VIETQR': true,
    'BANK_STATEMENTS': true,
    'FEEDBACK': true,
  },
);

const _quickActionsUser = User(
  id: 'shell-user-quick-actions',
  email: 'quick-actions@example.com',
  role: 'USER',
  organizationNodeId: 'org-store-cp01',
  featureAccess: {
    'FIFO': true,
    'WARRANTY': true,
    'VIETQR': true,
    'BANK_STATEMENTS': true,
    'FEEDBACK': true,
    'QUICK_ACTIONS': true,
    'QUICK_ACTION_FIFO': true,
  },
);

const _quickActionsPayload = QuickActionsPayload(
  stores: [QuickActionStore(storeCode: 'CP01', storeName: 'Showroom CP01')],
  selectedStoreCode: null,
  availableActionCodes: {},
  links: {},
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;
  int logoutCalls = 0;
  bool _loggedOut = false;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => _loggedOut ? null : currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => !_loggedOut;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    _loggedOut = true;
    notifyListeners();
  }
}

class _FakeQuickActionsProvider extends QuickActionsProvider {
  final QuickActionsPayload currentPayload;

  _FakeQuickActionsProvider(this.currentPayload)
    : super(QuickActionsRepository(ApiClient()));

  @override
  QuickActionsPayload get payload => currentPayload;
}

class _LoggedOutAuthProvider extends AuthProvider {
  _LoggedOutAuthProvider() : super(AuthRepository(ApiClient()));

  @override
  User? get user => null;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => false;
}

class _FakeAppNotificationsProvider extends AppNotificationsProvider {
  int loadCalls = 0;
  int markReadCalls = 0;

  _FakeAppNotificationsProvider()
    : super(
        BankStatementRepository(ApiClient()),
        offsetAdjustmentRepository: OffsetAdjustmentRepository(ApiClient()),
      );

  @override
  bool get isEnabled => true;

  @override
  bool get isLoading => false;

  @override
  int get count => 0;

  @override
  int get totalCount => 0;

  @override
  bool get canReviewStatementOrderTransfers => false;

  @override
  List<BankStatementOrderTransferRequest> get statementOrderRequests =>
      const [];

  @override
  List<OffsetAdjustment> get offsetAdjustmentRequests => const [];

  @override
  Future<void> load({bool silent = false}) async {
    loadCalls += 1;
  }

  @override
  Future<void> markVisibleNotificationsRead() async {
    markReadCalls += 1;
  }
}
