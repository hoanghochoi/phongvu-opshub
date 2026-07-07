import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_organization_node.dart';
import '../../domain/admin_policy_definition.dart';
import '../../domain/admin_role_definition.dart';

class PolicyAdminScreen extends StatefulWidget {
  final AuthRepository? repository;

  const PolicyAdminScreen({super.key, this.repository});

  @override
  State<PolicyAdminScreen> createState() => _PolicyAdminScreenState();
}

class _PolicyAdminScreenState extends State<PolicyAdminScreen> {
  late final AuthRepository _repository;
  List<AdminPolicyDefinition> _policies = [];
  List<AdminPolicyRule> _rules = [];
  List<AdminSettingDefinition> _settings = [];
  List<AdminOrganizationNode> _organizationNodes = [];
  String? _rulePolicyFilter;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AuthRepository(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy management load started',
        context: {'policyFilter': _rulePolicyFilter},
      );
      final results = await Future.wait([
        _repository.listAdminPolicies(),
        _repository.listAdminPolicyRules(policyCode: _rulePolicyFilter),
        _repository.listAdminSettings(),
        _repository.listAdminPolicyScopeTree(),
      ]);
      if (!mounted) return;
      setState(() {
        _policies = results[0] as List<AdminPolicyDefinition>;
        _rules = results[1] as List<AdminPolicyRule>;
        _settings = results[2] as List<AdminSettingDefinition>;
        _organizationNodes = results[3] as List<AdminOrganizationNode>;
        _errorMessage = null;
      });
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy management load succeeded',
        context: {
          'policies': _policies.length,
          'rules': _rules.length,
          'settings': _settings.length,
          'organizationNodes': _organizationNodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Policy management load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'policyFilter': _rulePolicyFilter,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(() => _errorMessage = 'Chưa tải được quản lý chính sách.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPolicyEditor([AdminPolicyDefinition? policy]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _PolicyEditorDialog(repository: _repository, policy: policy),
    );
    if (updated == true) await _load();
  }

