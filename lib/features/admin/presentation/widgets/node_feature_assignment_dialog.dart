import 'package:flutter/material.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_organization_node.dart';

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

  Future<void> _save() async {
    final node = _selectedNode();
    if (node == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn node tổ chức.')),
      );
      return;
    }
    final featureCodes = _selectedCodes.toList()..sort();
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
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa lưu được quyền tính năng node.')),
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
    return AlertDialog(
      title: const Text('Tính năng theo node'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: AppFormColumn(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedNodeId,
                decoration: const InputDecoration(labelText: 'Node áp dụng'),
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
                  'Nhóm: ${AdminOrganizationNodeTypes.titleOf(selectedNode.type)} • ${selectedNode.businessCode ?? selectedNode.storeId ?? selectedNode.code} • user ảnh hưởng: $impactedUsers',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              _NodeFeatureCheckboxTree(
                features: widget.features,
                selectedCodes: _selectedCodes,
                onChanged: _toggleFeature,
              ),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => setState(_selectedCodes.clear),
          child: const Text('Bỏ chọn hết'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Đang lưu...' : 'Lưu'),
        ),
      ],
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
          borderRadius: BorderRadius.circular(8),
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
            isDisabled ? '${feature.code} • đang tắt' : feature.code,
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
