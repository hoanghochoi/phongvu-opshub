import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/logging/app_logger.dart';
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
    try {
      final results = await Future.wait([
        _repository.listUsers(query: _searchController.text),
        _repository.listAdminStores(),
        _repository.listAdminRoles(),
        _repository.listAdminDepartments(),
        _repository.listAdminJobRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<User>;
        _stores = results[1] as List<StoreBranch>;
        _roles = results[2] as List<AdminRoleDefinition>;
        _departments = results[3] as List<AdminPersonnelDefinition>;
        _jobRoles = results[4] as List<AdminPersonnelDefinition>;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword(User user) async {
    final userId = user.id;
    if (userId == null || userId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset mật khẩu'),
        content: Text('Gửi link đổi mật khẩu đến ${user.email}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Gửi link'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppLogger.instance.info(
      'Admin',
      'Admin password reset started',
      context: {'userId': userId, 'email': user.email, 'role': user.role},
    );
    try {
      await _repository.resetAdminUserPassword(userId, email: user.email);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await AppLogger.instance.info(
        'Admin',
        'Admin password reset succeeded',
        context: {'userId': userId, 'email': user.email},
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('Đã gửi link đổi mật khẩu đến ${user.email}'),
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
          content: Text('Không gửi được link đổi mật khẩu'),
          backgroundColor: Colors.red,
        ),
      );
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
                              if (canResetPassword)
                                AppIconAction(
                                  onPressed: () => _resetPassword(user),
                                  icon: Icons.lock_reset_outlined,
                                  tooltip: 'Reset mật khẩu',
                                ),
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
  final User? user;
  final bool canEditRole;

  const _UserEditorDialog({
    required this.repository,
    required this.stores,
    required this.roles,
    required this.departments,
    required this.jobRoles,
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
    return role == 'SUPER_ADMIN' || role == 'ADMIN' ? 'NATIONAL' : 'STORE';
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
    if (scope == 'STORE') {
      return _storeId?.isNotEmpty == true
          ? '${jobRoleCode}_$_storeId'
          : '${jobRoleCode}_STORE';
    }
    if (scope == 'ONLINE') return jobRoleCode;
    return '${jobRoleCode}_$scope';
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
                onChanged: (value) =>
                    setState(() => _workScopeType = value ?? 'STORE'),
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
