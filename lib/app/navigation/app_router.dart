import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/platform/app_platform_capabilities.dart';
import '../../features/bank_statement/data/bank_statement_repository.dart';
import '../../features/bank_statement/presentation/providers/bank_statement_provider.dart';
import '../../features/bank_statement/presentation/screens/bank_statement_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/email_check_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/store_selection_screen.dart';
import '../../features/admin/presentation/screens/admin_menu_screen.dart';
import '../../features/admin/presentation/screens/feature_admin_screen.dart';
import '../../features/admin/presentation/screens/inventory_import_screen.dart';
import '../../features/admin/presentation/screens/personnel_catalog_admin_screen.dart';
import '../../features/admin/presentation/screens/region_admin_screen.dart';
import '../../features/admin/presentation/screens/role_admin_screen.dart';
import '../../features/admin/presentation/screens/store_admin_screen.dart';
import '../../features/admin/presentation/screens/user_admin_screen.dart';
import '../../features/warranty/presentation/screens/warranty_screen.dart';
import '../../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../../features/warranty/presentation/screens/check_warranty_screen.dart';
import '../../features/feedback/presentation/screens/feedback_screen.dart';
import '../../features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import '../../features/payment_monitor/presentation/screens/payment_monitor_unsupported_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/vietqr/presentation/screens/vietqr_screen.dart';
import '../../features/fifo/presentation/screens/fifo_check_screen.dart';
import '../../features/fifo/presentation/screens/fifo_menu_screen.dart';
import '../../features/fifo/presentation/screens/fifo_history_screen.dart';
import '../../features/sort/presentation/screens/sort_screen.dart';
import 'main_navigation_screen.dart';

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
        final needsStore = authProvider.user?.needsStoreSelection ?? false;

        final isLoading = location == '/loading';
        final isLoggingIn = location == '/login';
        final isRegistering = location == '/register';
        final isForgotPassword = location == '/forgot-password';

        if (!isAuthenticated) {
          if (isLoggingIn || isRegistering || isForgotPassword) return null;
          return '/login';
        }

        if (needsStore) {
          if (location == '/select-store') return null;
          return '/select-store';
        }

        final routeFeature = _featureForRoute(location);
        if (routeFeature != null &&
            authProvider.user?.canUseFeature(routeFeature) != true) {
          return '/home';
        }

        if (isLoading ||
            isLoggingIn ||
            isRegistering ||
            isForgotPassword ||
            location == '/select-store') {
          return '/home';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/loading',
          builder: (context, state) =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const EmailCheckScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) {
            final email = state.extra as String?;
            return RegisterScreen(initialEmail: email);
          },
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/select-store',
          builder: (context, state) => const StoreSelectionScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const MainNavigationScreen(),
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
          path: '/admin/regions',
          builder: (context, state) => const RegionAdminScreen(),
        ),
        GoRoute(
          path: '/admin/personnel',
          builder: (context, state) => const PersonnelCatalogAdminScreen(),
        ),
        GoRoute(
          path: '/admin/features',
          builder: (context, state) => const FeatureAdminScreen(),
        ),
        GoRoute(
          path: '/admin/stores',
          builder: (context, state) => const StoreAdminScreen(),
        ),
        GoRoute(
          path: '/admin/inventory-import',
          builder: (context, state) => const InventoryImportScreen(),
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
        GoRoute(path: '/sort', builder: (context, state) => const SortScreen()),
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
          builder: (context, state) =>
              AppPlatformCapabilities.isPaymentMonitorSupported()
              ? const PaymentMonitorScreen()
              : const PaymentMonitorUnsupportedScreen(),
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
          path: '/feedback',
          builder: (context, state) => const FeedbackScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
  }

  static String? _featureForRoute(String location) {
    return switch (location) {
      '/admin' => 'ADMIN',
      '/admin/users' => 'ADMIN_USERS',
      '/admin/roles' => 'ADMIN_ROLES',
      '/admin/stores' => 'ADMIN_STORES',
      '/admin/regions' => 'ADMIN_REGIONS',
      '/admin/personnel' => 'ADMIN_PERSONNEL',
      '/admin/features' => 'ADMIN_FEATURES',
      '/admin/inventory-import' => 'FIFO_IMPORT',
      '/fifo-menu' => 'FIFO',
      '/fifo-check' => 'FIFO',
      '/fifo-history' => 'FIFO',
      '/sort' => 'FIFO',
      '/warranty-main' => 'WARRANTY',
      '/warranty' => 'WARRANTY',
      '/check-warranty' => 'WARRANTY',
      '/vietqr' => 'VIETQR',
      '/bank-statement' => 'BANK_STATEMENTS',
      '/payment-monitor' => 'PAYMENT_MONITOR',
      '/feedback' => 'FEEDBACK',
      _ => null,
    };
  }
}
