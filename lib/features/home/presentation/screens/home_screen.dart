import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../notifications/presentation/widgets/app_notifications_bell.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';

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
    final isAdmin = context.select<AuthProvider, bool>(
      (auth) => auth.user?.isAdmin == true,
    );
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
    final canUseFeedback = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('FEEDBACK') == true,
    );
    final canUsePaymentSpeaker = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('PAYMENT_SPEAKER') == true,
    );
    final supportsPaymentSpeaker =
        AppPlatformCapabilities.isPaymentSpeakerSupported();
    final actions = _buildHomeActions(
      context,
      isAdmin,
      canUseFifoMenu,
      canUseWarranty,
      canUseBankStatements,
      canUseOffsetAdjustments,
      canUseVietQr,
      canUsePaymentMonitor,
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
    bool isAdmin,
    bool canUseFifoMenu,
    bool canUseWarranty,
    bool canUseBankStatements,
    bool canUseOffsetAdjustments,
    bool canUseVietQr,
    bool canUsePaymentMonitor,
    bool canUseFeedback,
  ) {
    return [
      if (isAdmin)
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
            Icon(Icons.support_agent_rounded, color: AppTheme.primaryBlue),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.neutral200),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
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
                const Text(
                  'Quét QR bằng Seatalk hoặc mở link group hỗ trợ:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.neutral600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _supportGroupInviteUrl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
          FilledButton.icon(
            onPressed: () => _openSupportGroupLink(dialogContext),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Mở group'),
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
    return Drawer(
      backgroundColor: Colors.transparent,
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
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PhongVu',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'OpsHub',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, thickness: 1),
              ListTile(
                leading: const Icon(Icons.person_outline, color: Colors.white),
                title: const Text(
                  'Thông tin cá nhân',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/profile');
                },
              ),
              if (context.watch<AuthProvider>().user?.isAdmin == true)
                ListTile(
                  leading: const Icon(
                    Icons.admin_panel_settings_outlined,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Quản trị',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push('/admin');
                  },
                ),
              ListTile(
                leading: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Cài đặt',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/settings');
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.menu_book_outlined,
                  color: Colors.white,
                ),
                title: const Text(
                  'Hướng dẫn sử dụng',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_openHelpPage(context));
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white),
                title: const Text(
                  'Thông tin ứng dụng',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAppInfoDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.white),
                title: const Text(
                  'Đăng xuất',
                  style: TextStyle(color: Colors.white, fontSize: 16),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAppInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.primaryBlue),
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
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _version.isNotEmpty ? 'Version $_version' : '',
              style: const TextStyle(fontSize: 14, color: AppColors.neutral500),
            ),
            const SizedBox(height: 12),
            const Text(
              'Dev by Hoang Nguyen aka Hoàng Học Hỏi',
              style: TextStyle(fontSize: 13, color: AppColors.neutral600),
            ),
            const SizedBox(height: 16),
            Text(
              'Kết nối con người. Đồng bộ vận hành.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.neutral600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Đóng',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
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

    return Card(
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
        title: const Text(
          'Đọc loa tiền vào',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(statusText),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
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
    final fallbackAvatar = Text(
      initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        gradient: GradientHeader.getGradient(context),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18),
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
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  'PhongVu OpsHub',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hỗ trợ',
                onPressed: onSupport,
                icon: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                ),
              ),
              const IconTheme(
                data: IconThemeData(color: Colors.white),
                child: AppNotificationsBell(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InkWell(
                onTap: onProfile,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.store_outlined,
                          color: Colors.white70,
                          size: 15,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            storeInfo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
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
