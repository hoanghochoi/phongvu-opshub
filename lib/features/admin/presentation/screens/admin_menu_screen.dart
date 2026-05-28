import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AdminMenuScreen extends StatelessWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String?>(
      (auth) => auth.user?.role,
    );
    final isSuperAdmin = role == 'SUPER_ADMIN';
    final canImportInventory = role == 'ADMIN' || role == 'SUPER_ADMIN';
    final actions = [
      AppFeatureAction(
        icon: Icons.people_alt_outlined,
        title: 'Quản lý người dùng',
        description: 'Tài khoản và chi nhánh',
        color: const Color(0xFF2563EB),
        onTap: () => context.push('/admin/users'),
      ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Quản lý vai trò',
          description: 'Quyền và phạm vi',
          color: const Color(0xFF7C3AED),
          onTap: () => context.push('/admin/roles'),
        ),
      AppFeatureAction(
        icon: Icons.store_mall_directory_outlined,
        title: 'Quản lý showroom',
        description: 'Chi nhánh, tài khoản chuyển khoản',
        color: const Color(0xFF059669),
        onTap: () => context.push('/admin/stores'),
      ),
      if (canImportInventory)
        AppFeatureAction(
          icon: Icons.upload_file_outlined,
          title: 'Cập nhật tồn kho',
          description: 'Import Excel cho FIFO',
          color: const Color(0xFFDC2626),
          onTap: () => context.push('/admin/inventory-import'),
        ),
    ];

    return Scaffold(
      appBar: const GradientHeader(title: 'Quản trị', showBack: true),
      body: AppResponsiveContent(child: AppFeatureSection(actions: actions)),
    );
  }
}
