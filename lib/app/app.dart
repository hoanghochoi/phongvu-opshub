import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import '../core/config/app_brand.dart';
import '../core/logging/app_logger.dart';
import '../core/network/api_client.dart';
import '../features/auth/data/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/app_update/presentation/app_update_gate.dart';
import '../features/bank_statement/data/bank_statement_repository.dart';
import '../features/home/data/repositories/home_summary_repository.dart';
import '../features/home/presentation/providers/home_summary_provider.dart';
import '../features/notifications/presentation/providers/app_notifications_provider.dart';
import '../features/warranty/data/repositories/warranty_repository.dart';
import '../features/warranty/presentation/providers/warranty_provider.dart';
import '../features/payment_monitor/data/payment_speaker.dart';
import '../features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import '../features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import '../features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../features/fifo/data/repositories/fifo_repository.dart';
import '../features/fifo/presentation/providers/fifo_provider.dart';
import '../features/offset_adjustment/data/offset_adjustment_repository.dart';
import '../features/quick_actions/data/quick_actions_repository.dart';
import '../features/quick_actions/presentation/quick_actions_provider.dart';
import '../features/sort/data/repositories/sort_repository.dart';
import '../features/sort/presentation/providers/sort_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'navigation/app_router.dart';
import 'widgets/app_layout.dart';

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
        ChangeNotifierProxyProvider<AuthProvider, WarrantyProvider>(
          lazy: false,
          create: (_) => WarrantyProvider(WarrantyRepository(ApiClient())),
          update: (_, auth, warranty) {
            final provider =
                warranty ?? WarrantyProvider(WarrantyRepository(ApiClient()));
            Future.microtask(
              () => provider.syncAuth(
                auth.user,
                isInitialized: auth.isInitialized,
              ),
            );
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => SortProvider(SortRepository(ApiClient())),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AppNotificationsProvider>(
          lazy: false,
          create: (_) => AppNotificationsProvider(
            BankStatementRepository(ApiClient()),
            offsetAdjustmentRepository: OffsetAdjustmentRepository(ApiClient()),
          ),
          update: (_, auth, notifications) {
            final provider =
                notifications ??
                AppNotificationsProvider(
                  BankStatementRepository(ApiClient()),
                  offsetAdjustmentRepository: OffsetAdjustmentRepository(
                    ApiClient(),
                  ),
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
        ChangeNotifierProxyProvider<
          AuthProvider,
          PaymentDeliveryMetricsProvider
        >(
          lazy: false,
          create: (_) => PaymentDeliveryMetricsProvider(
            PaymentMonitorRepository(ApiClient()),
          ),
          update: (_, auth, metrics) {
            final provider =
                metrics ??
                PaymentDeliveryMetricsProvider(
                  PaymentMonitorRepository(ApiClient()),
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
        ChangeNotifierProxyProvider<AuthProvider, HomeSummaryProvider>(
          lazy: false,
          create: (_) =>
              HomeSummaryProvider(HomeSummaryRepository(ApiClient())),
          update: (_, auth, homeSummary) {
            final provider =
                homeSummary ??
                HomeSummaryProvider(HomeSummaryRepository(ApiClient()));
            Future.microtask(
              () => provider.syncAuth(
                auth.user,
                isInitialized: auth.isInitialized,
              ),
            );
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, QuickActionsProvider>(
          lazy: false,
          create: (_) =>
              QuickActionsProvider(QuickActionsRepository(ApiClient())),
          update: (_, auth, quickActions) {
            final provider =
                quickActions ??
                QuickActionsProvider(QuickActionsRepository(ApiClient()));
            Future.microtask(() => provider.syncUser(auth.user));
            return provider;
          },
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
      title: AppBrand.title,
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
      supportedLocales: const [Locale('vi', ''), Locale('en', '')],
      builder: (context, child) {
        return AppGlobalSelectionScope(
          child: AppMobileTypographyDensity(
            child: _SessionExpiredDialogGate(
              router: _router,
              child: AppUpdateGate(child: child ?? const SizedBox()),
            ),
          ),
        );
      },
    );
  }
}

class _SessionExpiredDialogGate extends StatefulWidget {
  final GoRouter router;
  final Widget child;

  const _SessionExpiredDialogGate({required this.router, required this.child});

  @override
  State<_SessionExpiredDialogGate> createState() =>
      _SessionExpiredDialogGateState();
}

class _SessionExpiredDialogGateState extends State<_SessionExpiredDialogGate> {
  bool _dialogVisible = false;
  int _presentationAttempts = 0;

  @override
  Widget build(BuildContext context) {
    final message = context.select<AuthProvider, String?>(
      (auth) => auth.sessionExpiredDialogMessage,
    );
    _showDialogIfNeeded(message);
    return widget.child;
  }

  void _showDialogIfNeeded(String? message) {
    if (message == null || _dialogVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _dialogVisible) return;
      final authProvider = context.read<AuthProvider>();
      final currentMessage = authProvider.sessionExpiredDialogMessage;
      if (currentMessage == null) return;
      final navigatorContext =
          AppRouter.navigatorKey.currentState?.overlay?.context;
      if (navigatorContext == null) {
        _presentationAttempts += 1;
        await AppLogger.instance.warn(
          'Auth',
          'Session expired dialog presentation deferred',
          context: {
            'reason': 'root_navigator_unavailable',
            'attempt': _presentationAttempts,
          },
        );
        if (mounted && _presentationAttempts < 3) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showDialogIfNeeded(currentMessage),
          );
        } else if (mounted) {
          await AppLogger.instance.error(
            'Auth',
            'Session expired dialog navigator unavailable',
            context: {'attempts': _presentationAttempts},
            upload: true,
          );
          authProvider.clearSessionExpiredDialogMessage();
          widget.router.go('/login');
          _presentationAttempts = 0;
        }
        return;
      }

      _presentationAttempts = 0;
      _dialogVisible = true;
      try {
        await AppLogger.instance.info(
          'Auth',
          'Session expired dialog presentation started',
        );
        if (!navigatorContext.mounted) {
          await AppLogger.instance.warn(
            'Auth',
            'Session expired dialog cancelled before presentation',
            context: {'reason': 'root_navigator_unmounted'},
          );
          return;
        }
        await showDialog<void>(
          context: navigatorContext,
          barrierDismissible: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Phiên đăng nhập đã hết hạn'),
            content: Text(currentMessage),
            actions: [
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(dialogContext, rootNavigator: true).pop(),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Đăng nhập lại'),
              ),
            ],
          ),
        );
        await AppLogger.instance.info(
          'Auth',
          'Session expired dialog dismissed',
        );
      } catch (error, stackTrace) {
        await AppLogger.instance.error(
          'Auth',
          'Session expired dialog presentation failed',
          error: error,
          stackTrace: stackTrace,
          upload: true,
        );
      } finally {
        if (mounted) {
          authProvider.clearSessionExpiredDialogMessage();
          widget.router.go('/login');
          _dialogVisible = false;
        }
      }
    });
  }
}
