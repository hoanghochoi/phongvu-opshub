import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class AdminMenuScreen extends StatelessWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((auth) => auth.user);
    final supportChatEnabled = context.select<AuthProvider, bool>(
      (auth) => auth.supportChatEnabled,
    );
    bool canUse(String featureCode) => user?.canUseFeature(featureCode) == true;
    final isSuperAdmin = user?.role == 'SUPER_ADMIN';
    final managerRole = {
      'STORE_MANAGER',
      'AREA_MANAGER',
      'REGION_MANAGER',
      'REGIONAL_MANAGER',
    }.contains(user?.jobRoleCode?.trim().toUpperCase());

    final administrationActions = [
      if (canUse('ADMIN_USERS'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.usersThree,
          title: 'Quản lý người dùng',
          description: 'Tài khoản và phạm vi',
          color: AppColors.infoOf(context),
          onTap: () => context.push('/admin/users'),
        ),
      if (canUse('ADMIN_ROLES'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.shield,
          title: 'Quản lý vai trò',
          description: 'Quyền hệ thống',
          color: AppColors.accentOf(context),
          onTap: () => context.push('/admin/roles'),
        ),
      if (canUse('ADMIN_ORG_TREE'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.treeStructure,
          title: 'Cơ cấu tổ chức',
          description: 'Cây tổ chức cấp 0-5',
          color: AppColors.infoOf(context),
          onTap: () => context.push('/admin/organization'),
        ),
      if (canUse('ADMIN_POLICIES'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.shieldCheck,
          title: 'Quản lý chính sách',
          description: 'Quyền và cấu hình hệ thống',
          color: AppColors.warningOf(context),
          onTap: () => context.push('/admin/policies'),
        ),
      if (canUse('ADMIN_FEATURES'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.slidersHorizontal,
          title: 'Quản lý tính năng',
          description: 'Tính năng và quyền truy cập',
          color: AppColors.accentOf(context),
          onTap: () => context.push('/admin/features'),
        ),
      if (canUse('ADMIN_PERSONNEL'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.identificationBadge,
          title: 'Danh mục nhân sự',
          description: 'Phòng ban và chức danh',
          color: AppColors.infoOf(context),
          onTap: () => context.push('/admin/personnel'),
        ),
      if (canUse('ADMIN_SALES_TARGETS'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.chartLineUp,
          title: 'Quản lý doanh số',
          description: 'Chỉ tiêu theo tháng và showroom',
          color: AppColors.secondaryOf(context),
          onTap: () => context.push('/admin/sales-targets'),
        ),
      if (canUse('ADMIN_QUICK_ACTION_CODES') && (isSuperAdmin || managerRole))
        AppFeatureAction(
          icon: PhosphorIconsRegular.qrCode,
          title: 'Quản lý mã',
          description: 'Liên kết QR theo showroom',
          color: AppColors.primaryOf(context),
          onTap: () => context.push('/admin/quick-action-links'),
        ),
      if (canUse('ADMIN_SALES_REPORTS'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.table,
          title: 'Danh sách báo cáo bán hàng',
          description: 'Lọc danh sách và xuất file',
          color: AppColors.secondaryOf(context),
          onTap: () {
            unawaited(
              AppLogger.instance.info(
                'Admin',
                'Sales report admin list selected',
                context: {
                  'route': '/admin/sales-reports',
                  'userId': user?.id,
                  'storeId': user?.storeId,
                },
              ),
            );
            context.push('/admin/sales-reports');
          },
        ),
      if (isSuperAdmin && supportChatEnabled)
        AppFeatureAction(
          icon: PhosphorIconsRegular.headset,
          title: 'Hỗ trợ nhân viên',
          description: 'Hộp thư hỗ trợ nội bộ',
          color: AppColors.infoOf(context),
          onTap: () => context.push('/admin/support-chats'),
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: PhosphorIconsRegular.plugsConnected,
          title: 'Quản lý kết nối API',
          description: 'Client và khóa ngân hàng',
          color: AppColors.warningOf(context),
          onTap: () {
            unawaited(
              AppLogger.instance.info(
                'Admin',
                'API connection administration selected',
                context: {'route': '/admin/api-connections'},
              ),
            );
            context.push('/admin/api-connections');
          },
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: PhosphorIconsRegular.bookOpen,
          title: 'Quản lý hướng dẫn',
          description: 'Nội dung runtime công khai',
          color: AppColors.secondaryOf(context),
          onTap: () => context.push('/admin/help-content'),
        ),
      if (isSuperAdmin)
        AppFeatureAction(
          icon: PhosphorIconsRegular.lightbulb,
          title: 'Danh sách góp ý',
          description: 'Góp ý nội bộ',
          color: AppColors.secondaryOf(context),
          onTap: () => context.push('/admin/feedback'),
        ),
    ];
    final fifoActions = [
      if (canUse('FIFO_IMPORT'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.package,
          title: 'Cập nhật tồn kho',
          description: 'Nhập dữ liệu tồn kho FIFO',
          color: AppColors.infoOf(context),
          onTap: () => context.push('/admin/inventory-import'),
        ),
      if (canUse('FIFO'))
        AppFeatureAction(
          icon: PhosphorIconsRegular.clockCounterClockwise,
          title: 'Lịch sử FIFO',
          description: 'Tra cứu lịch sử kiểm tra và sắp xếp',
          color: AppColors.secondaryOf(context),
          onTap: () => context.push('/fifo-history'),
        ),
    ];
    final hasActions =
        administrationActions.isNotEmpty || fifoActions.isNotEmpty;

    return AppResponsiveScrollView(
      onRefresh: context.read<AuthProvider>().refreshUserData,
      refreshLogSource: 'Admin',
      refreshLogContext: () => {
        'administrationActionCount': administrationActions.length,
        'fifoActionCount': fifoActions.length,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hasActions)
            const AppStatePanel.empty(
              title: 'Chưa có tính năng quản trị',
              message: 'Liên hệ quản trị viên để được cấp quyền phù hợp.',
              icon: PhosphorIconsRegular.shield,
            )
          else ...[
            if (administrationActions.isNotEmpty)
              _AdminFeatureSection(
                title: 'Chức năng quản trị',
                actions: administrationActions,
              ),
            if (administrationActions.isNotEmpty && fifoActions.isNotEmpty)
              const SizedBox(height: AppLayoutTokens.sectionGap),
            if (fifoActions.isNotEmpty)
              _AdminFeatureSection(
                key: const Key('admin-fifo-tools-section'),
                title: 'Công cụ FIFO',
                actions: fifoActions,
              ),
          ],
        ],
      ),
    );
  }
}

class _AdminFeatureSection extends StatelessWidget {
  const _AdminFeatureSection({
    super.key,
    required this.title,
    required this.actions,
  });

  final String title;
  final List<AppFeatureAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.headingS.copyWith(
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 980
                ? 4
                : width >= 680
                ? 3
                : width >= 360
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 92,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemBuilder: (context, index) =>
                  _AdminFeatureTile(actions[index]),
            );
          },
        ),
      ],
    );
  }
}

class _AdminFeatureTile extends StatelessWidget {
  const _AdminFeatureTile(this.action);

  final AppFeatureAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Chức năng ${action.title}',
      hint: action.description,
      child: AppSurfaceCard(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.infoSurfaceOf(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  action.icon,
                  color: AppColors.infoOf(context),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                PhosphorIconsRegular.caretRight,
                color: AppColors.primaryOf(context),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
