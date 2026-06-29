import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../notifications/presentation/widgets/app_notifications_bell.dart';
import '../../../payment_monitor/presentation/providers/payment_delivery_metrics_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../../../payment_monitor/presentation/widgets/payment_delivery_metrics_chip.dart';

const _supportQrAssetPath = 'data/group_invitation.jpg';
const _supportGroupInviteUrl =
    'https://link.seatalk.io/group/open?invite_id=IkaYSKrlQkImmkCfNj4aBdpd5cpcCWFPaaegCUhYXjgcfi1Tzn9E9Gbuac_qt8Jk5mruc0AJGqQLaQeSWG1e';
const _supportLogSource = 'HomeSupport';
const _helpLogSource = 'HomeHelp';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = packageInfo.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canUseAdminMenu = context.select<AuthProvider, bool>((auth) {
      return _canOpenAdminUser(auth.user);
    });
    final canUseFifoMenu = context.select<AuthProvider, bool>((auth) {
      final user = auth.user;
      return user?.canUseFeature('FIFO') == true ||
          user?.canUseFeature('FIFO_IMPORT') == true;
    });
    final canUseWarranty = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('WARRANTY') == true,
    );
    final canUseBankStatements = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseBankStatements == true,
    );
    final canUseOffsetAdjustments = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseOffsetAdjustments == true,
    );
    final canUseVietQr = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('VIETQR') == true,
    );
    final canUsePaymentMonitor = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('PAYMENT_MONITOR') == true,
    );
    final canUseSalesReportHub = context.select<AuthProvider, bool>((auth) {
      final user = auth.user;
      return user?.canUseFeature('SALES_REPORT') == true ||
          user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
    });
    final canUseFeedback = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('FEEDBACK') == true,
    );
    final canUsePaymentSpeaker = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('PAYMENT_SPEAKER') == true,
    );
    final supportsPaymentSpeaker =
        AppPlatformCapabilities.isPaymentSpeakerSupported();
    final supportsPaymentMonitor =
        AppPlatformCapabilities.isPaymentMonitorSupported();
    final actions = _buildHomeActions(
      context,
      canUseAdminMenu,
      canUseFifoMenu,
      canUseWarranty,
      canUseBankStatements,
      canUseOffsetAdjustments,
      canUseVietQr,
      canUsePaymentMonitor && supportsPaymentMonitor,
      canUseSalesReportHub,
      canUseFeedback,
    );

    return Scaffold(
      drawer: _buildDrawer(context),
      body: Column(
        children: [
          Builder(
            builder: (scaffoldContext) {
              return Selector<
                AuthProvider,
                ({String userName, String storeInfo, String? avatarUrl})
              >(
                selector: (_, auth) => (
                  userName: auth.user?.name ?? auth.user?.email ?? '',
                  storeInfo:
                      auth.user?.assignedStoreHeaderInfo ??
                      'Chưa có SR được gán',
                  avatarUrl: auth.user?.avatarUrl,
                ),
                builder: (context, data, _) {
                  return _CompactHomeHeader(
                    userName: data.userName,
                    storeInfo: data.storeInfo,
                    avatarUrl: data.avatarUrl,
                    onMenu: () => Scaffold.of(scaffoldContext).openDrawer(),
                    onProfile: () => context.push('/profile'),
                    onSupport: () => _showSupportDialog(context),
                  );
                },
              );
            },
          ),
          Expanded(
            child: AppResponsiveScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canUsePaymentSpeaker && supportsPaymentSpeaker) ...[
                    const _PaymentMonitorQuickToggle(),
                    const SizedBox(height: 16),
                  ],
                  AppFeatureSection(actions: actions),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AppFeatureAction> _buildHomeActions(
    BuildContext context,
    bool canUseAdminMenu,
    bool canUseFifoMenu,
    bool canUseWarranty,
    bool canUseBankStatements,
    bool canUseOffsetAdjustments,
    bool canUseVietQr,
    bool canUsePaymentMonitor,
    bool canUseSalesReportHub,
    bool canUseFeedback,
  ) {
    return [
      if (canUseAdminMenu)
        AppFeatureAction(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Quản trị',
          description: 'Tài khoản & vai trò',
          color: AppColors.neutral600,
          onTap: () => context.push('/admin'),
        ),
      if (canUseFifoMenu)
        AppFeatureAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'FIFO',
          description: 'Kiểm tra & sắp xếp',
          color: AppColors.info,
          onTap: () => context.push('/fifo-menu'),
        ),
      if (canUseWarranty)
        AppFeatureAction(
          icon: Icons.camera_alt_rounded,
          title: 'BH / SC',
          description: 'Ảnh bảo hành',
          color: AppColors.success,
          onTap: () => context.push('/warranty-main'),
        ),
      if (canUseVietQr)
        AppFeatureAction(
          icon: Icons.qr_code_2_rounded,
          title: 'VietQR',
          description: 'Tạo mã chuyển khoản',
          color: AppColors.teal600,
          onTap: () => context.push('/vietqr'),
        ),
      if (canUseBankStatements)
        AppFeatureAction(
          icon: Icons.fact_check_outlined,
          title: 'Sao kê',
          description: 'Rà soát mã đơn',
          color: AppColors.info,
          onTap: () => context.push('/bank-statement'),
        ),
      if (canUseOffsetAdjustments)
        AppFeatureAction(
          icon: Icons.swap_horiz_rounded,
          title: 'Cấn trừ',
          description: 'Gửi Kế toán xác nhận',
          color: AppColors.teal600,
          onTap: () => context.push('/offset-adjustments'),
        ),
      if (canUsePaymentMonitor)
        AppFeatureAction(
          icon: Icons.payments_outlined,
          title: 'Tiền vào',
          description: 'Cập nhật giao dịch',
          color: AppColors.violet600,
          onTap: () => context.push('/payment-monitor'),
        ),
      if (canUseSalesReportHub)
        AppFeatureAction(
          icon: Icons.assignment_outlined,
          title: 'Báo cáo',
          description: 'Báo cáo sale',
          color: AppColors.info,
          onTap: () => context.push('/sales-reports'),
        ),
      if (canUseFeedback)
        AppFeatureAction(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Góp ý',
          description: 'Đề xuất & báo lỗi',
          color: AppColors.amber500,
          onTap: () async {
            await AppLogger.instance.info(
              'Feedback',
              'Suggestion opened from home',
            );
            if (context.mounted) context.push('/feedback');
          },
        ),
    ];
  }

  Future<void> _logout(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    try {
      await AppLogger.instance.info('Home', 'Logout from side menu started');
      await authProvider.logout();
      await AppLogger.instance.info('Home', 'Logout from side menu succeeded');
      if (context.mounted) {
        context.go('/login');
      }
    } catch (error) {
      await AppLogger.instance.warn(
        'Home',
        'Logout from side menu failed',
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
    unawaited(
      AppLogger.instance.info(
        _supportLogSource,
        'Support group dialog requested',
        context: logContext,
      ),
    );
    if (!context.mounted) {
      unawaited(
        AppLogger.instance.warn(
          _supportLogSource,
          'Support group dialog skipped',
          context: {...logContext, 'reason': 'context_unmounted'},
        ),
      );
      return;
    }
    unawaited(
      AppLogger.instance.info(
        _supportLogSource,
        'Support group dialog shown',
        context: logContext,
      ),
    );
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
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                    border: Border.all(color: AppColors.neutral200),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                    child: Image.asset(
                      _supportQrAssetPath,
                      semanticLabel: 'QR mời vào group hỗ trợ Seatalk',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Không tải được QR. Vui lòng dùng link bên dưới.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quét QR bằng Seatalk hoặc mở link group hỗ trợ:',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.neutral600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _supportGroupInviteUrl,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.primary,
                    height: 1.35,
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
          AppDialogConfirmButton(
            onPressed: () => _openSupportGroupLink(dialogContext),
            icon: Icons.open_in_new_rounded,
            label: 'Mở group',
          ),
        ],
      ),
    );
    await AppLogger.instance.info(
      _supportLogSource,
      'Support group dialog closed',
      context: logContext,
    );
  }

  Future<void> _openSupportGroupLink(BuildContext context) async {
    final inviteUri = Uri.parse(_supportGroupInviteUrl);
    final logContext = {'urlHost': inviteUri.host, 'urlPath': inviteUri.path};
    await AppLogger.instance.info(
      _supportLogSource,
      'Support group link opening',
      context: logContext,
    );
    try {
      final opened = await launchUrl(
        inviteUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        await AppLogger.instance.info(
          _supportLogSource,
          'Support group link opened',
          context: logContext,
        );
        return;
      }
      await AppLogger.instance.warn(
        _supportLogSource,
        'Support group link launcher returned false',
        context: logContext,
      );
    } catch (error) {
      await AppLogger.instance.error(
        _supportLogSource,
        'Support group link open failed',
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
      _helpLogSource,
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
          _helpLogSource,
          'Help page opened',
          context: logContext,
        );
        return;
      }
      await AppLogger.instance.warn(
        _helpLogSource,
        'Help page launcher returned false',
        context: logContext,
      );
    } catch (error) {
      await AppLogger.instance.error(
        _helpLogSource,
        'Help page open failed',
        error: error,
        context: logContext,
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Chưa mở được hướng dẫn. Vui lòng thử lại hoặc mở trang tải ứng dụng.',
          ),
        ),
      );
    }
  }

  Widget _buildDrawer(BuildContext context) {
    final onGradient = AppColors.surface;
    final onGradientMuted = AppColors.surface.withValues(alpha: 0.70);
    final onGradientDivider = AppColors.surface.withValues(alpha: 0.24);
    final onGradientSubtle = AppColors.surface.withValues(alpha: 0.50);

    return Drawer(
      backgroundColor: AppColors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: GradientHeader.getGradient(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    const AppLogo(size: 48, borderRadius: 16),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PhongVu',
                          style: AppTextStyles.headingM.copyWith(
                            color: onGradient,
                          ),
                        ),
                        Text(
                          'OpsHub',
                          style: AppTextStyles.bodyL.copyWith(
                            color: onGradientMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(color: onGradientDivider, thickness: 1),
              ListTile(
                leading: Icon(Icons.person_outline, color: onGradient),
                title: Text(
                  'Thông tin cá nhân',
                  style: AppTextStyles.bodyL.copyWith(color: onGradient),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/profile');
                },
              ),
              if (_canOpenAdminMenu(context.watch<AuthProvider>().user))
                ListTile(
                  leading: Icon(
                    Icons.admin_panel_settings_outlined,
                    color: onGradient,
                  ),
                  title: Text(
                    'Quản trị',
                    style: AppTextStyles.bodyL.copyWith(color: onGradient),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/admin');
                  },
                ),
              ListTile(
                leading: Icon(Icons.settings_outlined, color: onGradient),
                title: Text(
                  'Cài đặt',
                  style: AppTextStyles.bodyL.copyWith(color: onGradient),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/settings');
                },
              ),
              ListTile(
                leading: Icon(Icons.menu_book_outlined, color: onGradient),
                title: Text(
                  'Hướng dẫn sử dụng',
                  style: AppTextStyles.bodyL.copyWith(color: onGradient),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_openHelpPage(context));
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: onGradient),
                title: Text(
                  'Thông tin ứng dụng',
                  style: AppTextStyles.bodyL.copyWith(color: onGradient),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAppInfoDialog(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.logout_rounded, color: onGradient),
                title: Text(
                  'Đăng xuất',
                  style: AppTextStyles.bodyL.copyWith(color: onGradient),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_logout(context));
                },
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _version.isNotEmpty ? 'Version $_version' : '',
                  style: AppTextStyles.labelS.copyWith(color: onGradientSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _canOpenAdminMenu(dynamic user) {
    return _canOpenAdminUser(user);
  }

  bool _canOpenAdminUser(dynamic user) {
    return user?.isAdmin == true ||
        user?.canUseFeature('ADMIN') == true ||
        user?.canUseFeature('ADMIN_USERS') == true ||
        user?.canUseFeature('ADMIN_ROLES') == true ||
        user?.canUseFeature('ADMIN_ORG_TREE') == true ||
        user?.canUseFeature('ADMIN_POLICIES') == true ||
        user?.canUseFeature('ADMIN_FEEDBACK') == true;
  }

  void _showAppInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary),
            const SizedBox(width: 12),
            const Text('Thông tin ứng dụng'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PhongVu OpsHub',
              style: AppTextStyles.headingM.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 4),
            Text(
              _version.isNotEmpty ? 'Version $_version' : '',
              style: AppTextStyles.bodyM.copyWith(color: AppColors.neutral500),
            ),
            const SizedBox(height: 12),
            Text(
              'Dev by Hoang Nguyen aka Hoàng Học Hỏi',
              style: AppTextStyles.bodyS.copyWith(color: AppColors.neutral600),
            ),
            const SizedBox(height: 16),
            Text(
              'Kết nối con người. Đồng bộ vận hành.',
              style: AppTextStyles.labelS.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.neutral600,
              ),
            ),
          ],
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Đóng',
          ),
        ],
      ),
    );
  }
}

