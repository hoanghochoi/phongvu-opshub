import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../core/config/app_brand.dart';
import '../../core/logging/app_logger.dart';
import '../../core/runtime/app_runtime_coordinator.dart';
import '../../features/auth/domain/entities/user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/notifications/presentation/providers/app_notifications_provider.dart';
import '../../features/notifications/presentation/widgets/app_notifications_bell.dart';
import '../../features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import '../../features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';
import '../../features/quick_actions/presentation/quick_actions_launcher.dart';
import '../../features/support_chat/presentation/support_chat_surface.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_logout_confirmation_dialog.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_notification_action.dart';
import '../widgets/app_state_widgets.dart';
import 'app_nav_model.dart';

const _supportQrAssetPath = 'data/group_invitation.jpg';
const _supportGroupInviteUrl =
    'https://link.seatalk.io/group/open?invite_id=IkaYSKrlQkImmkCfNj4aBdpd5cpcCWFPaaegCUhYXjgcfi1Tzn9E9Gbuac_qt8Jk5mruc0AJGqQLaQeSWG1e';
const _appDeveloperName = 'Hoàng Học Hỏi';

class AppShell extends StatefulWidget {
  final String location;
  final Widget child;

  const AppShell({super.key, required this.location, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastBackPress;
  String _lastNavLogKey = '';
  String _version = '';
  final List<String> _routeHistory = [];
  bool _suppressNextHistoryPush = false;
  AppRuntimeCoordinator? _runtimeCoordinator;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _scheduleRuntimeRouteSync();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = packageInfo.version);
  }

  Future<bool> _handleBackNavigation() async {
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      return true;
    }

