import 'package:flutter/material.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_organization_node.dart';
import '../../domain/admin_personnel_definition.dart';
import '../../domain/admin_role_definition.dart';
import '../widgets/node_feature_assignment_dialog.dart';

class FeatureAdminScreen extends StatefulWidget {
  const FeatureAdminScreen({super.key});

  @override
  State<FeatureAdminScreen> createState() => _FeatureAdminScreenState();
}

class _FeatureAdminScreenState extends State<FeatureAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminFeatureDefinition> _features = [];
  List<AdminFeatureRule> _rules = [];
  List<AdminNodeFeatureAssignment> _nodeAssignments = [];
  List<AdminRoleDefinition> _roles = [];
  List<AdminPersonnelDefinition> _departments = [];
  List<AdminPersonnelDefinition> _jobRoles = [];
  List<AdminOrganizationNode> _organizationNodes = [];
  List<User> _users = [];
  String? _ruleFeatureFilter;
  String? _nodeFeatureFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature management load started',
        context: {'featureFilter': _ruleFeatureFilter},
      );
      final results = await Future.wait([
        _repository.listAdminFeatures(),
        _repository.listAdminFeatureRules(featureCode: _ruleFeatureFilter),
        _repository.listAdminFeatureNodeAssignments(
          featureCode: _nodeFeatureFilter,
        ),
        _repository.listAdminRoles(),
        _repository.listAdminDepartments(),
        _repository.listAdminJobRoles(),
        _repository.listAdminOrganizationTree(),
        _repository.listUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _features = results[0] as List<AdminFeatureDefinition>;
        _rules = results[1] as List<AdminFeatureRule>;
        _nodeAssignments = results[2] as List<AdminNodeFeatureAssignment>;
        _roles = results[3] as List<AdminRoleDefinition>;
        _departments = results[4] as List<AdminPersonnelDefinition>;
        _jobRoles = results[5] as List<AdminPersonnelDefinition>;
        _organizationNodes = results[6] as List<AdminOrganizationNode>;
        _users = results[7] as List<User>;
      });
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature management load succeeded',
        context: {
          'features': _features.length,
          'rules': _rules.length,
          'nodeAssignments': _nodeAssignments.length,
          'users': _users.length,
          'organizationNodes': _organizationNodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature management load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) {
        _showMessage('Chưa tải được quản lý tính năng. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFeatureEditor([AdminFeatureDefinition? feature]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _FeatureEditorDialog(repository: _repository, feature: feature),
    );
    if (updated == true) await _load();
  }

  Future<void> _openRuleEditor([AdminFeatureRule? rule]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _FeatureRuleEditorDialog(
        repository: _repository,
        rule: rule,
        features: _features,
        roles: _roles,
        departments: _departments,
        jobRoles: _jobRoles,
        organizationNodes: _organizationNodes,
        users: _users,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _openNodeAssignmentEditor({AdminOrganizationNode? node}) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => NodeFeatureAssignmentDialog(
        repository: _repository,
        nodes: _organizationNodes,
        features: _features,
        assignments: _nodeAssignments,
        initialNode: node,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _editNodeAssignmentGroup(
    AdminNodeFeatureAssignment assignment,
  ) async {
    await _openNodeAssignmentEditor(node: _nodeForAssignment(assignment));
  }

  Future<void> _deleteFeature(AdminFeatureDefinition feature) async {
    final confirmed = await _confirm(
      title: 'Xóa tính năng',
      message: 'Xóa tính năng ${feature.title}?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Feature delete started',
        context: {'featureCode': feature.code},
      );
      await _repository.deleteAdminFeature(feature.code);
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Feature delete succeeded',
        context: {'featureCode': feature.code},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'featureCode': feature.code},
      );
      if (mounted) {
        _showMessage('Chưa xóa được tính năng. Có thể đang có quy tắc.');
      }
    }
  }

  Future<void> _toggleNodeAssignment(
    AdminNodeFeatureAssignment assignment,
    bool enabled,
  ) async {
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Node feature assignment toggle started',
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
          'enabled': enabled,
        },
      );
      await _repository.updateAdminFeatureNodeAssignment(
        assignment.id,
        enabled: enabled,
      );
      await AppLogger.instance.info(
        'AdminFeatures',
        'Node feature assignment toggle succeeded',
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
          'enabled': enabled,
        },
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Node feature assignment toggle failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
          'enabled': enabled,
        },
      );
      if (mounted) _showMessage('Chưa cập nhật được quyền đơn vị.');
    }
  }

  Future<void> _deleteNodeAssignment(
    AdminNodeFeatureAssignment assignment,
  ) async {
    final confirmed = await _confirm(
      title: 'Xóa quyền đơn vị',
      message: 'Xóa quyền ${assignment.featureName} khỏi nhóm đơn vị này?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Node feature assignment delete started',
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
          'nodeType': assignment.nodeType,
          'nodeKey': assignment.nodeKey,
        },
      );
      await _repository.deleteAdminFeatureNodeAssignment(assignment.id);
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Node feature assignment delete succeeded',
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
        },
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Node feature assignment delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'assignmentId': assignment.id,
          'featureCode': assignment.featureCode,
        },
      );
      if (mounted) _showMessage('Chưa xóa được quyền đơn vị.');
    }
  }

  Future<void> _deleteRule(AdminFeatureRule rule) async {
    final ruleId = rule.id;
    if (ruleId == null || ruleId.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Xóa quy tắc',
      message: 'Xóa quy tắc của ${_featureTitle(rule.featureCode)}?',
    );
    if (!confirmed) return;
    try {
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Feature rule delete started',
        context: {'ruleId': ruleId, 'featureCode': rule.featureCode},
      );
      await _repository.deleteAdminFeatureRule(ruleId);
      await AppLogger.instance.warn(
        'AdminFeatures',
        'Feature rule delete succeeded',
        context: {'ruleId': ruleId, 'featureCode': rule.featureCode},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature rule delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'ruleId': ruleId, 'featureCode': rule.featureCode},
      );
      if (mounted) _showMessage('Chưa xóa được quy tắc. Vui lòng thử lại.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
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

  String _featureTitle(String code) {
    for (final feature in _features) {
      if (feature.code == code) return feature.title;
    }
    return code;
  }

  AdminOrganizationNode? _nodeForAssignment(
    AdminNodeFeatureAssignment assignment,
  ) {
    for (final nodeId in assignment.organizationNodeIds) {
      for (final node in _organizationNodes) {
        if (node.id == nodeId) return node;
      }
    }
    final assignmentType = AdminOrganizationNode.canonicalType(
      assignment.nodeType,
    );
    final assignmentKey = assignment.nodeKey.trim().toUpperCase();
    for (final node in _organizationNodes) {
      final nodeKey = (node.businessCode ?? node.storeId ?? node.code)
          .trim()
          .toUpperCase();
      if (node.type == assignmentType && nodeKey == assignmentKey) return node;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          AppResponsiveContent(
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quản lý tính năng',
                    style: AppTextStyles.headingM.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppActionRow(
                    desktopAlignment: MainAxisAlignment.start,
                    maxButtonWidth: 210,
                    children: [
                      AppSecondaryButton(
                        onPressed: _loading ? null : () => _openFeatureEditor(),
                        icon: Icons.add_box_outlined,
                        label: 'Thêm tính năng',
                      ),
                      AppSecondaryButton(
                        onPressed: _loading
                            ? null
                            : () => _openNodeAssignmentEditor(),
                        icon: Icons.account_tree_outlined,
                        label: 'Gán đơn vị',
                      ),
                      AppSecondaryButton(
                        onPressed: _loading ? null : () => _openRuleEditor(),
                        icon: Icons.rule_folder_outlined,
                        label: 'Thêm quy tắc cũ',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          AppResponsiveContent(
            child: AppSurfaceCard(
              padding: EdgeInsets.zero,
              child: TabBar(
                labelColor: AppColors.primary,
                unselectedLabelColor: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant,
                indicatorColor: AppColors.primary,
                dividerColor: Theme.of(context).dividerColor,
                tabs: const [
                  Tab(text: 'Tính năng'),
                  Tab(text: 'Theo đơn vị'),
                  Tab(text: 'Quy tắc cũ'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const AppResponsiveContent(
                    child: AppListSkeleton(itemCount: 6, itemHeight: 76),
                  )
                : TabBarView(
                    children: [
                      _FeatureList(
                        features: _features,
                        onRefresh: _load,
                        onEdit: _openFeatureEditor,
                        onDelete: (feature) => feature.isSystem
                            ? null
                            : () {
                                _deleteFeature(feature);
                              },
                      ),
                      _NodeAssignmentList(
                        assignments: _nodeAssignments,
                        features: _features,
                        featureFilter: _nodeFeatureFilter,
                        onFilterChanged: (value) async {
                          setState(() => _nodeFeatureFilter = value);
                          await _load();
                        },
                        onRefresh: _load,
                        onAdd: () => _openNodeAssignmentEditor(),
                        onEdit: _editNodeAssignmentGroup,
                        onToggle: _toggleNodeAssignment,
                        onDelete: _deleteNodeAssignment,
                      ),
                      _RuleList(
                        rules: _rules,
                        features: _features,
                        featureFilter: _ruleFeatureFilter,
                        featureTitle: _featureTitle,
                        onFilterChanged: (value) async {
                          setState(() => _ruleFeatureFilter = value);
                          await _load();
                        },
                        onRefresh: _load,
                        onEdit: _openRuleEditor,
                        onDelete: _deleteRule,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  final List<AdminFeatureDefinition> features;
  final RefreshCallback onRefresh;
  final void Function(AdminFeatureDefinition feature) onEdit;
  final VoidCallback? Function(AdminFeatureDefinition feature) onDelete;

  const _FeatureList({
    required this.features,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có tính năng',
        message: 'Bấm nút thêm để tạo tính năng đầu tiên.',
        icon: Icons.toggle_off_outlined,
      );
    }
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      onRefresh: onRefresh,
      refreshLogSource: 'AdminFeatures',
      refreshLogContext: () => {'tab': 'features', 'count': features.length},
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppLayoutTokens.pagePaddingFor(
          MediaQuery.sizeOf(context).width,
        ),
        itemCount: features.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final feature = features[index];
          return _FeatureCard(
            feature: feature,
            onEdit: () => onEdit(feature),
            onDelete: onDelete(feature),
          );
        },
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final AdminFeatureDefinition feature;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _FeatureCard({
    required this.feature,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = feature.isActive ? AppColors.info : AppColors.neutral500;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.toggle_on_outlined, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${feature.nodeAssignmentCount} đơn vị • ${feature.ruleCount} quy tắc cũ${feature.description.isEmpty ? '' : ' • ${feature.description}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${feature.isActive ? 'Đang bật' : 'Đang tắt'}${feature.isSystem ? ' • hệ thống' : ''}',
                  style: AppTextStyles.labelS.copyWith(
                    color: feature.isActive
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppIconAction(
            onPressed: onEdit,
            icon: Icons.edit_outlined,
            tooltip: 'Sửa',
          ),
          const SizedBox(width: 8),
          AppIconAction(
            onPressed: onDelete,
            icon: Icons.delete_outline,
            tooltip: feature.isSystem ? 'Tính năng hệ thống' : 'Xóa',
          ),
        ],
      ),
    );
  }
}

class _NodeAssignmentList extends StatelessWidget {
  final List<AdminNodeFeatureAssignment> assignments;
  final List<AdminFeatureDefinition> features;
  final String? featureFilter;
  final ValueChanged<String?> onFilterChanged;
  final RefreshCallback onRefresh;
  final VoidCallback onAdd;
  final void Function(AdminNodeFeatureAssignment assignment) onEdit;
  final void Function(AdminNodeFeatureAssignment assignment, bool enabled)
  onToggle;
  final void Function(AdminNodeFeatureAssignment assignment) onDelete;

  const _NodeAssignmentList({
    required this.assignments,
    required this.features,
    required this.featureFilter,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      onRefresh: onRefresh,
      refreshLogSource: 'AdminFeatures',
      refreshLogContext: () => {
        'tab': 'node_assignments',
        'count': assignments.length,
        'featureFilter': featureFilter,
      },
      child: Column(
        children: [
          Padding(
            padding: AppLayoutTokens.pagePaddingFor(
              MediaQuery.sizeOf(context).width,
            ).copyWith(bottom: 0),
            child: Row(
              children: [
                Expanded(
                  child: AppSelectField<String?>(
                    value: featureFilter,
                    label: 'Lọc theo tính năng',
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tất cả'),
                      ),
                      ...features.map(
                        (feature) => DropdownMenuItem<String?>(
                          value: feature.code,
                          child: Text(feature.title),
                        ),
                      ),
                    ],
                    onChanged: onFilterChanged,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 150,
                  child: AppSecondaryButton(
                    onPressed: onAdd,
                    icon: Icons.account_tree_outlined,
                    label: 'Gán đơn vị',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: assignments.isEmpty
                ? const AppStatePanel.empty(
                    title: 'Chưa có quyền theo đơn vị',
                    message: 'Bấm Gán đơn vị để thiết lập phạm vi sử dụng.',
                    icon: Icons.account_tree_outlined,
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppLayoutTokens.pagePaddingFor(
                      MediaQuery.sizeOf(context).width,
                    ).copyWith(top: 0),
                    itemCount: assignments.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final assignment = assignments[index];
                      return _NodeAssignmentCard(
                        assignment: assignment,
                        onEdit: () => onEdit(assignment),
                        onToggle: (enabled) => onToggle(assignment, enabled),
                        onDelete: () => onDelete(assignment),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NodeAssignmentCard extends StatelessWidget {
  final AdminNodeFeatureAssignment assignment;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  const _NodeAssignmentCard({
    required this.assignment,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = assignment.enabled ? AppColors.success : AppColors.error;
    final typeTitle = AdminOrganizationNodeTypes.titleOf(assignment.nodeType);
    final scope = assignment.scopeRootNodeName ?? assignment.scopeRootNodeId;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.account_tree_outlined, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assignment.featureName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$scope • $typeTitle ${assignment.nodeKey} • ${assignment.impactedUserCount} người dùng',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (assignment.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    assignment.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelS,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: assignment.enabled, onChanged: onToggle),
          const SizedBox(width: 8),
          AppIconAction(
            onPressed: onEdit,
            icon: Icons.edit_outlined,
            tooltip: 'Sửa nhóm đơn vị',
          ),
          const SizedBox(width: 8),
          AppIconAction(
            onPressed: onDelete,
            icon: Icons.delete_outline,
            tooltip: 'Xóa quyền đơn vị',
          ),
        ],
      ),
    );
  }
}

class _RuleList extends StatelessWidget {
  final List<AdminFeatureRule> rules;
  final List<AdminFeatureDefinition> features;
  final String? featureFilter;
  final String Function(String code) featureTitle;
  final ValueChanged<String?> onFilterChanged;
  final RefreshCallback onRefresh;
  final void Function(AdminFeatureRule rule) onEdit;
  final void Function(AdminFeatureRule rule) onDelete;

  const _RuleList({
    required this.rules,
    required this.features,
    required this.featureFilter,
    required this.featureTitle,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      onRefresh: onRefresh,
      refreshLogSource: 'AdminFeatures',
      refreshLogContext: () => {
        'tab': 'legacy_rules',
        'count': rules.length,
        'featureFilter': featureFilter,
      },
      child: Column(
        children: [
          Padding(
            padding: AppLayoutTokens.pagePaddingFor(
              MediaQuery.sizeOf(context).width,
            ).copyWith(bottom: 0),
            child: AppSelectField<String?>(
              value: featureFilter,
              label: 'Lọc theo tính năng',
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tất cả'),
                ),
                ...features.map(
                  (feature) => DropdownMenuItem<String?>(
                    value: feature.code,
                    child: Text(feature.title),
                  ),
                ),
              ],
              onChanged: onFilterChanged,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rules.isEmpty
                ? const AppStatePanel.empty(
                    title: 'Chưa có quy tắc cũ',
                    message: 'Chưa có ngoại lệ quyền nào cần hiển thị.',
                    icon: Icons.rule_folder_outlined,
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: AppLayoutTokens.pagePaddingFor(
                      MediaQuery.sizeOf(context).width,
                    ).copyWith(top: 0),
                    itemCount: rules.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final rule = rules[index];
                      return _RuleCard(
                        rule: rule,
                        featureTitle: featureTitle(rule.featureCode),
                        onEdit: () => onEdit(rule),
                        onDelete: () => onDelete(rule),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final AdminFeatureRule rule;
  final String featureTitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.rule,
    required this.featureTitle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = rule.enabled ? AppColors.success : AppColors.error;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              rule.enabled ? Icons.check_circle_outline : Icons.block_outlined,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rule.enabled ? 'Bật' : 'Tắt'} $featureTitle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _ruleScopeText(rule),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (rule.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    rule.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelS,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppIconAction(
            onPressed: onEdit,
            icon: Icons.edit_outlined,
            tooltip: 'Sửa quy tắc',
          ),
          const SizedBox(width: 8),
          AppIconAction(
            onPressed: onDelete,
            icon: Icons.delete_outline,
            tooltip: 'Xóa quy tắc',
          ),
        ],
      ),
    );
  }

  String _ruleScopeText(AdminFeatureRule rule) {
    final parts = [
      if (rule.emailDomain?.isNotEmpty == true)
        'Tên miền email @${rule.emailDomain}',
      if (rule.userEmail?.isNotEmpty == true) 'Người dùng ${rule.userEmail}',
      if (rule.userId?.isNotEmpty == true && rule.userEmail == null)
        'Người dùng ${rule.userId}',
      if (rule.organizationNodeName?.isNotEmpty == true)
        'Đơn vị ${rule.organizationNodeName}',
      if (rule.organizationNodeId?.isNotEmpty == true &&
          rule.organizationNodeName == null)
        'Đơn vị ${rule.organizationNodeId}',
      if (rule.storeCode?.isNotEmpty == true) 'Showroom ${rule.storeCode}',
      if (rule.areaCode?.isNotEmpty == true) 'Vùng ${rule.areaCode}',
      if (rule.regionCode?.isNotEmpty == true) 'Miền ${rule.regionCode}',
      if (rule.workScopeType?.isNotEmpty == true)
        'Phạm vi ${rule.workScopeType}',
      if (rule.jobRoleCode?.isNotEmpty == true) 'Chức danh ${rule.jobRoleCode}',
      if (rule.departmentCode?.isNotEmpty == true)
        'Phòng ban ${rule.departmentCode}',
      if (rule.systemRole?.isNotEmpty == true)
        'Vai trò ${User.roleDisplayName(rule.systemRole)}',
    ];
    return parts.isEmpty
        ? 'Áp dụng toàn hệ thống trong phạm vi quyền cũ'
        : parts.join(' • ');
  }
}

class _FeatureEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminFeatureDefinition? feature;

  const _FeatureEditorDialog({required this.repository, this.feature});

  @override
  State<_FeatureEditorDialog> createState() => _FeatureEditorDialogState();
}

class _FeatureEditorDialogState extends State<_FeatureEditorDialog> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final feature = widget.feature;
    _codeController.text = feature?.code ?? '';
    _titleController.text = feature?.title ?? '';
    _descriptionController.text = feature?.description ?? '';
    _isActive = feature?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final feature = AdminFeatureDefinition(
      code: _codeController.text.trim().toUpperCase(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      isActive: _isActive,
    );
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature save started',
        context: {
          'featureCode': feature.code,
          'mode': widget.feature == null ? 'create' : 'update',
        },
      );
      final current = widget.feature;
      if (current == null) {
        await widget.repository.createAdminFeature(feature);
      } else {
        await widget.repository.updateAdminFeature(current.code, feature);
      }
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature save succeeded',
        context: {'featureCode': feature.code},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'featureCode': feature.code},
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Chưa lưu được tính năng. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.feature?.isSystem == true;
    return AlertDialog(
      title: Text(widget.feature == null ? 'Thêm tính năng' : 'Sửa tính năng'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              AppTextInput(
                controller: _codeController,
                enabled: !isSystem,
                label: 'Mã tính năng',
                textCapitalization: TextCapitalization.characters,
              ),
              AppTextInput(
                controller: _titleController,
                label: 'Tên tính năng',
              ),
              AppTextInput(
                controller: _descriptionController,
                label: 'Mô tả',
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Đang bật'),
              ),
            ],
          ),
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

class _FeatureRuleEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminFeatureRule? rule;
  final List<AdminFeatureDefinition> features;
  final List<AdminRoleDefinition> roles;
  final List<AdminPersonnelDefinition> departments;
  final List<AdminPersonnelDefinition> jobRoles;
  final List<AdminOrganizationNode> organizationNodes;
  final List<User> users;

  const _FeatureRuleEditorDialog({
    required this.repository,
    required this.features,
    required this.roles,
    required this.departments,
    required this.jobRoles,
    required this.organizationNodes,
    required this.users,
    this.rule,
  });

  @override
  State<_FeatureRuleEditorDialog> createState() =>
      _FeatureRuleEditorDialogState();
}

class _FeatureRuleEditorDialogState extends State<_FeatureRuleEditorDialog> {
  final _noteController = TextEditingController();
  final _emailDomainsController = TextEditingController();
  late String _featureCode;
  bool _enabled = true;
  String? _systemRole;
  String? _departmentCode;
  String? _jobRoleCode;
  String? _workScopeType;
  String? _organizationNodeId;
  String? _userId;
  final Set<String> _systemRoles = {};
  final Set<String> _departmentCodes = {};
  final Set<String> _jobRoleCodes = {};
  final Set<String> _workScopeTypes = {};
  final Set<String> _organizationNodeIds = {};
  final Set<String> _userIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _featureCode =
        rule?.featureCode ??
        (widget.features.isEmpty ? '' : widget.features.first.code);
    _enabled = rule?.enabled ?? true;
    _systemRole = rule?.systemRole;
    _departmentCode = rule?.departmentCode;
    _jobRoleCode = rule?.jobRoleCode;
    _workScopeType = rule?.workScopeType;
    _organizationNodeId = rule?.organizationNodeId ?? _legacyNodeIdFor(rule);
    _userId = rule?.userId;
    _emailDomainsController.text = rule?.emailDomain ?? '';
    if (_systemRole != null) _systemRoles.add(_systemRole!);
    if (_departmentCode != null) _departmentCodes.add(_departmentCode!);
    if (_jobRoleCode != null) _jobRoleCodes.add(_jobRoleCode!);
    if (_workScopeType != null) _workScopeTypes.add(_workScopeType!);
    if (_organizationNodeId != null) {
      _organizationNodeIds.add(_organizationNodeId!);
    }
    if (_userId != null) _userIds.add(_userId!);
    _noteController.text = rule?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    _emailDomainsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_featureCode.isEmpty) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Vui lòng chọn tính năng.')),
      );
      return;
    }
    setState(() => _saving = true);
    final current = widget.rule;
    final note = _noteController.text.trim();
    final domainValues = _domainValuesFromController();
    final emailDomain = domainValues.isEmpty ? null : domainValues.first;
    final rule = AdminFeatureRule(
      id: current?.id,
      featureCode: _featureCode,
      enabled: _enabled,
      emailDomain: emailDomain,
      systemRole: _systemRole,
      departmentCode: _departmentCode,
      jobRoleCode: _jobRoleCode,
      workScopeType: _workScopeType,
      regionCode: null,
      areaCode: null,
      organizationNodeId: _organizationNodeId,
      storeCode: null,
      userId: _userId,
      note: note,
    );
    final batchRequest = AdminFeatureRuleBatchRequest(
      featureCode: _featureCode,
      enabled: _enabled,
      emailDomains: domainValues,
      systemRoles: _sortedValues(_systemRoles),
      departmentCodes: _sortedValues(_departmentCodes),
      jobRoleCodes: _sortedValues(_jobRoleCodes),
      workScopeTypes: _sortedValues(_workScopeTypes),
      organizationNodeIds: _sortedValues(_organizationNodeIds),
      userIds: _sortedValues(_userIds),
      note: note,
    );
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature rule save started',
        context: {
          'featureCode': rule.featureCode,
          'enabled': rule.enabled,
          'mode': current == null ? 'batchCreate' : 'update',
          'roleCount': _systemRoles.length,
          'departmentCount': _departmentCodes.length,
          'jobRoleCount': _jobRoleCodes.length,
          'scopeCount': _workScopeTypes.length,
          'organizationNodeCount': _organizationNodeIds.length,
          'userCount': _userIds.length,
          'domainCount': domainValues.length,
        },
      );
      if (current == null) {
        final created = await widget.repository.createAdminFeatureRulesBatch(
          batchRequest,
        );
        await AppLogger.instance.info(
          'AdminFeatures',
          'Feature rule batch save succeeded',
          context: {
            'featureCode': rule.featureCode,
            'count': created.length,
            'domainCount': domainValues.length,
          },
        );
      } else {
        await widget.repository.updateAdminFeatureRule(current.id ?? '', rule);
        await AppLogger.instance.info(
          'AdminFeatures',
          'Feature rule save succeeded',
          context: {
            'featureCode': rule.featureCode,
            'enabled': rule.enabled,
            'domainCount': domainValues.length,
          },
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature rule save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'featureCode': rule.featureCode,
          'enabled': rule.enabled,
          'domainCount': domainValues.length,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Chưa lưu được quy tắc. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _sortedValues(Set<String> values) {
    return values.toList()..sort();
  }

  List<String> _domainValuesFromController() {
    final seen = <String>{};
    final values = <String>[];
    for (final raw in _emailDomainsController.text.split(RegExp(r'[\s,;]+'))) {
      final value = raw.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
      if (value.isEmpty || seen.contains(value)) continue;
      seen.add(value);
      values.add(value);
    }
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.rule != null;
    return AlertDialog(
      title: Text(widget.rule == null ? 'Thêm quy tắc' : 'Sửa quy tắc'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              AppSelectField<String>(
                value: _featureCode.isEmpty ? null : _featureCode,
                label: 'Tính năng',
                items: widget.features
                    .map(
                      (feature) => DropdownMenuItem(
                        value: feature.code,
                        child: Text(feature.title),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _featureCode = value ?? ''),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: Text(_enabled ? 'Bật tính năng' : 'Tắt tính năng'),
              ),
              AppTextInput(
                controller: _emailDomainsController,
                label: 'Tên miền email',
                hintText: isEditing ? 'acare.vn' : 'acare.vn, phongvu.vn',
                keyboardType: TextInputType.emailAddress,
                textInputAction: isEditing
                    ? TextInputAction.next
                    : TextInputAction.newline,
                maxLines: isEditing ? 1 : 2,
              ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Vai trò hệ thống',
                  value: _systemRole,
                  items: widget.roles
                      .map((role) => (role.value, role.title))
                      .toList(),
                  onChanged: (value) => setState(() => _systemRole = value),
                )
              else
                _multiSelectField(
                  label: 'Vai trò hệ thống',
                  selectedValues: _systemRoles,
                  items: widget.roles
                      .map((role) => (role.value, role.title))
                      .toList(),
                  onChanged: (values) => setState(() {
                    _systemRoles
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Phòng ban',
                  value: _departmentCode,
                  items: widget.departments
                      .map((item) => (item.code, item.title))
                      .toList(),
                  onChanged: (value) => setState(() => _departmentCode = value),
                )
              else
                _multiSelectField(
                  label: 'Phòng ban',
                  selectedValues: _departmentCodes,
                  items: widget.departments
                      .map((item) => (item.code, item.title))
                      .toList(),
                  onChanged: (values) => setState(() {
                    _departmentCodes
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Chức danh',
                  value: _jobRoleCode,
                  items: widget.jobRoles
                      .map((item) => (item.code, item.title))
                      .toList(),
                  onChanged: (value) => setState(() => _jobRoleCode = value),
                )
              else
                _multiSelectField(
                  label: 'Chức danh',
                  selectedValues: _jobRoleCodes,
                  items: widget.jobRoles
                      .map((item) => (item.code, item.title))
                      .toList(),
                  onChanged: (values) => setState(() {
                    _jobRoleCodes
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Phạm vi',
                  value: _workScopeType,
                  items: AdminWorkScopes.definitions
                      .map((scope) => (scope.value, scope.title))
                      .toList(),
                  onChanged: (value) => setState(() => _workScopeType = value),
                )
              else
                _multiSelectField(
                  label: 'Phạm vi',
                  selectedValues: _workScopeTypes,
                  items: AdminWorkScopes.definitions
                      .map((scope) => (scope.value, scope.title))
                      .toList(),
                  onChanged: (values) => setState(() {
                    _workScopeTypes
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Đơn vị tổ chức',
                  value: _organizationNodeId,
                  items: _organizationNodeItems(),
                  onChanged: (value) =>
                      setState(() => _organizationNodeId = value),
                )
              else
                _multiSelectField(
                  label: 'Đơn vị tổ chức',
                  selectedValues: _organizationNodeIds,
                  items: _organizationNodeItems(),
                  onChanged: (values) => setState(() {
                    _organizationNodeIds
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              if (isEditing)
                _optionalDropdown(
                  label: 'Người dùng riêng',
                  value: _userId,
                  items: widget.users
                      .where((user) => user.id?.isNotEmpty == true)
                      .map((user) => (user.id!, user.email))
                      .toList(),
                  onChanged: (value) => setState(() => _userId = value),
                )
              else
                _multiSelectField(
                  label: 'Người dùng riêng',
                  selectedValues: _userIds,
                  items: widget.users
                      .where((user) => user.id?.isNotEmpty == true)
                      .map((user) => (user.id!, user.email))
                      .toList(),
                  onChanged: (values) => setState(() {
                    _userIds
                      ..clear()
                      ..addAll(values);
                  }),
                ),
              AppTextInput(
                controller: _noteController,
                label: 'Ghi chú',
                maxLines: 2,
              ),
            ],
          ),
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

  Widget _optionalDropdown({
    required String label,
    required String? value,
    required List<(String, String)> items,
    required ValueChanged<String?> onChanged,
  }) {
    return AppSelectField<String?>(
      value: value,
      label: label,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Không áp dụng'),
        ),
        ...items.map(
          (item) =>
              DropdownMenuItem<String?>(value: item.$1, child: Text(item.$2)),
        ),
      ],
      onChanged: onChanged,
    );
  }

  String? _legacyNodeIdFor(AdminFeatureRule? rule) {
    if (rule == null) return null;
    final storeNode = _nodeIdByTypeAndCode('LV4_STORE', rule.storeCode);
    if (storeNode != null) return storeNode;
    final areaNode = _nodeIdByTypeAndCode('LV3_AREA', rule.areaCode);
    if (areaNode != null) return areaNode;
    return _nodeIdByTypeAndCode('LV2_REGION', rule.regionCode);
  }

  String? _nodeIdByTypeAndCode(String type, String? code) {
    final normalized = _normalizeLegacyCode(code);
    if (normalized == null) return null;
    for (final node in widget.organizationNodes) {
      if (node.type != AdminOrganizationNode.canonicalType(type)) continue;
      final candidates = [
        node.businessCode,
        node.storeId,
        node.code,
        _legacyCodeFromNodeCode(node.code),
      ];
      if (candidates.any((item) => _normalizeLegacyCode(item) == normalized)) {
        return node.id;
      }
    }
    return null;
  }

  String? _normalizeLegacyCode(String? value) {
    final normalized = value?.trim().toUpperCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String _legacyCodeFromNodeCode(String code) {
    return code
        .replaceFirst(
          RegExp(r'^(LV2_REGION|LV3_AREA|REGION|AREA)_(PHONGVU|ACARE)_'),
          '',
        )
        .replaceFirst(RegExp(r'^STORE_'), '')
        .toUpperCase();
  }

  List<(String, String)> _organizationNodeItems() {
    return widget.organizationNodes
        .where((node) => node.isActive)
        .map(
          (node) => (
            node.id,
            '${AdminOrganizationNodeTypes.titleOf(node.type)} • ${node.businessCode ?? node.storeId ?? node.code} • ${node.title}',
          ),
        )
        .toList();
  }

  Widget _multiSelectField({
    required String label,
    required Set<String> selectedValues,
    required List<(String, String)> items,
    required ValueChanged<Set<String>> onChanged,
  }) {
    final selectedLabels = items
        .where((item) => selectedValues.contains(item.$1))
        .map((item) => item.$2)
        .toList();
    return InkWell(
      onTap: _saving
          ? null
          : () async {
              final values = await showDialog<Set<String>>(
                context: context,
                builder: (context) => _MultiSelectDialog(
                  title: label,
                  items: items,
                  selectedValues: selectedValues,
                ),
              );
              if (values != null) onChanged(values);
            },
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: InputDecorator(
        decoration: appInputDecoration(label: label),
        child: Text(
          selectedLabels.isEmpty ? 'Không áp dụng' : selectedLabels.join(', '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<(String, String)> items;
  final Set<String> selectedValues;

  const _MultiSelectDialog({
    required this.title,
    required this.items,
    required this.selectedValues,
  });

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
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
        : widget.items.where((item) {
            return item.$1.toLowerCase().contains(query) ||
                item.$2.toLowerCase().contains(query);
          }).toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 520,
        child: Column(
          children: [
            AppTextInput(
              controller: _searchController,
              label: 'Tìm kiếm',
              icon: Icons.search,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredItems.isEmpty
                  ? const AppStatePanel.empty(
                      title: 'Không tìm thấy dữ liệu',
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(item.$1),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) => setState(() {
                            if (value == true) {
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
