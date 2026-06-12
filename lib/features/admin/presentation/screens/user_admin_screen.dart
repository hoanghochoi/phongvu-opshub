import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/theme/app_colors.dart';
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
  List<AdminPersonnelDefinition> _departments = [];
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
    final canUsePersonnel =
        currentUser?.canUseFeature('ADMIN_PERSONNEL') == true;
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
        'canUsePersonnel': canUsePersonnel,
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
        canUsePersonnel
            ? _repository.listAdminDepartments()
            : Future.value(<AdminPersonnelDefinition>[]),
        canUsePersonnel
            ? _repository.listAdminJobRoles()
            : Future.value(<AdminPersonnelDefinition>[]),
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
        _departments = results[2] as List<AdminPersonnelDefinition>;
        _jobRoles = results[3] as List<AdminPersonnelDefinition>;
        _regions = const <AdminRegionDefinition>[];
        _areas = const <AdminAreaDefinition>[];
        _features = results[4] as List<AdminFeatureDefinition>;
        _orgNodes = results[5] as List<AdminOrganizationNode>;
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
    final canEditFeatures = canEditRole;
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => _UserEditorDialog(
        repository: _repository,
        roles: _roles,
        departments: _departments,
        jobRoles: _jobRoles,
        regions: _regions,
        areas: _areas,
        features: _features,
        orgNodes: _orgNodes,
        user: user,
        canEditRole: canEditRole,
        canEditFeatures: canEditFeatures,
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
  final List<AdminPersonnelDefinition> departments;
  final List<AdminPersonnelDefinition> jobRoles;
  final List<AdminRegionDefinition> regions;
  final List<AdminAreaDefinition> areas;
  final List<AdminFeatureDefinition> features;
  final List<AdminOrganizationNode> orgNodes;
  final User? user;
  final bool canEditRole;
  final bool canEditFeatures;

  const _UserEditorDialog({
    required this.repository,
    required this.roles,
    required this.departments,
    required this.jobRoles,
    required this.regions,
    required this.areas,
    required this.features,
    required this.orgNodes,
    required this.canEditRole,
    required this.canEditFeatures,
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
  String? _departmentCode;
  String? _jobRoleCode;
  String _workScopeType = 'STORE';
  String? _regionCode;
  String? _areaCode;
  String? _organizationNodeId;
  final Set<String> _featureCodes = <String>{};
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
    _departmentCode = user?.departmentCode;
    _jobRoleCode = user?.jobRoleCode;
    _workScopeType = user?.workScopeType ?? _defaultScopeForRole(_role);
    _regionCode = user?.regionCode;
    _areaCode = user?.areaCode;
    _organizationNodeId = user?.organizationNodeId ?? _legacyScopeNodeId(user);
    _applyOrganizationNodeToState(_selectedOrganizationNode());
    _featureCodes.addAll(user?.featureCodes ?? const []);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
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
          'featureCount': _featureCodes.length,
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
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      await AppLogger.instance.error(
        'Admin',
        'Admin user editor save failed',
        error: error,
        upload: true,
        context: {
          'mode': user == null ? 'create' : 'update',
          'targetUserId': user?.id,
          'targetEmail': user?.email ?? body['email'],
          'targetRole': _role,
          'workScopeType': _workScopeType,
          'organizationNodeId': _organizationNodeId,
          'organizationNodeType': selectedNode?.type,
        },
      );
      if (mounted) {
        final message = adminUserSaveErrorMessage(error);
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
      departmentCode: _departmentCode,
      jobRoleCode: _jobRoleCode,
      organizationNodeId: _organizationNodeId,
      canEditRole: widget.canEditRole,
      canEditFeatures: widget.canEditFeatures,
      featureTreeCodes: _sortedFeatureCodes(),
    );
  }

  List<String> _sortedFeatureCodes() => _featureCodes.toList()..sort();

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
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
    addIfChanged('departmentCode', user.departmentCode, 'Phòng ban');
    addIfChanged('jobRoleCode', user.jobRoleCode, 'Chức danh');
    addIfChanged('organizationNodeId', user.organizationNodeId, 'Node tổ chức');
    if (widget.canEditRole) addIfChanged('role', user.role, 'Quyền hệ thống');
    if (widget.canEditFeatures) {
      final oldCodes = user.featureCodes.toList()..sort();
      final newCodes = _sortedFeatureCodes();
      if (!_sameStringList(oldCodes, newCodes)) {
        changes.add('Chức năng được dùng');
      }
    }
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
      _departmentCode = user.departmentCode;
      _jobRoleCode = user.jobRoleCode;
      _workScopeType = user.workScopeType ?? _defaultScopeForRole(_role);
      _regionCode = user.regionCode;
      _areaCode = user.areaCode;
      _organizationNodeId = user.organizationNodeId ?? _legacyScopeNodeId(user);
      _applyOrganizationNodeToState(_selectedOrganizationNode());
      _featureCodes
        ..clear()
        ..addAll(user.featureCodes);
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

  void _toggleFeature(AdminFeatureDefinition feature, bool selected) {
    setState(() {
      if (selected) {
        _featureCodes.add(feature.code);
        var parentCode = feature.parentCode;
        while (parentCode != null && parentCode.isNotEmpty) {
          _featureCodes.add(parentCode);
          parentCode = _featureByCode(parentCode)?.parentCode;
        }
      } else {
        _featureCodes.remove(feature.code);
        for (final child in _descendantsOf(feature.code)) {
          _featureCodes.remove(child.code);
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

  String? _organizationNodeValue() {
    final items = _scopeNodeItems().map((item) => item.$1.id).toSet();
    return items.contains(_organizationNodeId) ? _organizationNodeId : null;
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

  List<(AdminOrganizationNode, String)> _scopeNodeItems() {
    return widget.orgNodes
        .where((node) => node.isActive)
        .map(
          (node) => (
            node,
            '${AdminOrganizationNodeTypes.titleOf(node.type)} • ${node.businessCode ?? node.storeId ?? node.code} • ${node.title}',
          ),
        )
        .toList();
  }

  String _scopeNodeLabel() => 'Node tổ chức';

  String _scopeNodeHint() {
    if (_allowsGlobalNationalScope) return 'Toàn hệ thống';
    return 'Chọn Lv0-Lv5';
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
    _regionCode = null;
    _areaCode = null;
    _workScopeType = _defaultScopeForRole(_role);
    if (node == null) return;
    _workScopeType = _scopeForNode(node);
    final code = node.businessCode ?? node.storeId ?? node.code;
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
              DropdownButtonFormField<String?>(
                initialValue: _departmentCode,
                decoration: const InputDecoration(labelText: 'Phòng ban'),
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
              DropdownButtonFormField<String?>(
                initialValue: _jobRoleCode,
                decoration: const InputDecoration(labelText: 'Chức danh'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Chưa gán'),
                  ),
                  ...widget.jobRoles.map(
                    (jobRole) => DropdownMenuItem<String?>(
                      value: jobRole.code,
                      child: Text(jobRole.title),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _jobRoleCode = value),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _organizationNodeValue(),
                decoration: InputDecoration(labelText: _scopeNodeLabel()),
                hint: Text(_scopeNodeHint()),
                items: [
                  if (_allowsGlobalNationalScope)
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toàn hệ thống'),
                    ),
                  ..._scopeNodeItems().map(
                    (item) => DropdownMenuItem<String?>(
                      value: item.$1.id,
                      child: Text(item.$2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged:
                    _scopeNodeItems().isNotEmpty || _allowsGlobalNationalScope
                    ? _applyOrganizationNode
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
              if (widget.canEditFeatures)
                _FeatureCheckboxTree(
                  features: widget.features,
                  selectedCodes: _featureCodes,
                  onChanged: _toggleFeature,
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

class _FeatureCheckboxTree extends StatelessWidget {
  final List<AdminFeatureDefinition> features;
  final Set<String> selectedCodes;
  final void Function(AdminFeatureDefinition feature, bool selected) onChanged;

  const _FeatureCheckboxTree({
    required this.features,
    required this.selectedCodes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) {
      return const Text('Chưa tải được danh sách chức năng');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chức năng được sử dụng',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final feature in roots)
                  _FeatureCheckboxTile(
                    feature: feature,
                    byParent: byParent,
                    selectedCodes: selectedCodes,
                    depth: 0,
                    onChanged: onChanged,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureCheckboxTile extends StatelessWidget {
  final AdminFeatureDefinition feature;
  final Map<String?, List<AdminFeatureDefinition>> byParent;
  final Set<String> selectedCodes;
  final int depth;
  final void Function(AdminFeatureDefinition feature, bool selected) onChanged;

  const _FeatureCheckboxTile({
    required this.feature,
    required this.byParent,
    required this.selectedCodes,
    required this.depth,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final children = byParent[feature.code] ?? const <AdminFeatureDefinition>[];
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
            feature.code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) => onChanged(feature, value == true),
        ),
        for (final child in children)
          _FeatureCheckboxTile(
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
