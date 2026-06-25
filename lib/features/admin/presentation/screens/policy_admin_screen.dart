import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../domain/admin_organization_node.dart';
import '../../domain/admin_policy_definition.dart';
import '../../domain/admin_role_definition.dart';

class PolicyAdminScreen extends StatefulWidget {
  const PolicyAdminScreen({super.key});

  @override
  State<PolicyAdminScreen> createState() => _PolicyAdminScreenState();
}

class _PolicyAdminScreenState extends State<PolicyAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  List<AdminPolicyDefinition> _policies = [];
  List<AdminPolicyRule> _rules = [];
  List<AdminSettingDefinition> _settings = [];
  List<AdminOrganizationNode> _organizationNodes = [];
  String? _rulePolicyFilter;
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
      );
      if (mounted) _showMessage('Chưa tải được quản lý policy.');
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
    final confirmed = await _confirm('Xóa policy ${policy.code}?');
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
      if (mounted) _showMessage('Chưa xóa được policy. Có thể đang có rule.');
    }
  }

  Future<void> _deleteRule(AdminPolicyRule rule) async {
    final id = rule.id;
    if (id == null || id.isEmpty) return;
    final confirmed = await _confirm('Xóa rule của ${rule.policyCode}?');
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
      if (mounted) _showMessage('Chưa xóa được rule.');
    }
  }

  Future<bool> _confirm(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận'),
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

  String _policyTitle(String code) {
    for (final policy in _policies) {
      if (policy.code == code) return policy.title;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: GradientHeader(
          title: 'Quản lý policy',
          showBack: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Policy'),
              Tab(text: 'Rules'),
              Tab(text: 'Cấu hình'),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _loading ? null : () => _openPolicyEditor(),
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Thêm policy',
            ),
            IconButton(
              onPressed: _loading ? null : () => _openRuleEditor(),
              icon: const Icon(Icons.rule_folder_outlined),
              tooltip: 'Thêm rule',
            ),
            IconButton(
              onPressed: _loading ? null : () => _openSettingEditor(),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Thêm cấu hình',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : AppResponsiveContent(
                child: TabBarView(
                  children: [
                    _buildPoliciesTab(),
                    _buildRulesTab(),
                    _buildSettingsTab(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPoliciesTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _policies.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final policy = _policies[index];
        return ListTile(
          title: Text('${policy.title} (${policy.code})'),
          subtitle: Text(
            '${policy.category} • default=${policy.defaultAllowed ? 'bật' : 'tắt'} • ${policy.ruleCount} rules',
          ),
          leading: Icon(
            policy.isActive ? Icons.policy_outlined : Icons.block_outlined,
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                onPressed: () => _openPolicyEditor(policy),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Sửa',
              ),
              IconButton(
                onPressed: policy.isSystem ? null : () => _deletePolicy(policy),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Xóa',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRulesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String?>(
            initialValue: _rulePolicyFilter,
            decoration: const InputDecoration(labelText: 'Lọc theo policy'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Tất cả'),
              ),
              ..._policies.map(
                (policy) => DropdownMenuItem<String?>(
                  value: policy.code,
                  child: Text('${policy.title} (${policy.code})'),
                ),
              ),
            ],
            onChanged: (value) async {
              setState(() => _rulePolicyFilter = value);
              await _load();
            },
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _rules.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final rule = _rules[index];
              return ListTile(
                leading: Icon(
                  rule.allowed
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                  color: rule.allowed ? Colors.green : Colors.red,
                ),
                title: Text(
                  '${_policyTitle(rule.policyCode)} (${rule.policyCode})',
                ),
                subtitle: Text(_ruleSummary(rule)),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      onPressed: () => _openRuleEditor(rule),
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Sửa',
                    ),
                    IconButton(
                      onPressed: () => _deleteRule(rule),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Xóa',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _settings.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final setting = _settings[index];
        return ListTile(
          leading: const Icon(Icons.tune_outlined),
          title: Text('${setting.title} (${setting.key})'),
          subtitle: Text(
            '${setting.category} • ${_compactJson(setting.value)}',
          ),
          trailing: IconButton(
            onPressed: () => _openSettingEditor(setting),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Sửa',
          ),
        );
      },
    );
  }

  String _ruleSummary(AdminPolicyRule rule) {
    final parts = <String>[
      rule.allowed ? 'Cho phép' : 'Chặn',
      if (rule.emailDomain?.isNotEmpty == true)
        'Domain email: ${rule.emailDomain}',
      if (rule.systemRole?.isNotEmpty == true)
        'Vai trò: ${AdminRoles.displayTitle(rule.systemRole)}',
      if (rule.organizationNodeName?.isNotEmpty == true)
        'Node tổ chức: ${rule.organizationNodeName}',
      if (rule.organizationNodeId?.isNotEmpty == true &&
          rule.organizationNodeName == null)
        'Node tổ chức: ${rule.organizationNodeId}',
      if (_legacyRuleSummary(rule) != null)
        'Điều kiện cũ: ${_legacyRuleSummary(rule)}',
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
      if (rule.storeCode?.isNotEmpty == true) 'SR: ${rule.storeCode}',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chưa lưu được policy.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.policy == null ? 'Thêm policy' : 'Sửa policy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Mã policy'),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Tên hiển thị'),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Nhóm'),
            ),
            SwitchListTile(
              value: _defaultAllowed,
              onChanged: (value) => setState(() => _defaultAllowed = value),
              title: const Text('Mặc định bật khi không có rule'),
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
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Lưu'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chọn node tổ chức cho rule.')),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chưa lưu được rule.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? 'Thêm policy rule' : 'Sửa policy rule'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _policyCode,
              decoration: const InputDecoration(labelText: 'Policy'),
              items: widget.policies
                  .map(
                    (policy) => DropdownMenuItem(
                      value: policy.code,
                      child: Text('${policy.title} (${policy.code})'),
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
            _csvField(_emailDomains, 'Domain email'),
            _csvField(_systemRoles, 'Vai trò hệ thống'),
            _organizationNodePicker(),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Lưu'),
        ),
      ],
    );
  }

  Widget _csvField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'Có thể nhập nhiều giá trị, phân tách bằng dấu phẩy',
      ),
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
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Node tổ chức',
          border: OutlineInputBorder(),
        ),
        child: Text(
          selectedLabels.isEmpty ? 'Chưa chọn node' : selectedLabels.join(', '),
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
      title: const Text('Node tổ chức'),
      content: SizedBox(
        width: 560,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Tìm node',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filteredItems.isEmpty
                  ? const Center(child: Text('Không có dữ liệu'))
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
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('Bỏ chọn'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({..._selected}),
          child: const Text('Áp dụng'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giá trị phải là JSON hợp lệ.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _key,
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Tên hiển thị'),
            ),
            TextField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Mô tả'),
            ),
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Nhóm'),
            ),
            TextField(
              controller: _value,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(labelText: 'Giá trị JSON'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
