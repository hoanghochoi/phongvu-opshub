import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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
  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final userName = authProvider.user?.name ?? authProvider.user?.email ?? '';
    final storeInfo = authProvider.user?.storeInfo ?? '#N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('PhongVu OpsHub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await authProvider.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome message
                Text(
                  'Xin chào,',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  userName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                // Store information
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.store,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          storeInfo,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Chức năng
                Text(
                  'Chức năng',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),

                // Chat với BOT
                _FeatureButton(
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat với BOT',
                  description: 'Trò chuyện với trợ lý AI (Mới chỉ có FIFO thôi =))',
                  color: AppTheme.iconColor,
                  onTap: widget.onTabChange != null ? () => widget.onTabChange!(0) : null,
                ),
                const SizedBox(height: 24),

                // Bảo hành/Sửa chữa
                _FeatureButton(
                  icon: Icons.build_circle_outlined,
                  title: 'Bảo hành/Sửa chữa',
                  description: 'Lưu và xem lại hình ảnh BH/SC',
                  color: AppTheme.iconColor,
                  onTap: widget.onTabChange != null ? () => widget.onTabChange!(2) : null,
                ),
                const SizedBox(height: 24),

                // Sắp xếp hàng hóa
                _FeatureButton(
                  icon: Icons.inventory_2_outlined,
                  title: 'Sắp xếp hàng hóa',
                  description: 'Quét hoặc nhập SKU/BIN để sắp xếp',
                  color: AppTheme.iconColor,
                  route: '/sort',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.primaryBlue,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.store,
                          size: 28,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
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
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, thickness: 1),

            // Menu items
            ListTile(
              leading: const Icon(Icons.feedback_outlined, color: Colors.white),
              title: const Text(
                'Phản hồi',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              onTap: () {
                Navigator.of(context).pop(); // Close drawer
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
                Navigator.of(context).pop(); // Close drawer
                _showAppInfoDialog(context);
              },
            ),

            // Placeholder for future menu items
            // Add more ListTile widgets here as needed

            const Spacer(),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Version 1.0.0',
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
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              const Text('Thông tin ứng dụng'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // App name and version
                Text(
                  'PhongVu OpsHub',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 20),

                // Main features
                const Text(
                  'Chức năng chính:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildFeatureItem('💬 Chat với BOT AI hỗ trợ'),
                _buildFeatureItem('🔧 Quản lý bảo hành/sửa chữa'),
                _buildFeatureItem('📸 Lưu trữ hình ảnh sản phẩm'),
                _buildFeatureItem('🔍 Tra cứu thông tin bảo hành'),
                const SizedBox(height: 20),

                // Developer info
                const Text(
                  'Người phát triển:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hoàng Học Hỏi',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () {
                    // TODO: Open email client
                  },
                  child: const Text(
                    'hoanghochoi1618@gmail.com',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Footer
                Text(
                  'Kết nối con người. Đồng bộ vận hành.',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final String? route;
  final VoidCallback? onTap;

  const _FeatureButton({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    this.route,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Card(
        elevation: 2,
        child: InkWell(
          onTap: onTap ?? (route != null ? () => Navigator.of(context).pushNamed(route!) : null),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 40,
                    color: color,
                  ),
                ),
                const SizedBox(width: 16),

                // Text
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Arrow icon
                Icon(
                  Icons.arrow_forward_ios,
                  size: 20,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
