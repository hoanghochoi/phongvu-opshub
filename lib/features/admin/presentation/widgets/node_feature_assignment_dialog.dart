import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_radius.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_organization_node.dart';

class RelatedFeaturePolicyHint {
  final String featureCode;
  final String featureName;
  final String policyCode;
  final String policyName;
  final String message;

  const RelatedFeaturePolicyHint({
    required this.featureCode,
    required this.featureName,
    required this.policyCode,
    required this.policyName,
    required this.message,
  });
}

const _relatedPolicyHints = <String, RelatedFeaturePolicyHint>{
  'BANK_STATEMENTS': RelatedFeaturePolicyHint(
    featureCode: 'BANK_STATEMENTS',
    featureName: 'Sao kê',
    policyCode: 'BANK_STATEMENT_ALL_SCOPE',
    policyName: 'Xem sao kê toàn hệ thống',
    message:
        'Tính năng Sao kê chỉ mở quyền xem theo phạm vi đơn vị/showroom. '
        'Muốn xem tất cả showroom hoặc chọn nhiều showroom thì bật quyền xem sao kê toàn hệ thống trong Quản lý chính sách.',
  ),
};

@visibleForTesting
List<RelatedFeaturePolicyHint> relatedPolicyHintsForFeatureCodes(
  Iterable<String> selectedFeatureCodes,
) {
  final seen = <String>{};
  final hints = <RelatedFeaturePolicyHint>[];
  for (final rawCode in selectedFeatureCodes) {
    final code = rawCode.trim().toUpperCase();
    final hint = _relatedPolicyHints[code];
    if (hint == null || !seen.add(hint.policyCode)) continue;
    hints.add(hint);
  }
  hints.sort((left, right) => left.policyCode.compareTo(right.policyCode));
  return hints;
}

@visibleForTesting
Map<String, List<AdminOrganizationNode>> blockedNodeFeatureCodesForParentGate({
  required AdminOrganizationNode node,
  required List<AdminOrganizationNode> nodes,
  required Iterable<String> selectedFeatureCodes,
  required List<AdminNodeFeatureAssignment> assignments,
}) {
  final selectedCodes = selectedFeatureCodes.toSet();
  if (selectedCodes.isEmpty) return const {};
  final byId = {for (final item in nodes) item.id: item};
  final parents = <AdminOrganizationNode>[];
  var parentId = node.parentId;
  for (var guard = 0; parentId != null && guard < 50; guard += 1) {
    final parent = byId[parentId];
    if (parent == null) break;
    if (!_isRootOrganizationNode(parent)) parents.add(parent);
    parentId = parent.parentId;
  }
  if (parents.isEmpty) return const {};

  final result = <String, List<AdminOrganizationNode>>{};
  for (final featureCode in selectedCodes) {
    final missingParents = parents
        .where(
          (parent) => !_nodeHasEnabledFeatureAssignment(
            parent,
            featureCode,
            assignments,
          ),
        )
        .toList();
    if (missingParents.isNotEmpty) {
      result[featureCode] = missingParents;
    }
  }
  return result;
}

bool _nodeHasEnabledFeatureAssignment(
  AdminOrganizationNode node,
  String featureCode,
  List<AdminNodeFeatureAssignment> assignments,
) {
  return assignments.any(
    (assignment) =>
        assignment.enabled &&
        assignment.featureCode == featureCode &&
        assignment.organizationNodeIds.contains(node.id),
  );
}

bool _isRootOrganizationNode(AdminOrganizationNode node) {
  return AdminOrganizationNode.canonicalType(node.type) == 'LV0_DOMAIN';
}

class NodeFeatureAssignmentDialog extends StatefulWidget {
  final AuthRepository repository;
  final List<AdminOrganizationNode> nodes;
  final List<AdminFeatureDefinition> features;
  final List<AdminNodeFeatureAssignment> assignments;
  final AdminOrganizationNode? initialNode;

  const NodeFeatureAssignmentDialog({
    super.key,
    required this.repository,
    required this.nodes,
    required this.features,
    required this.assignments,
    this.initialNode,
  });

  @override
  State<NodeFeatureAssignmentDialog> createState() =>
      _NodeFeatureAssignmentDialogState();
}