  Future<void> _openRuleEditor([AdminPolicyRule? rule]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _PolicyRuleEditorDialog(
        repository: _repository,
        rule: rule,
        policies: _policies,
        organizationNodes: _organizationNodes,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _openSettingEditor([AdminSettingDefinition? setting]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _SettingEditorDialog(repository: _repository, setting: setting),
    );
    if (updated == true) await _load();
  }

  Future<void> _deletePolicy(AdminPolicyDefinition policy) async {
    final confirmed = await _confirm('Xóa chính sách "${policy.title}"?');
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminPolicies',
        'Policy delete started',
        context: {'policyCode': policy.code},
      );
      await _repository.deleteAdminPolicy(policy.code);
      await AppLogger.instance.warn(
        'AdminPolicies',
        'Policy delete succeeded',
        context: {'policyCode': policy.code},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Policy delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'policyCode': policy.code},
      );
      if (mounted) {
        _showMessage('Chưa xóa được chính sách. Có thể còn quy tắc liên quan.');
      }
    }
  }

  Future<void> _deleteRule(AdminPolicyRule rule) async {
    final id = rule.id;
    if (id == null || id.isEmpty) return;
    final confirmed = await _confirm(
      'Xóa quy tắc của ${_policyTitle(rule.policyCode)}?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminPolicies',
        'Policy rule delete started',
        context: {'ruleId': id, 'policyCode': rule.policyCode},
      );
      await _repository.deleteAdminPolicyRule(id);
      await AppLogger.instance.warn(
        'AdminPolicies',
        'Policy rule delete succeeded',
        context: {'ruleId': id, 'policyCode': rule.policyCode},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Policy rule delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'ruleId': id, 'policyCode': rule.policyCode},
      );
      if (mounted) _showMessage('Chưa xóa được quy tắc.');
    }
  }

  Future<bool> _confirm(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận'),
            content: Text(message),
            actions: [
              AppDialogCancelButton(
                onPressed: () => Navigator.of(context).pop(false),
              ),
              AppDialogConfirmButton(
                onPressed: () => Navigator.of(context).pop(true),
                label: 'Xóa',
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    AppToast.show(context, SnackBar(content: Text(message)));
  }

  String _policyTitle(String code) {
    for (final policy in _policies) {
      if (policy.code == code) return policy.title;
    }
    return 'Chính sách chưa đồng bộ';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AppResponsiveContent(
        onRefresh: _load,
        refreshLogSource: 'AdminPolicies',
        refreshLogContext: () => {
          'policyCount': _policies.length,
          'ruleCount': _rules.length,
          'settingCount': _settings.length,
          'policyFilter': _rulePolicyFilter,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PolicyAdminHeader(
              loading: _loading,
              policyCount: _policies.length,
              ruleCount: _rules.length,
              settingCount: _settings.length,
              onRefresh: _loading ? null : _load,
              onCreatePolicy: _loading ? null : () => _openPolicyEditor(),
              onCreateRule: _loading ? null : () => _openRuleEditor(),
              onCreateSetting: _loading ? null : () => _openSettingEditor(),
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
            AppSurfaceCard(
              key: const Key('policy-admin-tabs'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                indicatorColor: AppColors.primary,
                dividerColor: AppColors.transparent,
                tabs: const [
                  Tab(text: 'Chính sách'),
                  Tab(text: 'Quy tắc'),
                  Tab(text: 'Cấu hình'),
                ],
              ),
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppListSkeleton(itemCount: 6, itemHeight: 92);
    }

    if (_errorMessage != null) {
      return AppStatePanel.error(
        title: _errorMessage!,
        message: 'Kiểm tra kết nối rồi thử tải lại dữ liệu chính sách.',
        actionLabel: 'Thử tải lại',
        actionIcon: Icons.refresh,
        onAction: _load,
      );
    }

    return TabBarView(
      children: [_buildPoliciesTab(), _buildRulesTab(), _buildSettingsTab()],
    );
  }

  Widget _buildPoliciesTab() {
    if (_policies.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có chính sách',
        message: 'Bấm nút thêm để tạo chính sách đầu tiên.',
        icon: Icons.policy_outlined,
      );
    }
    return ListView.separated(
      key: const Key('policy-admin-policy-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _policies.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppLayoutTokens.cardGap),
      itemBuilder: (context, index) {
        final policy = _policies[index];
        return _PolicyCard(
          policy: policy,
          onEdit: () => _openPolicyEditor(policy),
          onDelete: policy.isSystem ? null : () => _deletePolicy(policy),
        );
      },
    );
  }

  Widget _buildRulesTab() {
    return Column(
      children: [
        AppSurfaceCard(
          padding: const EdgeInsets.all(12),
          child: AppSelectField<String?>(
            value: _rulePolicyFilter,
            label: 'Lọc theo chính sách',
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tất cả'),
              ),
              ..._policies.map(
                (policy) => DropdownMenuItem<String?>(
                  value: policy.code,
                  child: Text(policy.title),
                ),
              ),
            ],
            onChanged: (value) async {
              setState(() => _rulePolicyFilter = value);
              await _load();
            },
          ),
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        Expanded(
          child: _rules.isEmpty
              ? const AppStatePanel.empty(
                  title: 'Chưa có quy tắc',
                  message: 'Bấm nút thêm để tạo quy tắc đầu tiên.',
                  icon: Icons.rule_folder_outlined,
                )
              : ListView.separated(
                  key: const Key('policy-admin-rule-list'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _rules.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppLayoutTokens.cardGap),
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return _PolicyRuleCard(
                      title: _policyTitle(rule.policyCode),
                      summary: _ruleSummary(rule),
                      rule: rule,
                      onEdit: () => _openRuleEditor(rule),
                      onDelete: () => _deleteRule(rule),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    if (_settings.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có cấu hình',
        message: 'Bấm nút thêm để tạo cấu hình đầu tiên.',
        icon: Icons.tune_outlined,
      );
    }
    return ListView.separated(
      key: const Key('policy-admin-setting-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _settings.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppLayoutTokens.cardGap),
      itemBuilder: (context, index) {
        final setting = _settings[index];
        return _SettingCard(
          setting: setting,
          valuePreview: _compactJson(setting.value),
          onEdit: () => _openSettingEditor(setting),
        );
      },
    );
  }

  String _ruleSummary(AdminPolicyRule rule) {
    final parts = <String>[
      rule.allowed ? 'Cho phép' : 'Chặn',
      if (rule.emailDomain?.isNotEmpty == true)
        'Tên miền email: ${rule.emailDomain}',
      if (rule.systemRole?.isNotEmpty == true)
        'Vai trò: ${AdminRoles.displayTitle(rule.systemRole)}',
      if (rule.organizationNodeName?.isNotEmpty == true)
        'Đơn vị tổ chức: ${rule.organizationNodeName}',
      if (rule.organizationNodeId?.isNotEmpty == true &&
          rule.organizationNodeName == null)
        'Đơn vị tổ chức: Đã chọn đơn vị',
      if (_legacyRuleSummary(rule) != null) 'Điều kiện cũ: Đã cấu hình',
    ];
    return parts.join(' • ');
  }

  String? _legacyRuleSummary(AdminPolicyRule rule) {
    final legacy = [
      if (rule.departmentCode?.isNotEmpty == true)
        'Phòng ban: ${rule.departmentCode}',
      if (rule.jobRoleCode?.isNotEmpty == true)
        'Chức danh: ${rule.jobRoleCode}',
      if (rule.workScopeType?.isNotEmpty == true)
        'Phạm vi: ${rule.workScopeType}',
      if (rule.regionCode?.isNotEmpty == true) 'Miền: ${rule.regionCode}',
      if (rule.areaCode?.isNotEmpty == true) 'Vùng: ${rule.areaCode}',
      if (rule.storeCode?.isNotEmpty == true) 'Showroom: ${rule.storeCode}',
      if (rule.userId?.isNotEmpty == true) 'Người dùng: ${rule.userId}',
      if (rule.scopeContains?.isNotEmpty == true)
        'Có chứa: ${rule.scopeContains}',
    ];
    return legacy.isEmpty ? null : legacy.join(', ');
  }

  String _compactJson(dynamic value) {
    final text = jsonEncode(value);
    return text.length <= 120 ? text : '${text.substring(0, 120)}...';
  }
}

class _PolicyAdminHeader extends StatelessWidget {
  final bool loading;
  final int policyCount;
  final int ruleCount;
  final int settingCount;
  final VoidCallback? onRefresh;
  final VoidCallback? onCreatePolicy;
  final VoidCallback? onCreateRule;
  final VoidCallback? onCreateSetting;

  const _PolicyAdminHeader({
    required this.loading,
    required this.policyCount,
    required this.ruleCount,
    required this.settingCount,
    required this.onRefresh,
    required this.onCreatePolicy,
    required this.onCreateRule,
    required this.onCreateSetting,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('policy-admin-header'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quản lý chính sách',
                style: AppTextStyles.headingM.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Quản trị chính sách, quy tắc áp dụng và cấu hình vận hành.',
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
                    label: loading
                        ? 'Đang tải chính sách'
                        : '$policyCount chính sách',
                    color: AppColors.primary,
                  ),
                  AppStatusChip(
                    label: '$ruleCount quy tắc',
                    color: AppColors.info,
                  ),
                  AppStatusChip(
                    label: '$settingCount cấu hình',
                    color: AppColors.neutral700,
                  ),
                ],
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppLayoutTokens.formInlineGap,
            runSpacing: AppLayoutTokens.formInlineGap,
            alignment: isCompact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              AppIconAction(
                onPressed: onRefresh,
                icon: Icons.refresh,
                tooltip: 'Tải lại chính sách',
              ),
              AppIconAction(
                onPressed: onCreatePolicy,
                icon: Icons.add_box_outlined,
                tooltip: 'Thêm chính sách',
                filled: true,
              ),
              AppIconAction(
                onPressed: onCreateRule,
                icon: Icons.rule_folder_outlined,
                tooltip: 'Thêm quy tắc',
              ),
              AppIconAction(
                onPressed: onCreateSetting,
                icon: Icons.settings_outlined,
                tooltip: 'Thêm cấu hình',
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppLayoutTokens.formFieldGap),
                actions,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final AdminPolicyDefinition policy;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _PolicyCard({
    required this.policy,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PolicyIcon(
            icon: policy.isActive
                ? Icons.policy_outlined
                : Icons.block_outlined,
            color: policy.isActive ? AppColors.info : AppColors.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  policy.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  policy.description.isEmpty
                      ? 'Chưa có mô tả chính sách.'
                      : policy.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusChip(
                      label: policy.isActive ? 'Đang hoạt động' : 'Đã tắt',
                      color: policy.isActive
                          ? AppColors.success
                          : AppColors.error,
                    ),
                    AppStatusChip(
                      label: policy.defaultAllowed
                          ? 'Mặc định cho phép'
                          : 'Mặc định chặn',
                      color: policy.defaultAllowed
                          ? AppColors.success
                          : AppColors.neutral700,
                    ),
                    AppStatusChip(
                      label: '${policy.ruleCount} quy tắc',
                      color: AppColors.info,
                    ),
                    AppStatusChip(
                      label: policy.isSystem ? 'Hệ thống' : 'Tùy chỉnh',
                      color: AppColors.neutral700,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _RowActions(
            onEdit: onEdit,
            onDelete: onDelete,
            deleteTooltip: policy.isSystem
                ? 'Chính sách hệ thống không thể xóa'
                : 'Xóa chính sách',
          ),
        ],
      ),
    );
  }
}

class _PolicyRuleCard extends StatelessWidget {
  final String title;
  final String summary;
  final AdminPolicyRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PolicyRuleCard({
    required this.title,
    required this.summary,
    required this.rule,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PolicyIcon(
            icon: rule.allowed
                ? Icons.check_circle_outline
                : Icons.block_outlined,
            color: rule.allowed ? AppColors.success : AppColors.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary.isEmpty
                      ? 'Áp dụng cho phạm vi đã cấu hình.'
                      : summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppStatusChip(
                      label: rule.allowed ? 'Cho phép' : 'Chặn',
                      color: rule.allowed ? AppColors.success : AppColors.error,
                    ),
                    if (rule.organizationNodeId?.isNotEmpty == true)
                      const AppStatusChip(
                        label: 'Có đơn vị tổ chức',
                        color: AppColors.info,
                      ),
                    if (rule.note?.isNotEmpty == true)
                      const AppStatusChip(
                        label: 'Có ghi chú',
                        color: AppColors.neutral700,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _RowActions(
            onEdit: onEdit,
            onDelete: onDelete,
            deleteTooltip: 'Xóa quy tắc',
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final AdminSettingDefinition setting;
  final String valuePreview;
  final VoidCallback onEdit;

  const _SettingCard({
    required this.setting,
    required this.valuePreview,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PolicyIcon(icon: Icons.tune_outlined, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  setting.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  setting.description.isEmpty
                      ? 'Chưa có mô tả cấu hình.'
                      : setting.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (setting.isSensitive)
                      const AppStatusChip(
                        label: 'Nhạy cảm',
                        color: AppColors.error,
                      ),
                    AppStatusChip(
                      label: 'Giá trị: $valuePreview',
                      color: AppColors.neutral700,
                      maxWidth: 260,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppIconAction(
            onPressed: onEdit,
            icon: Icons.edit_outlined,
            tooltip: 'Sửa cấu hình',
          ),
        ],
      ),
    );
  }
}

class _PolicyIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _PolicyIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _RowActions extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final String deleteTooltip;

  const _RowActions({
    required this.onEdit,
    required this.onDelete,
    required this.deleteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppIconAction(
          onPressed: onEdit,
          icon: Icons.edit_outlined,
          tooltip: 'Sửa',
        ),
        AppIconAction(
          onPressed: onDelete,
          icon: Icons.delete_outline,
          tooltip: deleteTooltip,
        ),
      ],
    );
  }
}

class _PolicyEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminPolicyDefinition? policy;

  const _PolicyEditorDialog({required this.repository, this.policy});

  @override
  State<_PolicyEditorDialog> createState() => _PolicyEditorDialogState();
}

class _PolicyEditorDialogState extends State<_PolicyEditorDialog> {
  late final TextEditingController _code;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late bool _defaultAllowed;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _code = TextEditingController(text: policy?.code ?? '');
    _title = TextEditingController(text: policy?.title ?? '');
    _description = TextEditingController(text: policy?.description ?? '');
    _category = TextEditingController(text: policy?.category ?? 'GENERAL');
    _defaultAllowed = policy?.defaultAllowed ?? false;
    _isActive = policy?.isActive ?? true;
  }

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _description.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final policy = AdminPolicyDefinition(
      code: _code.text.trim(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category.text.trim().isEmpty
          ? 'GENERAL'
          : _category.text.trim(),
      defaultAllowed: _defaultAllowed,
      isActive: _isActive,
    );
    try {
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy save started',
        context: {'policyCode': policy.code, 'isEdit': widget.policy != null},
      );
      if (widget.policy == null) {
        await widget.repository.createAdminPolicy(policy);
      } else {
        await widget.repository.updateAdminPolicy(widget.policy!.code, policy);
      }
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy save succeeded',
        context: {'policyCode': policy.code},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Policy save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'policyCode': policy.code},
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Chưa lưu được chính sách.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.policy == null ? 'Thêm chính sách' : 'Sửa chính sách'),
      content: SingleChildScrollView(
        child: AppFormColumn(
          children: [
            AppTextInput(controller: _code, label: 'Mã chính sách'),
            AppTextInput(controller: _title, label: 'Tên hiển thị'),
            AppTextInput(controller: _description, label: 'Mô tả'),
            AppTextInput(controller: _category, label: 'Nhóm'),
            SwitchListTile(
              value: _defaultAllowed,
              onChanged: (value) => setState(() => _defaultAllowed = value),
              title: const Text('Mặc định bật khi không có quy tắc'),
            ),
            SwitchListTile(
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              title: const Text('Đang hoạt động'),
            ),
          ],
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppDialogConfirmButton(
          onPressed: _saving ? null : _save,
          label: _saving ? 'Đang lưu...' : 'Lưu',
          isLoading: _saving,
        ),
      ],
    );
  }
}

class _PolicyRuleEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminPolicyRule? rule;
  final List<AdminPolicyDefinition> policies;
  final List<AdminOrganizationNode> organizationNodes;

  const _PolicyRuleEditorDialog({
    required this.repository,
    required this.policies,
    required this.organizationNodes,
    this.rule,
  });

  @override
  State<_PolicyRuleEditorDialog> createState() =>
      _PolicyRuleEditorDialogState();
}

class _PolicyRuleEditorDialogState extends State<_PolicyRuleEditorDialog> {
  late String _policyCode;
  late bool _allowed;
  late final TextEditingController _emailDomains;
  late final TextEditingController _systemRoles;
  late final TextEditingController _note;
  final Set<String> _organizationNodeIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _policyCode =
        rule?.policyCode ??
        (widget.policies.isNotEmpty ? widget.policies.first.code : 'ADMIN');
    _allowed = rule?.allowed ?? true;
    _emailDomains = TextEditingController(text: rule?.emailDomain ?? '');
    _systemRoles = TextEditingController(text: rule?.systemRole ?? '');
    final organizationNodeId = rule?.organizationNodeId;
    if (organizationNodeId != null && organizationNodeId.isNotEmpty) {
      _organizationNodeIds.add(organizationNodeId);
    }
    _note = TextEditingController(text: rule?.note ?? '');
  }

  @override
  void dispose() {
    for (final controller in [_emailDomains, _systemRoles, _note]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _csv(TextEditingController controller) => controller.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    final emailDomains = _csv(_emailDomains);
    final systemRoles = _csv(_systemRoles);
    final organizationNodeIds = _organizationNodeIds.toList()..sort();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (organizationNodeIds.isEmpty) {
      await AppLogger.instance.warn(
        'AdminPolicies',
        'Policy rule save blocked without organization node',
        context: {'policyCode': _policyCode, 'isEdit': widget.rule != null},
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Chọn đơn vị tổ chức cho quy tắc.')),
        );
        setState(() => _saving = false);
      }
      return;
    }
    try {
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy rule save started',
        context: {
          'policyCode': _policyCode,
          'isEdit': widget.rule != null,
          'domainCount': emailDomains.length,
          'roleCount': systemRoles.length,
          'organizationNodeCount': organizationNodeIds.length,
        },
      );
      if (widget.rule?.id == null) {
        await widget.repository.createAdminPolicyRulesBatch(
          AdminPolicyRuleBatchRequest(
            policyCode: _policyCode,
            allowed: _allowed,
            emailDomains: emailDomains,
            systemRoles: systemRoles,
            organizationNodeIds: organizationNodeIds,
            note: note,
          ),
        );
      } else {
        await widget.repository.updateAdminPolicyRule(
          widget.rule!.id!,
          AdminPolicyRule(
            policyCode: _policyCode,
            allowed: _allowed,
            emailDomain: emailDomains.isEmpty ? null : emailDomains.first,
            systemRole: systemRoles.isEmpty ? null : systemRoles.first,
            organizationNodeId: organizationNodeIds.isEmpty
                ? null
                : organizationNodeIds.first,
            note: note,
          ),
        );
      }
      await AppLogger.instance.info(
        'AdminPolicies',
        'Policy rule save succeeded',
        context: {
          'policyCode': _policyCode,
          'isEdit': widget.rule != null,
          'organizationNodeCount': organizationNodeIds.length,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Policy rule save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'policyCode': _policyCode,
          'isEdit': widget.rule != null,
          'organizationNodeCount': organizationNodeIds.length,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Chưa lưu được quy tắc.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? 'Thêm quy tắc' : 'Sửa quy tắc'),
      content: SingleChildScrollView(
        child: AppFormColumn(
          children: [
            AppSelectField<String>(
              value: _policyCode,
              label: 'Chính sách',
              items: widget.policies
                  .map(
                    (policy) => DropdownMenuItem(
                      value: policy.code,
                      child: Text(policy.title),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _policyCode = value ?? _policyCode),
            ),
            SwitchListTile(
              value: _allowed,
              onChanged: (value) => setState(() => _allowed = value),
              title: Text(_allowed ? 'Cho phép' : 'Chặn'),
            ),
            _csvField(_emailDomains, 'Tên miền email'),
            _csvField(_systemRoles, 'Vai trò hệ thống'),
            _organizationNodePicker(),
            AppTextInput(controller: _note, label: 'Ghi chú'),
          ],
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppDialogConfirmButton(
          onPressed: _saving ? null : _save,
          label: _saving ? 'Đang lưu...' : 'Lưu',
          isLoading: _saving,
        ),
      ],
    );
  }

  Widget _csvField(TextEditingController controller, String label) {
    return AppTextInput(
      controller: controller,
      label: label,
      helperText: 'Có thể nhập nhiều giá trị, phân tách bằng dấu phẩy',
    );
  }

  Widget _organizationNodePicker() {
    final items = _organizationNodeItems();
    final selectedLabels = items
        .where((item) => _organizationNodeIds.contains(item.$1))
        .map((item) => item.$2)
        .toList();
    final isEditing = widget.rule != null;
    return InkWell(
      onTap: _saving
          ? null
          : () async {
              final values = await showDialog<Set<String>>(
                context: context,
                builder: (context) => _PolicyNodeSelectDialog(
                  allowMultiple: !isEditing,
                  items: items,
                  selectedValues: _organizationNodeIds,
                ),
              );
              if (values == null) return;
              setState(() {
                _organizationNodeIds
                  ..clear()
                  ..addAll(values);
              });
            },
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InputDecorator(
        decoration: appInputDecoration(label: 'Đơn vị tổ chức'),
        child: Text(
          selectedLabels.isEmpty
              ? 'Chưa chọn đơn vị'
              : selectedLabels.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  List<(String, String)> _organizationNodeItems() {
    final byId = {for (final node in widget.organizationNodes) node.id: node};
    return widget.organizationNodes
        .where((node) => node.isActive)
        .map(
          (node) => (
            node.id,
            '${AdminOrganizationNodeTypes.titleOf(node.type)} • ${node.businessCode ?? node.storeId ?? node.code} • ${_breadcrumbFor(node, byId)}',
          ),
        )
        .toList();
  }

  String _breadcrumbFor(
    AdminOrganizationNode node,
    Map<String, AdminOrganizationNode> byId,
  ) {
    final names = <String>[];
    AdminOrganizationNode? cursor = node;
    for (var guard = 0; cursor != null && guard < 20; guard += 1) {
      names.add(cursor.title);
      final parentId = cursor.parentId;
      cursor = parentId == null ? null : byId[parentId];
    }
    return names.reversed.join(' / ');
  }
}

class _PolicyNodeSelectDialog extends StatefulWidget {
  final bool allowMultiple;
  final List<(String, String)> items;
  final Set<String> selectedValues;

  const _PolicyNodeSelectDialog({
    required this.allowMultiple,
    required this.items,
    required this.selectedValues,
  });

  @override
  State<_PolicyNodeSelectDialog> createState() =>
      _PolicyNodeSelectDialogState();
}

class _PolicyNodeSelectDialogState extends State<_PolicyNodeSelectDialog> {
  final _searchController = TextEditingController();
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selectedValues};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filteredItems = query.isEmpty
        ? widget.items
        : widget.items
              .where(
                (item) =>
                    item.$1.toLowerCase().contains(query) ||
                    item.$2.toLowerCase().contains(query),
              )
              .toList();
    return AlertDialog(
      title: const Text('Đơn vị tổ chức'),
      content: SizedBox(
        width: 560,
        height: 560,
        child: Column(
          children: [
            AppTextInput(
              controller: _searchController,
              label: 'Tìm đơn vị',
              icon: Icons.search,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredItems.isEmpty
                  ? const AppStatePanel.empty(
                      title: 'Không tìm thấy đơn vị',
                      message: 'Thử đổi từ khóa tìm kiếm.',
                      icon: Icons.search_off_rounded,
                      compact: true,
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final selected = _selected.contains(item.$1);
                        return CheckboxListTile(
                          value: selected,
                          title: Text(
                            item.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(item.$1),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              if (!widget.allowMultiple) _selected.clear();
                              _selected.add(item.$1);
                            } else {
                              _selected.remove(item.$1);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: () => setState(_selected.clear),
          label: 'Bỏ chọn',
        ),
        AppDialogCancelButton(onPressed: () => Navigator.of(context).pop(null)),
        AppDialogConfirmButton(
          onPressed: () => Navigator.of(context).pop({..._selected}),
          label: 'Áp dụng',
        ),
      ],
    );
  }
}

class _SettingEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminSettingDefinition? setting;

  const _SettingEditorDialog({required this.repository, this.setting});

  @override
  State<_SettingEditorDialog> createState() => _SettingEditorDialogState();
}

class _SettingEditorDialogState extends State<_SettingEditorDialog> {
  late final TextEditingController _key;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final setting = widget.setting;
    _key = TextEditingController(text: setting?.key ?? '');
    _title = TextEditingController(text: setting?.title ?? '');
    _description = TextEditingController(text: setting?.description ?? '');
    _category = TextEditingController(text: setting?.category ?? 'GENERAL');
    _value = TextEditingController(
      text: setting == null
          ? '[]'
          : const JsonEncoder.withIndent('  ').convert(setting.value),
    );
  }

  @override
  void dispose() {
    _key.dispose();
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    dynamic decoded;
    try {
      decoded = jsonDecode(_value.text);
    } catch (_) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Giá trị cấu hình không đúng định dạng.')),
      );
      return;
    }
    setState(() => _saving = true);
    final setting = AdminSettingDefinition(
      key: _key.text.trim(),
      title: _title.text.trim(),
      description: _description.text.trim(),
      category: _category.text.trim().isEmpty
          ? 'GENERAL'
          : _category.text.trim(),
      value: decoded,
    );
    try {
      await AppLogger.instance.info(
        'AdminPolicies',
        'Setting save started',
        context: {'settingKey': setting.key, 'isEdit': widget.setting != null},
      );
      if (widget.setting == null) {
        await widget.repository.createAdminSetting(setting);
      } else {
        await widget.repository.updateAdminSetting(
          widget.setting!.key,
          setting,
        );
      }
      await AppLogger.instance.info(
        'AdminPolicies',
        'Setting save succeeded',
        context: {'settingKey': setting.key},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPolicies',
        'Setting save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'settingKey': setting.key},
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Chưa lưu được cấu hình.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.setting == null ? 'Thêm cấu hình' : 'Sửa cấu hình'),
      content: SingleChildScrollView(
        child: AppFormColumn(
          children: [
            AppTextInput(controller: _key, label: 'Mã cấu hình'),
            AppTextInput(controller: _title, label: 'Tên hiển thị'),
            AppTextInput(controller: _description, label: 'Mô tả'),
            AppTextInput(controller: _category, label: 'Nhóm'),
            AppTextInput(
              controller: _value,
              minLines: 6,
              maxLines: 12,
              label: 'Giá trị cấu hình',
            ),
          ],
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        AppDialogConfirmButton(
          onPressed: _saving ? null : _save,
          label: _saving ? 'Đang lưu...' : 'Lưu',
          isLoading: _saving,
        ),
      ],
    );
  }
}
