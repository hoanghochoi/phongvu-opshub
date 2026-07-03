import 'dart:async';

import 'package:flutter/material.dart';
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

class ReportWorkspaceScreen extends StatefulWidget {
  const ReportWorkspaceScreen({super.key});

  @override
  State<ReportWorkspaceScreen> createState() => _ReportWorkspaceScreenState();
}

class _ReportWorkspaceScreenState extends State<ReportWorkspaceScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, User?>((auth) => auth.user);
    final actions = _buildActions(context, user);

    _logResolved(actions.length, user);

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReportWorkspaceHeader(actionCount: actions.length),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          if (actions.isEmpty)
            const AppSurfaceCard(
              key: Key('reports-empty-state'),
              child: AppStatePanel.empty(
                icon: Icons.assignment_outlined,
                title: 'Chưa có báo cáo khả dụng',
                message:
                    'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
              ),
            )
          else
            AppFeatureSection(title: 'Báo cáo khả dụng', actions: actions),
        ],
      ),
    );
  }

  List<AppFeatureAction> _buildActions(BuildContext context, User? user) {
    final canSubmitSalesReport = user?.canUseFeature('SALES_REPORT') == true;
    final canAdminSalesReport =
        user?.canUseFeature('ADMIN_SALES_REPORTS') == true;
    return [
      if (canSubmitSalesReport)
        AppFeatureAction(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Báo cáo sale',
          description: 'Đơn chưa báo cáo và form mua/chưa mua',
          color: AppColors.info,
          onTap: () => _openReport(context, '/sales-reports', 'sales_hub'),
        ),
      if (canAdminSalesReport)
        AppFeatureAction(
          icon: Icons.table_chart_outlined,
          title: 'Danh sách báo cáo sale',
          description: 'Lọc danh sách và xuất file',
          color: AppColors.teal600,
          onTap: () =>
              _openReport(context, '/admin/sales-reports', 'sales_admin'),
        ),
    ];
  }

  void _openReport(BuildContext context, String route, String source) {
    unawaited(
      AppLogger.instance.info(
        'Reports',
        'Report workspace action selected',
        context: {'route': route, 'source': source},
      ),
    );
    context.push(route);
  }

  void _logResolved(int actionCount, User? user) {
    final key =
        '$actionCount|${user?.canUseFeature('SALES_REPORT')}|'
        '${user?.canUseFeature('ADMIN_SALES_REPORTS')}';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Reports',
          'Report workspace resolved',
          context: {
            'actionCount': actionCount,
            'hasSalesReport': user?.canUseFeature('SALES_REPORT') == true,
            'hasAdminSalesReports':
                user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
          },
        ),
      );
    });
  }
}

class _ReportWorkspaceHeader extends StatelessWidget {
  final int actionCount;

  const _ReportWorkspaceHeader({required this.actionCount});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('reports-workspace-header'),
      backgroundColor: AppColors.info.withValues(alpha: 0.08),
      borderColor: AppColors.info.withValues(alpha: 0.18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(Icons.assignment_outlined, color: AppColors.info),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lối vào báo cáo', style: AppTextStyles.headingM),
                const SizedBox(height: 6),
                Text(
                  'Tổng hợp các báo cáo vận hành theo quyền tài khoản.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Text(
                  actionCount > 0
                      ? '$actionCount báo cáo khả dụng'
                      : 'Chưa có báo cáo khả dụng',
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
