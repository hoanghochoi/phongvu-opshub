import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
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
  final Set<String> _expandedIds = <String>{};
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
        canEditStructure:
            context.read<AuthProvider>().user?.role == 'SUPER_ADMIN',
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
      if (mounted) {
        final message = error is ApiException
            ? error.message
            : 'Chưa xóa được node tổ chức.';
        _showMessage(message);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String?>(
      (auth) => auth.user?.role,
    );
    final canEditStructure = role == 'SUPER_ADMIN';
    final canEditMap = role == 'ADMIN_PHONGVU' || role == 'ADMIN_ACARE';
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
          if (canEditStructure)
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
                    expandedIds: _expandedIds,
                    onSelect: (id) => setState(() => _selectedId = id),
                    onExpansionChanged: (id, expanded) => setState(() {
                      if (expanded) {
                        _expandedIds.add(id);
                      } else {
                        _expandedIds.remove(id);
                      }
                    }),
                  );
                  final detail = _OrganizationNodeDetail(
                    node: selected,
                    nodes: _nodes,
                    canAddChild: canEditStructure,
                    canEdit:
                        canEditStructure ||
                        (canEditMap && selected?.type == 'SHOWROOM'),
                    canDelete: canEditStructure,
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
  final Set<String> expandedIds;
  final ValueChanged<String> onSelect;
  final void Function(String id, bool expanded) onExpansionChanged;

  const _OrganizationTreeList({
    required this.nodes,
    required this.selectedId,
    required this.expandedIds,
    required this.onSelect,
    required this.onExpansionChanged,
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
            expandedIds: expandedIds,
            depth: 0,
            onSelect: onSelect,
            onExpansionChanged: onExpansionChanged,
          ),
      ],
    );
  }
}

class _TreeNodeTile extends StatelessWidget {
  final AdminOrganizationNode node;
  final Map<String?, List<AdminOrganizationNode>> byParent;
  final String? selectedId;
  final Set<String> expandedIds;
  final int depth;
  final ValueChanged<String> onSelect;
  final void Function(String id, bool expanded) onExpansionChanged;

  const _TreeNodeTile({
    required this.node,
    required this.byParent,
    required this.selectedId,
    required this.expandedIds,
    required this.depth,
    required this.onSelect,
    required this.onExpansionChanged,
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
      initiallyExpanded: expandedIds.contains(node.id),
      onExpansionChanged: (expanded) => onExpansionChanged(node.id, expanded),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: tile,
      children: [
        for (final child in children)
          _TreeNodeTile(
            node: child,
            byParent: byParent,
            selectedId: selectedId,
            expandedIds: expandedIds,
            depth: depth + 1,
            onSelect: onSelect,
            onExpansionChanged: onExpansionChanged,
          ),
      ],
    );
  }
}