    _lastBackPress = now;
    if (mounted) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Nhấn back lần nữa để thoát'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location == widget.location) return;
    _scheduleRuntimeRouteSync();
    if (_suppressNextHistoryPush) {
      _suppressNextHistoryPush = false;
      return;
    }
    if (_routeHistory.isEmpty || _routeHistory.last != oldWidget.location) {
      _routeHistory.add(oldWidget.location);
      if (_routeHistory.length > 12) _routeHistory.removeAt(0);
    }
  }

  void _scheduleRuntimeRouteSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final runtime = context.read<AppRuntimeCoordinator>();
        _runtimeCoordinator = runtime;
        runtime.setActiveRoute(widget.location);
      } on ProviderNotFoundException {
        // Lightweight widget tests may render AppShell without the app root.
      }
    });
  }

  @override
  void dispose() {
    final runtime = _runtimeCoordinator;
    final route = widget.location;
    Future.microtask(() => runtime?.clearActiveRoute(route));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final supportChat = maybeSupportChatProvider(context, listen: true);
    final sidebarDestinations = AppNavModel.visibleSidebarDestinations(user);
    final mobileDestinations = AppNavModel.visibleMobileDestinations(user);
    final hiddenCount = AppNavModel.hiddenSidebarCount(user);
    final mediaQuery = MediaQuery.of(context);
    final width = mediaQuery.size.width;
    final floatingBottomInset = math.max(
      mediaQuery.padding.bottom,
      mediaQuery.viewInsets.bottom,
    );
    final shellUsesRail = width >= AppLayoutTokens.compactBreakpoint;
    final windowsHomeStack =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        widget.location == '/home';
    final layout = shellUsesRail
        ? width >= AppLayoutTokens.desktopBreakpoint
              ? 'desktop'
              : 'tablet'
        : 'mobile';
    final activeDestination =
        AppNavModel.destinationForLocation(widget.location) ??
        AppNavModel.destinations.first;

    _logNavigationModel(
      layout: layout,
      visibleCount: sidebarDestinations.length,
      hiddenCount: hiddenCount,
    );

    final interceptAndroidBack =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    final shell = shellUsesRail
        ? _WideShell(
            layout: layout,
            location: widget.location,
            destinations: sidebarDestinations,
            activeDestination: activeDestination,
            user: user,
            version: _version,
            onNavigate: _navigate,
            onLogout: () => _logout(context),
            onAppInfo: () => _showAppInfoDialog(context),
            child: widget.child,
          )
        : _MobileShell(
            location: widget.location,
            drawerDestinations: sidebarDestinations,
            destinations: mobileDestinations,
            activeDestination: activeDestination,
            version: _version,
            onNavigate: _navigate,
            child: widget.child,
          );

    return PopScope(
      canPop: interceptAndroidBack ? false : widget.location != '/home',
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (interceptAndroidBack) {
          await _handleAndroidBackNavigation();
          return;
        }
        if (widget.location == '/home') {
          final shouldExit = await _handleBackNavigation();
          if (shouldExit && context.mounted) {
            SystemNavigator.pop();
          }
        }
      },
      child: SizedBox(
        width: width,
        height: mediaQuery.size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            shell,
            if (shellUsesRail &&
                widget.location != '/admin/support-chats' &&
                (supportChat?.enabled == true || windowsHomeStack))
              Positioned(
                right: windowsHomeStack
                    ? width >= AppLayoutTokens.desktopBreakpoint
                          ? 16
                          : 24
                    : width >= AppLayoutTokens.tabletBreakpoint
                    ? 24
                    : 16,
                bottom:
                    (windowsHomeStack
                        ? width >= AppLayoutTokens.desktopBreakpoint
                              ? 24
                              : 32
                        : width >= AppLayoutTokens.tabletBreakpoint
                        ? 32
                        : 116) +
                    floatingBottomInset,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (windowsHomeStack)
                      QuickActionsLauncher(
                        menuAxis: Axis.vertical,
                        location: widget.location,
                        visibleWhenUnavailable: true,
                      ),
                    if (windowsHomeStack) const SizedBox(height: 12),
                    SupportChatBubble(
                      onPressed: () => _openSupport(context),
                      visibleWhenDisabled: windowsHomeStack,
                      usePrimaryStyle: windowsHomeStack,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAndroidBackNavigation() async {
    if (_routeHistory.isNotEmpty) {
      final previous = _routeHistory.removeLast();
      _suppressNextHistoryPush = true;
      await AppLogger.instance.info(
        'AppShell',
        'Android system back navigated to previous route',
        context: {'from': widget.location, 'to': previous},
      );
      if (mounted) context.go(previous);
      return;
    }

    if (widget.location != '/home') {
      _suppressNextHistoryPush = true;
      await AppLogger.instance.info(
        'AppShell',
        'Android system back returned to home',
        context: {'from': widget.location},
      );
      if (mounted) context.go('/home');
      return;
    }

    final shouldExit = await _handleBackNavigation();
    if (shouldExit && mounted) {
      SystemNavigator.pop();
    }
  }

  void _navigate(AppNavDestination destination) {
    unawaited(
      AppLogger.instance.info(
        'AppShell',
        'Navigation item selected',
        context: {'destination': destination.id, 'route': destination.route},
      ),
    );
    context.go(destination.route);
  }

  void _logNavigationModel({
    required String layout,
    required int visibleCount,
    required int hiddenCount,
  }) {
    final key = '$layout|$visibleCount|$hiddenCount|${widget.location}';
    if (_lastNavLogKey == key) return;
    _lastNavLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'AppShell',
          'Navigation model resolved',
          context: {
            'layout': layout,
            'route': widget.location,
            'visibleCount': visibleCount,
            'hiddenCount': hiddenCount,
          },
        ),
      );
    });
  }

  Future<void> _logout(BuildContext context) async {
    await AppLogger.instance.info('AppShell', 'Logout confirmation requested');
    if (!context.mounted) return;
    final confirmed = await showLogoutConfirmationDialog(context);
    if (!context.mounted) return;
    if (!confirmed) {
      await AppLogger.instance.info('AppShell', 'Logout cancelled');
      return;
    }
    await AppLogger.instance.info('AppShell', 'Logout confirmed');
    if (!context.mounted) return;
    final authProvider = context.read<AuthProvider>();
    try {
      await AppLogger.instance.info('AppShell', 'Logout started');
      await authProvider.logout();
      await AppLogger.instance.info('AppShell', 'Logout succeeded');
      if (context.mounted) context.go('/login');
    } catch (error) {
      await AppLogger.instance.warn(
        'AppShell',
        'Logout failed',
        context: {'error': error.toString()},
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        const SnackBar(content: Text('Chưa đăng xuất được. Vui lòng thử lại.')),
      );
    }
  }

  Future<void> _showSupportDialog(BuildContext context) async {
    final inviteUri = Uri.parse(_supportGroupInviteUrl);
    final logContext = {
      'asset': _supportQrAssetPath,
      'urlHost': inviteUri.host,
      'urlPath': inviteUri.path,
    };
    await AppLogger.instance.info(
      'AppShellSupport',
      'Support dialog requested',
      context: logContext,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              PhosphorIconsRegular.headset,
              color: AppColors.primaryOf(dialogContext),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Hỗ trợ OpsHub')),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: AppRadius.allMd,
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: AppRadius.allMd,
                    child: Image.asset(
                      _supportQrAssetPath,
                      semanticLabel: 'QR mời vào group hỗ trợ Seatalk',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Không tải được QR. Vui lòng dùng nút mở group bên dưới.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quét QR bằng Seatalk hoặc dùng nút bên dưới để mở hoặc sao chép liên kết group hỗ trợ.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Đóng',
          ),
          AppDialogSecondaryButton(
            onPressed: () => _copySupportGroupLink(dialogContext),
            icon: PhosphorIconsRegular.copy,
            label: 'Sao chép liên kết',
          ),
          AppDialogConfirmButton(
            onPressed: () => _openSupportGroupLink(dialogContext),
            icon: PhosphorIconsRegular.arrowSquareOut,
            label: 'Mở group',
          ),
        ],
      ),
    );
    await AppLogger.instance.info(
      'AppShellSupport',
      'Support dialog closed',
      context: logContext,
    );
  }

  Future<void> _openSupport(BuildContext context) async {
    final supportChat = maybeSupportChatProvider(context);
    if (supportChat?.enabled == true) {
      await showSupportChatSurface(context);
      return;
    }
    await _showSupportDialog(context);
  }

  Future<void> _copySupportGroupLink(BuildContext context) async {
    final inviteUri = Uri.parse(_supportGroupInviteUrl);
    final logContext = {'urlHost': inviteUri.host, 'urlPath': inviteUri.path};
    await AppLogger.instance.info(
      'AppShellSupport',
      'Support link copy requested',
      context: logContext,
    );
    try {
      await Clipboard.setData(
        const ClipboardData(text: _supportGroupInviteUrl),
      );
      await AppLogger.instance.info(
        'AppShellSupport',
        'Support link copied',
        context: logContext,
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        const SnackBar(content: Text('Đã sao chép liên kết group hỗ trợ.')),
      );
    } catch (error) {
      await AppLogger.instance.error(
        'AppShellSupport',
        'Support link copy failed',
        error: error,
        context: logContext,
      );
      if (!context.mounted) return;
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Chưa sao chép được liên kết. Vui lòng thử lại.'),
        ),
      );
    }
  }

  Future<void> _openSupportGroupLink(BuildContext context) async {
    final inviteUri = Uri.parse(_supportGroupInviteUrl);
    final logContext = {'urlHost': inviteUri.host, 'urlPath': inviteUri.path};
    await AppLogger.instance.info(
      'AppShellSupport',
      'Support link opening',
      context: logContext,
    );
    try {
      final opened = await launchUrl(
        inviteUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        await AppLogger.instance.info(
          'AppShellSupport',
          'Support link opened',
          context: logContext,
        );
        return;
      }
    } catch (error) {
      await AppLogger.instance.error(
        'AppShellSupport',
        'Support link open failed',
        error: error,
        context: logContext,
      );
    }
    if (context.mounted) {
      AppToast.show(
        context,
        const SnackBar(
          content: Text(
            'Chưa mở được link. Vui lòng copy link trong hộp thoại.',
          ),
        ),
      );
    }
  }

  void _showAppInfoDialog(BuildContext context) {
    final currentYear = DateTime.now().year;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              PhosphorIconsRegular.info,
              color: AppColors.primaryOf(dialogContext),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Thông tin ứng dụng')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppBrand.title,
              style: AppTextStyles.headingM.copyWith(
                color: AppColors.primaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _version.isNotEmpty ? 'Version $_version' : 'Đang tải phiên bản',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.textMutedOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Dev: $_appDeveloperName',
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.textMutedOf(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '© $currentYear ${AppBrand.productionTitle}',
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.textMutedOf(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppBrand.slogan,
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Đóng',
          ),
        ],
      ),
    );
  }
}

