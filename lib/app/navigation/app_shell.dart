import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_brand.dart';
import '../../core/constants/api_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../features/auth/domain/entities/user.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/notifications/presentation/widgets/app_notifications_bell.dart';
import '../../features/payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import '../../features/payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_logo.dart';
import 'app_nav_model.dart';

const _supportQrAssetPath = 'data/group_invitation.jpg';
const _supportGroupInviteUrl =
    'https://link.seatalk.io/group/open?invite_id=IkaYSKrlQkImmkCfNj4aBdpd5cpcCWFPaaegCUhYXjgcfi1Tzn9E9Gbuac_qt8Jk5mruc0AJGqQLaQeSWG1e';

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

  @override
  void initState() {
    super.initState();
    _loadVersion();
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
      ScaffoldMessenger.of(context).showSnackBar(
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
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final sidebarDestinations = AppNavModel.visibleSidebarDestinations(user);
    final mobileDestinations = AppNavModel.visibleMobileDestinations(user);
    final hiddenCount = AppNavModel.hiddenSidebarCount(user);
    final width = MediaQuery.sizeOf(context).width;
    final layout = width >= AppLayoutTokens.tabletBreakpoint
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

    return PopScope(
      canPop: widget.location != '/home',
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || widget.location != '/home') return;
        final shouldExit = await _handleBackNavigation();
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: width >= AppLayoutTokens.tabletBreakpoint
          ? _WideShell(
              layout: layout,
              location: widget.location,
              destinations: sidebarDestinations,
              activeDestination: activeDestination,
              user: user,
              version: _version,
              onNavigate: _navigate,
              onSupport: () => _showSupportDialog(context),
              onHelp: () => _openHelpPage(context),
              onLogout: () => _logout(context),
              onAppInfo: () => _showAppInfoDialog(context),
              child: widget.child,
            )
          : _MobileShell(
              location: widget.location,
              destinations: mobileDestinations,
              activeDestination: activeDestination,
              onNavigate: _navigate,
              onSupport: () => _showSupportDialog(context),
              child: widget.child,
            ),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
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
            const Icon(Icons.support_agent_rounded, color: AppColors.primary),
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
            icon: Icons.copy_rounded,
            label: 'Sao chép liên kết',
          ),
          AppDialogConfirmButton(
            onPressed: () => _openSupportGroupLink(dialogContext),
            icon: Icons.open_in_new_rounded,
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa mở được link. Vui lòng copy link trong hộp thoại.',
          ),
        ),
      );
    }
  }

  Future<void> _openHelpPage(BuildContext context) async {
    final helpUri = ApiConstants.helpPageUri;
    final logContext = {'urlHost': helpUri.host, 'urlPath': helpUri.path};
    await AppLogger.instance.info(
      'AppShellHelp',
      'Help page opening',
      context: logContext,
    );
    try {
      final opened = await launchUrl(
        helpUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        await AppLogger.instance.info(
          'AppShellHelp',
          'Help page opened',
          context: logContext,
        );
        return;
      }
    } catch (error) {
      await AppLogger.instance.error(
        'AppShellHelp',
        'Help page open failed',
        error: error,
        context: logContext,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa mở được hướng dẫn. Vui lòng thử lại.'),
        ),
      );
    }
  }

  void _showAppInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary),
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
            const SizedBox(height: 12),
            Text(
              'Kết nối con người. Đồng bộ vận hành.',
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
  final VoidCallback onSupport;
  final VoidCallback onHelp;
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
    required this.onSupport,
    required this.onHelp,
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
                  activeDestination: activeDestination,
                  user: user,
                  onSupport: onSupport,
                  onHelp: onHelp,
                  onLogout: onLogout,
                  onAppInfo: onAppInfo,
                ),
                Expanded(
                  child: _RouteViewport(location: location, child: child),
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
  final List<AppNavDestination> destinations;
  final AppNavDestination activeDestination;
  final ValueChanged<AppNavDestination> onNavigate;
  final VoidCallback onSupport;
  final Widget child;

  const _MobileShell({
    required this.location,
    required this.destinations,
    required this.activeDestination,
    required this.onNavigate,
    required this.onSupport,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedMobileIndex();
    return Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      appBar: AppBar(
        centerTitle: true,
        leadingWidth: 116,
        leading: const Align(
          alignment: Alignment.centerLeft,
          child: _ShellMetricsPill(),
        ),
        title: Text(
          activeDestination.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Hỗ trợ',
            onPressed: onSupport,
            icon: const Icon(Icons.support_agent_rounded),
          ),
          const AppNotificationsBell(),
          const SizedBox(width: 4),
        ],
      ),
      body: _RouteViewport(location: location, child: child),
      bottomNavigationBar: NavigationBar(
        height: AppLayoutTokens.mobileBottomNavHeight,
        selectedIndex: selectedIndex,
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
              tooltip: destination.description,
            ),
        ],
        onDestinationSelected: (index) => onNavigate(destinations[index]),
      ),
    );
  }

  int _selectedMobileIndex() {
    final directIndex = destinations.indexWhere(
      (destination) => AppNavModel.isSelected(destination, location),
    );
    if (directIndex >= 0) return directIndex;
    final tasksIndex = destinations.indexWhere(
      (destination) => destination.id == 'tasks',
    );
    return tasksIndex >= 0 ? tasksIndex : 0;
  }
}