class _OrganizationNodeDetail extends StatelessWidget {
  final AdminOrganizationNode? node;
  final List<AdminOrganizationNode> nodes;
  final bool canAddChild;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onAddChild;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _OrganizationNodeDetail({
    required this.node,
    required this.nodes,
    required this.canAddChild,
    required this.canEdit,
    required this.canDelete,
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
    AdminOrganizationNode? parent;
    for (final item in nodes) {
      if (item.id == node.parentId) {
        parent = item;
        break;
      }
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
          if (node.type == 'SHOWROOM') ...[
            _DetailRow(
              label: 'Mã showroom',
              value: node.storeId ?? node.businessCode ?? node.code,
            ),
            _DetailRow(
              label: 'Tên showroom',
              value: node.storeName ?? node.title,
            ),
            _DetailRow(
              label: 'MAP username',
              value: node.mapVietinUsername?.isNotEmpty == true
                  ? node.mapVietinUsername!
                  : 'Chưa cấu hình',
            ),
            _DetailRow(
              label: 'MAP password',
              value: node.hasMapVietinPassword
                  ? 'Đã cấu hình'
                  : 'Chưa cấu hình',
            ),
            _DetailRow(
              label: 'Tài khoản nhận',
              value: node.transferAccountNumber?.isNotEmpty == true
                  ? node.transferAccountNumber!
                  : 'Chưa cấu hình',
            ),
          ] else
            _DetailRow(
              label: 'Mã nghiệp vụ',
              value: node.businessCode ?? node.code,
            ),
          if (node.abbreviation?.isNotEmpty == true)
            _DetailRow(label: 'Viết tắt', value: node.abbreviation!),
          if (node.description?.isNotEmpty == true)
            _DetailRow(label: 'Mô tả', value: node.description!),
          _DetailRow(label: 'Node cha', value: parent?.title ?? 'Không có'),
          _DetailRow(
            label: 'Loại node',
            value: AdminOrganizationNodeTypes.titleOf(node.type),
          ),
          _DetailRow(
            label: 'Trạng thái',
            value: node.isActive ? 'Đang hoạt động' : 'Đã tắt',
          ),
          _DetailRow(label: 'Node con', value: '${node.childCount}'),
          _DetailRow(label: 'User', value: '${node.userCount}'),
          _DetailRow(label: 'SR', value: '${node.storeCount}'),
          _DetailRow(
            label: 'Danh mục liên kết',
            value: '${node.referenceCount}',
          ),
          if (canAddChild || canEdit || canDelete)
            AppActionRow(
              children: [
                if (canAddChild)
                  AppSecondaryButton(
                    onPressed: onAddChild,
                    icon: Icons.add_outlined,
                    label: 'Thêm con',
                  ),
                if (canEdit)
                  AppSecondaryButton(
                    onPressed: onEdit,
                    icon: Icons.edit_outlined,
                    label: 'Sửa',
                  ),
                if (canDelete)
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
  final bool canEditStructure;

  const _OrganizationNodeEditorDialog({
    required this.repository,
    required this.nodes,
    required this.canEditStructure,
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
  final _businessCodeController = TextEditingController();
  final _abbreviationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _emailDomainController = TextEditingController();
  final _sortOrderController = TextEditingController(text: '0');
  final _transferAccountNumberController = TextEditingController();
  final _transferAccountNameController = TextEditingController();
  final _transferBankNameController = TextEditingController();
  final _transferBankBinController = TextEditingController();
  final _mapVietinUsernameController = TextEditingController();
  final _mapVietinPasswordController = TextEditingController();
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
    _businessCodeController.text = node?.businessCode ?? node?.storeId ?? '';
    _abbreviationController.text = node?.abbreviation ?? '';
    _descriptionController.text = node?.description ?? '';
    _emailDomainController.text = node?.emailDomain ?? '';
    _sortOrderController.text = '${node?.sortOrder ?? 0}';
    _transferAccountNumberController.text = node?.transferAccountNumber ?? '';
    _transferAccountNameController.text = node?.transferAccountName ?? '';
    _transferBankNameController.text = node?.transferBankName ?? '';
    _transferBankBinController.text = node?.transferBankBin ?? '';
    _mapVietinUsernameController.text = node?.mapVietinUsername ?? '';
    _type = node?.type ?? (widget.parentId == null ? 'ROOT_DOMAIN' : 'BLOCK');
    _parentId = node?.parentId ?? widget.parentId;
    _loginAllowed = node?.loginAllowed ?? _type == 'ROOT_DOMAIN';
    _isActive = node?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _businessCodeController.dispose();
    _abbreviationController.dispose();
    _descriptionController.dispose();
    _emailDomainController.dispose();
    _sortOrderController.dispose();
    _transferAccountNumberController.dispose();
    _transferAccountNameController.dispose();
    _transferBankNameController.dispose();
    _transferBankBinController.dispose();
    _mapVietinUsernameController.dispose();
    _mapVietinPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final effectiveParentId = _effectiveParentId();
    final node = AdminOrganizationNode(
      id: widget.node?.id ?? '',
      code: _codeController.text.trim(),
      title: _titleController.text.trim(),
      businessCode: _businessCodeController.text.trim().isEmpty
          ? null
          : _businessCodeController.text.trim(),
      abbreviation: _abbreviationController.text.trim().isEmpty
          ? null
          : _abbreviationController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      type: _type,
      parentId: effectiveParentId,
      emailDomain: _emailDomainController.text.trim().isEmpty
          ? null
          : _emailDomainController.text.trim(),
      loginAllowed: _loginAllowed,
      isActive: _isActive,
      sortOrder: int.tryParse(_sortOrderController.text.trim()) ?? 0,
      storeId: _businessCodeController.text.trim().isEmpty
          ? null
          : _businessCodeController.text.trim(),
      storeName: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      transferAccountNumber:
          _transferAccountNumberController.text.trim().isEmpty
          ? null
          : _transferAccountNumberController.text.trim(),
      transferAccountName: _transferAccountNameController.text.trim().isEmpty
          ? null
          : _transferAccountNameController.text.trim(),
      transferBankName: _transferBankNameController.text.trim().isEmpty
          ? null
          : _transferBankNameController.text.trim(),
      transferBankBin: _transferBankBinController.text.trim().isEmpty
          ? null
          : _transferBankBinController.text.trim(),
      mapVietinUsername: _mapVietinUsernameController.text.trim().isEmpty
          ? null
          : _mapVietinUsernameController.text.trim(),
    );
    final body = node.toJson();
    final mapPassword = _mapVietinPasswordController.text.trim();
    if (mapPassword.isNotEmpty) body['mapVietinPassword'] = mapPassword;
    try {
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization node save started',
        context: {
          'nodeId': widget.node?.id,
          'type': _type,
          'parentId': effectiveParentId,
        },
      );
      if (widget.node == null) {
        await widget.repository.createAdminOrganizationNodeBody(body);
      } else {
        await widget.repository.updateAdminOrganizationNodeBody(
          widget.node!.id,
          body,
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
        final message = error is ApiException
            ? error.message
            : 'Chưa lưu được node tổ chức.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDomain = _type == 'ROOT_DOMAIN' || _type == 'SUBDOMAIN';
    final isShowroom = _type == 'SHOWROOM';
    final canEditStructure = widget.canEditStructure;
    final canEditMap = isShowroom;
    final parentOptions = _parentOptions();
    final parentValue = _validParentId(parentOptions);
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
                enabled: canEditStructure,
              ),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Mã internal'),
                enabled: canEditStructure,
              ),
              TextField(
                controller: _businessCodeController,
                decoration: InputDecoration(
                  labelText: isShowroom ? 'Mã SR' : 'Mã nghiệp vụ',
                ),
                enabled: canEditStructure,
              ),
              if (_type == 'REGION' || _type == 'AREA')
                TextField(
                  controller: _abbreviationController,
                  decoration: const InputDecoration(labelText: 'Viết tắt'),
                  enabled: canEditStructure,
                ),
              if (_type == 'REGION' || _type == 'AREA')
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  enabled: canEditStructure,
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
                onChanged: !canEditStructure || widget.node?.isSystem == true
                    ? null
                    : (value) => setState(() => _setType(value ?? 'BLOCK')),
              ),
              DropdownButtonFormField<String?>(
                key: ValueKey('parent-$_type-${parentValue ?? 'none'}'),
                initialValue: parentValue,
                decoration: const InputDecoration(labelText: 'Node cha'),
                items: [
                  if (_allowsEmptyParent(_type))
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Không có'),
                    ),
                  ...parentOptions.map(
                    (node) => DropdownMenuItem<String?>(
                      value: node.id,
                      child: Text(node.title),
                    ),
                  ),
                ],
                onChanged: !canEditStructure || widget.node?.isSystem == true
                    ? null
                    : (value) => setState(() => _parentId = value),
              ),
              if (isDomain)
                TextField(
                  controller: _emailDomainController,
                  decoration: const InputDecoration(labelText: 'Email domain'),
                  enabled: canEditStructure,
                ),
              if (isShowroom) ...[
                TextField(
                  controller: _mapVietinUsernameController,
                  decoration: const InputDecoration(labelText: 'MAP username'),
                  enabled: canEditMap,
                ),
                TextField(
                  controller: _mapVietinPasswordController,
                  decoration: InputDecoration(
                    labelText: widget.node?.hasMapVietinPassword == true
                        ? 'MAP password mới'
                        : 'MAP password',
                  ),
                  obscureText: true,
                  enabled: canEditMap,
                ),
                TextField(
                  controller: _transferAccountNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Số tài khoản nhận tiền',
                  ),
                  enabled: canEditStructure,
                ),
                TextField(
                  controller: _transferAccountNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên tài khoản nhận tiền',
                  ),
                  enabled: canEditStructure,
                ),
                TextField(
                  controller: _transferBankNameController,
                  decoration: const InputDecoration(labelText: 'Ngân hàng'),
                  enabled: canEditStructure,
                ),
                TextField(
                  controller: _transferBankBinController,
                  decoration: const InputDecoration(labelText: 'BIN'),
                  enabled: canEditStructure,
                ),
              ],
              TextField(
                controller: _sortOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Thứ tự'),
                enabled: canEditStructure,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isActive,
                title: const Text('Đang hoạt động'),
                onChanged: canEditStructure
                    ? (value) => setState(() => _isActive = value)
                    : null,
              ),
              if (isDomain)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _loginAllowed,
                  title: const Text('Cho phép đăng nhập'),
                  onChanged: canEditStructure
                      ? (value) => setState(() => _loginAllowed = value)
                      : null,
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

  void _setType(String type) {
    _type = type;
    _loginAllowed = _type == 'ROOT_DOMAIN' || _type == 'SUBDOMAIN';
    final parentOptions = _parentOptions();
    _parentId = _validParentId(parentOptions);
    if (_parentId == null && !_allowsEmptyParent(_type)) {
      _parentId = parentOptions.isEmpty ? null : parentOptions.first.id;
    }
  }

  List<AdminOrganizationNode> _parentOptions() {
    return widget.nodes
        .where(
          (node) =>
              node.id != widget.node?.id && _canUseParentForType(node, _type),
        )
        .toList();
  }

  String? _validParentId(List<AdminOrganizationNode> parentOptions) {
    if (_parentId == null) return null;
    for (final node in parentOptions) {
      if (node.id == _parentId) return _parentId;
    }
    return null;
  }

  String? _effectiveParentId() {
    final parentOptions = _parentOptions();
    final validParentId = _validParentId(parentOptions);
    if (validParentId != null || _allowsEmptyParent(_type)) {
      return validParentId;
    }
    return parentOptions.isEmpty ? null : parentOptions.first.id;
  }

  bool _allowsEmptyParent(String type) {
    return type == 'ROOT_DOMAIN' || type == 'SUBDOMAIN' || type == 'REGION';
  }

  bool _canUseParentForType(AdminOrganizationNode parent, String type) {
    final allowedTypes = switch (type) {
      'SUBDOMAIN' => const {'ROOT_DOMAIN'},
      'REGION' => const {'ROOT_DOMAIN', 'SUBDOMAIN', 'BLOCK'},
      'AREA' => const {'REGION'},
      'SHOWROOM' => const {'ROOT_DOMAIN', 'AREA', 'BLOCK'},
      _ => null,
    };
    return allowedTypes == null || allowedTypes.contains(parent.type);
  }
}

IconData _iconForType(String type) {
  return switch (type) {
    'ROOT_DOMAIN' => Icons.language_outlined,
    'SUBDOMAIN' => Icons.alternate_email_outlined,
    'DEPARTMENT' => Icons.apartment_outlined,
    'REGION' => Icons.public_outlined,
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
    'REGION' => AppColors.teal600,
    'AREA' => AppColors.emerald600,
    'SHOWROOM' => AppColors.success,
    'JOB_ROLE' => AppColors.violet600,
    'VIRTUAL_SCOPE' => AppColors.warning,
    _ => AppColors.neutral500,
  };
}
