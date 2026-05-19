import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onTabChange;

  const HomeScreen({super.key, this.onTabChange});

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
    final actions = _buildHomeActions(context, isAdmin);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
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
                  storeInfo: auth.user?.storeInfo ?? '#N/A',
                ),
                builder: (context, data, _) {
                  return _CompactHomeHeader(
                    userName: data.userName,
                    storeInfo: data.storeInfo,
                    onMenu: () => Scaffold.of(scaffoldContext).openDrawer(),
                    onProfile: () =>
                        Navigator.of(context).pushNamed('/profile'),
                    onLogout: () => _logout(context),
                  );
                },
              );
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppFeatureSection(actions: actions),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      _version.isNotEmpty ? 'v$_version' : '',
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<AppFeatureAction> _buildHomeActions(BuildContext context, bool isAdmin) {
    return [
      if (isAdmin)
        AppFeatureAction(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Quản trị',
          description: 'Users & role',
          color: const Color(0xFF4B5563),
          onTap: () => Navigator.of(context).pushNamed('/admin'),
        ),
      AppFeatureAction(
        icon: Icons.qr_code_scanner_rounded,
        title: 'FIFO',
        description: 'Kiểm tra & sắp xếp',
        color: const Color(0xFF2563EB),
        onTap: () => Navigator.of(context).pushNamed('/fifo-menu'),
      ),
      AppFeatureAction(
        icon: Icons.camera_alt_rounded,
        title: 'BH / SC',
        description: 'Ảnh bảo hành',
        color: const Color(0xFF16A34A),
        onTap: widget.onTabChange != null ? () => widget.onTabChange!(2) : null,
      ),
      AppFeatureAction(
        icon: Icons.qr_code_2_rounded,
        title: 'VietQR',
        description: 'Tạo mã chuyển khoản',
        color: const Color(0xFF0F766E),
        onTap: () => Navigator.of(context).pushNamed('/vietqr'),
      ),
    ];
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthProvider>().logout();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D1B6F),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.hub_rounded,
                      size: 28,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
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
                Navigator.of(context).pushNamed('/profile');
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
                  Navigator.of(context).pushNamed('/admin');
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
                Navigator.of(context).pushNamed('/feedback');
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
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              'Kết nối con người. Đồng bộ vận hành.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
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
    final initials = userName.isNotEmpty ? userName[0].toUpperCase() : '?';

    return Container(
      decoration: const BoxDecoration(
        gradient: GradientHeader.gradient,
        borderRadius: BorderRadius.only(
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
                    fontWeight: FontWeight.w800,
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
                      fontWeight: FontWeight.w800,
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
                        fontWeight: FontWeight.w800,
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