class _PaymentMonitorQuickToggle extends StatelessWidget {
  const _PaymentMonitorQuickToggle();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<PaymentMonitorProvider>();
    final canToggle = monitor.canUsePaymentSpeaker;
    final speakerEnabled = monitor.isSpeakerEnabled;
    final speakerActive = canToggle && speakerEnabled;
    final speakerSelectionNotice = monitor.speakerSelectionNotice;
    final statusText =
        speakerSelectionNotice ??
        (monitor.isActive
            ? speakerActive
                  ? 'Đang cập nhật, có đọc loa'
                  : 'Đang cập nhật, đã tắt loa'
            : canToggle
            ? 'Đang chuẩn bị cập nhật'
            : 'Chọn showroom để dùng');

    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
        value: speakerActive,
        onChanged: canToggle
            ? (value) => context
                  .read<PaymentMonitorProvider>()
                  .setSpeakerEnabled(value)
            : null,
        secondary: Icon(
          speakerActive ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: speakerActive ? AppColors.success : AppColors.neutral500,
        ),
        title: const Text('Đọc loa tiền vào', style: AppTextStyles.labelM),
        subtitle: Text(statusText, style: AppTextStyles.bodyS),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }
}

class _HomePaymentDeliveryMetricsPill extends StatelessWidget {
  const _HomePaymentDeliveryMetricsPill();

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

