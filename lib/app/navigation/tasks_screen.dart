import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/logging/app_logger.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_cards.dart';
import '../widgets/app_chips.dart';
import '../widgets/app_feature_grid.dart';
import '../widgets/app_layout.dart';
import '../widgets/app_state_widgets.dart';
import 'app_nav_model.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String _lastLogKey = '';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final destinations = AppNavModel.visibleTaskDestinations(user);
    final hiddenCount = AppNavModel.destinations
        .where((destination) => destination.showInTasks)
        .where(
          (destination) => !AppNavModel.canUseDestination(user, destination),
        )
        .length;

    _logOpen(destinations.length, hiddenCount);

    final actions = [
      for (final destination in destinations)
        AppFeatureAction(
          icon: destination.icon,
          title: destination.label,
          description: destination.description,
          color: destination.color,
          onTap: () {
            unawaited(
              AppLogger.instance.info(
                'Tasks',
                'Workspace opened from task index',
                context: {
                  'destination': destination.id,
                  'route': destination.route,
                },
              ),
            );
            context.go(destination.route);
          },
        ),
    ];

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TasksHeader(
            visibleCount: destinations.length,
            hiddenCount: hiddenCount,
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          if (actions.isEmpty)
            const AppSurfaceCard(
              key: Key('tasks-empty-state'),
              child: AppStatePanel.empty(
                icon: Icons.apps_outlined,
                title: 'Chưa có tác vụ khả dụng',
                message:
                    'Vui lòng liên hệ quản lý để kiểm tra phân quyền truy cập.',
              ),
            )
          else
            AppFeatureSection(title: 'Không gian làm việc', actions: actions),
        ],
      ),
    );
  }

  void _logOpen(int visibleCount, int hiddenCount) {
    final key = '$visibleCount|$hiddenCount';
    if (_lastLogKey == key) return;
    _lastLogKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        AppLogger.instance.info(
          'Tasks',
          'Task index resolved',
          context: {'visibleCount': visibleCount, 'hiddenCount': hiddenCount},
        ),
      );
    });
  }
}

class _TasksHeader extends StatelessWidget {
  final int visibleCount;
  final int hiddenCount;

  const _TasksHeader({required this.visibleCount, required this.hiddenCount});

  @override
  Widget build(BuildContext context) {
    final visibleText = visibleCount == 1
        ? '1 tác vụ khả dụng'
        : '$visibleCount tác vụ khả dụng';
    return AppSurfaceCard(
      key: const Key('tasks-header'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: Icon(
              Icons.apps_rounded,
              color: AppColors.primaryOf(context),
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tác vụ của bạn',
                  style: AppTextStyles.headingS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hiddenCount > 0
                      ? 'Đang hiển thị các không gian làm việc phù hợp với quyền truy cập của bạn.'
                      : 'Chọn không gian làm việc cần xử lý.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppInfoChip(
                      Icons.checklist_rounded,
                      visibleText,
                      color: AppColors.primaryOf(context),
                    ),
                    if (hiddenCount > 0)
                      AppInfoChip(
                        Icons.lock_outline_rounded,
                        '$hiddenCount tác vụ cần thêm quyền',
                        color: AppColors.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