class _NodeFeatureAssignmentDialogState
    extends State<NodeFeatureAssignmentDialog> {
  final _noteController = TextEditingController();
  final Set<String> _selectedCodes = <String>{};
  String? _selectedNodeId;
  String? _lastParentWarningLogKey;
  String? _lastRelatedPolicyReminderLogKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initialNode = widget.initialNode;
    if (initialNode != null && initialNode.isActive) {
      _selectedNodeId = initialNode.id;
    } else {
      final nodes = _activeNodes();
      _selectedNodeId = nodes.isEmpty ? null : nodes.first.id;
    }
    _loadSelectedCodesForNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleGuidanceLogs();
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  List<AdminOrganizationNode> _activeNodes() {
    final nodes = widget.nodes.where((node) => node.isActive).toList();
    nodes.sort((left, right) {
      final levelOrder = left.level.compareTo(right.level);
      if (levelOrder != 0) return levelOrder;
      return _nodeLabel(left).compareTo(_nodeLabel(right));
    });
    return nodes;
  }

  AdminOrganizationNode? _selectedNode() {
    final id = _selectedNodeId;
    if (id == null) return null;
    for (final node in widget.nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<AdminNodeFeatureAssignment> _assignmentsForNode(
    AdminOrganizationNode node,
  ) {
    return widget.assignments
        .where(
          (assignment) =>
              assignment.enabled &&
              assignment.organizationNodeIds.contains(node.id),
        )
        .toList();
  }

  void _loadSelectedCodesForNode() {
    final node = _selectedNode();
    _selectedCodes.clear();
    if (node == null) return;
    _selectedCodes.addAll(
      _assignmentsForNode(node).map((assignment) => assignment.featureCode),
    );
  }

  String _nodeLabel(AdminOrganizationNode node) {
    final type = AdminOrganizationNodeTypes.titleOf(node.type);
    final code = node.businessCode ?? node.storeId ?? node.code;
    return '$type • $code • ${node.title}';
  }

  void _selectNode(String? nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
      _loadSelectedCodesForNode();
    });
    _scheduleGuidanceLogs();
  }

  void _toggleFeature(AdminFeatureDefinition feature, bool selected) {
    setState(() {
      if (selected) {
        _selectedCodes.add(feature.code);
        var parentCode = feature.parentCode;
        while (parentCode != null && parentCode.isNotEmpty) {
          _selectedCodes.add(parentCode);
          parentCode = _featureByCode(parentCode)?.parentCode;
        }
      } else {
        _selectedCodes.remove(feature.code);
        for (final child in _descendantsOf(feature.code)) {
          _selectedCodes.remove(child.code);
        }
      }
    });
    _scheduleGuidanceLogs();
  }

  AdminFeatureDefinition? _featureByCode(String code) {
    for (final feature in widget.features) {
      if (feature.code == code) return feature;
    }
    return null;
  }

  List<AdminFeatureDefinition> _descendantsOf(String code) {
    final result = <AdminFeatureDefinition>[];
    void visit(String parentCode) {
      for (final feature in widget.features) {
        if (feature.parentCode == parentCode) {
          result.add(feature);
          visit(feature.code);
        }
      }
    }

    visit(code);
    return result;
  }

  Map<String, List<AdminOrganizationNode>> _blockedSelectedFeatureCodes(
    AdminOrganizationNode node,
  ) {
    return blockedNodeFeatureCodesForParentGate(
      node: node,
      nodes: widget.nodes,
      selectedFeatureCodes: _selectedCodes,
      assignments: widget.assignments,
    );
  }

  String _featureLabel(String code) {
    final feature = _featureByCode(code);
    return feature == null ? 'Tính năng chưa đặt tên' : feature.title;
  }

  String _nodeShortLabel(AdminOrganizationNode node) {
    final code = node.businessCode ?? node.storeId ?? node.code;
    return '${AdminOrganizationNodeTypes.titleOf(node.type)} $code';
  }

  void _scheduleParentWarningLog() {
    unawaited(_logParentWarningIfNeeded());
  }

  void _scheduleRelatedPolicyReminderLog() {
    unawaited(_logRelatedPolicyReminderIfNeeded());
  }

  void _scheduleGuidanceLogs() {
    _scheduleParentWarningLog();
    _scheduleRelatedPolicyReminderLog();
  }

  Future<void> _logParentWarningIfNeeded() async {
    final node = _selectedNode();
    if (node == null) return;
    final blocked = _blockedSelectedFeatureCodes(node);
    if (blocked.isEmpty) {
      _lastParentWarningLogKey = null;
      return;
    }
    final sortedCodes = blocked.keys.toList()..sort();
    final logKey = '${node.id}|${sortedCodes.join(',')}';
    if (_lastParentWarningLogKey == logKey) return;
    _lastParentWarningLogKey = logKey;
    await AppLogger.instance.info(
      'AdminFeatures',
      'Node feature assignment parent veto warning shown',
      context: {
        'organizationNodeId': node.id,
        'organizationNodeType': node.type,
        'blockedFeatureCount': blocked.length,
        'missingParentCount': blocked.values.fold<int>(
          0,
          (sum, parents) => sum + parents.length,
        ),
      },
    );
  }

  Future<void> _logRelatedPolicyReminderIfNeeded() async {
    final node = _selectedNode();
    if (node == null) return;
    final hints = relatedPolicyHintsForFeatureCodes(_selectedCodes);
    if (hints.isEmpty) {
      _lastRelatedPolicyReminderLogKey = null;
      return;
    }
    final policyCodes = hints.map((hint) => hint.policyCode).join(',');
    final featureCodes = hints.map((hint) => hint.featureCode).join(',');
    final logKey = '${node.id}|$featureCodes|$policyCodes';
    if (_lastRelatedPolicyReminderLogKey == logKey) return;
    _lastRelatedPolicyReminderLogKey = logKey;
    await AppLogger.instance.info(
      'AdminFeatures',
      'Node feature assignment related policy reminder shown',
      context: {
        'organizationNodeId': node.id,
        'organizationNodeType': node.type,
        'featureCount': hints.length,
        'policyCount': hints.length,
      },
    );
  }

  Future<void> _save() async {
    final node = _selectedNode();
    if (node == null) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Vui lòng chọn đơn vị tổ chức.')),
      );
      return;
    }
    final featureCodes = _selectedCodes.toList()..sort();
    final blockedFeatures = _blockedSelectedFeatureCodes(node);
    final stopwatch = Stopwatch()..start();
    setState(() => _saving = true);
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Node feature assignment dialog save started',
        context: {
          'organizationNodeId': node.id,
          'organizationNodeType': node.type,
          'featureCount': featureCodes.length,
          'parentBlockedFeatureCount': blockedFeatures.length,
          'replaceExisting': true,
        },
      );
      await widget.repository.saveAdminFeatureNodeAssignments(
        AdminNodeFeatureAssignmentBatchRequest(
          organizationNodeIds: [node.id],
          featureTreeCodes: featureCodes,
          replaceExisting: true,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
      );
      await AppLogger.instance.info(
        'AdminFeatures',
        'Node feature assignment dialog save succeeded',
        context: {
          'organizationNodeId': node.id,
          'organizationNodeType': node.type,
          'featureCount': featureCodes.length,
          'parentBlockedFeatureCount': blockedFeatures.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Node feature assignment dialog save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'organizationNodeId': node.id,
          'organizationNodeType': node.type,
          'featureCount': featureCodes.length,
          'parentBlockedFeatureCount': blockedFeatures.length,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Chưa lưu được quyền tính năng cho đơn vị.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _activeNodes();
    final selectedNode = _selectedNode();
    final currentAssignments = selectedNode == null
        ? const <AdminNodeFeatureAssignment>[]
        : _assignmentsForNode(selectedNode);
    final impactedUsers = currentAssignments.fold<int>(
      0,
      (max, assignment) => assignment.impactedUserCount > max
          ? assignment.impactedUserCount
          : max,
    );
    final blockedFeatures = selectedNode == null
        ? const <String, List<AdminOrganizationNode>>{}
        : _blockedSelectedFeatureCodes(selectedNode);
    final relatedPolicyHints = relatedPolicyHintsForFeatureCodes(
      _selectedCodes,
    );
    return AlertDialog(
      title: const Text('Tính năng theo đơn vị'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: AppFormColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSelectField<String>(
                value: _selectedNodeId,
                label: 'Đơn vị áp dụng',
                items: nodes
                    .map(
                      (node) => DropdownMenuItem(
                        value: node.id,
                        child: Text(
                          _nodeLabel(node),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving ? null : _selectNode,
              ),
              if (selectedNode != null)
                Text(
                  'Nhóm: ${AdminOrganizationNodeTypes.titleOf(selectedNode.type)} • ${selectedNode.businessCode ?? selectedNode.storeId ?? selectedNode.code} • người dùng ảnh hưởng: $impactedUsers',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              _NodeFeatureCheckboxTree(
                features: widget.features,
                selectedCodes: _selectedCodes,
                onChanged: _toggleFeature,
              ),
              if (relatedPolicyHints.isNotEmpty)
                _RelatedPolicyReminder(hints: relatedPolicyHints),
              if (blockedFeatures.isNotEmpty)
                _ParentFeatureVetoWarning(
                  blockedFeatures: blockedFeatures,
                  featureLabel: _featureLabel,
                  nodeLabel: _nodeShortLabel,
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
          onPressed: _saving ? null : () => setState(_selectedCodes.clear),
          label: 'Bỏ chọn hết',
        ),
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

class _RelatedPolicyReminder extends StatelessWidget {
  final List<RelatedFeaturePolicyHint> hints;

  const _RelatedPolicyReminder({required this.hints});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.policy_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chính sách liên quan',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final hint in hints)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${hint.policyName}: ${hint.message}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ParentFeatureVetoWarning extends StatelessWidget {
  final Map<String, List<AdminOrganizationNode>> blockedFeatures;
  final String Function(String code) featureLabel;
  final String Function(AdminOrganizationNode node) nodeLabel;

  const _ParentFeatureVetoWarning({
    required this.blockedFeatures,
    required this.featureLabel,
    required this.nodeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = blockedFeatures.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final visibleEntries = entries.take(4).toList();
    final extraCount = entries.length - visibleEntries.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Một số tính năng sẽ chưa có hiệu lực vì đơn vị cha chưa được chọn cùng tính năng.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in visibleEntries)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${featureLabel(entry.key)} thiếu ${entry.value.map(nodeLabel).join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (extraCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Còn $extraCount tính năng khác đang bị chặn bởi đơn vị cha.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NodeFeatureCheckboxTree extends StatelessWidget {
  final List<AdminFeatureDefinition> features;
  final Set<String> selectedCodes;
  final void Function(AdminFeatureDefinition feature, bool selected) onChanged;

  const _NodeFeatureCheckboxTree({
    required this.features,
    required this.selectedCodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) {
      return const Text('Chưa có danh sách tính năng');
    }
    final byParent = <String?, List<AdminFeatureDefinition>>{};
    for (final feature in features) {
      byParent.putIfAbsent(feature.parentCode, () => []).add(feature);
    }
    for (final list in byParent.values) {
      list.sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.title.compareTo(b.title);
      });
    }
    final roots = byParent[null] ?? const <AdminFeatureDefinition>[];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final feature in roots)
              _NodeFeatureCheckboxTile(
                feature: feature,
                byParent: byParent,
                selectedCodes: selectedCodes,
                depth: 0,
                onChanged: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _NodeFeatureCheckboxTile extends StatelessWidget {
  final AdminFeatureDefinition feature;
  final Map<String?, List<AdminFeatureDefinition>> byParent;
  final Set<String> selectedCodes;
  final int depth;
  final void Function(AdminFeatureDefinition feature, bool selected) onChanged;

  const _NodeFeatureCheckboxTile({
    required this.feature,
    required this.byParent,
    required this.selectedCodes,
    required this.depth,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final children = byParent[feature.code] ?? const <AdminFeatureDefinition>[];
    final isDisabled = !feature.isActive;
    final description = feature.description.trim();
    final subtitle = description.isEmpty ? 'Chưa có mô tả' : description;
    return Column(
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 8.0 + depth * 18, right: 8),
          value: selectedCodes.contains(feature.code),
          title: Text(
            feature.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            isDisabled ? '$subtitle • đang tắt' : subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: isDisabled
              ? null
              : (value) => onChanged(feature, value == true),
        ),
        for (final child in children)
          _NodeFeatureCheckboxTile(
            feature: child,
            byParent: byParent,
            selectedCodes: selectedCodes,
            depth: depth + 1,
            onChanged: onChanged,
          ),
      ],
    );
  }
}
