import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/app_update/presentation/app_update_gate.dart';
import '../features/warranty/data/repositories/warranty_repository.dart';
import '../features/warranty/presentation/providers/warranty_provider.dart';
import '../features/payment_monitor/data/payment_speaker.dart';
import '../features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import '../features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../features/fifo/data/repositories/fifo_repository.dart';
import '../features/fifo/presentation/providers/fifo_provider.dart';
import '../features/sort/data/repositories/sort_repository.dart';
import '../features/sort/presentation/providers/sort_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'navigation/app_router.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
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
      child: const AppRouterGateway(),
    );
  }
}

class AppRouterGateway extends StatefulWidget {
  const AppRouterGateway({super.key});

  @override
  State<AppRouterGateway> createState() => _AppRouterGatewayState();
}

class _AppRouterGatewayState extends State<AppRouterGateway> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final authProvider = context.read<AuthProvider>();
    _router = AppRouter.createRouter(authProvider);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      title: 'PhongVu OpsHub',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.mode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', ''),
        Locale('en', ''),
      ],
      builder: (context, child) {
        return AppUpdateGate(child: child ?? const SizedBox());
      },
    );
  }
}
