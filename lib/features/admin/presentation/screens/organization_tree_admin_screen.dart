import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_organization_node.dart';
import '../widgets/node_feature_assignment_dialog.dart';

class OrganizationTreeAdminScreen extends StatefulWidget {
  final AuthRepository? repository;

  const OrganizationTreeAdminScreen({super.key, this.repository});

  @override
  State<OrganizationTreeAdminScreen> createState() =>
      _OrganizationTreeAdminScreenState();
}

class _OrganizationTreeAdminScreenState
    extends State<OrganizationTreeAdminScreen> {
  late final AuthRepository _repository;
  final _treeSearchController = TextEditingController();
  List<AdminOrganizationNode> _nodes = [];
  String? _selectedId;
  String _treeSearchQuery = '';
  final Set<String> _expandedIds = <String>{};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AuthRepository(ApiClient());
    _load();
  }

  @override
  void dispose() {
    _treeSearchController.dispose();
    super.dispose();
  }

  AdminOrganizationNode? get _selectedNode {
    for (final node in _nodes) {
      if (node.id == _selectedId) return node;
    }
    return _nodes.isEmpty ? null : _nodes.first;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
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
        _loadError = null;
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
      if (mounted) {
        setState(() => _loadError = 'Chưa tải được cơ cấu tổ chức.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTreeSearch(String value) {
    final filtered = filterAdminOrganizationNodesForSearch(_nodes, value);
    final normalizedQuery = normalizeAdminOrganizationSearchText(value);
    AdminOrganizationNode? firstMatch;
    if (normalizedQuery.isNotEmpty) {
      for (final node in _nodes) {
        if (adminOrganizationNodeMatchesSearch(node, normalizedQuery)) {
          firstMatch = node;
          break;
        }
      }
    }
    setState(() {
      _treeSearchQuery = value;
      if (value.trim().isEmpty || filtered.isEmpty) return;
      if (firstMatch != null && firstMatch.id != _selectedId) {
        _selectedId = firstMatch.id;
      } else if (filtered.every((node) => node.id != _selectedId)) {
        _selectedId = firstMatch?.id ?? filtered.first.id;
      }
    });
  }

  void _clearTreeSearch() {
    _treeSearchController.clear();
    _applyTreeSearch('');
  }

  Future<void> _logTreeSearch() async {
    final query = _treeSearchQuery.trim();
    if (query.isEmpty) return;
    final resultCount = filterAdminOrganizationNodesForSearch(
      _nodes,
      query,
    ).length;
    await AppLogger.instance.info(
      'AdminOrganization',
      'Organization tree search submitted',
      context: {'queryLength': query.length, 'resultCount': resultCount},
    );
  }

  Set<String> _ancestorIdsFor(List<AdminOrganizationNode> visibleNodes) {
    final byId = {for (final node in _nodes) node.id: node};
    final ancestorIds = <String>{};
    for (final node in visibleNodes) {
      var parentId = node.parentId;
      while (parentId != null) {
        if (!ancestorIds.add(parentId)) break;
        parentId = byId[parentId]?.parentId;
      }
    }
    return ancestorIds;
  }

  AdminOrganizationNode? _visibleSelectedNode(
    List<AdminOrganizationNode> visibleNodes,
    AdminOrganizationNode? fallback,
  ) {
    if (_treeSearchQuery.trim().isEmpty) return fallback;
    for (final node in visibleNodes) {
      if (node.id == fallback?.id) return node;
    }
    return visibleNodes.isEmpty ? null : visibleNodes.first;
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

  Future<void> _openFeatureAssignment() async {
    final node = _selectedNode;
    if (node == null) return;
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization node feature panel load started',
        context: {'nodeId': node.id, 'type': node.type},
      );
      final results = await Future.wait<Object>([
        _repository.listAdminFeatureTree(),
        _repository.listAdminFeatureNodeAssignments(),
      ]);
      if (!mounted) return;
      final updated = await showDialog<bool>(
        context: context,
        builder: (context) => NodeFeatureAssignmentDialog(
          repository: _repository,
          nodes: _nodes,
          features: results[0] as List<AdminFeatureDefinition>,
          assignments: results[1] as List<AdminNodeFeatureAssignment>,
          initialNode: node,
        ),
      );
      await AppLogger.instance.info(
        'AdminOrganization',
        'Organization node feature panel closed',
        context: {
          'nodeId': node.id,
          'updated': updated == true,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (updated == true) await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminOrganization',
        'Organization node feature panel failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'nodeId': node.id, 'type': node.type},
      );
      if (mounted) _showMessage('Chưa mở được panel tính năng của node.');
    }
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
          AppDialogCancelButton(
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: 'Xóa',
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
    final currentUser = context.watch<AuthProvider>().user;
    final role = currentUser?.role;
    final canEditStructure = role == 'SUPER_ADMIN';
    final canEditMap = User.isAdminRole(role);
    final canManageFeatures =
        role == 'SUPER_ADMIN' ||
        currentUser?.canUseFeature('ADMIN_FEATURES') == true;
    final selected = _selectedNode;
    return AppResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrganizationTreeHeader(
            key: const Key('organization-tree-header'),
            loading: _loading,
            selected: selected,
            canEditStructure: canEditStructure,
            onReload: _load,
            onAdd: selected == null || (selected.level >= 5)
                ? null
                : () => _openEditor(parentId: selected.id),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          if (_loading)
            const Expanded(child: AppListSkeleton(itemCount: 6, itemHeight: 76))
          else if (_loadError != null)
            Expanded(
              child: AppStatePanel.error(
                title: _loadError!,
                message: 'Kiểm tra kết nối rồi thử tải lại cây tổ chức.',
                actionLabel: 'Thử tải lại',
                actionIcon: Icons.refresh_outlined,
                onAction: () => unawaited(_load()),
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchActive = _treeSearchQuery.trim().isNotEmpty;
                  final visibleNodes = filterAdminOrganizationNodesForSearch(
                    _nodes,
                    _treeSearchQuery,
                  );
                  final visibleSelected = _visibleSelectedNode(
                    visibleNodes,
                    selected,
                  );
                  final expandedIds = searchActive
                      ? <String>{
                          ..._expandedIds,
                          ..._ancestorIdsFor(visibleNodes),
                        }
                      : _expandedIds;
                  final tree = _OrganizationTreePanel(
                    key: const Key('organization-tree-list-panel'),
                    searchController: _treeSearchController,
                    searchQuery: _treeSearchQuery,
                    onSearchChanged: _applyTreeSearch,
                    onSearchSubmitted: (_) => unawaited(_logTreeSearch()),
                    onClearSearch: _clearTreeSearch,
                    child: _OrganizationTreeList(
                      nodes: visibleNodes,
                      totalCount: _nodes.length,
                      searchQuery: _treeSearchQuery,
                      selectedId: visibleSelected?.id,
                      expandedIds: expandedIds,
                      onSelect: (id) => setState(() => _selectedId = id),
                      onExpansionChanged: (id, expanded) => setState(() {
                        if (expanded) {
                          _expandedIds.add(id);
                        } else {
                          _expandedIds.remove(id);
                        }
                      }),
                    ),
                  );
                  final detail = _OrganizationNodeDetail(
                    key: const Key('organization-tree-detail-panel'),
                    node: visibleSelected,
                    nodes: _nodes,
                    canAddChild:
                        canEditStructure && (visibleSelected?.level ?? 0) < 5,
                    canEdit:
                        canEditStructure ||
                        (canEditMap && visibleSelected?.type == 'LV4_STORE'),
                    canDelete: canEditStructure,
                    canManageFeatures: canManageFeatures,
                    onAddChild: visibleSelected == null
                        ? null
                        : () => _openEditor(parentId: visibleSelected.id),
                    onEdit: visibleSelected == null
                        ? null
                        : () => _openEditor(node: visibleSelected),
                    onDelete:
                        visibleSelected == null || visibleSelected.isSystem
                        ? null
                        : _deleteSelected,
                    onManageFeatures: visibleSelected == null
                        ? null
                        : _openFeatureAssignment,
                  );
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [
                        SizedBox(height: 380, child: tree),
                        const SizedBox(height: AppLayoutTokens.sectionGap),
                        Expanded(child: detail),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 380, child: tree),
                      const SizedBox(width: AppLayoutTokens.sectionGap),
                      Expanded(child: detail),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OrganizationTreeHeader extends StatelessWidget {
  final bool loading;
  final AdminOrganizationNode? selected;
  final bool canEditStructure;
  final Future<void> Function() onReload;
  final VoidCallback? onAdd;

  const _OrganizationTreeHeader({
    super.key,
    required this.loading,
    required this.selected,
    required this.canEditStructure,
    required this.onReload,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 640;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cơ cấu tổ chức', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Quản lý cây tổ chức và quyền theo node.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        AdminOrganizationNodeTypes.titleOf(selected!.type),
                      ),
                    ),
                    Chip(
                      label: Text(
                        selected!.isActive ? 'Đang hoạt động' : 'Đã tắt',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconAction(
                onPressed: loading ? null : () => unawaited(onReload()),
                icon: Icons.refresh_outlined,
                tooltip: 'Tải lại',
              ),
              if (canEditStructure) ...[
                const SizedBox(width: 8),
                AppIconAction(
                  onPressed: loading ? null : onAdd,
                  icon: Icons.add_outlined,
                  tooltip: 'Thêm node',
                ),
              ],
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.account_tree_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: title),
                  ],
                ),
                const SizedBox(height: 12),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.account_tree_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(child: title),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _OrganizationTreePanel extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onClearSearch;
  final Widget child;

  const _OrganizationTreePanel({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClearSearch,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextInput(
            key: const Key('organization-tree-search-field'),
            controller: searchController,
            label: 'Tìm node',
            hintText: 'Mã nghiệp vụ, viết tắt hoặc tên node',
            icon: Icons.search,
            textInputAction: TextInputAction.search,
            onChanged: onSearchChanged,
            onSubmitted: onSearchSubmitted,
            suffixIcon: searchQuery.trim().isEmpty
                ? null
                : AppIconAction(
                    onPressed: onClearSearch,
                    icon: Icons.close_rounded,
                    tooltip: 'Xóa tìm kiếm',
                  ),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _OrganizationTreeList extends StatelessWidget {
  final List<AdminOrganizationNode> nodes;
  final int totalCount;
  final String searchQuery;
  final String? selectedId;
  final Set<String> expandedIds;
  final ValueChanged<String> onSelect;
  final void Function(String id, bool expanded) onExpansionChanged;

  const _OrganizationTreeList({
    required this.nodes,
    required this.totalCount,
    required this.searchQuery,
    required this.selectedId,
    required this.expandedIds,
    required this.onSelect,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      final hasSearch = searchQuery.trim().isNotEmpty;
      return AppStatePanel.empty(
        title: hasSearch ? 'Không tìm thấy node' : 'Chưa có node tổ chức',
        message: hasSearch ? null : 'Bấm nút thêm để tạo node đầu tiên.',
        icon: Icons.account_tree_outlined,
      );
    }
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
    final hasSearch = searchQuery.trim().isNotEmpty;
    return ListView(
      children: [
        if (hasSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Đang hiển thị ${nodes.length}/$totalCount node',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
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
  final bool canManageFeatures;
  final VoidCallback? onAddChild;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onManageFeatures;

  const _OrganizationNodeDetail({
    super.key,
    required this.node,
    required this.nodes,
    required this.canAddChild,
    required this.canEdit,
    required this.canDelete,
    required this.canManageFeatures,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
    required this.onManageFeatures,
  });

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node == null) {
      return const AppStatePanel.empty(
        key: Key('organization-tree-detail-empty-state'),
        icon: Icons.account_tree_outlined,
        title: 'Chưa chọn node',
        message: 'Chọn node để xem chi tiết.',
      );
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
            ],
          ),
          if (node.type == 'LV4_STORE') ...[
            _DetailRow(
              label: 'Mã cửa hàng',
              value: node.storeId ?? node.businessCode ?? node.code,
            ),
            _DetailRow(
              label: 'Tên cửa hàng',
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
          if (canAddChild || canEdit || canDelete || canManageFeatures)
            AppActionRow(
              children: [
                if (canManageFeatures)
                  AppSecondaryButton(
                    onPressed: onManageFeatures,
                    icon: Icons.account_tree_outlined,
                    label: 'Tính năng',
                  ),
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
        Expanded(child: Text(value, style: AppTextStyles.labelM)),
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
    _type =
        node?.type ??
        _defaultChildType(widget.parentId == null ? null : _parentNode());
    _parentId = node?.parentId ?? widget.parentId;
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
    final isDomain = _type == 'LV0_DOMAIN';
    final isShowroom = _type == 'LV4_STORE';
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
              AppTextInput(
                controller: _titleController,
                label: 'Tên hiển thị',
                enabled: canEditStructure,
              ),
              AppTextInput(
                controller: _codeController,
                label: 'Mã internal',
                enabled: canEditStructure,
              ),
              AppTextInput(
                controller: _businessCodeController,
                label: isShowroom ? 'Mã SR' : 'Mã nghiệp vụ',
                enabled: canEditStructure,
              ),
              if (_type == 'LV2_REGION' || _type == 'LV3_AREA')
                AppTextInput(
                  controller: _abbreviationController,
                  label: 'Viết tắt',
                  enabled: canEditStructure,
                ),
              if (_type == 'LV2_REGION' || _type == 'LV3_AREA')
                AppTextInput(
                  controller: _descriptionController,
                  label: 'Mô tả',
                  enabled: canEditStructure,
                ),
              AppSelectField<String>(
                value: _type,
                label: 'Loại node',
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
                    : (value) => setState(() => _setType(value ?? 'LV4_STORE')),
              ),
              AppSelectField<String?>(
                key: ValueKey('parent-$_type-${parentValue ?? 'none'}'),
                value: parentValue,
                label: 'Node cha',
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
                AppTextInput(
                  controller: _emailDomainController,
                  label: 'Email domain',
                  enabled: canEditStructure,
                ),
              if (isShowroom) ...[
                AppTextInput(
                  controller: _mapVietinUsernameController,
                  label: 'MAP username',
                  enabled: canEditMap,
                ),
                AppTextInput(
                  controller: _mapVietinPasswordController,
                  label: widget.node?.hasMapVietinPassword == true
                      ? 'MAP password mới'
                      : 'MAP password',
                  obscureText: true,
                  enabled: canEditMap,
                ),
                AppTextInput(
                  controller: _transferAccountNumberController,
                  label: 'Số tài khoản nhận tiền',
                  enabled: canEditStructure,
                ),
                AppTextInput(
                  controller: _transferAccountNameController,
                  label: 'Tên tài khoản nhận tiền',
                  enabled: canEditStructure,
                ),
                AppTextInput(
                  controller: _transferBankNameController,
                  label: 'Ngân hàng',
                  enabled: canEditStructure,
                ),
                AppTextInput(
                  controller: _transferBankBinController,
                  label: 'BIN',
                  enabled: canEditStructure,
                ),
              ],
              AppTextInput(
                controller: _sortOrderController,
                keyboardType: TextInputType.number,
                label: 'Thứ tự',
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

  void _setType(String type) {
    _type = AdminOrganizationNode.canonicalType(type);
    final parentOptions = _parentOptions();
    _parentId = _validParentId(parentOptions);
    if (_parentId == null && !_allowsEmptyParent(_type)) {
      _parentId = parentOptions.isEmpty ? null : parentOptions.first.id;
    }
  }

  AdminOrganizationNode? _parentNode() {
    final parentId = widget.parentId;
    if (parentId == null) return null;
    for (final node in widget.nodes) {
      if (node.id == parentId) return node;
    }
    return null;
  }

  String _defaultChildType(AdminOrganizationNode? parent) {
    if (parent == null) return 'LV0_DOMAIN';
    return switch (AdminOrganizationNode.canonicalType(parent.type)) {
      'LV0_DOMAIN' => 'LV1_BLOCK',
      'LV1_BLOCK' => 'LV2_REGION',
      'LV2_DEPARTMENT' => 'LV3_UNIT',
      'LV2_REGION' => 'LV3_AREA',
      'LV3_AREA' || 'LV3_UNIT' => 'LV4_STORE',
      'LV4_STORE' => 'LV5_POSITION',
      _ => 'LV5_POSITION',
    };
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
    return AdminOrganizationNode.canonicalType(type) == 'LV0_DOMAIN';
  }

  bool _canUseParentForType(AdminOrganizationNode parent, String type) {
    if (!parent.isActive) return false;
    final childType = AdminOrganizationNode.canonicalType(type);
    if (childType == 'LV0_DOMAIN') return false;
    final childLevel = AdminOrganizationNode.levelOf(childType);
    final parentLevel = AdminOrganizationNode.levelOf(parent.type);
    return parentLevel < childLevel;
  }
}

IconData _iconForType(String type) {
  return switch (AdminOrganizationNode.canonicalType(type)) {
    'LV0_DOMAIN' => Icons.language_outlined,
    'LV1_BLOCK' => Icons.account_tree_outlined,
    'LV2_DEPARTMENT' => Icons.apartment_outlined,
    'LV2_REGION' => Icons.public_outlined,
    'LV3_AREA' => Icons.map_outlined,
    'LV3_UNIT' => Icons.hub_outlined,
    'LV4_STORE' => Icons.store_mall_directory_outlined,
    'LV5_POSITION' => Icons.badge_outlined,
    _ => Icons.account_tree_outlined,
  };
}

Color _colorForType(String type) {
  return switch (AdminOrganizationNode.canonicalType(type)) {
    'LV0_DOMAIN' => AppColors.info,
    'LV1_BLOCK' => AppColors.sky500,
    'LV2_DEPARTMENT' => AppColors.purple600,
    'LV2_REGION' => AppColors.teal600,
    'LV3_AREA' => AppColors.emerald600,
    'LV3_UNIT' => AppColors.warning,
    'LV4_STORE' => AppColors.success,
    'LV5_POSITION' => AppColors.violet600,
    _ => AppColors.neutral500,
  };
}
