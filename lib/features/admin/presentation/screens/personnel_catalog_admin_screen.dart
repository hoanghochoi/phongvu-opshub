import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_personnel_definition.dart';

class PersonnelCatalogAdminScreen extends StatefulWidget {
  const PersonnelCatalogAdminScreen({super.key});

  @override
  State<PersonnelCatalogAdminScreen> createState() =>
      _PersonnelCatalogAdminScreenState();
}

class _PersonnelCatalogAdminScreenState
    extends State<PersonnelCatalogAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminPersonnelDefinition> _departments = [];
  List<AdminPersonnelDefinition> _jobRoles = [];
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
      await AppLogger.instance.info('AdminPersonnel', 'Catalog load started');
      final results = await Future.wait([
        _repository.listAdminDepartments(),
        _repository.listAdminJobRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _departments = results[0];
        _jobRoles = results[1];
      });
      await AppLogger.instance.info(
        'AdminPersonnel',
        'Catalog load succeeded',
        context: {
          'departments': _departments.length,
          'jobRoles': _jobRoles.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPersonnel',
        'Catalog load failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) {
        _showMessage('Chưa tải được danh mục nhân sự. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDepartmentEditor([AdminPersonnelDefinition? item]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _PersonnelEditorDialog(
        repository: _repository,
        type: _CatalogType.department,
        item: item,
        departments: _departments,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _openJobRoleEditor([AdminPersonnelDefinition? item]) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _PersonnelEditorDialog(
        repository: _repository,
        type: _CatalogType.jobRole,
        item: item,
        departments: _departments,
      ),
    );
    if (updated == true) await _load();
  }

  Future<void> _deleteItem(
    AdminPersonnelDefinition item,
    _CatalogType type,
  ) async {
    final label = type == _CatalogType.department ? 'Phòng ban' : 'Chức danh';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xóa $label'),
        content: Text('Xóa $label ${item.title}?'),
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
        'AdminPersonnel',
        'Catalog delete started',
        context: {'type': type.name, 'code': item.code},
      );
      if (type == _CatalogType.department) {
        await _repository.deleteAdminDepartment(item.code);
      } else {
        await _repository.deleteAdminJobRole(item.code);
      }
      await AppLogger.instance.warn(
        'AdminPersonnel',
        'Catalog delete succeeded',
        context: {'type': type.name, 'code': item.code},
      );
      await _load();
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPersonnel',
        'Catalog delete failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'type': type.name, 'code': item.code},
      );
      if (mounted) {
        _showMessage('Chưa xóa được $label. Có thể đang được sử dụng.');
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GradientHeader(
          title: 'Phòng ban & Chức danh',
          showBack: true,
          bottom: TabBar(
            labelColor: AppColors.surface,
            unselectedLabelColor: AppColors.surface.withValues(alpha: 0.70),
            indicatorColor: AppColors.surface,
            dividerColor: AppColors.transparent,
            tabs: const [
              Tab(text: 'Phòng ban'),
              Tab(text: 'Chức danh'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => _openDepartmentEditor(),
              icon: const Icon(Icons.apartment_outlined),
              tooltip: 'Thêm phòng ban',
            ),
            IconButton(
              onPressed: _loading ? null : () => _openJobRoleEditor(),
              icon: const Icon(Icons.badge_outlined),
              tooltip: 'Thêm chức danh',
            ),
          ],
        ),
        body: _loading
            ? const AppResponsiveContent(
                child: AppListSkeleton(itemCount: 6, itemHeight: 72),
              )
            : TabBarView(
                children: [
                  _CatalogList(
                    emptyText: 'Chưa có phòng ban',
                    itemCount: _departments.length,
                    itemBuilder: (context, index) {
                      final item = _departments[index];
                      return _PersonnelCard(
                        item: item,
                        icon: Icons.apartment_outlined,
                        color: AppColors.info,
                        metadata: '${item.userCount} người dùng',
                        onEdit: () => _openDepartmentEditor(item),
                        onDelete: item.isSystem
                            ? null
                            : () => _deleteItem(item, _CatalogType.department),
                      );
                    },
                  ),
                  _CatalogList(
                    emptyText: 'Chưa có chức danh',
                    itemCount: _jobRoles.length,
                    itemBuilder: (context, index) {
                      final item = _jobRoles[index];
                      final department = _departmentTitle(item.departmentCode);
                      return _PersonnelCard(
                        item: item,
                        icon: Icons.badge_outlined,
                        color: AppColors.accent,
                        metadata: [
                          department,
                          '${item.userCount} người dùng',
                        ].where((value) => value.isNotEmpty).join(' • '),
                        onEdit: () => _openJobRoleEditor(item),
                        onDelete: item.isSystem
                            ? null
                            : () => _deleteItem(item, _CatalogType.jobRole),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }

  String _departmentTitle(String? code) {
    if (code == null || code.isEmpty) return '';
    for (final department in _departments) {
      if (department.code == code) return department.title;
    }
    return code;
  }
}

class _CatalogList extends StatelessWidget {
  final String emptyText;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _CatalogList({
    required this.emptyText,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) {
      return AppStatePanel.empty(
        title: emptyText,
        message: 'Bấm nút thêm trên thanh tiêu đề để tạo dữ liệu.',
        icon: Icons.badge_outlined,
      );
    }
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        padding: AppLayoutTokens.pagePaddingFor(
          MediaQuery.sizeOf(context).width,
        ),
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _PersonnelCard extends StatelessWidget {
  final AdminPersonnelDefinition item;
  final IconData icon;
  final Color color;
  final String metadata;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _PersonnelCard({
    required this.item,
    required this.icon,
    required this.color,
    required this.metadata,
    required this.onEdit,
    required this.onDelete,
  });

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
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyL.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.code} • $metadata${item.description.isEmpty ? '' : ' • ${item.description}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.isActive ? 'Đang bật' : 'Đang tắt'}${item.isSystem ? ' • hệ thống' : ''}',
                  style: AppTextStyles.labelS.copyWith(
                    color: item.isActive ? AppColors.success : AppColors.error,
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
            tooltip: item.isSystem ? 'Dòng hệ thống' : 'Xóa',
          ),
        ],
      ),
    );
  }
}

enum _CatalogType { department, jobRole }

class _PersonnelEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final _CatalogType type;
  final AdminPersonnelDefinition? item;
  final List<AdminPersonnelDefinition> departments;

  const _PersonnelEditorDialog({
    required this.repository,
    required this.type,
    required this.departments,
    this.item,
  });

  @override
  State<_PersonnelEditorDialog> createState() => _PersonnelEditorDialogState();
}

class _PersonnelEditorDialogState extends State<_PersonnelEditorDialog> {
  final _codeController = TextEditingController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _departmentCode;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _codeController.text = item?.code ?? '';
    _titleController.text = item?.title ?? '';
    _descriptionController.text = item?.description ?? '';
    _departmentCode = item?.departmentCode;
    _isActive = item?.isActive ?? true;
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
    final item = AdminPersonnelDefinition(
      code: _codeController.text.trim().toUpperCase(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      departmentCode: widget.type == _CatalogType.jobRole
          ? _departmentCode
          : null,
      isActive: _isActive,
    );
    try {
      await AppLogger.instance.info(
        'AdminPersonnel',
        'Catalog save started',
        context: {
          'type': widget.type.name,
          'code': item.code,
          'mode': widget.item == null ? 'create' : 'update',
        },
      );
      final current = widget.item;
      if (widget.type == _CatalogType.department) {
        if (current == null) {
          await widget.repository.createAdminDepartment(item);
        } else {
          await widget.repository.updateAdminDepartment(current.code, item);
        }
      } else {
        if (current == null) {
          await widget.repository.createAdminJobRole(item);
        } else {
          await widget.repository.updateAdminJobRole(current.code, item);
        }
      }
      await AppLogger.instance.info(
        'AdminPersonnel',
        'Catalog save succeeded',
        context: {'type': widget.type.name, 'code': item.code},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminPersonnel',
        'Catalog save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'type': widget.type.name, 'code': item.code},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được danh mục. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystem = widget.item?.isSystem == true;
    final label = widget.type == _CatalogType.department
        ? 'Phòng ban'
        : 'Chức danh';
    return AlertDialog(
      title: Text(widget.item == null ? 'Thêm $label' : 'Sửa $label'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              AppTextInput(
                controller: _codeController,
                enabled: !isSystem,
                label: 'Mã $label',
                textCapitalization: TextCapitalization.characters,
              ),
              AppTextInput(controller: _titleController, label: 'Tên $label'),
              if (widget.type == _CatalogType.jobRole)
                AppSelectField<String?>(
                  value: _departmentCode,
                  label: 'Phòng ban',
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Chưa gán'),
                    ),
                    ...widget.departments.map(
                      (department) => DropdownMenuItem<String?>(
                        value: department.code,
                        child: Text(department.title),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _departmentCode = value),
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