    return const PaymentDeliveryMetricsChip();
  }
}

class _CompactHomeHeader extends StatelessWidget {
  final String userName;
  final String storeInfo;
  final String? avatarUrl;
  final VoidCallback onMenu;
  final VoidCallback onProfile;
  final VoidCallback onSupport;

  const _CompactHomeHeader({
    required this.userName,
    required this.storeInfo,
    required this.avatarUrl,
    required this.onMenu,
    required this.onProfile,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) {
    final cleanName = userName.contains('@')
        ? userName.split('@').first
        : userName;
    final nameParts = cleanName.trim().split(' ');
    final initials = (nameParts.isNotEmpty && nameParts.first.isNotEmpty)
        ? nameParts.first[0].toUpperCase()
        : '?';
    final cleanAvatarUrl = avatarUrl?.trim();
    final hasRemoteAvatar =
        cleanAvatarUrl != null &&
        (cleanAvatarUrl.startsWith('http://') ||
            cleanAvatarUrl.startsWith('https://'));
    final onGradient = AppColors.surface;
    final onGradientMuted = AppColors.surface.withValues(alpha: 0.70);
    final onGradientSubtle = AppColors.surface.withValues(alpha: 0.16);
    final fallbackAvatar = Text(
      initials,
      style: AppTextStyles.headingM.copyWith(color: onGradient),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: GradientHeader.getGradient(context),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppRadius.lg),
          bottomRight: Radius.circular(AppRadius.lg),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 8,
        12,
        14,
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Menu',
                onPressed: onMenu,
                icon: Icon(Icons.menu_rounded, color: onGradient),
              ),
              Expanded(
                child: Text(
                  'PhongVu OpsHub',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headingS.copyWith(color: onGradient),
                ),
              ),
              IconButton(
                tooltip: 'Hỗ trợ',
                onPressed: onSupport,
                icon: Icon(Icons.support_agent_rounded, color: onGradient),
              ),
              const _HomePaymentDeliveryMetricsPill(),
              IconTheme(
                data: IconThemeData(color: onGradient),
                child: AppNotificationsBell(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: onGradientSubtle,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: onGradientSubtle),
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child: hasRemoteAvatar
                      ? Image.network(
                          cleanAvatarUrl,
                          key: ValueKey(cleanAvatarUrl),
                          width: 46,
                          height: 46,
                          fit: BoxFit.cover,
                          frameBuilder: (context, child, frame, _) {
                            if (frame == null) return fallbackAvatar;
                            return child;
                          },
                          errorBuilder: (_, _, _) => fallbackAvatar,
                        )
                      : fallbackAvatar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.headingS.copyWith(color: onGradient),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.store_outlined,
                          color: onGradientMuted,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            storeInfo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyS.copyWith(
                              color: onGradientMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
