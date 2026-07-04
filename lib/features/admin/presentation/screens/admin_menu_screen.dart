import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
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
          _AdminMenuHeader(actionCount: actions.length),
          const SizedBox(height: AppLayoutTokens.sectionGap),
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

class _AdminMenuHeader extends StatelessWidget {
  final int actionCount;

  const _AdminMenuHeader({required this.actionCount});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('admin-menu-header'),
      backgroundColor: AppColors.primarySurfaceOf(context),
      borderColor: AppColors.primaryOf(context).withValues(alpha: 0.22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryOf(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: Icon(
              Icons.admin_panel_settings_outlined,
              color: AppColors.primaryOf(context),
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Công cụ theo quyền', style: AppTextStyles.headingM),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Text(
                  actionCount > 0
                      ? '$actionCount chức năng khả dụng'
                      : 'Chưa có chức năng khả dụng',
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.textMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
