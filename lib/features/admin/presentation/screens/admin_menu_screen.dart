import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
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
          description: 'Cây tổ chức cấp 0-5',
          color: AppColors.info,
          onTap: () => context.push('/admin/organization'),
        ),
      if (canUse('ADMIN_POLICIES'))
        AppFeatureAction(
          icon: Icons.policy_outlined,
          title: 'Quản lý chính sách',
          description: 'Quyền và cấu hình hệ thống',
          color: AppColors.warning,
          onTap: () => context.push('/admin/policies'),
        ),
      if (canUse('ADMIN_FEATURES'))
        AppFeatureAction(
          icon: Icons.tune_outlined,
          title: 'Quản lý tính năng',
          description: 'Tính năng và quyền truy cập',
          color: AppColors.violet600,
          onTap: () => context.push('/admin/features'),
        ),
      if (canUse('ADMIN_PERSONNEL'))
        AppFeatureAction(
          icon: Icons.badge_outlined,
          title: 'Danh mục nhân sự',
          description: 'Phòng ban và chức danh',
          color: AppColors.info,
          onTap: () => context.push('/admin/personnel'),
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: Icons.menu_book_outlined,
          title: 'Quản lý hướng dẫn',
          description: 'Nội dung runtime công khai',
          color: AppColors.secondary,
          onTap: () => context.push('/admin/help-content'),
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Danh sách góp ý',
          description: 'Góp ý nội bộ',
          color: AppColors.teal600,
          onTap: () => context.push('/admin/feedback'),
        ),
    ];

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (actions.isEmpty)
            const AppStatePanel.empty(
              title: 'Chưa có tính năng quản trị',
              message: 'Liên hệ quản trị viên để được cấp quyền phù hợp.',
              icon: Icons.admin_panel_settings_outlined,
            )
          else
            AppFeatureSection(title: 'Chức năng quản trị', actions: actions),
        ],
      ),
    );
  }
}