class _RouteViewport extends StatelessWidget {
  final String location;
  final Widget child;

  const _RouteViewport({required this.location, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: AppColors.canvasOf(context),
        child: ClipRect(
          child: RepaintBoundary(
            key: ValueKey('route-$location'),
            child: child,
          ),
        ),
      ),
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
    return Container(
      width: AppLayoutTokens.sidebarWidth,
      color: AppColors.sidebarSurfaceOf(context),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const AppLogo(size: 44, borderRadius: AppRadius.md),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PhongVu',
                          style: AppTextStyles.labelL.copyWith(
                            color: AppColors.sidebarTextOf(context),
                          ),
                        ),
                        Text(
                          'OpsHub',
                          style: AppTextStyles.bodyS.copyWith(
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
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  return _SidebarItem(
                    destination: destination,
                    selected: AppNavModel.isSelected(destination, location),
                    onTap: () => onNavigate(destination),
                  );
                },
              ),
            ),
            if (version.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Version $version',
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.sidebarMutedOf(context),
                  ),
                ),
              ),
          ],
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
      width: AppLayoutTokens.tabletRailWidth,
      color: AppColors.sidebarSurfaceOf(context),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AppLogo(size: 44, borderRadius: AppRadius.md),
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
                                ? AppColors.primaryOf(context)
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
    final foreground = selected
        ? AppColors.primaryOf(context)
        : AppColors.sidebarTextOf(context);
    return Material(
      color: selected
          ? AppColors.sidebarSelectedOf(context)
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

class _ShellTopBar extends StatelessWidget {
  final AppNavDestination activeDestination;
  final User? user;
  final VoidCallback onSupport;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onAppInfo;

  const _ShellTopBar({
    required this.activeDestination,
    required this.user,
    required this.onSupport,
    required this.onHelp,
    required this.onLogout,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppLayoutTokens.shellTopBarHeight,
      decoration: BoxDecoration(
        color: AppColors.raisedOf(context),
        border: Border(
          bottom: BorderSide(color: AppColors.subtleBorderOf(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeDestination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeDestination.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Hỗ trợ',
            onPressed: onSupport,
            icon: const Icon(Icons.support_agent_rounded),
          ),
          const _ShellMetricsPill(),
          const AppNotificationsBell(),
          const SizedBox(width: 8),
          _AccountMenuButton(
            user: user,
            onHelp: onHelp,
            onLogout: onLogout,
            onAppInfo: onAppInfo,
          ),
        ],
      ),
    );
  }
}

class _AccountMenuButton extends StatelessWidget {
  final User? user;
  final VoidCallback onHelp;
  final VoidCallback onLogout;
  final VoidCallback onAppInfo;

  const _AccountMenuButton({
    required this.user,
    required this.onHelp,
    required this.onLogout,
    required this.onAppInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName = (user?.name?.trim().isNotEmpty == true
        ? user!.name!
        : user?.email ?? 'Tài khoản');
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
          case _AccountAction.help:
            onHelp();
          case _AccountAction.appInfo:
            onAppInfo();
          case _AccountAction.logout:
            onLogout();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AccountAction.profile,
          child: ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Thông tin cá nhân'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.settings,
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Cài đặt'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.help,
          child: ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Hướng dẫn sử dụng'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.appInfo,
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Thông tin ứng dụng'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.logout,
          child: ListTile(
            leading: Icon(Icons.logout_rounded),
            title: Text('Đăng xuất'),
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primarySurfaceOf(context),
          borderRadius: AppRadius.allMd,
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Text(
          initials,
          style: AppTextStyles.labelL.copyWith(
            color: AppColors.primaryOf(context),
          ),
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

enum _AccountAction { profile, settings, help, appInfo, logout }
