import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/validators.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_feature_definition.dart';
import '../../domain/admin_organization_node.dart';
import '../../domain/admin_personnel_definition.dart';
import '../../domain/admin_role_definition.dart';
import '../../domain/admin_user_editor_payload.dart';

String adminUserSaveErrorMessage(Object error) =>
    error is ApiException ? error.message : 'Không lưu được người dùng';

class UserAdminScreen extends StatefulWidget {
  const UserAdminScreen({super.key});

  @override
  State<UserAdminScreen> createState() => _UserAdminScreenState();
}

class _UserAdminScreenState extends State<UserAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  final _searchController = TextEditingController();
  List<User> _users = [];
  List<AdminRoleDefinition> _roles = AdminRoles.definitions;
  List<AdminPersonnelDefinition> _jobRoles = [];
  List<AdminRegionDefinition> _regions = [];
  List<AdminAreaDefinition> _areas = [];
  List<AdminFeatureDefinition> _features = [];
  List<AdminOrganizationNode> _orgNodes = [];
  String? _domainFilter;
  String? _orgNodeFilter;
  String? _featureFilter;
  String? _roleFilter;
  String? _statusFilter;
  bool _loading = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final currentUser = context.read<AuthProvider>().user;
    final canUseRoles = currentUser?.canUseFeature('ADMIN_ROLES') == true;
    final canUseUserScopeTree =
        currentUser?.role == 'SUPER_ADMIN' ||
        currentUser?.canUseFeature('ADMIN_USERS') == true;
    final canUseFeatures =
        currentUser?.role == 'SUPER_ADMIN' ||
        currentUser?.canUseFeature('ADMIN_FEATURES') == true;
    await AppLogger.instance.info(
      'Admin',
      'Admin user management load started',
      context: {
        'role': currentUser?.role,
        'email': currentUser?.email,
        'canUseRoles': canUseRoles,
        'canUseUserScopeTree': canUseUserScopeTree,
        'canUseFeatures': canUseFeatures,
      },
    );
    try {
      final results = await Future.wait<Object>([
        _repository.listUsers(
          query: _searchController.text,
          domain: _domainFilter,
          orgNodeId: _orgNodeFilter,
          featureCode: _featureFilter,
          role: _roleFilter,
          status: _statusFilter,
        ),
        canUseRoles
            ? _repository.listAdminRoles()
            : Future.value(AdminRoles.definitions),
        canUseFeatures
            ? _repository.listAdminFeatureTree()
            : Future.value(<AdminFeatureDefinition>[]),
        canUseUserScopeTree
            ? _repository.listAdminUserScopeTree()
            : Future.value(<AdminOrganizationNode>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<User>;
        _roles = results[1] as List<AdminRoleDefinition>;
        _jobRoles = const <AdminPersonnelDefinition>[];
        _regions = const <AdminRegionDefinition>[];
        _areas = const <AdminAreaDefinition>[];
        _features = results[2] as List<AdminFeatureDefinition>;
        _orgNodes = results[3] as List<AdminOrganizationNode>;
      });
      await AppLogger.instance.info(
        'Admin',
        'Admin user management load succeeded',
        context: {
          'role': currentUser?.role,
          'userCount': _users.length,
          'roleCount': _roles.length,
          'featureCount': _features.length,
          'orgNodeCount': _orgNodes.length,
        },
      );
    } catch (error) {
      await AppLogger.instance.error(
        'Admin',
        'Admin user management load failed',
        error: error,
        upload: true,
        context: {'role': currentUser?.role, 'email': currentUser?.email},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tải được danh sách người dùng')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword(User user) async {
    final userId = user.id;
    if (userId == null || userId.isEmpty) return;
    final newPassword = await _showAdminResetPasswordDialog(user);
    if (newPassword == null) return;

    await AppLogger.instance.info(
      'Admin',
      'Admin password reset started',
      context: {'userId': userId, 'email': user.email, 'role': user.role},
    );
    try {
      await _repository.resetAdminUserPassword(
        userId,
        email: user.email,
        newPassword: newPassword,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await AppLogger.instance.info(
        'Admin',
        'Admin password reset succeeded',
        context: {'userId': userId, 'email': user.email},
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã đổi mật khẩu cho ${user.email}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await AppLogger.instance.error(
        'Admin',
        'Admin password reset failed',
        error: e,
        upload: true,
        context: {'userId': userId, 'email': user.email},
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Không đổi được mật khẩu'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _showAdminResetPasswordDialog(User user) async {
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var obscurePassword = true;
    var obscureConfirm = true;

    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Đổi mật khẩu user'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(user.email),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        Validators.getPasswordError(value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    obscureText: obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Nhập lại mật khẩu mới',
                      prefixIcon: const Icon(Icons.lock_reset_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscureConfirm = !obscureConfirm,
                        ),
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value != passwordController.text) {
                        return 'Mật khẩu nhập lại chưa khớp';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(context).pop(passwordController.text);
                },
                child: const Text('Đổi mật khẩu'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passwordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _openEditor([User? user]) async {
    final canEditRole =
        context.read<AuthProvider>().user?.role == 'SUPER_ADMIN';
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _UserEditorDialog(
        repository: _repository,
        roles: _roles,
        regions: _regions,
        areas: _areas,
        orgNodes: _orgNodes,
        user: user,
        canEditRole: canEditRole,
      ),
    );
    if (updated == true) await _load();
  }

  String _roleTitle(String? value) {
    for (final role in _roles) {
      if (role.value == value) return role.title;
    }
    return value?.isNotEmpty == true ? value! : 'Chưa gán';
  }

  String _personnelTitle(User user) {
    final code = user.personnelCode;
    if (code?.isNotEmpty == true) return code!;
    final jobRole = _definitionTitle(_jobRoles, user.jobRoleCode);
    final scope = AdminWorkScopes.titleOf(user.workScopeType);
    if (jobRole != 'Chưa gán') return '$jobRole • $scope';
    return scope;
  }

  String _definitionTitle(
    List<AdminPersonnelDefinition> definitions,
    String? value,
  ) {
    for (final definition in definitions) {
      if (definition.code == value) return definition.title;
    }
    return value?.isNotEmpty == true ? value! : 'Chưa gán';
  }

  List<String> get _domainOptions {
    final domains =
        _orgNodes
            .map((node) => node.emailDomain)
            .where((domain) => domain?.isNotEmpty == true)
            .cast<String>()
            .toSet()
            .toList()
          ..sort();
    return domains;
  }

  void _resetFilters() {
    setState(() {
      _domainFilter = null;
      _orgNodeFilter = null;
      _featureFilter = null;
      _roleFilter = null;
      _statusFilter = null;
      _searchController.clear();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final currentRole = context.watch<AuthProvider>().user?.role;
    final canResetPassword =
        currentRole == 'SUPER_ADMIN' || User.isAdminRole(currentRole);
    return Scaffold(
      appBar: GradientHeader(
        title: 'Quản lý người dùng',
        showBack: true,
        actions: [
          IconButton(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Thêm người dùng',
          ),
        ],
      ),
      body: AppResponsiveContent(
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm email hoặc tên',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: AppIconAction(
                  onPressed: _load,
                  icon: Icons.refresh,
                  tooltip: 'Tải lại',
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterDropdown<String>(
                  width: 180,
                  value: _domainFilter,
                  label: 'Domain',
                  items: _domainOptions
                      .map(
                        (domain) => DropdownMenuItem(
                          value: domain,
                          child: Text(domain),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _domainFilter = value);
                    _load();
                  },
                ),
                _FilterDropdown<String>(
                  width: 220,
                  value: _orgNodeFilter,
                  label: 'Cơ cấu',
                  items: _orgNodes
                      .map(
                        (node) => DropdownMenuItem(
                          value: node.id,
                          child: Text(node.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _orgNodeFilter = value);
                    _load();
                  },
                ),
                _FilterDropdown<String>(
                  width: 220,
                  value: _featureFilter,
                  label: 'Màn hình',
                  items: _features
                      .map(
                        (feature) => DropdownMenuItem(
                          value: feature.code,
                          child: Text(feature.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _featureFilter = value);
                    _load();
                  },
                ),
                _FilterDropdown<String>(
                  width: 180,
                  value: _roleFilter,
                  label: 'Role',
                  items: _roles
                      .map(
                        (role) => DropdownMenuItem(
                          value: role.value,
                          child: Text(role.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _roleFilter = value);
                    _load();
                  },
                ),
                _FilterDropdown<String>(
                  width: 160,
                  value: _statusFilter,
                  label: 'Trạng thái',
                  items: const [
                    DropdownMenuItem(value: 'yes', child: Text('Hoạt động')),
                    DropdownMenuItem(value: 'no', child: Text('Khóa')),
                  ],
                  onChanged: (value) {
                    setState(() => _statusFilter = value);
                    _load();
                  },
                ),
                SizedBox(
                  width: 150,
                  child: AppSecondaryButton(
                    onPressed: _resetFilters,
                    icon: Icons.filter_alt_off_outlined,
                    label: 'Xóa filter',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return ListTile(
                          tileColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: CircleAvatar(
                            child: Text(
                              (user.name ?? user.email)[0].toUpperCase(),
                            ),
                          ),
                          title: Text(user.email),
                          subtitle: Text(
                            '${_roleTitle(user.role)} • ${user.storeInfo}\n${_personnelTitle(user)}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canResetPassword) ...[
                                AppIconAction(
                                  onPressed: () => _resetPassword(user),
                                  icon: Icons.lock_reset_outlined,
                                  tooltip: 'Reset mật khẩu',
                                ),
                                const SizedBox(width: 8),
                              ],
                              AppIconAction(
                                onPressed: () => _openEditor(user),
                                icon: Icons.edit_outlined,
                                tooltip: 'Sửa người dùng',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final double width;
  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.width,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          DropdownMenuItem<T?>(value: null, child: const Text('Tất cả')),
          ...items,
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _UserEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final List<AdminRoleDefinition> roles;
  final List<AdminRegionDefinition> regions;
  final List<AdminAreaDefinition> areas;
  final List<AdminOrganizationNode> orgNodes;
  final User? user;
  final bool canEditRole;

  const _UserEditorDialog({
    required this.repository,
    required this.roles,
    required this.regions,
    required this.areas,
    required this.orgNodes,
    required this.canEditRole,
    this.user,
  });

  @override
  State<_UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<_UserEditorDialog> {
  final _emailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  String _role = 'USER';
  String _status = 'yes';
  String? _storeId;
  String? _jobRoleCode;
  String _workScopeType = 'STORE';
  String? _regionCode;
  String? _areaCode;
  String? _organizationNodeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _emailController.text = user?.email ?? '';
    _firstNameController.text = user?.name ?? '';
    _lastNameController.text = user?.lastName ?? '';
    _role = User.normalizeRole(user?.role);
    _status = user?.status ?? 'yes';
    _storeId = user?.storeId;
    _jobRoleCode = user?.jobRoleCode;
    _workScopeType = user?.workScopeType ?? _defaultScopeForRole(_role);
    _regionCode = user?.regionCode;
    _areaCode = user?.areaCode;
    _organizationNodeId = user?.organizationNodeId ?? _legacyScopeNodeId(user);
    _applyOrganizationNodeToState(_selectedOrganizationNode());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final stopwatch = Stopwatch()..start();
    final body = _buildBody();
    final user = widget.user;
    final selectedNode = _selectedOrganizationNode();
    if (user != null) {
      final changes = _changeSummary(user, body);
      if (changes.isEmpty) {
        Navigator.of(context).pop(false);
        return;
      }
      final confirmed = await _confirmSave(changes);
      if (confirmed != true) {
        _resetToOriginal();
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await AppLogger.instance.info(
        'Admin',
        'Admin user editor save started',
        context: {
          'mode': user == null ? 'create' : 'update',
          'targetUserId': user?.id,
          'targetEmail': user?.email ?? body['email'],
          'targetRole': _role,
          'workScopeType': _workScopeType,
          'organizationNodeId': _organizationNodeId,
          'organizationNodeType': selectedNode?.type,
          'durationMs': 0,
        },
      );
      if (user == null) {
        await widget.repository.createAdminUser(body);
      } else {
        await widget.repository.updateAdminUser(user.id ?? '', body);
      }
      await AppLogger.instance.info(
        'Admin',
        'Admin user editor save succeeded',
        context: {
          'mode': user == null ? 'create' : 'update',
          'targetUserId': user?.id,
          'targetEmail': user?.email ?? body['email'],
          'targetRole': _role,
          'workScopeType': _workScopeType,
          'organizationNodeId': _organizationNodeId,
          'organizationNodeType': selectedNode?.type,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      final message = adminUserSaveErrorMessage(error);
      await AppLogger.instance.error(
        'Admin',
        'Admin user editor save failed',
        error: message,
        upload: true,
        context: {
          'mode': user == null ? 'create' : 'update',
          'targetUserId': user?.id,
          'targetEmail': user?.email ?? body['email'],
          'targetRole': _role,
          'workScopeType': _workScopeType,
          'organizationNodeId': _organizationNodeId,
          'organizationNodeType': selectedNode?.type,
          'errorType': error.runtimeType.toString(),
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _buildBody() {
    return AdminUserEditorPayload.build(
      email: _emailController.text,
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      status: _status,
      role: _role,
      organizationNodeId: _organizationNodeId,
      canEditRole: widget.canEditRole,
    );
  }

  List<String> _changeSummary(User user, Map<String, dynamic> body) {
    final changes = <String>[];
    void addIfChanged(String key, Object? oldValue, String label) {
      final nextValue = body[key];
      if ((oldValue ?? '').toString() != (nextValue ?? '').toString()) {
        changes.add(label);
      }
    }

    addIfChanged('firstName', user.name, 'Tên');
    addIfChanged('lastName', user.lastName, 'Họ');
    addIfChanged('status', user.status, 'Trạng thái');
    addIfChanged('organizationNodeId', user.organizationNodeId, 'Node tổ chức');
    if (widget.canEditRole) addIfChanged('role', user.role, 'Quyền hệ thống');
    return changes;
  }

  Future<bool?> _confirmSave(List<String> changes) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận lưu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final change in changes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text(change),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy thay đổi'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xác nhận lưu'),
          ),
        ],
      ),
    );
  }

  void _resetToOriginal() {
    final user = widget.user;
    if (user == null) return;
    setState(() {
      _emailController.text = user.email;
      _firstNameController.text = user.name ?? '';
      _lastNameController.text = user.lastName ?? '';
      _role = User.normalizeRole(user.role);
      _status = user.status ?? 'yes';
      _storeId = user.storeId;
      _jobRoleCode = user.jobRoleCode;
      _workScopeType = user.workScopeType ?? _defaultScopeForRole(_role);
      _regionCode = user.regionCode;
      _areaCode = user.areaCode;
      _organizationNodeId = user.organizationNodeId ?? _legacyScopeNodeId(user);
      _applyOrganizationNodeToState(_selectedOrganizationNode());
    });
  }

  String _roleTitle(String value) {
    for (final role in widget.roles) {
      if (role.value == value) return role.title;
    }
    return value;
  }

  String _defaultScopeForRole(String role) {
    return User.isAdminRole(role) ? 'NATIONAL' : 'STORE';
  }

  void _setRole(String value) {
    setState(() {
      _role = User.normalizeRole(value);
      if (widget.user?.workScopeType == null) {
        _workScopeType = _defaultScopeForRole(_role);
      }
    });
  }

  String _previewPersonnelCode(String? jobRoleCode, String scope) {
    if (jobRoleCode == null || jobRoleCode.isEmpty) return 'Chưa gán';
    final region = _regionAbbr(_regionCode);
    final area = _areaAbbr(_areaCode);
    if (scope == 'STORE') {
      final store = _storeId?.isNotEmpty == true ? _storeId! : 'STORE';
      return '${jobRoleCode}_${store}_${area ?? 'CHUA_GAN'}_${region ?? 'CHUA_GAN'}';
    }
    if (scope == 'AREA') {
      final value = area ?? 'CHUA_GAN';
      return '${jobRoleCode}_${value}_${value}_${region ?? 'CHUA_GAN'}';
    }
    if (scope == 'REGION') {
      final value = region ?? 'CHUA_GAN';
      return '${jobRoleCode}_${value}_${value}_$value';
    }
    return '${jobRoleCode}_NATIONAL_NATIONAL_NATIONAL';
  }

  String? _regionAbbr(String? code) {
    final node = _scopeNodeByBusinessCode('REGION', code);
    if (node?.abbreviation?.isNotEmpty == true) return node!.abbreviation;
    for (final region in widget.regions) {
      if (region.code == code) return region.abbreviation;
    }
    return code;
  }

  String? _areaAbbr(String? code) {
    final node = _scopeNodeByBusinessCode('AREA', code);
    if (node?.abbreviation?.isNotEmpty == true) return node!.abbreviation;
    for (final area in widget.areas) {
      if (area.code == code) return area.abbreviation;
    }
    return code;
  }

  bool get _allowsGlobalNationalScope =>
      _workScopeType == 'NATIONAL' && _role == 'SUPER_ADMIN';

  String? _nodeTypeForScope(String scope) {
    return switch (scope) {
      'NATIONAL' => 'LV0_DOMAIN',
      'REGION' => 'LV2_REGION',
      'AREA' => 'LV3_AREA',
      'STORE' => 'LV4_STORE',
      _ => null,
    };
  }

  List<AdminOrganizationNode> _scopeNodes() =>
      widget.orgNodes.where((node) => node.isActive).toList();

  String _scopeNodeLabel() => 'Node tổ chức';

  String _scopeNodeHint() {
    if (_allowsGlobalNationalScope) return 'Toàn hệ thống';
    return 'Chọn Lv0-Lv5';
  }

  String _selectedOrganizationNodeText() {
    if (_organizationNodeId == null && _allowsGlobalNationalScope) {
      return 'Toàn hệ thống';
    }
    final node = _selectedOrganizationNode();
    if (node == null) return '';
    return _nodeBreadcrumb(node);
  }

  AdminOrganizationNode? _selectedOrganizationNode() =>
      _nodeById(_organizationNodeId);

  AdminOrganizationNode? _nodeById(String? nodeId) {
    if (nodeId == null || nodeId.isEmpty) return null;
    for (final node in widget.orgNodes) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  String _nodeCode(AdminOrganizationNode node) =>
      node.businessCode ?? node.storeId ?? node.code;

  String _nodeBreadcrumb(AdminOrganizationNode node) {
    final path = <AdminOrganizationNode>[node];
    var parentId = node.parentId;
    for (var guard = 0; parentId != null && guard < 50; guard += 1) {
      final parent = _nodeById(parentId);
      if (parent == null) break;
      path.insert(0, parent);
      parentId = parent.parentId;
    }
    return path.map(_nodeCompactLabel).join(' / ');
  }

  String _nodeCompactLabel(AdminOrganizationNode node) {
    final code = _nodeCode(node);
    if (code.isEmpty || code == node.title) return node.title;
    return '${node.title} ($code)';
  }

  String _nodeSearchText(AdminOrganizationNode node) {
    return [
      _nodeBreadcrumb(node),
      AdminOrganizationNodeTypes.titleOf(node.type),
      node.title,
      node.code,
      node.businessCode,
      node.abbreviation,
      node.emailDomain,
      node.storeId,
      node.storeName,
    ].whereType<String>().join(' ').toLowerCase();
  }

  List<AdminOrganizationNode> _filteredScopeNodes(String query, String? type) {
    final normalizedQuery = query.trim().toLowerCase();
    final normalizedType = type?.trim();
    final nodes = _scopeNodes().where((node) {
      final typeMatches =
          normalizedType == null ||
          normalizedType.isEmpty ||
          node.type == normalizedType;
      final queryMatches =
          normalizedQuery.isEmpty ||
          _nodeSearchText(node).contains(normalizedQuery);
      return typeMatches && queryMatches;
    }).toList();
    nodes.sort((left, right) {
      final level = left.level.compareTo(right.level);
      if (level != 0) return level;
      final order = left.sortOrder.compareTo(right.sortOrder);
      if (order != 0) return order;
      return _nodeBreadcrumb(left).compareTo(_nodeBreadcrumb(right));
    });
    return nodes;
  }

  Future<void> _openOrganizationNodePicker() async {
    var query = '';
    String? type;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final nodes = _filteredScopeNodes(query, type);
            return AlertDialog(
              title: const Text('Chọn node tổ chức'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Tìm node, mã SR, domain',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                    DropdownButtonFormField<String?>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Loại node'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Tất cả'),
                        ),
                        ...AdminOrganizationNodeTypes.definitions.map(
                          (item) => DropdownMenuItem(
                            value: item.$1,
                            child: Text(item.$2),
                          ),
                        ),
                      ],
                      onChanged: (value) => setDialogState(() => type = value),
                    ),
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                    Expanded(
                      child: ListView.separated(
                        itemCount:
                            nodes.length + (_allowsGlobalNationalScope ? 1 : 0),
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (_allowsGlobalNationalScope && index == 0) {
                            final selected = _organizationNodeId == null;
                            return ListTile(
                              selected: selected,
                              leading: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.public_rounded,
                              ),
                              title: const Text('Toàn hệ thống'),
                              subtitle: const Text('SUPER_ADMIN global'),
                              onTap: () =>
                                  Navigator.of(context).pop('__GLOBAL__'),
                            );
                          }
                          final nodeIndex = _allowsGlobalNationalScope
                              ? index - 1
                              : index;
                          final node = nodes[nodeIndex];
                          return _OrganizationNodeOptionTile(
                            node: node,
                            selected: node.id == _organizationNodeId,
                            title: _nodeBreadcrumb(node),
                            code: _nodeCode(node),
                            onTap: () => Navigator.of(context).pop(node.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;
    if (selected == null) return;
    final nextNodeId = selected == '__GLOBAL__' ? null : selected;
    if (nextNodeId != _organizationNodeId) {
      _applyOrganizationNode(nextNodeId);
    }
  }

  AdminOrganizationNode? _scopeNodeByBusinessCode(String type, String? code) {
    if (code == null || code.isEmpty) return null;
    final canonicalType = AdminOrganizationNode.canonicalType(type);
    for (final node in widget.orgNodes) {
      final nodeCode = node.businessCode ?? node.storeId ?? node.code;
      if (node.type == canonicalType && nodeCode == code) return node;
    }
    return null;
  }

  String? _legacyScopeNodeId(User? user) {
    if (user == null) return null;
    final nodeType = _nodeTypeForScope(user.workScopeType ?? '');
    if (nodeType == null) return null;
    final code = switch (user.workScopeType) {
      'STORE' => user.storeId,
      'REGION' => user.regionCode,
      'AREA' => user.areaCode,
      _ => null,
    };
    return _scopeNodeByBusinessCode(nodeType, code)?.id;
  }

  void _applyOrganizationNode(String? nodeId) {
    setState(() {
      _organizationNodeId = nodeId;
      _applyOrganizationNodeToState(_nodeById(nodeId));
    });
  }

  void _applyOrganizationNodeToState(AdminOrganizationNode? node) {
    _storeId = null;
    _jobRoleCode = null;
    _regionCode = null;
    _areaCode = null;
    _workScopeType = _defaultScopeForRole(_role);
    if (node == null) return;
    _workScopeType = _scopeForNode(node);
    final code = node.businessCode ?? node.storeId ?? node.code;
    if (node.type == 'LV5_POSITION') {
      _jobRoleCode = code;
    }
    if (node.type == 'LV2_REGION') {
      _regionCode = code;
    } else if (node.type == 'LV3_AREA') {
      _areaCode = code;
      _regionCode = _ancestorBusinessCode(node, 'LV2_REGION');
    } else if (node.type == 'LV4_STORE' || node.type == 'LV5_POSITION') {
      final storeNode = node.type == 'LV5_POSITION'
          ? _ancestorNode(node, 'LV4_STORE')
          : node;
      _storeId = storeNode?.storeId ?? storeNode?.businessCode;
      _areaCode = _ancestorBusinessCode(node, 'LV3_AREA');
      _regionCode = _ancestorBusinessCode(node, 'LV2_REGION');
    }
  }

  String _scopeForNode(AdminOrganizationNode node) {
    if (node.type == 'LV4_STORE' || node.type == 'LV5_POSITION') {
      return 'STORE';
    }
    if (node.type == 'LV3_AREA' || node.level == 3) return 'AREA';
    if (node.level == 2) return 'REGION';
    return 'NATIONAL';
  }

  String? _ancestorBusinessCode(AdminOrganizationNode node, String type) {
    final value = _ancestorNode(node, type);
    return value?.businessCode ?? value?.code;
  }

  AdminOrganizationNode? _ancestorNode(
    AdminOrganizationNode node,
    String type,
  ) {
    final canonicalType = AdminOrganizationNode.canonicalType(type);
    var parentId = node.parentId;
    for (var guard = 0; parentId != null && guard < 50; guard += 1) {
      final value = _nodeById(parentId);
      if (value == null) return null;
      if (value.type == canonicalType) return value;
      parentId = value.parentId;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.user == null ? 'Thêm người dùng' : 'Sửa người dùng'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: AppFormColumn(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _emailController,
                enabled: widget.user == null,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Tên'),
              ),
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Họ'),
              ),
              if (widget.canEditRole)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Quyền hệ thống',
                  ),
                  items: widget.roles
                      .map(
                        (role) => DropdownMenuItem(
                          value: role.value,
                          child: Text(role.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => _setRole(value ?? 'USER'),
                )
              else
                TextFormField(
                  initialValue: _roleTitle(_role),
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: 'Quyền hệ thống',
                  ),
                ),
              _OrganizationNodeSelector(
                label: _scopeNodeLabel(),
                valueText: _selectedOrganizationNodeText(),
                hintText: _scopeNodeHint(),
                selectedNode: _selectedOrganizationNode(),
                nodeCode: _nodeCode,
                onTap: _scopeNodes().isNotEmpty || _allowsGlobalNationalScope
                    ? _openOrganizationNodePicker
                    : null,
              ),
              TextFormField(
                key: ValueKey(
                  '${widget.user?.personnelCode}|$_jobRoleCode|$_workScopeType|$_storeId',
                ),
                initialValue: _previewPersonnelCode(
                  _jobRoleCode,
                  _workScopeType,
                ),
                enabled: false,
                decoration: const InputDecoration(labelText: 'Mã nhân sự'),
              ),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: const [
                  DropdownMenuItem(value: 'yes', child: Text('Hoạt động')),
                  DropdownMenuItem(value: 'no', child: Text('Khóa')),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'yes'),
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

class _OrganizationNodeSelector extends StatelessWidget {
  final String label;
  final String valueText;
  final String hintText;
  final AdminOrganizationNode? selectedNode;
  final String Function(AdminOrganizationNode node) nodeCode;
  final VoidCallback? onTap;

  const _OrganizationNodeSelector({
    required this.label,
    required this.valueText,
    required this.hintText,
    required this.selectedNode,
    required this.nodeCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final node = selectedNode;
    final hasValue = valueText.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.search_rounded),
        ),
        child: Row(
          children: [
            if (node != null) ...[
              _NodeTypeBadge(type: node.type),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
            ],
            Expanded(
              child: Text(
                hasValue ? valueText : hintText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasValue
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).hintColor,
                  fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (node != null) ...[
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Text(
                nodeCode(node),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrganizationNodeOptionTile extends StatelessWidget {
  final AdminOrganizationNode node;
  final bool selected;
  final String title;
  final String code;
  final VoidCallback onTap;

  const _OrganizationNodeOptionTile({
    required this.node,
    required this.selected,
    required this.title,
    required this.code,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final typeTitle = AdminOrganizationNodeTypes.titleOf(node.type);
    final metadata = [
      typeTitle,
      if (code.isNotEmpty) code,
      if (node.emailDomain?.isNotEmpty == true) node.emailDomain!,
      if (node.storeName?.isNotEmpty == true) node.storeName!,
    ].join(' • ');
    return ListTile(
      selected: selected,
      leading: _NodeTypeBadge(type: node.type),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(metadata, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: selected
          ? Icon(
              Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}

class _NodeTypeBadge extends StatelessWidget {
  final String type;

  const _NodeTypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final title = AdminOrganizationNodeTypes.titleOf(type);
    return Container(
      constraints: const BoxConstraints(minWidth: 76),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