class _WideShell extends StatelessWidget {
  final String layout;
  final String location;
  final List<AppNavDestination> destinations;
  final AppNavDestination activeDestination;
  final User? user;
  final String version;
  final ValueChanged<AppNavDestination> onNavigate;
  final VoidCallback onLogout;
  final VoidCallback onAppInfo;
  final Widget child;

  const _WideShell({
    required this.layout,
    required this.location,
    required this.destinations,
    required this.activeDestination,
    required this.user,
    required this.version,
    required this.onNavigate,
    required this.onLogout,
    required this.onAppInfo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = layout == 'desktop';
    return Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      body: Row(
        children: [
          if (isDesktop)
            _DesktopSidebar(
              location: location,
              destinations: destinations,
              version: version,
              onNavigate: onNavigate,
            )
          else
            _TabletRail(
              location: location,
              destinations: destinations,
              onNavigate: onNavigate,
            ),
          Expanded(
            child: Column(
              children: [
                _ShellTopBar(
                  location: location,
                  activeDestination: activeDestination,
                  user: user,
                  onLogout: onLogout,
                  onAppInfo: onAppInfo,
                ),
                Expanded(
                  child: _ShellAccessSyncSurface(
                    child: _RouteViewport(location: location, child: child),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final String location;
  final List<AppNavDestination> drawerDestinations;
  final List<AppNavDestination> destinations;
  final AppNavDestination activeDestination;
  final String version;
  final ValueChanged<AppNavDestination> onNavigate;
  final Widget child;

  const _MobileShell({
    required this.location,
    required this.drawerDestinations,
    required this.destinations,
    required this.activeDestination,
    required this.version,
    required this.onNavigate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final header = _shellHeaderFor(location, activeDestination);
    final compactMobile =
        mediaQuery.size.width < AppLayoutTokens.compactBreakpoint;
    final bottomNavHeight = compactMobile
        ? AppLayoutTokens.compactMobileBottomNavHeight
        : AppLayoutTokens.mobileBottomNavHeight;
    final showQuickActions =
        (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) &&
        QuickActionsLauncher.isAvailable(context);
    final quickActionsIndex = destinations.length ~/ 2;
    final selectedIndex = _selectedMobileIndex(
      quickActionsIndex: showQuickActions ? quickActionsIndex : null,
    );
    final selectedNavigationColor = AppColors.selectedNavigationOf(context);
    final unselectedNavigationColor = AppColors.textMutedOf(context);
    final mobileTheme = Theme.of(context).copyWith(
      navigationBarTheme: compactMobile
          ? NavigationBarThemeData(
              height: bottomNavHeight,
              indicatorColor: AppColors.sidebarSelectedOf(context),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 22,
                  color: states.contains(WidgetState.selected)
                      ? selectedNavigationColor
                      : unselectedNavigationColor,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => AppTextStyles.caption.copyWith(
                  color: states.contains(WidgetState.selected)
                      ? selectedNavigationColor
                      : unselectedNavigationColor,
                ),
              ),
            )
          : NavigationBarThemeData(
              height: bottomNavHeight,
              indicatorColor: AppColors.sidebarSelectedOf(context),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected)
                      ? selectedNavigationColor
                      : unselectedNavigationColor,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => AppTextStyles.labelS.copyWith(
                  color: states.contains(WidgetState.selected)
                      ? selectedNavigationColor
                      : unselectedNavigationColor,
                ),
              ),
            ),
    );
    return Theme(
      data: mobileTheme,
      child: Scaffold(
        backgroundColor: AppColors.canvasOf(context),
        drawer: _MobileNavigationDrawer(
          location: location,
          destinations: drawerDestinations,
          version: version,
          onNavigate: onNavigate,
        ),
        appBar: _FoundationCompactShellTopBar(title: header.title),
        body: _ShellAccessSyncSurface(
          child: _RouteViewport(location: location, child: child),
        ),
        bottomNavigationBar: NavigationBar(
          key: const Key('mobile-bottom-navigation'),
          height: bottomNavHeight,
          selectedIndex: selectedIndex,
          destinations: [
            for (var index = 0; index <= destinations.length; index++) ...[
              if (showQuickActions && index == quickActionsIndex)
                NavigationDestination(
                  key: const Key('mobile-quick-actions-destination'),
                  icon: Transform.translate(
                    // NavigationDestination raises its icon lane by 5.5 px.
                    // Offset the 68 px Figma track back to the nav surface top.
                    offset: const Offset(0, 5.5),
                    child: SizedBox(
                      key: const Key('mobile-quick-actions-track'),
                      height: 68,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: QuickActionsLauncher(
                            menuAxis: Axis.horizontal,
                            location: location,
                            buttonSize: 48,
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  label: '',
                ),
              if (index < destinations.length)
                NavigationDestination(
                  icon: destinations[index].id == 'notifications'
                      ? const _MobileNotificationDestinationIcon()
                      : Icon(destinations[index].icon),
                  label: destinations[index].label,
                  tooltip: destinations[index].description,
                ),
            ],
          ],
          onDestinationSelected: (index) {
            if (showQuickActions && index == quickActionsIndex) return;
            final destinationIndex =
                showQuickActions && index > quickActionsIndex
                ? index - 1
                : index;
            onNavigate(destinations[destinationIndex]);
          },
        ),
      ),
    );
  }

  int _selectedMobileIndex({int? quickActionsIndex}) {
    final directIndex = destinations.indexWhere(
      (destination) => AppNavModel.isSelected(destination, location),
    );
    if (directIndex >= 0) {
      return quickActionsIndex != null && directIndex >= quickActionsIndex
          ? directIndex + 1
          : directIndex;
    }
    return 0;
  }
}

class _FoundationCompactShellTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String title;

  const _FoundationCompactShellTopBar({required this.title});

  @override
  Size get preferredSize =>
      const Size.fromHeight(AppLayoutTokens.shellTopBarHeight);

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.raisedOf(context);
    final foreground = AppColors.textPrimaryOf(context);
    return Material(
      color: surface,
      child: Container(
        key: const ValueKey('mobile-shell-topbar'),
        height: preferredSize.height,
        // The 1px Foundation border is inside the 375px frame. Keep the
        // visible controls at the source-node x=12 / x=315 positions.
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Row(
          children: [
            Builder(
              builder: (context) => SizedBox.square(
                dimension: 48,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: 'Mở menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: Icon(PhosphorIconsRegular.list, color: foreground),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.headingS.copyWith(color: foreground),
              ),
            ),
            const SizedBox(width: 12),
            const SizedBox.square(
              dimension: 48,
              child: _FoundationNotificationAction(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellAccessSyncSurface extends StatelessWidget {
  const _ShellAccessSyncSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.hasUsableAccessSnapshot) {
      if (auth.isAccessSyncing) {
        return const AppStatePanel.loading(
          title: 'Đang đồng bộ quyền truy cập',
          message: 'Ứng dụng đang cập nhật chức năng dành cho tài khoản này.',
        );
      }
      return AppStatePanel.error(
        title: 'Chưa tải được quyền truy cập',
        message:
            'Vui lòng thử lại để ứng dụng hiển thị đúng các chức năng của bạn.',
        actionLabel: 'Thử lại',
        onAction: () => unawaited(auth.retryAccessSync()),
      );
    }
    final warning = auth.accessSyncWarning;
    if (warning == null) return child;
    final lastSyncedAt = auth.accessLastSyncedAt?.toLocal();
    final lastSyncedText = lastSyncedAt == null
        ? 'Chưa có lần đồng bộ quyền thành công trên thiết bị này.'
        : 'Lần đồng bộ gần nhất: ${_formatAccessSyncTime(lastSyncedAt)}.';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: AppStatusBanner(
            icon: PhosphorIconsRegular.cloudSlash,
            title: 'Quyền truy cập chưa được cập nhật',
            message: '$warning $lastSyncedText',
            tone: AppStateTone.warning,
            actionLabel: auth.isAccessSyncing ? 'Đang thử lại…' : 'Thử lại',
            actionBusy: auth.isAccessSyncing,
            onAction: () => unawaited(auth.retryAccessSync()),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

String _formatAccessSyncTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)} '
      '${two(value.day)}/${two(value.month)}/${value.year}';
}

class _MobileNotificationDestinationIcon extends StatelessWidget {
  const _MobileNotificationDestinationIcon();

  @override
  Widget build(BuildContext context) {
    late final AppNotificationsProvider notifications;
    try {
      notifications = context.watch<AppNotificationsProvider>();
    } on ProviderNotFoundException {
      return const Icon(PhosphorIconsRegular.bell);
    }

    return Badge(
      isLabelVisible: notifications.count > 0,
      label: Text(notifications.count > 99 ? '99+' : '${notifications.count}'),
      child: const Icon(PhosphorIconsRegular.bell),
    );
  }
}

class _FoundationNotificationAction extends StatelessWidget {
  const _FoundationNotificationAction();

  @override
  Widget build(BuildContext context) {
    var count = 0;
    try {
      final notifications = context.watch<AppNotificationsProvider>();
      if (notifications.isEnabled) count = notifications.count;
    } on ProviderNotFoundException {
      // Lightweight shell tests can omit the notifications provider. The
      // Foundation action remains visible and safely becomes a no-op.
    }

    return AppNotificationIconButton(
      count: count,
      tooltip: count > 0 ? '$count thông báo mới' : 'Thông báo',
      onPressed: () => unawaited(AppNotificationsBell.showPanel(context)),
    );
  }
}

class _MobileNavigationDrawer extends StatelessWidget {
  const _MobileNavigationDrawer({
    required this.location,
    required this.destinations,
    required this.version,
    required this.onNavigate,
  });

  final String location;
  final List<AppNavDestination> destinations;
  final String version;
  final ValueChanged<AppNavDestination> onNavigate;

  @override
  Widget build(BuildContext context) {
    final sections = _SidebarSection.fromDestinations(destinations);
    return Drawer(
      backgroundColor: AppColors.sidebarSurfaceOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Row(
                children: [
                  AppLogo(
                    key: const ValueKey('mobile-drawer-logo'),
                    size: 32,
                    borderRadius: AppRadius.md,
                    strokeColor: AppColors.sidebarTextOf(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PhongVu OpsHub',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelL.copyWith(
                            color: AppColors.sidebarTextOf(context),
                          ),
                        ),
                        Text(
                          AppBrand.slogan,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.sidebarMutedOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('mobile-drawer-list'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                      child: Text(
                        section.label,
                        style: AppTextStyles.labelS.copyWith(
                          color: AppColors.sidebarMutedOf(context),
                        ),
                      ),
                    ),
                    for (final destination in section.destinations) ...[
                      _MobileDrawerItem(
                        destination: destination,
                        selected: AppNavModel.isSelected(destination, location),
                        onTap: () {
                          Navigator.of(context).pop();
                          onNavigate(destination);
                        },
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ],
              ),
            ),
            _SidebarFooter(
              version: version,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileDrawerItem extends StatelessWidget {
  const _MobileDrawerItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppColors.selectedNavigationOf(context)
        : AppColors.sidebarTextOf(context);
    return Material(
      color: selected
          ? AppColors.sidebarSelectedOf(context).withValues(alpha: 0.16)
          : AppColors.transparent,
      borderRadius: AppRadius.allMd,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(destination.icon, color: foreground, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteViewport extends StatelessWidget {
  final String location;
  final Widget child;

  const _RouteViewport({required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.sizeOf(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : mediaSize.width;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : mediaSize.height;
        final routeMediaQuery = MediaQuery.of(
          context,
        ).copyWith(size: Size(width, height));
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: AppColors.canvasOf(context),
            child: ClipRect(
              child: RepaintBoundary(
                key: ValueKey('route-$location'),
                child: MediaQuery(
                  data: routeMediaQuery,
                  child: SizedBox(width: width, height: height, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final String location;
  final List<AppNavDestination> destinations;
  final String version;
  final ValueChanged<AppNavDestination> onNavigate;

  const _DesktopSidebar({
    required this.location,
    required this.destinations,
    required this.version,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final sections = _SidebarSection.fromDestinations(destinations);
    return Container(
      width: AppLayoutTokens.sidebarWidth,
      color: AppColors.sidebarSurfaceOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Figma node 326:2699: an 8px shell inset with a 64px brand row.
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    key: const ValueKey('desktop-sidebar-brand'),
                    children: [
                      AppLogo(
                        key: const ValueKey('desktop-sidebar-logo'),
                        size: 56,
                        borderRadius: 12,
                        strokeColor: AppColors.sidebarTextOf(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PhongVu OpsHub',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.headingS.copyWith(
                                color: AppColors.sidebarTextOf(context),
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kết nối nguồn lực.\nĐồng bộ vận hành.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.sidebarTextOf(
                                  context,
                                ).withValues(alpha: 0.78),
                                fontSize: 12,
                                height: 17 / 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('desktop-sidebar-list'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final section in sections) ...[
                    _SidebarSectionHeader(section: section),
                    for (final destination in section.destinations) ...[
                      _SidebarItem(
                        destination: destination,
                        selected: AppNavModel.isSelected(destination, location),
                        onTap: () => onNavigate(destination),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            _SidebarFooter(version: version),
          ],
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.version,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 14),
  });

  final String version;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final footerTextStyle = AppTextStyles.caption.copyWith(
      color: AppColors.sidebarMutedOf(context).withValues(alpha: 0.66),
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (version.isNotEmpty)
            Text('Version $version', style: footerTextStyle),
          const SizedBox(height: 4),
          Text('Dev: $_appDeveloperName', style: footerTextStyle),
          const SizedBox(height: 1),
          Text(
            '© $currentYear ${AppBrand.productionTitle}',
            style: footerTextStyle,
          ),
        ],
      ),
    );
  }
}

class _SidebarSection {
  final AppNavGroup group;
  final String label;
  final List<AppNavDestination> destinations;

  const _SidebarSection({
    required this.group,
    required this.label,
    required this.destinations,
  });

  static List<_SidebarSection> fromDestinations(
    List<AppNavDestination> destinations,
  ) {
    return [
      for (final group in AppNavGroup.values)
        if (destinations.any((destination) => destination.group == group))
          _SidebarSection(
            group: group,
            label: group.label,
            destinations: destinations
                .where((destination) => destination.group == group)
                .toList(growable: false),
          ),
    ];
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  final _SidebarSection section;

  const _SidebarSectionHeader({required this.section});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('sidebar-group-${section.group.name}'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Text(
        section.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.labelS.copyWith(
          color: AppColors.sidebarMutedOf(context),
        ),
      ),
    );
  }
}

class _TabletRail extends StatelessWidget {
  final String location;
  final List<AppNavDestination> destinations;
  final ValueChanged<AppNavDestination> onNavigate;

  const _TabletRail({
    required this.location,
    required this.destinations,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('tablet-shell-rail'),
      width: AppLayoutTokens.tabletRailWidth,
      color: AppColors.sidebarSurfaceOf(context),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AppLogo(
                size: 44,
                borderRadius: AppRadius.md,
                strokeColor: AppColors.sidebarTextOf(context),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  final selected = AppNavModel.isSelected(
                    destination,
                    location,
                  );
                  return Tooltip(
                    message: destination.label,
                    child: Material(
                      color: selected
                          ? AppColors.sidebarSelectedOf(context)
                          : AppColors.transparent,
                      borderRadius: AppRadius.allMd,
                      child: InkWell(
                        onTap: () => onNavigate(destination),
                        borderRadius: AppRadius.allMd,
                        child: SizedBox(
                          height: 52,
                          child: Icon(
                            destination.icon,
                            color: selected
                                ? AppColors.selectedNavigationOf(context)
                                : AppColors.sidebarMutedOf(context),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedForeground = AppColors.selectedNavigationOf(context);
    final selectedBackground = AppColors.sidebarSelectedOf(context);
    final foreground = selected
        ? selectedForeground
        : AppColors.sidebarTextOf(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        key: ValueKey('sidebar-item-${destination.id}'),
        color: selected ? selectedBackground : AppColors.transparent,
        borderRadius: AppRadius.allLg,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allLg,
          hoverColor: selectedForeground.withValues(alpha: 0.08),
          focusColor: selectedForeground.withValues(alpha: 0.12),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
              child: Row(
                children: [
                  Container(
                    key: ValueKey(
                      'sidebar-selected-indicator-${destination.id}',
                    ),
                    width: 4,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedForeground
                          : AppColors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(destination.icon, color: foreground, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  final String location;
  final AppNavDestination activeDestination;
  final User? user;
  final VoidCallback onLogout;
  final VoidCallback onAppInfo;

  const _ShellTopBar({
    required this.location,
    required this.activeDestination,
    required this.user,
    required this.onLogout,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    final header = _shellHeaderFor(location, activeDestination);
    final foundationTabletTopBar =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.desktopBreakpoint;
    return Container(
      key: const ValueKey('tablet-shell-topbar'),
      height: AppLayoutTokens.shellTopBarHeight,
      decoration: BoxDecoration(
        color: AppColors.raisedOf(context),
        border: Border(
          bottom: BorderSide(color: AppColors.subtleBorderOf(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (foundationTabletTopBar) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShellTitleText(title: header.title),
                      const SizedBox(height: 2),
                      Text(
                        header.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const _FoundationNotificationAction(),
                const SizedBox(width: 16),
                _AccountMenuButton(
                  user: user,
                  onLogout: onLogout,
                  onAppInfo: onAppInfo,
                ),
              ],
            );
          }

          // The Figma tablet rail has room for the three retained actions,
          // but not their desktop labels or delivery-metrics pill.
          final desktopTopBarTarget =
              location == '/operations' || location == '/home';
          final compactActions =
              constraints.maxWidth < (desktopTopBarTarget ? 960 : 880);
          return Row(
            children: [
              Expanded(
                child: desktopTopBarTarget
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [_ShellTitleText(title: header.title)],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShellTitleText(title: header.title),
                          const SizedBox(height: 2),
                          Text(
                            header.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyS.copyWith(
                              color: AppColors.textMutedOf(context),
                            ),
                          ),
                        ],
                      ),
              ),
              if (!compactActions) const _ShellMetricsPill(),
              AppNotificationsBell(showLabel: !compactActions),
              const SizedBox(width: 8),
              _AccountMenuButton(
                user: user,
                onLogout: onLogout,
                onAppInfo: onAppInfo,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShellTitleText extends StatelessWidget {
  final String title;

  const _ShellTitleText({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.headingS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

({String title, String description}) _shellHeaderFor(
  String location,
  AppNavDestination activeDestination,
) {
  if (location.startsWith('/check-warranty/details/')) {
    return (
      title: 'Chi tiết biên nhận',
      description: 'Xem thông tin và hình ảnh biên nhận bảo hành',
    );
  }
  switch (location) {
    case '/admin/support-chats':
      return (title: 'Hỗ trợ', description: 'Quản lý hội thoại khách hàng');
    case '/admin/api-connections':
      return (
        title: 'Quản lý kết nối API',
        description: 'Cấu hình BIDV và quản lý khóa OpenPGP',
      );
    default:
      return (
        title: activeDestination.label,
        description: activeDestination.description,
      );
  }
}

class _AccountMenuButton extends StatelessWidget {
  static const double _avatarSize = 42;

  final User? user;
  final VoidCallback onLogout;
  final VoidCallback onAppInfo;

  const _AccountMenuButton({
    required this.user,
    required this.onLogout,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName = _accountDisplayName(user);
    final initials = cleanName.trim().isNotEmpty
        ? cleanName.trim().characters.first.toUpperCase()
        : '?';
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Tài khoản',
      offset: const Offset(0, 12),
      onSelected: (action) {
        switch (action) {
          case _AccountAction.profile:
            context.go('/profile');
          case _AccountAction.settings:
            context.go('/settings');
          case _AccountAction.appInfo:
            onAppInfo();
          case _AccountAction.logout:
            onLogout();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AccountAction.profile,
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.user),
            title: Text('Thông tin cá nhân'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.settings,
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.gear),
            title: Text('Cài đặt'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.appInfo,
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.info),
            title: Text('Thông tin ứng dụng'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.logout,
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.signOut),
            title: Text('Đăng xuất'),
          ),
        ),
      ],
      child: _AccountAvatar(initials: initials, size: _avatarSize),
    );
  }

  String _accountDisplayName(User? user) {
    final name = user?.name?.trim();
    if (name?.isNotEmpty == true) return name!;
    final email = user?.email.trim();
    if (email?.isNotEmpty == true) return email!;
    return 'Tài khoản';
  }
}

class _AccountAvatar extends StatelessWidget {
  final String initials;
  final double size;

  const _AccountAvatar({required this.initials, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySurfaceOf(context),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        initials,
        style: AppTextStyles.labelL.copyWith(
          color: AppColors.primaryOf(context),
        ),
      ),
    );
  }
}

class _ShellMetricsPill extends StatelessWidget {
  const _ShellMetricsPill();

  @override
  Widget build(BuildContext context) {
    late final bool shouldShow;
    try {
      shouldShow = context.select<PaymentDeliveryMetricsProvider, bool>(
        (provider) => provider.shouldShow,
      );
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!shouldShow) return const SizedBox.shrink();
    final compact =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: PaymentDeliveryMetricsChip(compact: compact),
    );
  }
}

enum _AccountAction { profile, settings, appInfo, logout }
