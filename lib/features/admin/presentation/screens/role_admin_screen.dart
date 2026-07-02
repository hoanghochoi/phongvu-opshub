import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_role_definition.dart';

class RoleAdminScreen extends StatefulWidget {
  final AuthRepository? repository;

  const RoleAdminScreen({super.key, this.repository});

  @override
  State<RoleAdminScreen> createState() => _RoleAdminScreenState();
}

class _RoleAdminScreenState extends State<RoleAdminScreen> {
  late final AuthRepository _repository;
  List<AdminRoleDefinition> _roles = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AuthRepository(ApiClient());
    _load();
  }

  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    await AppLogger.instance.info('Admin', 'Admin roles screen load started');
    try {
      final roles = await _repository.listAdminRoles();
      stopwatch.stop();
      if (!mounted) return;
      setState(() => _roles = roles);
      await AppLogger.instance.info(
        'Admin',
        'Admin roles screen load succeeded',
        context: {
          'roleCount': roles.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error) {
      stopwatch.stop();
      await AppLogger.instance.error(
        'Admin',
        'Admin roles screen load failed',
        error: error,
        upload: true,
        context: {'durationMs': stopwatch.elapsedMilliseconds},
      );
      if (!mounted) return;
      setState(() => _errorMessage = 'Không tải được danh sách vai trò');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleHeader(
            loading: _loading,
            roleCount: _roles.length,
            onRefresh: _loading ? null : _load,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppListSkeleton(itemCount: 6, itemHeight: 86);
    }

    if (_errorMessage != null) {
      return AppStatePanel.error(
        title: _errorMessage!,
        message: 'Kiểm tra kết nối rồi thử tải lại danh sách vai trò.',
        actionLabel: 'Thử tải lại',
        actionIcon: Icons.refresh,
        onAction: _load,
      );
    }

    if (_roles.isEmpty) {
      return AppStatePanel.empty(
        title: 'Chưa có vai trò',
        message: 'Hệ thống chưa trả về vai trò nào cho phạm vi quản trị.',
        icon: Icons.admin_panel_settings_outlined,
        actionLabel: 'Tải lại',
        actionIcon: Icons.refresh,
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('role-admin-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _roles.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppLayoutTokens.cardGap),
        itemBuilder: (context, index) {
          final role = _roles[index];
          return _RoleCard(role: role);
        },
      ),
    );
  }
}

class _RoleHeader extends StatelessWidget {
  final bool loading;
  final int roleCount;
  final VoidCallback? onRefresh;

  const _RoleHeader({
    required this.loading,
    required this.roleCount,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('role-admin-header'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản lý vai trò',
                style: AppTextStyles.headingM.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Theo dõi các vai trò đang dùng cho phân quyền hệ thống.',
                style: AppTextStyles.bodyM.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              Wrap(
                spacing: AppLayoutTokens.formInlineGap,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: loading ? 'Đang tải vai trò' : '$roleCount vai trò',
                    color: AppColors.primary,
                  ),
                  const AppStatusChip(
                    label: 'Chỉ đọc',
                    color: AppColors.neutral700,
                  ),
                ],
              ),
            ],
          );
          final refreshButton = AppIconAction(
            onPressed: onRefresh,
            icon: Icons.refresh,
            tooltip: 'Tải lại danh sách vai trò',
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                    refreshButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              refreshButton,
            ],
          );
        },
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final AdminRoleDefinition role;

  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: role.color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(role.icon, color: role.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role.description.isEmpty
                      ? 'Chưa có mô tả vai trò'
                      : role.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppStatusChip(
            label: role.isSystem ? 'Hệ thống' : 'Tùy chỉnh',
            color: role.isSystem ? AppColors.primary : AppColors.neutral700,
          ),
        ],
      ),
    );
  }
}
