import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/domain/entities/user.dart';
import '../../features/bank_statement/data/bank_statement_repository.dart';
import '../../features/bank_statement/presentation/providers/bank_statement_provider.dart';
import '../../features/bank_statement/presentation/screens/bank_statement_screen.dart';
import '../../features/offset_adjustment/data/offset_adjustment_repository.dart';
import '../../features/offset_adjustment/presentation/providers/offset_adjustment_provider.dart';
import '../../features/offset_adjustment/presentation/screens/offset_adjustment_screen.dart';
import '../../features/reports/presentation/screens/report_workspace_screen.dart';
import '../../features/sales_report/data/sales_report_repository.dart';
import '../../features/sales_report/presentation/providers/sales_report_provider.dart';
import '../../features/sales_report/presentation/screens/sales_report_admin_screen.dart';
import '../../features/sales_report/presentation/screens/sales_report_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/assignment_pending_screen.dart';
import '../../features/auth/presentation/screens/email_check_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/admin/presentation/screens/admin_menu_screen.dart';
import '../../features/admin/presentation/screens/feature_admin_screen.dart';
import '../../features/admin/presentation/screens/feedback_admin_screen.dart';
import '../../features/admin/presentation/screens/inventory_import_screen.dart';
import '../../features/admin/presentation/screens/organization_tree_admin_screen.dart';
import '../../features/admin/presentation/screens/personnel_catalog_admin_screen.dart';
import '../../features/admin/presentation/screens/policy_admin_screen.dart';
import '../../features/admin/presentation/screens/role_admin_screen.dart';
import '../../features/admin/presentation/screens/user_admin_screen.dart';
import '../../features/warranty/presentation/screens/warranty_screen.dart';
import '../../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../../features/warranty/presentation/screens/check_warranty_screen.dart';
import '../../features/feedback/presentation/screens/feedback_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import '../../features/payment_monitor/presentation/screens/payment_monitor_unsupported_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/vietqr/presentation/screens/vietqr_screen.dart';
import '../../features/fifo/presentation/screens/fifo_check_screen.dart';
import '../../features/fifo/presentation/screens/fifo_menu_screen.dart';
import '../../features/fifo/presentation/screens/fifo_history_screen.dart';
import '../../features/sort/presentation/screens/sort_screen.dart';
import '../../core/platform/app_platform_capabilities.dart';
import 'app_shell.dart';
import 'tasks_screen.dart';

