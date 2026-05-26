import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_role_definition.dart';

class RoleAdminScreen extends StatefulWidget {
  const RoleAdminScreen({super.key});

  @override
  State<RoleAdminScreen> createState() => _RoleAdminScreenState();
}

class _RoleAdminScreenState extends State<RoleAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminRoleDefinition> _roles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roles = await _repository.listAdminRoles();
      if (!mounted) return;
      setState(() => _roles = roles);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([AdminRoleDefinition? role]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _RoleEditorDialog(repository: _repository, role: role),
    );
    if (updated == true) await _load();
  }

  Future<void> _deleteRole(AdminRoleDefinition role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa vai trò'),
        content: Text('Xóa vai trò ${role.value}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Hủy',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Xóa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _repository.deleteAdminRole(role.value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final canManageRoles = context.select<AuthProvider, bool>(
      (auth) => auth.user?.role == 'SUPER_ADMIN',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: GradientHeader(
        title: 'Quản lý vai trò',
        showBack: true,
        actions: canManageRoles
            ? [
                IconButton(
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.add_moderator_outlined),
                  tooltip: 'Thêm vai trò',
                ),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AppResponsiveContent(
              padding: EdgeInsets.zero,
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: AppLayoutTokens.pagePaddingFor(
                    MediaQuery.sizeOf(context).width,
                  ),
                  itemCount: _roles.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppLayoutTokens.cardGap),
                  itemBuilder: (context, index) {
                    final role = _roles[index];
                    return _RoleCard(
                      role: role,
                      onEdit: canManageRoles ? () => _openEditor(role) : null,
                      onDelete: canManageRoles && !role.isSystem
                          ? () => _deleteRole(role)
                          : null,
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final AdminRoleDefinition role;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _RoleCard({
    required this.role,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: role.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
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
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role.description.isEmpty ? role.value : role.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppIconAction(
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              tooltip: 'Sửa vai trò',
            ),
            const SizedBox(width: 8),
            AppIconAction(
              onPressed: onDelete,
              icon: Icons.delete_outline,
              tooltip: role.isSystem ? 'Vai trò hệ thống' : 'Xóa vai trò',
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminRoleDefinition? role;

  const _RoleEditorDialog({required this.repository, this.role});

  @override
  State<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<_RoleEditorDialog> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _codeController.text = role?.value ?? '';
    _titleController.text = role?.title ?? '';
    _descriptionController.text = role?.description ?? '';
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
    try {
      final role = AdminRoleDefinition(
        value: _codeController.text.trim().toUpperCase(),
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        icon: Icons.security_outlined,
        color: const Color(0xFF9333EA),
      );

      final current = widget.role;
      if (current == null) {
        await widget.repository.createAdminRole(role);
      } else {
        await widget.repository.updateAdminRole(current.value, role);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.role?.isSystem == true;

    return AlertDialog(
      title: Text(widget.role == null ? 'Thêm vai trò' : 'Sửa vai trò'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _codeController,
                enabled: !isSystem,
                decoration: const InputDecoration(labelText: 'Mã vai trò'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Tên hiển thị'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Mô tả'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text(
            'Hủy',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving ? 'Đang lưu...' : 'Lưu',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}
