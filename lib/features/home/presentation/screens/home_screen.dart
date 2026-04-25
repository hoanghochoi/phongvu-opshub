import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/feature_card.dart';
import '../../../../app/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onTabChange;

  const HomeScreen({
    super.key,
    this.onTabChange,
  });

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
    setState(() {
      _version = packageInfo.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Column(
        children: [
          // Gradient Home Header - only rebuilds when user data changes
          Selector<AuthProvider, ({String userName, String storeInfo})>(
            selector: (_, auth) => (
              userName: auth.user?.name ?? auth.user?.email ?? '',
              storeInfo: auth.user?.storeInfo ?? '#N/A',
            ),
            builder: (context, data, _) {
              return GradientHomeHeader(
                userName: data.userName,
                storeInfo: data.storeInfo,
                onLogout: () async {
                  await context.read<AuthProvider>().logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed('/login');
                  }
                },
              );
            },
          ),

          // Feature cards
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chức năng',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // FIFO
                  FeatureCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'FIFO',
                    description: 'Kiểm tra FIFO & Sắp xếp hàng hóa',
                    gradientColors: const [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
                    onTap: () => Navigator.of(context).pushNamed('/fifo-menu'),
                  ),
                  const SizedBox(height: 16),

                  // Bảo hành / Sửa chữa
                  FeatureCard(
                    icon: Icons.camera_alt_rounded,
                    title: 'Bảo hành / Sửa chữa',
                    description: 'Lưu và xem lại hình ảnh BH/SC',
                    gradientColors: const [Color(0xFF2E7D32), Color(0xFF43A047), Color(0xFF66BB6A)],
                    onTap: widget.onTabChange != null ? () => widget.onTabChange!(2) : null,
                  ),
                  const SizedBox(height: 16),

                  // Phản hồi
                  FeatureCard(
                    icon: Icons.question_answer_rounded,
                    title: 'Phản hồi',
                    description: 'Gửi ý kiến và đánh giá',
                    gradientColors: const [Color(0xFF6A1B9A), Color(0xFF8E24AA), Color(0xFFAB47BC)],
                    onTap: () => Navigator.of(context).pushNamed('/feedback'),
                  ),

                  const SizedBox(height: 32),
                  // Version footer
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
      // Drawer
      drawer: _buildDrawer(context),
    );
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
                    child: Icon(Icons.hub_rounded, size: 28, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PhongVu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('OpsHub', style: TextStyle(fontSize: 16, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, thickness: 1),
            ListTile(
              leading: const Icon(Icons.question_answer_rounded, color: Colors.white),
              title: const Text('Phản hồi', style: TextStyle(color: Colors.white, fontSize: 16)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/feedback');
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text('Thông tin ứng dụng', style: TextStyle(color: Colors.white, fontSize: 16)),
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
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
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
            Text('PhongVu OpsHub', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            const SizedBox(height: 4),
            Text(_version.isNotEmpty ? 'Version $_version' : '', style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            Text('Kết nối con người. Đồng bộ vận hành.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[600])),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Đóng'))],
      ),
    );
  }
}