class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: '/home',
      refreshListenable: authProvider,
      debugLogDiagnostics: true,
      redirect: (context, state) {
        final location = state.matchedLocation;
        if (!authProvider.isInitialized) {
          return location == '/loading' ? null : '/loading';
        }

        final isAuthenticated = authProvider.isAuthenticated;
        final needsAssignment =
            authProvider.user?.needsOrganizationAssignment ?? false;

        final isLoading = location == '/loading';
        final isLoggingIn = location == '/login';
        final isRegistering = location == '/register';
        final isForgotPassword = location == '/forgot-password';
        final isAssignmentPending = location == '/assignment-pending';

        if (!isAuthenticated) {
          if (isLoggingIn || isRegistering || isForgotPassword) return null;
          return '/login';
        }

        if (needsAssignment) {
          if (isAssignmentPending) return null;
          return '/assignment-pending';
        }

        if (location == '/admin/feedback' &&
            authProvider.user?.role != 'SUPER_ADMIN') {
          return '/home';
        }

        final routeFeature = _featureForRoute(location);
        if (routeFeature != null &&
            !_canUseRouteFeature(authProvider.user, routeFeature)) {
          return '/home';
        }

        if (isLoading ||
            isLoggingIn ||
            isRegistering ||
            isForgotPassword ||
            isAssignmentPending) {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          builder: (context, state) => _selectable(
            const Scaffold(body: Center(child: CircularProgressIndicator())),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => _selectable(const EmailCheckScreen()),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) {
            final email = state.extra as String?;
            return _selectable(RegisterScreen(initialEmail: email));
          },
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) =>
              _selectable(const ForgotPasswordScreen()),
        ),
        GoRoute(
          path: '/assignment-pending',
          builder: (context, state) =>
              _selectable(const AssignmentPendingScreen()),
        ),
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(location: state.uri.path, child: _selectable(child)),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const TasksScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/admin',
              builder: (context, state) => const AdminMenuScreen(),
            ),
            GoRoute(
              path: '/admin/users',
              builder: (context, state) => const UserAdminScreen(),
            ),
            GoRoute(
              path: '/admin/roles',
              builder: (context, state) => const RoleAdminScreen(),
            ),
            GoRoute(
              path: '/admin/organization',
              builder: (context, state) => const OrganizationTreeAdminScreen(),
            ),
            GoRoute(
              path: '/admin/policies',
              builder: (context, state) => const PolicyAdminScreen(),
            ),
            GoRoute(
              path: '/admin/features',
              builder: (context, state) => const FeatureAdminScreen(),
            ),
            GoRoute(
              path: '/admin/personnel',
              builder: (context, state) => const PersonnelCatalogAdminScreen(),
            ),
            GoRoute(
              path: '/admin/inventory-import',
              builder: (context, state) => const InventoryImportScreen(),
            ),
            GoRoute(
              path: '/admin/feedback',
              builder: (context, state) => const FeedbackAdminScreen(),
            ),
            GoRoute(
              path: '/admin/sales-reports',
              builder: (context, state) => ChangeNotifierProvider(
                create: (_) =>
                    SalesReportProvider(SalesReportRepository(ApiClient())),
                child: const SalesReportAdminScreen(),
              ),
            ),
            GoRoute(
              path: '/fifo-menu',
              builder: (context, state) => const FifoMenuScreen(),
            ),
            GoRoute(
              path: '/fifo-check',
              builder: (context, state) => const FifoCheckScreen(),
            ),
            GoRoute(
              path: '/fifo-history',
              builder: (context, state) => const FifoHistoryScreen(),
            ),
            GoRoute(
              path: '/fifo/inventory-import',
              builder: (context, state) => const InventoryImportScreen(),
            ),
            GoRoute(
              path: '/sort',
              builder: (context, state) => const SortScreen(),
            ),
            GoRoute(
              path: '/warranty-main',
              builder: (context, state) =>
                  WarrantyMainScreen(onBackToHome: () => context.go('/home')),
            ),
            GoRoute(
              path: '/warranty',
              builder: (context, state) => const WarrantyScreen(),
            ),
            GoRoute(
              path: '/check-warranty',
              builder: (context, state) => const CheckWarrantyScreen(),
            ),
            GoRoute(
              path: '/vietqr',
              builder: (context, state) => const VietQrScreen(),
            ),
            GoRoute(
              path: '/payment-monitor',
              builder: (context, state) => buildPaymentMonitorRoute(),
            ),
            GoRoute(
              path: '/bank-statement',
              builder: (context, state) => ChangeNotifierProvider(
                create: (_) =>
                    BankStatementProvider(BankStatementRepository(ApiClient())),
                child: const BankStatementScreen(),
              ),
            ),
            GoRoute(
              path: '/offset-adjustments',
              builder: (context, state) => ChangeNotifierProvider(
                create: (_) => OffsetAdjustmentProvider(
                  OffsetAdjustmentRepository(ApiClient()),
                ),
                child: const OffsetAdjustmentScreen(),
              ),
            ),
            GoRoute(
              path: '/feedback',
              builder: (context, state) => const FeedbackScreen(),
            ),
            GoRoute(
              path: '/reports',
              builder: (context, state) => const ReportWorkspaceScreen(),
            ),
            GoRoute(
              path: '/sales-reports',
              builder: (context, state) => buildSalesReportHubRoute(),
            ),
            GoRoute(
              path: '/sales-reports/purchased',
              builder: (context, state) => ChangeNotifierProvider(
                create: (_) =>
                    SalesReportProvider(SalesReportRepository(ApiClient())),
                child: const SalesReportFormScreen.purchased(),
              ),
            ),
            GoRoute(
              path: '/sales-reports/not-purchased',
              builder: (context, state) => ChangeNotifierProvider(
                create: (_) =>
                    SalesReportProvider(SalesReportRepository(ApiClient())),
                child: const SalesReportFormScreen.notPurchased(),
              ),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }

  static String? _featureForRoute(String location) {
    return switch (location) {
      '/admin' => 'ADMIN',
      '/admin/users' => 'ADMIN_USERS',
      '/admin/roles' => 'ADMIN_ROLES',
      '/admin/organization' => 'ADMIN_ORG_TREE',
      '/admin/policies' => 'ADMIN_POLICIES',
      '/admin/features' => 'ADMIN_FEATURES',
      '/admin/personnel' => 'ADMIN_PERSONNEL',
      '/admin/inventory-import' => 'FIFO_IMPORT',
      '/admin/feedback' => 'ADMIN_FEEDBACK',
      '/admin/sales-reports' => 'ADMIN_SALES_REPORTS',
      '/tasks' => null,
      '/fifo-check' => 'FIFO',
      '/fifo-history' => 'FIFO',
      '/fifo/inventory-import' => 'FIFO_IMPORT',
      '/sort' => 'FIFO',
      '/warranty-main' => 'WARRANTY',
      '/warranty' => 'WARRANTY',
      '/check-warranty' => 'WARRANTY',
      '/vietqr' => 'VIETQR',
      '/bank-statement' => 'BANK_STATEMENTS',
      '/offset-adjustments' => 'OFFSET_ADJUSTMENTS',
      '/payment-monitor' => 'PAYMENT_MONITOR',
      '/feedback' => 'FEEDBACK',
      '/reports' => 'SALES_REPORT_HUB',
      '/sales-reports' => 'SALES_REPORT_HUB',
      '/sales-reports/purchased' => 'SALES_REPORT',
      '/sales-reports/not-purchased' => 'SALES_REPORT',
      _ => null,
    };
  }

  static bool _canUseRouteFeature(User? user, String featureCode) {
    if (featureCode == 'ADMIN') {
      return user?.canUseFeature('ADMIN') == true ||
          user?.canUseFeature('ADMIN_USERS') == true ||
          user?.canUseFeature('ADMIN_ROLES') == true ||
          user?.canUseFeature('ADMIN_ORG_TREE') == true ||
          user?.canUseFeature('ADMIN_POLICIES') == true ||
          user?.canUseFeature('ADMIN_FEATURES') == true ||
          user?.canUseFeature('ADMIN_PERSONNEL') == true ||
          user?.canUseFeature('ADMIN_FEEDBACK') == true;
    }
    if (featureCode == 'SALES_REPORT_HUB') {
      return user?.canUseFeature('SALES_REPORT') == true ||
          user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
    }
    if (featureCode == 'BANK_STATEMENTS') {
      return user?.canUseBankStatements == true;
    }
    if (featureCode == 'OFFSET_ADJUSTMENTS') {
      return user?.canUseOffsetAdjustments == true;
    }
    return user?.canUseFeature(featureCode) == true;
  }

  @visibleForTesting
  static bool canUseRouteForTesting(User? user, String location) {
    final routeFeature = _featureForRoute(location);
    if (routeFeature == null) return true;
    return _canUseRouteFeature(user, routeFeature);
  }

  @visibleForTesting
  static Widget buildSalesReportHubRoute({SalesReportRepository? repository}) {
    return ChangeNotifierProvider(
      create: (_) =>
          SalesReportProvider(repository ?? SalesReportRepository(ApiClient())),
      child: _selectable(const SalesReportScreen()),
    );
  }

  @visibleForTesting
  static Widget buildPaymentMonitorRoute({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    return _selectable(
      AppPlatformCapabilities.isPaymentMonitorSupported(
            isWeb: isWeb,
            platform: platform,
          )
          ? const PaymentMonitorScreen()
          : const PaymentMonitorUnsupportedScreen(),
    );
  }

  static Widget _selectable(Widget child) => SelectionArea(child: child);
}
