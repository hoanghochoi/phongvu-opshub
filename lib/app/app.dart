import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/email_check_screen.dart';
import '../features/auth/presentation/screens/profile_screen.dart';
import '../features/auth/presentation/screens/register_screen.dart';
import '../features/auth/presentation/screens/store_selection_screen.dart';
import '../features/app_update/presentation/app_update_gate.dart';
import '../features/admin/presentation/screens/admin_menu_screen.dart';
import '../features/admin/presentation/screens/inventory_import_screen.dart';
import '../features/admin/presentation/screens/role_admin_screen.dart';
import '../features/admin/presentation/screens/store_admin_screen.dart';
import '../features/admin/presentation/screens/user_admin_screen.dart';
import '../features/warranty/data/repositories/warranty_repository.dart';
import '../features/warranty/presentation/providers/warranty_provider.dart';
import '../features/warranty/presentation/screens/warranty_screen.dart';
import '../features/warranty/presentation/screens/warranty_main_screen.dart';
import '../features/warranty/presentation/screens/check_warranty_screen.dart';
import '../features/feedback/presentation/screens/feedback_screen.dart';
import '../features/payment_monitor/data/payment_speaker.dart';
import '../features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import '../features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import '../features/vietqr/presentation/screens/vietqr_screen.dart';
import '../features/fifo/data/repositories/fifo_repository.dart';
import '../features/fifo/presentation/providers/fifo_provider.dart';
import '../features/fifo/presentation/screens/fifo_check_screen.dart';
import '../features/fifo/presentation/screens/fifo_menu_screen.dart';
import '../features/fifo/presentation/screens/fifo_history_screen.dart';
import '../features/sort/data/repositories/sort_repository.dart';
import '../features/sort/presentation/providers/sort_provider.dart';
import '../features/sort/presentation/screens/sort_screen.dart';
import 'theme/app_theme.dart';
import 'navigation/main_navigation_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(AuthRepository(ApiClient())),
        ),
        ChangeNotifierProvider(
          create: (_) => FifoProvider(FifoRepository(ApiClient())),
        ),
        ChangeNotifierProvider(
          create: (_) => WarrantyProvider(WarrantyRepository(ApiClient())),
        ),
        ChangeNotifierProvider(
          create: (_) => SortProvider(SortRepository(ApiClient())),
        ),
        ChangeNotifierProxyProvider<AuthProvider, PaymentMonitorProvider>(
          lazy: false,
          create: (_) => PaymentMonitorProvider(
            PaymentMonitorRepository(ApiClient()),
            PaymentSpeaker(),
          ),
          update: (_, auth, monitor) {
            final provider =
                monitor ??
                PaymentMonitorProvider(
                  PaymentMonitorRepository(ApiClient()),
                  PaymentSpeaker(),
                );
            Future.microtask(
              () => provider.syncAuth(
                auth.user,
                isInitialized: auth.isInitialized,
              ),
            );
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: 'PhongVu OpsHub',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: AppUpdateGate(
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              if (!authProvider.isInitialized) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (!authProvider.isAuthenticated) {
                return const EmailCheckScreen();
              }
              if (authProvider.user?.needsStoreSelection == true) {
                return const StoreSelectionScreen();
              }
              return const MainNavigationScreen();
            },
          ),
        ),
        routes: {
          '/login': (context) => const EmailCheckScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainNavigationScreen(),
          '/select-store': (context) => const StoreSelectionScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/admin': (context) => const AdminMenuScreen(),
          '/admin/users': (context) => const UserAdminScreen(),
          '/admin/inventory-import': (context) => const InventoryImportScreen(),
          '/admin/roles': (context) => const RoleAdminScreen(),
          '/admin/stores': (context) => const StoreAdminScreen(),
          '/fifo-menu': (context) => const FifoMenuScreen(),
          '/fifo-check': (context) => const FifoCheckScreen(),
          '/chat': (context) => const FifoCheckScreen(),
          '/warranty-main': (context) => const WarrantyMainScreen(),
          '/warranty': (context) => const WarrantyScreen(),
          '/check-warranty': (context) => const CheckWarrantyScreen(),
          '/feedback': (context) => const FeedbackScreen(),
          '/payment-monitor': (context) => const PaymentMonitorScreen(),
          '/vietqr': (context) => const VietQrScreen(),
          '/sort': (context) => const SortScreen(),
          '/fifo-history': (context) => const FifoHistoryScreen(),
        },
      ),
    );
  }
}
