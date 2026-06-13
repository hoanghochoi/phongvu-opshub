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
    final isSuperAdmin = user?.role == 'SUPER_ADMIN';

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
      if (canUse('ADMIN_ORG_TREE'))
        AppFeatureAction(
          icon: Icons.account_tree_outlined,
          title: 'Cơ cấu tổ chức',
          description: 'Logic tree Lv0-Lv5',
          color: AppColors.info,
          onTap: () => context.push('/admin/organization'),
        ),
      if (canUse('ADMIN_POLICIES'))
        AppFeatureAction(
          icon: Icons.policy_outlined,
          title: 'Quản lý policy',
          description: 'Quyền và cấu hình hệ thống',
          color: AppColors.warning,
          onTap: () => context.push('/admin/policies'),
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: Icons.feedback_outlined,
          title: 'Danh sách phản hồi',
          description: 'Phản hồi nội bộ',
          color: AppColors.teal600,
          onTap: () => context.push('/admin/feedback'),
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
