import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AdminMenuScreen extends StatelessWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((auth) => auth.user);
    bool canUse(String featureCode) => user?.canUseFeature(featureCode) == true;

    final actions = [
      if (canUse('ADMIN_USERS'))
        AppFeatureAction(
          icon: Icons.people_alt_outlined,
          title: 'Quản lý người dùng',
          description: 'Tài khoản và phạm vi',
          color: AppColors.info,
          onTap: () => context.push('/admin/users'),
        ),
      if (canUse('ADMIN_ROLES'))
        AppFeatureAction(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Quản lý vai trò',
          description: 'Quyền hệ thống',
          color: AppColors.violet600,
          onTap: () => context.push('/admin/roles'),
        ),
      if (canUse('ADMIN_STORES'))
        AppFeatureAction(
          icon: Icons.store_mall_directory_outlined,
          title: 'Quản lý SR',
          description: 'Showroom và tài khoản',
          color: AppColors.emerald600,
          onTap: () => context.push('/admin/stores'),
        ),
      if (canUse('ADMIN_REGIONS'))
        AppFeatureAction(
          icon: Icons.account_tree_outlined,
          title: 'Cơ cấu tổ chức',
          description: 'Domain, khối, phòng ban, SR',
          color: AppColors.info,
          onTap: () => context.push('/admin/organization'),
        ),
      if (canUse('ADMIN_REGIONS'))
        AppFeatureAction(
          icon: Icons.map_outlined,
          title: 'Quản lý Vùng/Miền',
          description: 'Miền, Vùng, scope ảo',
          color: AppColors.sky500,
          onTap: () => context.push('/admin/regions'),
        ),
      if (canUse('ADMIN_PERSONNEL'))
        AppFeatureAction(
          icon: Icons.badge_outlined,
          title: 'Phòng ban & Chức danh',
          description: 'Catalog nhân sự',
          color: AppColors.purple600,
          onTap: () => context.push('/admin/personnel'),
        ),
      if (canUse('ADMIN_FEATURES'))
        AppFeatureAction(
          icon: Icons.rule_folder_outlined,
          title: 'Quản lý tính năng',
          description: 'Bật/tắt theo rule',
          color: AppColors.error,
          onTap: () => context.push('/admin/features'),
        ),
      if (canUse('ADMIN_POLICIES'))
        AppFeatureAction(
          icon: Icons.policy_outlined,
          title: 'Quản lý policy',
          description: 'Quyền và cấu hình hệ thống',
          color: AppColors.warning,
          onTap: () => context.push('/admin/policies'),
        ),
    ];

    return Scaffold(
      appBar: const GradientHeader(title: 'Quản trị', showBack: true),
      body: actions.isEmpty
          ? const Center(child: Text('Chưa có tính năng quản trị được bật.'))
          : AppResponsiveContent(child: AppFeatureSection(actions: actions)),
    );
  }
}
