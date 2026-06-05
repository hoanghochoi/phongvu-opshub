import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';

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
    final canUseVietQr = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('VIETQR') == true,
    );
    final canUsePaymentMonitor = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canUseFeature('PAYMENT_MONITOR') == true,
    );
    final supportsPaymentMonitor =
        AppPlatformCapabilities.isPaymentMonitorSupported();
    final actions = _buildHomeActions(
      context,
      isAdmin,
      canUseFifoMenu,
      canUseWarranty,
      canUseBankStatements,
      canUseVietQr,
      canUsePaymentMonitor,
      supportsPaymentMonitor,
    );

    return Scaffold(
      drawer: _buildDrawer(context),
      body: Column(
        children: [
          Builder(
            builder: (scaffoldContext) {
              return Selector<
                AuthProvider,
                ({String userName, String storeInfo})
              >(
                selector: (_, auth) => (
                  userName: auth.user?.name ?? auth.user?.email ?? '',
                  storeInfo: auth.user?.storeInfo ?? 'Chưa chọn showroom',
                ),
                builder: (context, data, _) {
                  return _CompactHomeHeader(
                    userName: data.userName,
                    storeInfo: data.storeInfo,
                    onMenu: () => Scaffold.of(scaffoldContext).openDrawer(),
                    onProfile: () => context.push('/profile'),
                    onLogout: () => _logout(context),
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
                  if (canUsePaymentMonitor && supportsPaymentMonitor) ...[
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
    bool canUseVietQr,
    bool canUsePaymentMonitor,
    bool supportsPaymentMonitor,
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
      if (canUsePaymentMonitor && supportsPaymentMonitor)
        AppFeatureAction(
          icon: Icons.volume_up_rounded,
          title: 'Tiền vào',
          description: 'Cập nhật giao dịch',
          color: AppColors.violet600,
          onTap: () => context.push('/payment-monitor'),
        ),
    ];
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().logout();
    if (context.mounted) {
      context.go('/login');
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
                  Icons.question_answer_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Phản hồi',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/feedback');
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
    final canToggle = monitor.canMonitorOnThisDevice && monitor.hasMonitorScope;
    final speakerEnabled = monitor.isSpeakerEnabled;
    final statusText = monitor.isActive
        ? speakerEnabled
              ? 'Đang cập nhật, có đọc loa'
              : 'Đang cập nhật, đã tắt loa'
        : canToggle
        ? 'Đang chuẩn bị cập nhật'
        : 'Chọn showroom để dùng';

    return Card(
      child: SwitchListTile.adaptive(
        value: speakerEnabled && canToggle,
        onChanged: canToggle
            ? (value) => context
                  .read<PaymentMonitorProvider>()
                  .setSpeakerEnabled(value)
            : null,
        secondary: Icon(
          speakerEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: speakerEnabled ? AppColors.success : AppColors.neutral500,
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
  final VoidCallback onMenu;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  const _CompactHomeHeader({
    required this.userName,
    required this.storeInfo,
    required this.onMenu,
    required this.onProfile,
    required this.onLogout,
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
                tooltip: 'Đăng xuất',
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded, color: Colors.white),
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
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                            maxLines: 1,
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
