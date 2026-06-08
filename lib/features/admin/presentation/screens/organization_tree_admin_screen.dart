import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_organization_node.dart';

class OrganizationTreeAdminScreen extends StatefulWidget {
  const OrganizationTreeAdminScreen({super.key});

  @override
  State<OrganizationTreeAdminScreen> createState() =>
      _OrganizationTreeAdminScreenState();
}

class _OrganizationTreeAdminScreenState
    extends State<OrganizationTreeAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminOrganizationNode> _nodes = [];
  String? _selectedId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AdminOrganizationNode? get _selectedNode {
    for (final node in _nodes) {
      if (node.id == _selectedId) return node;
    }
    return _nodes.isEmpty ? null : _nodes.first;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final startedAt = DateTime.now();
    await AppLogger.instance.info(
      'AdminOrganization',
      'Organization tree load started',
    );
    try {
      final nodes = await _repository.listAdminOrganizationTree();
      if (!mounted) return;
      setState(() {
        _nodes = nodes;
        _selectedId = _selectedId ?? (nodes.isEmpty ? null : nodes.first.id);
      });
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization tree load succeeded',
        context: {
          'count': nodes.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminOrganization',
        'Organization tree load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) _showMessage('Chưa tải được cơ cấu tổ chức.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({
    AdminOrganizationNode? node,
    String? parentId,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _OrganizationNodeEditorDialog(
        repository: _repository,
        nodes: _nodes,
        node: node,
        parentId: parentId,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteSelected() async {
    final node = _selectedNode;
    if (node == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa node tổ chức'),
        content: Text('Xóa hoặc tắt node ${node.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AppLogger.instance.warn(
        'AdminOrganization',
        'Organization node delete started',
        context: {'nodeId': node.id, 'type': node.type},
      );
      await _repository.deleteAdminOrganizationNode(node.id);
      await AppLogger.instance.warn(
        'AdminOrganization',
        'Organization node delete succeeded',
        context: {'nodeId': node.id},
      );
      _selectedId = null;
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminOrganization',
        'Organization node delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'nodeId': node.id},
      );
      if (mounted) _showMessage('Chưa xóa được node tổ chức.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canMutate = context.select<AuthProvider, bool>(
      (auth) => auth.user?.role == 'SUPER_ADMIN',
    );
    final selected = _selectedNode;
    return Scaffold(
      appBar: GradientHeader(
        title: 'Cơ cấu tổ chức',
        showBack: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Tải lại',
          ),
          if (canMutate)
            IconButton(
              onPressed: _loading
                  ? null
                  : () => _openEditor(parentId: selected?.id),
              icon: const Icon(Icons.add_outlined),
              tooltip: 'Thêm node',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppResponsiveContent(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tree = _OrganizationTreeList(
                    nodes: _nodes,
                    selectedId: selected?.id,
                    onSelect: (id) => setState(() => _selectedId = id),
                  );
                  final detail = _OrganizationNodeDetail(
                    node: selected,
                    canMutate: canMutate,
                    onAddChild: selected == null
                        ? null
                        : () => _openEditor(parentId: selected.id),
                    onEdit: selected == null
                        ? null
                        : () => _openEditor(node: selected),
                    onDelete: selected == null || selected.isSystem
                        ? null
                        : _deleteSelected,
                  );
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        SizedBox(height: 300, child: tree),
                        const SizedBox(height: AppLayoutTokens.sectionGap),
                        Expanded(child: detail),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 360, child: tree),
                      const SizedBox(width: AppLayoutTokens.sectionGap),
                      Expanded(child: detail),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _OrganizationTreeList extends StatelessWidget {
  final List<AdminOrganizationNode> nodes;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _OrganizationTreeList({
    required this.nodes,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const Center(child: Text('Chưa có node tổ chức'));
    final byParent = <String?, List<AdminOrganizationNode>>{};
    for (final node in nodes) {
      byParent.putIfAbsent(node.parentId, () => []).add(node);
    }
    for (final list in byParent.values) {
      list.sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.title.compareTo(b.title);
      });
    }
    return ListView(
      children: [
        for (final node in byParent[null] ?? const <AdminOrganizationNode>[])
          _TreeNodeTile(
            node: node,
            byParent: byParent,
            selectedId: selectedId,
            depth: 0,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

class _TreeNodeTile extends StatelessWidget {
  final AdminOrganizationNode node;
  final Map<String?, List<AdminOrganizationNode>> byParent;
  final String? selectedId;
  final int depth;
  final ValueChanged<String> onSelect;

  const _TreeNodeTile({
    required this.node,
    required this.byParent,
    required this.selectedId,
    required this.depth,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final children = byParent[node.id] ?? const <AdminOrganizationNode>[];
    final selected = selectedId == node.id;
    final color = selected ? AppColors.info.withValues(alpha: 0.12) : null;
    final tile = ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 12.0 + depth * 16, right: 8),
      tileColor: color,
      leading: Icon(_iconForType(node.type), color: _colorForType(node.type)),
      title: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        AdminOrganizationNodeTypes.titleOf(node.type),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: node.isActive
          ? null
          : const Icon(Icons.block_outlined, color: AppColors.error, size: 18),
      onTap: () => onSelect(node.id),
    );
    if (children.isEmpty) return tile;
    return ExpansionTile(
      initiallyExpanded: depth < 2,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: tile,
      children: [
        for (final child in children)
          _TreeNodeTile(
            node: child,
            byParent: byParent,
            selectedId: selectedId,
            depth: depth + 1,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

class _OrganizationNodeDetail extends StatelessWidget {
  final AdminOrganizationNode? node;
  final bool canMutate;
  final VoidCallback? onAddChild;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _OrganizationNodeDetail({
    required this.node,
    required this.canMutate,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node == null) {
      return const Center(child: Text('Chọn node để xem chi tiết'));
    }
    return SingleChildScrollView(
      child: AppFormColumn(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForType(node.type), color: _colorForType(node.type)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  node.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(AdminOrganizationNodeTypes.titleOf(node.type))),
              Chip(label: Text(node.isActive ? 'Đang hoạt động' : 'Đã tắt')),
              if (node.emailDomain?.isNotEmpty == true)
                Chip(label: Text(node.emailDomain!)),
              if (node.loginAllowed) const Chip(label: Text('Cho đăng nhập')),
            ],
          ),
          _DetailRow(label: 'Mã', value: node.code),
          _DetailRow(label: 'Node con', value: '${node.childCount}'),
          _DetailRow(label: 'User', value: '${node.userCount}'),
          _DetailRow(label: 'SR', value: '${node.storeCount}'),
          _DetailRow(
            label: 'Danh mục liên kết',
            value: '${node.referenceCount}',
          ),
          if (canMutate)
            AppActionRow(
              children: [
                AppSecondaryButton(
                  onPressed: onAddChild,
                  icon: Icons.add_outlined,
                  label: 'Thêm con',
                ),
                AppSecondaryButton(
                  onPressed: onEdit,
                  icon: Icons.edit_outlined,
                  label: 'Sửa',
                ),
                AppSecondaryButton(
                  onPressed: onDelete,
                  icon: Icons.delete_outline,
                  label: 'Xóa',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _OrganizationNodeEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final List<AdminOrganizationNode> nodes;
  final AdminOrganizationNode? node;
  final String? parentId;

  const _OrganizationNodeEditorDialog({
    required this.repository,
    required this.nodes,
    this.node,
    this.parentId,
  });

  @override
  State<_OrganizationNodeEditorDialog> createState() =>
      _OrganizationNodeEditorDialogState();
}

class _OrganizationNodeEditorDialogState
    extends State<_OrganizationNodeEditorDialog> {
  final _titleController = TextEditingController();
  final _codeController = TextEditingController();
  final _emailDomainController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  String _type = 'BLOCK';
  String? _parentId;
  bool _loginAllowed = false;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final node = widget.node;
    _titleController.text = node?.title ?? '';
    _codeController.text = node?.code ?? '';
    _emailDomainController.text = node?.emailDomain ?? '';
    _sortOrderController.text = '${node?.sortOrder ?? 0}';
    _type = node?.type ?? (widget.parentId == null ? 'ROOT_DOMAIN' : 'BLOCK');
    _parentId = node?.parentId ?? widget.parentId;
    _loginAllowed = node?.loginAllowed ?? _type == 'ROOT_DOMAIN';
    _isActive = node?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _emailDomainController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final node = AdminOrganizationNode(
      id: widget.node?.id ?? '',
      code: _codeController.text.trim(),
      title: _titleController.text.trim(),
      type: _type,
      parentId: _parentId,
      emailDomain: _emailDomainController.text.trim().isEmpty
          ? null
          : _emailDomainController.text.trim(),
      loginAllowed: _loginAllowed,
      isActive: _isActive,
      sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
    );
    try {
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization node save started',
        context: {'nodeId': widget.node?.id, 'type': _type},
      );
      if (widget.node == null) {
        await widget.repository.createAdminOrganizationNode(node);
      } else {
        await widget.repository.updateAdminOrganizationNode(
          widget.node!.id,
          node,
        );
      }
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization node save succeeded',
        context: {'nodeId': widget.node?.id, 'type': _type},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminOrganization',
        'Organization node save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'nodeId': widget.node?.id, 'type': _type},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chưa lưu được node tổ chức.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDomain = _type == 'ROOT_DOMAIN' || _type == 'SUBDOMAIN';
    return AlertDialog(
      title: Text(widget.node == null ? 'Thêm node' : 'Sửa node'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: AppFormColumn(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Tên hiển thị'),
              ),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Mã'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Loại node'),
                items: AdminOrganizationNodeTypes.definitions
                    .map(
                      (definition) => DropdownMenuItem(
                        value: definition.$1,
                        child: Text(definition.$2),
                      ),
                    )
                    .toList(),
                onChanged: widget.node?.isSystem == true
                    ? null
                    : (value) => setState(() {
                        _type = value ?? 'BLOCK';
                        _loginAllowed =
                            _type == 'ROOT_DOMAIN' || _type == 'SUBDOMAIN';
                      }),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _parentId,
                decoration: const InputDecoration(labelText: 'Node cha'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Không có'),
                  ),
                  ...widget.nodes
                      .where((node) => node.id != widget.node?.id)
                      .map(
                        (node) => DropdownMenuItem<String?>(
                          value: node.id,
                          child: Text(node.title),
                        ),
                      ),
                ],
                onChanged: widget.node?.isSystem == true
                    ? null
                    : (value) => setState(() => _parentId = value),
              ),
              if (isDomain)
                TextField(
                  controller: _emailDomainController,
                  decoration: const InputDecoration(labelText: 'Email domain'),
                ),
              TextField(
                controller: _sortOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Thứ tự'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('Đang hoạt động'),
                onChanged: (value) => setState(() => _isActive = value),
              ),
              if (isDomain)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _loginAllowed,
                  title: const Text('Cho phép đăng nhập'),
                  onChanged: (value) => setState(() => _loginAllowed = value),
                ),
            ],
          ),
        ),
      ),
      actions: [
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

IconData _iconForType(String type) {
  return switch (type) {
    'ROOT_DOMAIN' => Icons.language_outlined,
    'SUBDOMAIN' => Icons.alternate_email_outlined,
    'DEPARTMENT' => Icons.apartment_outlined,
    'AREA' => Icons.map_outlined,
    'SHOWROOM' => Icons.store_mall_directory_outlined,
    'JOB_ROLE' => Icons.badge_outlined,
    'VIRTUAL_SCOPE' => Icons.hub_outlined,
    _ => Icons.account_tree_outlined,
  };
}

Color _colorForType(String type) {
  return switch (type) {
    'ROOT_DOMAIN' => AppColors.info,
    'SUBDOMAIN' => AppColors.sky500,
    'DEPARTMENT' => AppColors.purple600,
    'AREA' => AppColors.emerald600,
    'SHOWROOM' => AppColors.success,
    'JOB_ROLE' => AppColors.violet600,
    'VIRTUAL_SCOPE' => AppColors.warning,
    _ => AppColors.neutral500,
  };
}
