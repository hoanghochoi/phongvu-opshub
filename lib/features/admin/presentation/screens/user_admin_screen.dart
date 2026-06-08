import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/validators.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/admin_personnel_definition.dart';
import '../../domain/admin_role_definition.dart';

class UserAdminScreen extends StatefulWidget {
  const UserAdminScreen({super.key});

  @override
  State<UserAdminScreen> createState() => _UserAdminScreenState();
}

class _UserAdminScreenState extends State<UserAdminScreen> {
  final _repository = AuthRepository(ApiClient());
  final _searchController = TextEditingController();
  List<User> _users = [];
  List<StoreBranch> _stores = [];
  List<AdminRoleDefinition> _roles = AdminRoles.definitions;
  List<AdminPersonnelDefinition> _departments = [];
  List<AdminPersonnelDefinition> _jobRoles = [];
  List<AdminRegionDefinition> _regions = [];
  List<AdminAreaDefinition> _areas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final currentUser = context.read<AuthProvider>().user;
    final canUseStores = currentUser?.canUseFeature('ADMIN_STORES') == true;
    final canUseRoles = currentUser?.canUseFeature('ADMIN_ROLES') == true;
    final canUsePersonnel =
        currentUser?.canUseFeature('ADMIN_PERSONNEL') == true;
    final canUseRegions = currentUser?.canUseFeature('ADMIN_REGIONS') == true;
    await AppLogger.instance.info(
      'Admin',
      'Admin user management load started',
      context: {
        'role': currentUser?.role,
        'email': currentUser?.email,
        'canUseStores': canUseStores,
        'canUseRoles': canUseRoles,
        'canUsePersonnel': canUsePersonnel,
        'canUseRegions': canUseRegions,
      },
    );
    try {
      final results = await Future.wait<Object>([
        _repository.listUsers(query: _searchController.text),
        canUseStores
            ? _repository.listAdminStores()
            : Future.value(<StoreBranch>[]),
        canUseRoles
            ? _repository.listAdminRoles()
            : Future.value(AdminRoles.definitions),
        canUsePersonnel
            ? _repository.listAdminDepartments()
            : Future.value(<AdminPersonnelDefinition>[]),
        canUsePersonnel
            ? _repository.listAdminJobRoles()
            : Future.value(<AdminPersonnelDefinition>[]),
        canUseRegions
            ? _repository.listAdminRegions()
            : Future.value(<AdminRegionDefinition>[]),
        canUseRegions
            ? _repository.listAdminAreas()
            : Future.value(<AdminAreaDefinition>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<User>;
        _stores = results[1] as List<StoreBranch>;
        _roles = results[2] as List<AdminRoleDefinition>;
        _departments = results[3] as List<AdminPersonnelDefinition>;
        _jobRoles = results[4] as List<AdminPersonnelDefinition>;
        _regions = results[5] as List<AdminRegionDefinition>;
        _areas = results[6] as List<AdminAreaDefinition>;
      });
      await AppLogger.instance.info(
        'Admin',
        'Admin user management load succeeded',
        context: {
          'role': currentUser?.role,
          'userCount': _users.length,
          'storeCount': _stores.length,
          'roleCount': _roles.length,
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
        stores: _stores,
        roles: _roles,
        departments: _departments,
        jobRoles: _jobRoles,
        regions: _regions,
        areas: _areas,
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

  @override
  Widget build(BuildContext context) {
    final canResetPassword =
        context.watch<AuthProvider>().user?.role == 'SUPER_ADMIN';
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

class _UserEditorDialog extends StatefulWidget {
  final AuthRepository repository;
  final List<StoreBranch> stores;
  final List<AdminRoleDefinition> roles;
  final List<AdminPersonnelDefinition> departments;
  final List<AdminPersonnelDefinition> jobRoles;
  final List<AdminRegionDefinition> regions;
  final List<AdminAreaDefinition> areas;
  final User? user;
  final bool canEditRole;

  const _UserEditorDialog({
    required this.repository,
    required this.stores,
    required this.roles,
    required this.departments,
    required this.jobRoles,
    required this.regions,
    required this.areas,
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
  String _role = 'STAFF';
  String _status = 'yes';
  String? _storeId;
  String? _departmentCode;
  String? _jobRoleCode;
  String _workScopeType = 'STORE';
  String? _regionCode;
  String? _areaCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _emailController.text = user?.email ?? '';
    _firstNameController.text = user?.name ?? '';
    _lastNameController.text = user?.lastName ?? '';
    _role = user?.role ?? 'STAFF';
    _status = user?.status ?? 'yes';
    _storeId = user?.storeId;
    _departmentCode = user?.departmentCode;
    _jobRoleCode = user?.jobRoleCode;
    _workScopeType = user?.workScopeType ?? _defaultScopeForRole(_role);
    _regionCode = user?.regionCode;
    _areaCode = user?.areaCode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final body = {
        'email': _emailController.text.trim(),
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'status': _status,
        'storeId': _storeId,
        'departmentCode': _departmentCode,
        'jobRoleCode': _jobRoleCode,
        'workScopeType': _workScopeType,
        'regionCode': _regionCode,
        'areaCode': _areaCode,
        if (widget.canEditRole) 'role': _role,
      };
      final user = widget.user;
      if (user == null) {
        await widget.repository.createAdminUser(body);
      } else {
        await widget.repository.updateAdminUser(user.id ?? '', body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      _role = value;
      if (widget.user?.workScopeType == null) {
        _workScopeType = _defaultScopeForRole(value);
      }
    });
  }

  String _previewPersonnelCode(String? jobRoleCode, String scope) {
    if (jobRoleCode == null || jobRoleCode.isEmpty) return 'Chưa gán';
    final region = _regionAbbr(_regionCode);
    final area = _areaAbbr(_areaCode);
    if (scope == 'STORE') {
      final store = _storeId?.isNotEmpty == true ? _storeId! : 'STORE';
      final storeArea =
          _areaAbbr(_storeAreaCode(_storeId)) ?? area ?? 'CHUA_GAN';
      final storeRegion =
          _regionAbbr(_storeRegionCode(_storeId)) ?? region ?? 'CHUA_GAN';
      return '${jobRoleCode}_${store}_${storeArea}_$storeRegion';
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
    for (final region in widget.regions) {
      if (region.code == code) return region.abbreviation;
    }
    return code;
  }

  String? _areaAbbr(String? code) {
    for (final area in widget.areas) {
      if (area.code == code) return area.abbreviation;
    }
    return code;
  }

  String? _storeAreaCode(String? storeId) {
    for (final store in widget.stores) {
      if (store.storeId == storeId) return store.areaCode;
    }
    return null;
  }

  String? _storeRegionCode(String? storeId) {
    for (final store in widget.stores) {
      if (store.storeId == storeId) return store.regionCode;
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
                  onChanged: (value) => _setRole(value ?? 'STAFF'),
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
              DropdownButtonFormField<String>(
                initialValue: _workScopeType,
                decoration: const InputDecoration(labelText: 'Phạm vi'),
                items: AdminWorkScopes.definitions
                    .map(
                      (scope) => DropdownMenuItem(
                        value: scope.value,
                        child: Text(scope.title),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _workScopeType = value ?? 'STORE';
                  if (_workScopeType != 'REGION') _regionCode = null;
                  if (_workScopeType != 'AREA') _areaCode = null;
                  if (_workScopeType != 'STORE') _storeId = null;
                }),
              ),
              if (_workScopeType == 'REGION')
                DropdownButtonFormField<String?>(
                  initialValue: _regionCode,
                  decoration: const InputDecoration(labelText: 'Mien'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Chua gan'),
                    ),
                    ...widget.regions.map(
                      (region) => DropdownMenuItem<String?>(
                        value: region.code,
                        child: Text('${region.abbreviation} - ${region.title}'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _regionCode = value),
                ),
              if (_workScopeType == 'AREA')
                DropdownButtonFormField<String?>(
                  initialValue: _areaCode,
                  decoration: const InputDecoration(labelText: 'Vung'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Chua gan'),
                    ),
                    ...widget.areas.map(
                      (area) => DropdownMenuItem<String?>(
                        value: area.code,
                        child: Text('${area.abbreviation} - ${area.title}'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _areaCode = value;
                    _regionCode = null;
                    for (final area in widget.areas) {
                      if (area.code == value) _regionCode = area.regionCode;
                    }
                  }),
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
              if (_workScopeType == 'STORE')
                DropdownButtonFormField<String?>(
                  initialValue: _storeId,
                  decoration: const InputDecoration(labelText: 'Chi nhánh'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Chưa gán'),
                    ),
                    ...widget.stores.map(
                      (store) => DropdownMenuItem<String?>(
                        value: store.storeId,
                        child: Text(store.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _storeId = value),
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
