import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
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
  final AuthRepository? repository;

  const UserAdminScreen({super.key, this.repository});

  @override
  State<UserAdminScreen> createState() => _UserAdminScreenState();
}

class _UserAdminScreenState extends State<UserAdminScreen> {
  late final AuthRepository _repository;
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
  bool _importing = false;
  bool _metadataLoaded = false;
  Timer? _searchDebounce;
  int _loadRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? AuthRepository(ApiClient());
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
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool reloadMetadata = false}) async {
    final requestSerial = ++_loadRequestSerial;
    final query = _searchController.text.trim();
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
        'reloadMetadata': reloadMetadata || !_metadataLoaded,
        'hasQuery': query.isNotEmpty,
        'queryLength': query.length,
        'searchSource': 'server',
      },
    );
    try {
      final shouldLoadMetadata = reloadMetadata || !_metadataLoaded;
      final results = await Future.wait<Object>([
        _repository.listUsers(
          query: query,
          domain: _domainFilter,
          orgNodeId: _orgNodeFilter,
          featureCode: _featureFilter,
          role: _roleFilter,
          status: _statusFilter,
        ),
        canUseRoles && shouldLoadMetadata
            ? _repository.listAdminRoles()
            : Future.value(_roles),
        canUseFeatures
            ? shouldLoadMetadata
                  ? _repository.listAdminFeatureTree()
                  : Future.value(_features)
            : Future.value(<AdminFeatureDefinition>[]),
        canUseUserScopeTree
            ? shouldLoadMetadata
                  ? _repository.listAdminUserScopeTree()
                  : Future.value(_orgNodes)
            : Future.value(<AdminOrganizationNode>[]),
      ]);
      if (!mounted || requestSerial != _loadRequestSerial) return;
      final users = results[0] as List<User>;
      setState(() {
        _users = users;
        _roles = results[1] as List<AdminRoleDefinition>;
        _jobRoles = const <AdminPersonnelDefinition>[];
        _regions = const <AdminRegionDefinition>[];
        _areas = const <AdminAreaDefinition>[];
        _features = results[2] as List<AdminFeatureDefinition>;
        _orgNodes = results[3] as List<AdminOrganizationNode>;
        _metadataLoaded = true;
      });
      await AppLogger.instance.info(
        'Admin',
        'Admin user management load succeeded',
        context: {
          'role': currentUser?.role,
          'userCount': users.length,
          'roleCount': _roles.length,
          'featureCount': _features.length,
          'orgNodeCount': _orgNodes.length,
          'hasQuery': query.isNotEmpty,
          'queryLength': query.length,
          'searchSource': 'server',
        },
      );
    } catch (error) {
      if (requestSerial != _loadRequestSerial) return;
      await AppLogger.instance.error(
        'Admin',
        'Admin user management load failed',
        error: error,
        upload: true,
        context: {'role': currentUser?.role, 'email': currentUser?.email},
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(content: Text('Không tải được danh sách người dùng')),
        );
      }
    } finally {
      if (mounted && requestSerial == _loadRequestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  void _runSearchNow() {
    _searchDebounce?.cancel();
    _load();
  }

  Future<void> _importUsers() async {
    if (_importing) return;
    await AppLogger.instance.info(
      'Admin',
      'Admin user import file picker opened',
    );
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      allowMultiple: false,
      withData: false,
    );
    final file = picked?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;

    await AppLogger.instance.info(
      'Admin',
      'Admin user import file selected',
      context: {'fileName': file.name, 'size': file.size},
    );
    if (!mounted) return;
    setState(() => _importing = true);
    final startedAt = DateTime.now();
    try {
      await AppLogger.instance.info(
        'Admin',
        'Admin user import started',
        context: {'fileName': file.name, 'size': file.size},
      );
      final result = await _repository.importAdminUsers(path);
      await AppLogger.instance.info(
        'Admin',
        'Admin user import succeeded',
        context: {
          'fileName': file.name,
          'totalRows': result.totalRows,
          'createdRows': result.createdRows,
          'updatedRows': result.updatedRows,
          'skippedRows': result.skippedRows,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _UserImportResultDialog(result: result),
      );
      await _load();
    } catch (error, stackTrace) {
      final message = adminUserSaveErrorMessage(error);
      await AppLogger.instance.error(
        'Admin',
        'Admin user import failed',
        error: message,
        stackTrace: stackTrace,
        upload: true,
        context: {
          'fileName': file.name,
          'errorType': error.runtimeType.toString(),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (!mounted) return;
      AppToast.show(context, SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _importing = false);
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
      await AppLogger.instance.info(
        'Admin',
        'Admin password reset succeeded',
        context: {'userId': userId, 'email': user.email},
      );
      if (!mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text('Đã đổi mật khẩu cho ${user.email}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await AppLogger.instance.error(
        'Admin',
        'Admin password reset failed',
        error: e,
        upload: true,
        context: {'userId': userId, 'email': user.email},
      );
      if (!mounted) return;
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Không đổi được mật khẩu'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteUser(User user) async {
    final userId = user.id;
    if (userId == null || userId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa hoàn toàn tài khoản?'),
        content: Text(
          'Tài khoản ${user.email} sẽ bị xóa khỏi hệ thống nếu không còn dữ liệu lịch sử.',
        ),
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

    await AppLogger.instance.warn(
      'Admin',
      'Admin user delete started',
      context: {'userId': userId, 'email': user.email},
    );
    try {
      await _repository.deleteAdminUser(userId, email: user.email);
      await AppLogger.instance.warn(
        'Admin',
        'Admin user delete succeeded',
        context: {'userId': userId, 'email': user.email},
      );
      if (!mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text('Đã xóa tài khoản ${user.email}'),
          backgroundColor: AppColors.success,
        ),
      );
      await _load();
    } catch (error) {
      final message = adminUserSaveErrorMessage(error);
      await AppLogger.instance.error(
        'Admin',
        'Admin user delete failed',
        error: message,
        upload: true,
        context: {'userId': userId, 'email': user.email},
      );
      if (!mounted) return;
      AppToast.show(context, SnackBar(content: Text(message)));
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
            title: const Text('Đổi mật khẩu người dùng'),
            content: Form(
              key: formKey,
              child: AppFormColumn(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(user.email),
                  ),
                  AppFormTextInput(
                    controller: passwordController,
                    label: 'Mật khẩu mới',
                    icon: Icons.lock_rounded,
                    obscureText: obscurePassword,
                    autofillHints: const [AutofillHints.newPassword],
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
                    validator: (value) =>
                        Validators.getPasswordError(value ?? ''),
                  ),
                  AppFormTextInput(
                    controller: confirmController,
                    label: 'Nhập lại mật khẩu mới',
                    icon: Icons.lock_reset_rounded,
                    obscureText: obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
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
              AppDialogCancelButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
              AppDialogConfirmButton(
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(context).pop(passwordController.text);
                },
                label: 'Đổi mật khẩu',
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
    return value?.isNotEmpty == true ? User.roleDisplayName(value) : 'Chưa gán';
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
    _searchDebounce?.cancel();
    _load();
  }

  Widget _buildFilterToolbar() {
    final controls = <({double width, Widget child})>[
      (
        width: 180,
        child: AppFilterDropdown<String>(
          label: 'Miền email',
          value: _domainFilter,
          options: _domainOptions
              .map((domain) => AppFilterOption(value: domain, label: domain))
              .toList(growable: false),
          onChanged: (value) {
            setState(() => _domainFilter = value);
            _load();
          },
        ),
      ),
      (
        width: 220,
        child: AppSearchableFilterDropdown<String>(
          label: 'Cơ cấu',
          value: _orgNodeFilter,
          options: _orgNodes
              .map((node) => AppFilterOption(value: node.id, label: node.title))
              .toList(growable: false),
          onChanged: (value) {
            setState(() => _orgNodeFilter = value);
            _load();
          },
        ),
      ),
      (
        width: 220,
        child: AppSearchableFilterDropdown<String>(
          label: 'Tính năng',
          value: _featureFilter,
          options: _features
              .map(
                (feature) =>
                    AppFilterOption(value: feature.code, label: feature.title),
              )
              .toList(growable: false),
          onChanged: (value) {
            setState(() => _featureFilter = value);
            _load();
          },
        ),
      ),
      (
        width: 180,
        child: AppFilterDropdown<String>(
          label: 'Vai trò',
          value: _roleFilter,
          options: _roles
              .map(
                (role) => AppFilterOption(value: role.value, label: role.title),
              )
              .toList(growable: false),
          onChanged: (value) {
            setState(() => _roleFilter = value);
            _load();
          },
        ),
      ),
      (
        width: 170,
        child: AppFilterDropdown<String>(
          label: 'Trạng thái',
          value: _statusFilter,
          options: const [
            AppFilterOption(value: 'yes', label: 'Hoạt động'),
            AppFilterOption(value: 'no', label: 'Đã khóa'),
          ],
          onChanged: (value) {
            setState(() => _statusFilter = value);
            _load();
          },
        ),
      ),
      (
        width: 150,
        child: AppSecondaryButton(
          onPressed: _resetFilters,
          icon: Icons.filter_alt_off_outlined,
          label: 'Xóa bộ lọc',
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppLayoutTokens.tabletBreakpoint) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < controls.length; index++) ...[
                  if (index > 0)
                    const SizedBox(width: AppLayoutTokens.formInlineGap),
                  SizedBox(
                    width: controls[index].width,
                    child: controls[index].child,
                  ),
                ],
              ],
            ),
          );
        }

        return Wrap(
          spacing: AppLayoutTokens.formInlineGap,
          runSpacing: AppLayoutTokens.formInlineGap,
          children: [
            for (final control in controls)
              SizedBox(width: control.width, child: control.child),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().user;
    final currentRole = currentUser?.role;
    final canCreateUsers = currentRole == 'SUPER_ADMIN';
    final canResetPassword =
        currentRole == 'SUPER_ADMIN' || User.isAdminRole(currentRole);
    return AppResponsiveContent(
      onRefresh: () => _load(reloadMetadata: true),
      refreshLogSource: 'Admin',
      refreshLogContext: () => {
        'userCount': _users.length,
        'reloadMetadata': true,
        'hasQuery': _searchController.text.trim().isNotEmpty,
      },
      child: Column(
        children: [
          AppSurfaceCard(
            key: const Key('user-admin-header'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quản lý người dùng',
                  style: AppTextStyles.headingM.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tìm, lọc và cập nhật tài khoản theo phạm vi quản trị.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (canCreateUsers) ...[
                  const SizedBox(height: AppLayoutTokens.formFieldGap),
                  AppActionRow(
                    desktopAlignment: MainAxisAlignment.start,
                    maxButtonWidth: 220,
                    children: [
                      AppSecondaryButton(
                        onPressed: _importing ? null : _importUsers,
                        icon: Icons.upload_file_outlined,
                        label: 'Nhập danh sách',
                        isLoading: _importing,
                        loadingLabel: 'Đang nhập dữ liệu',
                      ),
                      AppPrimaryButton(
                        onPressed: () => _openEditor(),
                        icon: Icons.person_add_alt_1_outlined,
                        label: 'Thêm người dùng',
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          AppSurfaceCard(
            key: const Key('user-admin-filters'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextInput(
                  controller: _searchController,
                  label: 'Tìm người dùng',
                  hintText: 'Tìm trực tiếp trong hệ thống',
                  icon: Icons.search,
                  suffixIcon: AppIconAction(
                    onPressed: _loading ? null : _load,
                    icon: Icons.refresh,
                    tooltip: 'Tải lại danh sách',
                  ),
                  onSubmitted: (_) => _runSearchNow(),
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                _buildFilterToolbar(),
              ],
            ),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          Expanded(
            child: _loading
                ? const AppListSkeleton(itemCount: 6, itemHeight: 108)
                : _users.isEmpty
                ? AppStatePanel.empty(
                    title: 'Không tìm thấy người dùng',
                    message: 'Thử đổi từ khóa hoặc xóa bộ lọc hiện tại.',
                    icon: Icons.person_search_outlined,
                    actionLabel: 'Xóa bộ lọc',
                    actionIcon: Icons.filter_alt_off_outlined,
                    onAction: _resetFilters,
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _users.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppLayoutTokens.cardGap),
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final canDeleteUser =
                          canCreateUsers &&
                          user.id != currentUser?.id &&
                          user.status?.toLowerCase() == 'no';
                      return _UserListItem(
                        user: user,
                        roleTitle: _roleTitle(user.role),
                        personnelTitle: _personnelTitle(user),
                        canResetPassword: canResetPassword,
                        canDelete: canDeleteUser,
                        onResetPassword: () => _resetPassword(user),
                        onEdit: () => _openEditor(user),
                        onDelete: () => _deleteUser(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _UserListItem extends StatelessWidget {
  final User user;
  final String roleTitle;
  final String personnelTitle;
  final bool canResetPassword;
  final bool canDelete;
  final VoidCallback onResetPassword;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UserListItem({
    required this.user,
    required this.roleTitle,
    required this.personnelTitle,
    required this.canResetPassword,
    required this.canDelete,
    required this.onResetPassword,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.name?.trim().isNotEmpty == true
        ? user.name!.trim()
        : user.email;
    final isLocked = user.status?.toLowerCase() == 'no';
    final statusLabel = user.assignmentPending
        ? 'Chờ gán tổ chức'
        : isLocked
        ? 'Đã khóa'
        : 'Hoạt động';
    final statusColor = user.assignmentPending || isLocked
        ? AppColors.warning
        : AppColors.success;
    final metadata = '$roleTitle • ${user.storeInfo}';

    final identity = Row(
      children: [
        CircleAvatar(child: Text(displayName.characters.first.toUpperCase())),
        const SizedBox(width: AppLayoutTokens.formInlineGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelL.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyS.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metadata,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canResetPassword) ...[
          AppIconAction(
            onPressed: onResetPassword,
            icon: Icons.lock_reset_outlined,
            tooltip: 'Đặt lại mật khẩu',
          ),
          const SizedBox(width: 8),
        ],
        AppIconAction(
          onPressed: onEdit,
          icon: Icons.edit_outlined,
          tooltip: 'Sửa người dùng',
        ),
        if (canDelete) ...[
          const SizedBox(width: 8),
          AppIconAction(
            onPressed: onDelete,
            icon: Icons.delete_outline,
            tooltip: 'Xóa tài khoản đã khóa',
          ),
        ],
      ],
    );

    return AppSurfaceCard(
      key: ValueKey('admin-user-${user.id ?? user.email}'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Row(
                  children: [
                    AppStatusChip(label: statusLabel, color: statusColor),
                    const Spacer(),
                    actions,
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  personnelTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 5, child: identity),
              const SizedBox(width: AppLayoutTokens.sectionGap),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStatusChip(label: statusLabel, color: statusColor),
                    const SizedBox(height: 8),
                    Text(
                      personnelTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyS.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppLayoutTokens.sectionGap),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _UserImportResultDialog extends StatelessWidget {
  final AdminUserImportResult result;

  const _UserImportResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final rows = result.results.take(8).toList();
    return AlertDialog(
      title: const Text('Kết quả nhập danh sách'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImportSummaryRow(label: 'Tổng dòng', value: result.totalRows),
            _ImportSummaryRow(label: 'Tạo mới', value: result.createdRows),
            _ImportSummaryRow(label: 'Cập nhật', value: result.updatedRows),
            _ImportSummaryRow(label: 'Dòng bỏ qua', value: result.skippedRows),
            _ImportSummaryRow(
              label: 'Email đã gửi',
              value: result.welcomeEmailSentRows,
            ),
            _ImportSummaryRow(
              label: 'Email lỗi',
              value: result.welcomeEmailFailedRows,
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        row.welcomeEmailError?.isNotEmpty == true
                            ? Icons.mark_email_unread_outlined
                            : row.action == 'created'
                            ? Icons.person_add_alt_1_outlined
                            : Icons.manage_accounts_outlined,
                      ),
                      title: Text(row.email),
                      subtitle: Text(
                        [
                          'Dòng ${row.rowNumber}',
                          row.role,
                          row.personnelCode ?? row.organizationNodeName ?? '-',
                          if (row.action == 'created')
                            row.welcomeEmailError?.isNotEmpty == true
                                ? 'Email lỗi'
                                : row.welcomeEmailSent
                                ? 'Đã gửi email'
                                : 'Chưa gửi email',
                        ].join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        AppDialogConfirmButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Đóng',
        ),
      ],
    );
  }
}

class _ImportSummaryRow extends StatelessWidget {
  final String label;
  final int value;

  const _ImportSummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: AppTextStyles.labelM,
            ),
          ),
        ],
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
  final Set<String> _organizationNodeIds = {};
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
    _organizationNodeIds
      ..clear()
      ..addAll(
        user?.organizationNodeIds.isNotEmpty == true
            ? user!.organizationNodeIds
            : [
                if (_organizationNodeId?.isNotEmpty == true)
                  _organizationNodeId!,
              ],
      );
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
      String? welcomeEmailError;
      if (user == null) {
        final result = await widget.repository.createAdminUser(body);
        welcomeEmailError = result.welcomeEmailError;
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
          'welcomeEmailFailed': welcomeEmailError?.isNotEmpty == true,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
      if (mounted && welcomeEmailError?.isNotEmpty == true) {
        AppToast.show(
          context,
          SnackBar(
            content: Text(
              'Đã tạo người dùng nhưng chưa gửi được email chào mừng: $welcomeEmailError',
            ),
          ),
        );
      }
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
        AppToast.show(context, SnackBar(content: Text(message)));
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
      organizationNodeIds: _sortedOrganizationNodeIds(),
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
    final previousNodeIds = user.organizationNodeIds.isNotEmpty
        ? user.organizationNodeIds
        : [
            if (user.organizationNodeId?.isNotEmpty == true)
              user.organizationNodeId!,
          ];
    if (previousNodeIds.join('|') != _sortedOrganizationNodeIds().join('|')) {
      changes.add('Vị trí trong cây tổ chức');
    }
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
          AppDialogCancelButton(
            onPressed: () => Navigator.of(context).pop(false),
            label: 'Hủy thay đổi',
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.of(context).pop(true),
            label: 'Xác nhận lưu',
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
      _organizationNodeIds
        ..clear()
        ..addAll(
          user.organizationNodeIds.isNotEmpty
              ? user.organizationNodeIds
              : [
                  if (_organizationNodeId?.isNotEmpty == true)
                    _organizationNodeId!,
                ],
        );
      _applyOrganizationNodeToState(_selectedOrganizationNode());
    });
  }

  String _roleTitle(String value) {
    for (final role in widget.roles) {
      if (role.value == value) return role.title;
    }
    return User.roleDisplayName(value);
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

  String _scopeNodeLabel() => 'Đơn vị tổ chức';

  String _scopeNodeHint() {
    if (_allowsGlobalNationalScope) return 'Toàn hệ thống';
    return 'Chọn đơn vị trong cây';
  }

  String _selectedOrganizationNodeText() {
    if (_organizationNodeId == null && _allowsGlobalNationalScope) {
      return 'Toàn hệ thống';
    }
    if (_organizationNodeIds.length > 1) {
      final primary = _selectedOrganizationNode();
      final primaryText = primary == null ? null : _nodeCompactLabel(primary);
      return [
        '${_organizationNodeIds.length} đơn vị đã chọn',
        if (primaryText != null) 'chính: $primaryText',
      ].join(' • ');
    }
    final node = _selectedOrganizationNode();
    if (node == null) return '';
    return _nodeBreadcrumb(node);
  }

  List<String> _sortedOrganizationNodeIds() {
    final ids = _organizationNodeIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    ids.sort();
    return ids;
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
    final searchController = TextEditingController();
    final selectedIds = _organizationNodeIds.toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final nodes = _filteredScopeNodes(query, type);
            return AlertDialog(
              title: const Text('Chọn đơn vị tổ chức'),
              content: SizedBox(
                width: 560,
                height: 520,
                child: Column(
                  children: [
                    AppTextInput(
                      controller: searchController,
                      label: 'Tìm đơn vị, mã showroom, tên miền',
                      icon: Icons.search_rounded,
                      autofocus: true,
                      onChanged: (value) => setDialogState(() => query = value),
                    ),
                    const SizedBox(height: AppLayoutTokens.formInlineGap),
                    AppSelectField<String?>(
                      value: type,
                      label: 'Loại đơn vị',
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
                            final isGlobal = selectedIds.isEmpty;
                            return CheckboxListTile(
                              value: isGlobal,
                              controlAffinity: ListTileControlAffinity.leading,
                              secondary: const Icon(Icons.public_rounded),
                              title: const Text('Toàn hệ thống'),
                              subtitle: const Text(
                                'Áp dụng cho toàn bộ hệ thống',
                              ),
                              onChanged: (value) =>
                                  setDialogState(selectedIds.clear),
                            );
                          }
                          final nodeIndex = _allowsGlobalNationalScope
                              ? index - 1
                              : index;
                          final node = nodes[nodeIndex];
                          final isSelected = selectedIds.contains(node.id);
                          return CheckboxListTile(
                            value: isSelected,
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: _NodeTypeBadge(type: node.type),
                            title: Text(_nodeBreadcrumb(node)),
                            subtitle: Text(_nodeCode(node)),
                            onChanged: (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedIds.add(node.id);
                                } else {
                                  selectedIds.remove(node.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                AppDialogCancelButton(
                  onPressed: () => Navigator.of(context).pop(),
                  label: 'Đóng',
                ),
                AppDialogConfirmButton(
                  onPressed: () => Navigator.of(context).pop(selectedIds),
                  label: 'Áp dụng',
                ),
              ],
            );
          },
        );
      },
    );
    searchController.dispose();
    if (!mounted) return;
    if (selected == null) return;
    _applyOrganizationNodes(selected);
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

  void _applyOrganizationNodes(Set<String> nodeIds) {
    final normalized = nodeIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    setState(() {
      _organizationNodeIds
        ..clear()
        ..addAll(normalized);
      _organizationNodeId = normalized.isEmpty ? null : normalized.first;
      _applyOrganizationNodeToState(_nodeById(_organizationNodeId));
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
    if (node.type == 'LV4_STORE') {
      return 'STORE';
    }
    if (node.type == 'LV5_POSITION') {
      if (_ancestorNode(node, 'LV4_STORE') != null) return 'STORE';
      if (_ancestorNode(node, 'LV3_AREA') != null) return 'AREA';
      if (_ancestorNode(node, 'LV2_REGION') != null) return 'REGION';
      return 'NATIONAL';
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
              AppTextInput(
                controller: _emailController,
                label: 'Email',
                enabled: widget.user == null,
              ),
              AppTextInput(controller: _firstNameController, label: 'Tên'),
              AppTextInput(controller: _lastNameController, label: 'Họ'),
              if (widget.canEditRole)
                AppSelectField<String>(
                  value: _role,
                  label: 'Quyền hệ thống',
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
                AppReadOnlyField(
                  value: _roleTitle(_role),
                  label: 'Quyền hệ thống',
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
              AppReadOnlyField(
                key: ValueKey(
                  '${widget.user?.personnelCode}|$_jobRoleCode|$_workScopeType|$_storeId',
                ),
                value: _previewPersonnelCode(_jobRoleCode, _workScopeType),
                label: 'Mã nhân sự',
              ),
              AppSelectField<String>(
                value: _status,
                label: 'Trạng thái',
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InputDecorator(
        decoration: appInputDecoration(
          label: label,
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
                style: AppTextStyles.bodyM.copyWith(
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
        borderRadius: BorderRadius.circular(AppRadius.xs),
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
