import 'package:flutter/material.dart';

import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_personnel_definition.dart';
import '../../domain/admin_role_definition.dart';

class FeatureAdminScreen extends StatefulWidget {
  const FeatureAdminScreen({super.key});

  @override
  State<FeatureAdminScreen> createState() => _FeatureAdminScreenState();
}

class _FeatureAdminScreenState extends State<FeatureAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminFeatureDefinition> _features = [];
  List<AdminFeatureRule> _rules = [];
  List<AdminRoleDefinition> _roles = [];
  List<AdminPersonnelDefinition> _departments = [];
  List<AdminPersonnelDefinition> _jobRoles = [];
  List<AdminRegionDefinition> _regions = [];
  List<AdminAreaDefinition> _areas = [];
  List<StoreBranch> _stores = [];
  List<User> _users = [];
  String? _ruleFeatureFilter;
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
        _repository.listAdminRoles(),
        _repository.listAdminDepartments(),
        _repository.listAdminJobRoles(),
        _repository.listAdminRegions(),
        _repository.listAdminAreas(),
        _repository.listAdminStores(),
        _repository.listUsers(),
      ]);
      if (!mounted) return;
      setState(() {
        _features = results[0] as List<AdminFeatureDefinition>;
        _rules = results[1] as List<AdminFeatureRule>;
        _roles = results[2] as List<AdminRoleDefinition>;
        _departments = results[3] as List<AdminPersonnelDefinition>;
        _jobRoles = results[4] as List<AdminPersonnelDefinition>;
        _regions = results[5] as List<AdminRegionDefinition>;
        _areas = results[6] as List<AdminAreaDefinition>;
        _stores = results[7] as List<StoreBranch>;
        _users = results[8] as List<User>;
      });
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature management load succeeded',
        context: {
          'features': _features.length,
          'rules': _rules.length,
          'users': _users.length,
          'stores': _stores.length,
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
        regions: _regions,
        areas: _areas,
        stores: _stores,
        users: _users,
      ),
    );
    if (updated == true) await _load();
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
        _showMessage('Chưa xóa được tính năng. Có thể đang có rule.');
      }
    }
  }

  Future<void> _deleteRule(AdminFeatureRule rule) async {
    final ruleId = rule.id;
    if (ruleId == null || ruleId.isEmpty) return;
    final confirmed = await _confirm(
      title: 'Xóa rule',
      message: 'Xóa rule của ${rule.featureCode}?',
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
      if (mounted) _showMessage('Chưa xóa được rule. Vui lòng thử lại.');
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
        ) ??
        false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _featureTitle(String code) {
    for (final feature in _features) {
      if (feature.code == code) return feature.title;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GradientHeader(
          title: 'Quản lý tính năng',
          showBack: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tính năng'),
              Tab(text: 'Rules'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => _openFeatureEditor(),
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Thêm tính năng',
            ),
            IconButton(
              onPressed: _loading ? null : () => _openRuleEditor(),
              icon: const Icon(Icons.rule_folder_outlined),
              tooltip: 'Thêm rule',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _FeatureList(
                    features: _features,
                    onEdit: _openFeatureEditor,
                    onDelete: (feature) => feature.isSystem
                        ? null
                        : () {
                            _deleteFeature(feature);
                          },
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
                    onEdit: _openRuleEditor,
                    onDelete: _deleteRule,
                  ),
                ],
              ),
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  final List<AdminFeatureDefinition> features;
  final void Function(AdminFeatureDefinition feature) onEdit;
  final VoidCallback? Function(AdminFeatureDefinition feature) onDelete;

  const _FeatureList({
    required this.features,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) return const Center(child: Text('Chưa có tính năng'));
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      child: ListView.separated(
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
    final color = feature.isActive
        ? const Color(0xFF2563EB)
        : const Color(0xFF6B7280);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${feature.code} • ${feature.ruleCount} rule${feature.description.isEmpty ? '' : ' • ${feature.description}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${feature.isActive ? 'Đang bật' : 'Đang tắt'}${feature.isSystem ? ' • hệ thống' : ''}',
                    style: TextStyle(
                      color: feature.isActive
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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
  final void Function(AdminFeatureRule rule) onEdit;
  final void Function(AdminFeatureRule rule) onDelete;

  const _RuleList({
    required this.rules,
    required this.features,
    required this.featureFilter,
    required this.featureTitle,
    required this.onFilterChanged,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppResponsiveContent(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: AppLayoutTokens.pagePaddingFor(
              MediaQuery.sizeOf(context).width,
            ).copyWith(bottom: 0),
            child: DropdownButtonFormField<String?>(
              initialValue: featureFilter,
              decoration: const InputDecoration(
                labelText: 'Lọc theo tính năng',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Tất cả'),
                ),
                ...features.map(
                  (feature) => DropdownMenuItem<String?>(
                    value: feature.code,
                    child: Text('${feature.code} - ${feature.title}'),
                  ),
                ),
              ],
              onChanged: onFilterChanged,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rules.isEmpty
                ? const Center(child: Text('Chưa có rule'))
                : ListView.separated(
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
    final color = rule.enabled
        ? const Color(0xFF059669)
        : const Color(0xFFDC2626);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                rule.enabled
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _ruleScopeText(rule),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  if (rule.note?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      rule.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            AppIconAction(
              onPressed: onEdit,
              icon: Icons.edit_outlined,
              tooltip: 'Sửa rule',
            ),
            const SizedBox(width: 8),
            AppIconAction(
              onPressed: onDelete,
              icon: Icons.delete_outline,
              tooltip: 'Xóa rule',
            ),
          ],
        ),
      ),
    );
  }

  String _ruleScopeText(AdminFeatureRule rule) {
    final parts = [
      if (rule.userEmail?.isNotEmpty == true) 'User ${rule.userEmail}',
      if (rule.userId?.isNotEmpty == true && rule.userEmail == null)
        'User ${rule.userId}',
      if (rule.storeCode?.isNotEmpty == true) 'SR ${rule.storeCode}',
      if (rule.areaCode?.isNotEmpty == true) 'Vùng ${rule.areaCode}',
      if (rule.regionCode?.isNotEmpty == true) 'Miền ${rule.regionCode}',
      if (rule.workScopeType?.isNotEmpty == true) 'Scope ${rule.workScopeType}',
      if (rule.jobRoleCode?.isNotEmpty == true) 'Chức danh ${rule.jobRoleCode}',
      if (rule.departmentCode?.isNotEmpty == true)
        'Phòng ban ${rule.departmentCode}',
      if (rule.systemRole?.isNotEmpty == true) 'Role ${rule.systemRole}',
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
        ScaffoldMessenger.of(context).showSnackBar(
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
              TextField(
                controller: _codeController,
                enabled: !isSystem,
                decoration: const InputDecoration(labelText: 'Mã tính năng'),
                textCapitalization: TextCapitalization.characters,
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Tên tính năng'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Mô tả'),
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

class _FeatureRuleEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final AdminFeatureRule? rule;
  final List<AdminFeatureDefinition> features;
  final List<AdminRoleDefinition> roles;
  final List<AdminPersonnelDefinition> departments;
  final List<AdminPersonnelDefinition> jobRoles;
  final List<AdminRegionDefinition> regions;
  final List<AdminAreaDefinition> areas;
  final List<StoreBranch> stores;
  final List<User> users;

  const _FeatureRuleEditorDialog({
    required this.repository,
    required this.features,
    required this.roles,
    required this.departments,
    required this.jobRoles,
    required this.regions,
    required this.areas,
    required this.stores,
    required this.users,
    this.rule,
  });

  @override
  State<_FeatureRuleEditorDialog> createState() =>
      _FeatureRuleEditorDialogState();
}

class _FeatureRuleEditorDialogState extends State<_FeatureRuleEditorDialog> {
  final _noteController = TextEditingController();
  late String _featureCode;
  bool _enabled = true;
  String? _systemRole;
  String? _departmentCode;
  String? _jobRoleCode;
  String? _workScopeType;
  String? _regionCode;
  String? _areaCode;
  String? _storeCode;
  String? _userId;
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
    _regionCode = rule?.regionCode;
    _areaCode = rule?.areaCode;
    _storeCode = rule?.storeCode;
    _userId = rule?.userId;
    _noteController.text = rule?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_featureCode.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng chọn tính năng.')));
      return;
    }
    setState(() => _saving = true);
    final rule = AdminFeatureRule(
      id: widget.rule?.id,
      featureCode: _featureCode,
      enabled: _enabled,
      systemRole: _systemRole,
      departmentCode: _departmentCode,
      jobRoleCode: _jobRoleCode,
      workScopeType: _workScopeType,
      regionCode: _regionCode,
      areaCode: _areaCode,
      storeCode: _storeCode,
      userId: _userId,
      note: _noteController.text.trim(),
    );
    try {
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature rule save started',
        context: {
          'featureCode': rule.featureCode,
          'enabled': rule.enabled,
          'mode': widget.rule == null ? 'create' : 'update',
          'hasUser': rule.userId != null,
          'storeCode': rule.storeCode,
          'areaCode': rule.areaCode,
          'regionCode': rule.regionCode,
        },
      );
      final current = widget.rule;
      if (current == null) {
        await widget.repository.createAdminFeatureRule(rule);
      } else {
        await widget.repository.updateAdminFeatureRule(current.id ?? '', rule);
      }
      await AppLogger.instance.info(
        'AdminFeatures',
        'Feature rule save succeeded',
        context: {'featureCode': rule.featureCode, 'enabled': rule.enabled},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AdminFeatures',
        'Feature rule save failed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
        context: {'featureCode': rule.featureCode, 'enabled': rule.enabled},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chưa lưu được rule. Vui lòng thử lại.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredAreas = _regionCode == null
        ? widget.areas
        : widget.areas.where((area) => area.regionCode == _regionCode).toList();
    return AlertDialog(
      title: Text(widget.rule == null ? 'Thêm rule' : 'Sửa rule'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: AppFormColumn(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _featureCode.isEmpty ? null : _featureCode,
                decoration: const InputDecoration(labelText: 'Tính năng'),
                items: widget.features
                    .map(
                      (feature) => DropdownMenuItem(
                        value: feature.code,
                        child: Text('${feature.code} - ${feature.title}'),
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
              _optionalDropdown(
                label: 'Vai trò hệ thống',
                value: _systemRole,
                items: widget.roles
                    .map((role) => (role.value, role.title))
                    .toList(),
                onChanged: (value) => setState(() => _systemRole = value),
              ),
              _optionalDropdown(
                label: 'Phòng ban',
                value: _departmentCode,
                items: widget.departments
                    .map((item) => (item.code, item.title))
                    .toList(),
                onChanged: (value) => setState(() => _departmentCode = value),
              ),
              _optionalDropdown(
                label: 'Chức danh',
                value: _jobRoleCode,
                items: widget.jobRoles
                    .map((item) => (item.code, item.title))
                    .toList(),
                onChanged: (value) => setState(() => _jobRoleCode = value),
              ),
              _optionalDropdown(
                label: 'Phạm vi',
                value: _workScopeType,
                items: AdminWorkScopes.definitions
                    .map((scope) => (scope.value, scope.title))
                    .toList(),
                onChanged: (value) => setState(() => _workScopeType = value),
              ),
              _optionalDropdown(
                label: 'Miền',
                value: _regionCode,
                items: widget.regions
                    .map(
                      (region) => (
                        region.code,
                        '${region.abbreviation} - ${region.title}',
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _regionCode = value;
                  if (value == null) return;
                  final areaMatchesRegion = widget.areas.any(
                    (area) =>
                        area.code == _areaCode && area.regionCode == value,
                  );
                  if (!areaMatchesRegion) _areaCode = null;
                }),
              ),
              _optionalDropdown(
                label: 'Vùng',
                value: _areaCode,
                items: filteredAreas
                    .map(
                      (area) =>
                          (area.code, '${area.abbreviation} - ${area.title}'),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _areaCode = value;
                  if (value == null) return;
                  for (final area in widget.areas) {
                    if (area.code == value) _regionCode = area.regionCode;
                  }
                }),
              ),
              _optionalDropdown(
                label: 'SR',
                value: _storeCode,
                items: widget.stores
                    .map((store) => (store.storeId, store.displayName))
                    .toList(),
                onChanged: (value) => setState(() => _storeCode = value),
              ),
              _optionalDropdown(
                label: 'User override',
                value: _userId,
                items: widget.users
                    .where((user) => user.id?.isNotEmpty == true)
                    .map((user) => (user.id!, user.email))
                    .toList(),
                onChanged: (value) => setState(() => _userId = value),
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

  Widget _optionalDropdown({
    required String label,
    required String? value,
    required List<(String, String)> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
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
}
