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
import '../../features/sales_report/data/sales_report_repository.dart';
import '../../features/sales_report/presentation/providers/sales_report_provider.dart';
import '../../features/sales_report/presentation/screens/sales_report_admin_screen.dart';
import '../../features/sales_report/presentation/screens/not_purchased_customers_screen.dart';
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
import '../../features/admin/presentation/screens/sales_target_admin_screen.dart';
import '../../features/admin/presentation/screens/user_admin_screen.dart';
import '../../features/admin/data/repositories/sales_target_repository.dart';
import '../../features/quick_actions/data/quick_actions_repository.dart';
import '../../features/quick_actions/presentation/quick_action_links_admin_screen.dart';
import '../../features/help/presentation/screens/help_content_admin_screen.dart';
import '../../features/help/presentation/screens/help_screen.dart';
import '../../features/warranty/presentation/screens/warranty_screen.dart';
import '../../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../../features/warranty/presentation/screens/check_warranty_screen.dart';
import '../../features/warranty/presentation/screens/warranty_details_screen.dart';
import '../../features/feedback/presentation/screens/feedback_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/operations/presentation/screens/operations_screen.dart';
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

class AppRouter {
  AppRouter._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String initialLocationForUri(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.startsWith('/')) return fragment;
    if (uri.path == '/help') return '/help';
    return '/home';
  }

  static GoRouter createRouter(
    AuthProvider authProvider, {
    Widget? helpScreen,
  }) {
    return GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: initialLocationForUri(Uri.base),
      overridePlatformDefaultLocation: true,
      refreshListenable: authProvider,
      debugLogDiagnostics: true,
      redirect: (context, state) {
        final location = state.matchedLocation;
        if (location == '/tasks') return '/home';

        if (!authProvider.isInitialized) {
          if (location == '/help') return null;
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
        final isPublicHelp = location == '/help';

        if (!isAuthenticated) {
          if (isLoggingIn ||
              isRegistering ||
              isForgotPassword ||
              isPublicHelp) {
            return null;
          }
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

        if (location == '/admin/help-content' &&
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
          builder: (context, state, child) {
            if (state.uri.path == '/help' && !authProvider.isAuthenticated) {
              return _selectable(child);
            }
            return AppShell(
              location: state.uri.path,
              child: _selectable(child),
            );
          },
          routes: [
            GoRoute(
              path: '/help',
              pageBuilder: (context, state) {
                final publicHelp =
                    helpScreen ??
                    HelpScreen(
                      onBack: () {
                        final navigator = navigatorKey.currentState;
                        if (navigator?.canPop() ?? false) {
                          navigator!.pop();
                          return;
                        }
                        context.go(
                          authProvider.isAuthenticated ? '/home' : '/login',
                        );
                      },
                    );
                final shellHelpChild =
                    helpScreen ?? const HelpScreen(embeddedInShell: true);
                return _noTransitionPage(
                  state,
                  authProvider.isAuthenticated ? shellHelpChild : publicHelp,
                );
              },
            ),
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const HomeScreen()),
            ),
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const ProfileScreen()),
            ),
            GoRoute(
              path: '/operations',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const OperationsScreen()),
            ),
            GoRoute(
              path: '/notifications',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const NotificationsScreen()),
            ),
            GoRoute(
              path: '/admin',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const AdminMenuScreen()),
            ),
            GoRoute(
              path: '/admin/users',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const UserAdminScreen()),
            ),
            GoRoute(
              path: '/admin/roles',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const RoleAdminScreen()),
            ),
            GoRoute(
              path: '/admin/organization',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const OrganizationTreeAdminScreen()),
            ),
            GoRoute(
              path: '/admin/policies',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const PolicyAdminScreen()),
            ),
            GoRoute(
              path: '/admin/features',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FeatureAdminScreen()),
            ),
            GoRoute(
              path: '/admin/personnel',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const PersonnelCatalogAdminScreen()),
            ),
            GoRoute(
              path: '/admin/sales-targets',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                SalesTargetAdminScreen(
                  repository: SalesTargetRepository(ApiClient()),
                ),
              ),
            ),
            GoRoute(
              path: '/admin/quick-action-links',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                QuickActionLinksAdminScreen(
                  repository: QuickActionsRepository(ApiClient()),
                ),
              ),
            ),
            GoRoute(
              path: '/admin/inventory-import',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const InventoryImportScreen()),
            ),
            GoRoute(
              path: '/admin/feedback',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FeedbackAdminScreen()),
            ),
            GoRoute(
              path: '/admin/help-content',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const HelpContentAdminScreen()),
            ),
            GoRoute(
              path: '/admin/sales-reports',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                ChangeNotifierProvider(
                  create: (_) =>
                      SalesReportProvider(SalesReportRepository(ApiClient())),
                  child: const SalesReportAdminScreen(),
                ),
              ),
            ),
            GoRoute(
              path: '/fifo-menu',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FifoMenuScreen()),
            ),
            GoRoute(
              path: '/fifo-check',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FifoCheckScreen()),
            ),
            GoRoute(
              path: '/fifo-history',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FifoHistoryScreen()),
            ),
            GoRoute(
              path: '/fifo/inventory-import',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const InventoryImportScreen()),
            ),
            GoRoute(
              path: '/sort',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const SortScreen()),
            ),
            GoRoute(
              path: '/warranty-main',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const WarrantyMainScreen()),
            ),
            GoRoute(
              path: '/warranty',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const WarrantyScreen()),
            ),
            GoRoute(
              path: '/check-warranty',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const CheckWarrantyScreen()),
            ),
            GoRoute(
              path: '/check-warranty/details/:receiptNumber',
              pageBuilder: (context, state) {
                final receiptNumber =
                    state.pathParameters['receiptNumber'] ?? '';
                return _noTransitionPage(
                  state,
                  WarrantyDetailsScreen(receiptNumber: receiptNumber),
                );
              },
            ),
            GoRoute(
              path: '/vietqr',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const VietQrScreen()),
            ),
            GoRoute(
              path: '/payment-monitor',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, buildPaymentMonitorRoute()),
            ),
            GoRoute(
              path: '/bank-statement',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                ChangeNotifierProvider(
                  create: (_) => BankStatementProvider(
                    BankStatementRepository(ApiClient()),
                  ),
                  child: BankStatementScreen(
                    initialOrderStatus:
                        state.uri.queryParameters['orderStatus'],
                    autoSearch:
                        state.uri.queryParameters['autoSearch'] == 'true',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/offset-adjustments',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                ChangeNotifierProvider(
                  create: (_) => OffsetAdjustmentProvider(
                    OffsetAdjustmentRepository(ApiClient()),
                  ),
                  child: const OffsetAdjustmentScreen(),
                ),
              ),
            ),
            GoRoute(
              path: '/feedback',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const FeedbackScreen()),
            ),
            GoRoute(
              path: '/reports',
              redirect: (context, state) => '/sales-reports',
            ),
            GoRoute(
              path: '/sales-reports',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, buildSalesReportHubRoute()),
            ),
            GoRoute(
              path: '/sales-reports/purchased',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                ChangeNotifierProvider(
                  create: (_) =>
                      SalesReportProvider(SalesReportRepository(ApiClient())),
                  child: const SalesReportFormScreen.purchased(),
                ),
              ),
            ),
            GoRoute(
              path: '/sales-reports/not-purchased',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                ChangeNotifierProvider(
                  create: (_) =>
                      SalesReportProvider(SalesReportRepository(ApiClient())),
                  child: const SalesReportFormScreen.notPurchased(),
                ),
              ),
            ),
            GoRoute(
              path: '/sales-reports/follow-up-cases',
              pageBuilder: (context, state) => _noTransitionPage(
                state,
                _selectable(const NotPurchasedCustomersScreen()),
              ),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  _noTransitionPage(state, const SettingsScreen()),
            ),
          ],
        ),
      ],
    );
  }

  static String? _featureForRoute(String location) {
    if (location.startsWith('/check-warranty')) return 'WARRANTY';

    return switch (location) {
      '/admin' => 'ADMIN',
      '/admin/users' => 'ADMIN_USERS',
      '/admin/roles' => 'ADMIN_ROLES',
      '/admin/organization' => 'ADMIN_ORG_TREE',
      '/admin/policies' => 'ADMIN_POLICIES',
      '/admin/features' => 'ADMIN_FEATURES',
      '/admin/personnel' => 'ADMIN_PERSONNEL',
      '/admin/sales-targets' => 'ADMIN_SALES_TARGETS',
      '/admin/quick-action-links' => 'ADMIN_QUICK_ACTION_CODES',
      '/admin/inventory-import' => 'FIFO_IMPORT',
      '/admin/feedback' => 'ADMIN_FEEDBACK',
      '/admin/sales-reports' => 'ADMIN_SALES_REPORTS',
      '/fifo-check' => 'FIFO',
      '/fifo-history' => 'FIFO',
      '/fifo/inventory-import' => 'FIFO_IMPORT',
      '/sort' => 'FIFO',
      '/warranty-main' => 'WARRANTY',
      '/warranty' => 'WARRANTY',
      '/vietqr' => 'VIETQR',
      '/bank-statement' => 'BANK_STATEMENTS',
      '/offset-adjustments' => 'OFFSET_ADJUSTMENTS',
      '/payment-monitor' => 'PAYMENT_MONITOR',
      '/feedback' => 'FEEDBACK',
      '/reports' => 'SALES_REPORT',
      '/sales-reports' => 'SALES_REPORT',
      '/sales-reports/purchased' => 'SALES_REPORT',
      '/sales-reports/not-purchased' => 'SALES_REPORT',
      '/sales-reports/follow-up-cases' => 'SALES_REPORT_FOLLOW_UP',
      _ => null,
    };
  }

  static bool _canUseRouteFeature(User? user, String featureCode) {
    if (featureCode == 'SALES_REPORT_FOLLOW_UP') {
      return user?.canUseFeature('SALES_REPORT') == true ||
          user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
    }
    if (featureCode == 'ADMIN_QUICK_ACTION_CODES') {
      final managerRole = {
        'STORE_MANAGER',
        'AREA_MANAGER',
        'REGION_MANAGER',
        'REGIONAL_MANAGER',
      }.contains(user?.jobRoleCode?.trim().toUpperCase());
      return user?.canUseFeature(featureCode) == true &&
          (user?.isSuperAdmin == true || managerRole);
    }
    if (featureCode == 'ADMIN') {
      return user?.canUseFeature('ADMIN') == true ||
          user?.canUseFeature('ADMIN_USERS') == true ||
          user?.canUseFeature('ADMIN_ROLES') == true ||
          user?.canUseFeature('ADMIN_ORG_TREE') == true ||
          user?.canUseFeature('ADMIN_POLICIES') == true ||
          user?.canUseFeature('ADMIN_FEATURES') == true ||
          user?.canUseFeature('ADMIN_PERSONNEL') == true ||
          user?.canUseFeature('ADMIN_SALES_TARGETS') == true ||
          user?.canUseFeature('ADMIN_QUICK_ACTION_CODES') == true ||
          user?.canUseFeature('ADMIN_SALES_REPORTS') == true ||
          user?.canUseFeature('ADMIN_FEEDBACK') == true;
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
    final routePath = Uri.tryParse(location)?.path ?? location.split('?').first;
    final routeFeature = _featureForRoute(routePath);
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

  static Page<void> _noTransitionPage(GoRouterState state, Widget child) =>
      NoTransitionPage<void>(key: state.pageKey, child: child);

  static Widget _selectable(Widget child) => SelectionArea(child: child);
}
