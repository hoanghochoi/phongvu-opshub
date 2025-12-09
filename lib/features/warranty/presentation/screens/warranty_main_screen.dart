import 'package:flutter/material.dart';
import '../../../../app/theme/app_theme.dart';

class WarrantyMainScreen extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const WarrantyMainScreen({
    super.key,
    this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảo hành/Sửa chữa'),
        leading: onBackToHome != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBackToHome,
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Lưu hình ảnh
              _FeatureButton(
                icon: Icons.add_photo_alternate,
                title: 'Lưu hình ảnh',
                description: 'Ghi nhận số biên nhận và hình ảnh sản phẩm bảo hành/sửa chữa',
                color: AppTheme.iconColor,
                route: '/warranty',
              ),
              const SizedBox(height: 12),

              // Xem lại hình ảnh
              _FeatureButton(
                icon: Icons.search,
                title: 'Xem lại hình ảnh',
                description: 'Tìm kiếm và xem lại hình ảnh theo số biên nhận',
                color: AppTheme.iconColor,
                route: '/check-warranty',
              ),
              const Spacer(),
            ],
          ),
        ),
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
