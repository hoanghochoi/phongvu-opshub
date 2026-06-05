import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _avatarExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  ];

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _firstNameController.text = user?.name ?? '';
    _lastNameController.text = user?.lastName ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final authProvider = context.read<AuthProvider>();
    await AppLogger.instance.info('Profile', 'Avatar picker opened');

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _avatarExtensions,
        allowMultiple: false,
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) {
        await AppLogger.instance.info('Profile', 'Avatar picker cancelled');
        return;
      }

      final path = file.path;
      final bytes = file.bytes;
      if (path == null && bytes == null) {
        await AppLogger.instance.warn(
          'Profile',
          'Avatar picker returned unreadable file',
          context: {'fileName': file.name, 'size': file.size},
        );
        if (mounted) {
          _showMessage('Chưa đọc được file ảnh. Vui lòng chọn ảnh khác.');
        }
        return;
      }

      await AppLogger.instance.info(
        'Profile',
        'Avatar file selected',
        context: {
          'fileName': file.name,
          'size': file.size,
          'hasPath': path != null,
          'hasBytes': bytes != null,
        },
      );
      if (!mounted) return;

      final success = await authProvider.uploadAvatar(
        path: path,
        bytes: bytes,
        fileName: file.name,
      );
      if (!success && mounted) {
        _showMessage(authProvider.errorMessage ?? 'Không cập nhật được avatar');
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Profile',
        'Avatar picker crashed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) {
        _showMessage('Chưa mở được bộ chọn ảnh. Vui lòng thử lại.');
      }
    }
  }

  void _showMessage(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (!mounted || changed != true) return;
    _showMessage('Đã đổi mật khẩu', success: true);
  }

  Future<void> _save() async {
    final success = await context.read<AuthProvider>().updateProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );
    if (!mounted) return;
    _showMessage(
      success
          ? 'Đã lưu thông tin cá nhân'
          : context.read<AuthProvider>().errorMessage ?? 'Không lưu được',
      success: success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final avatarUrl = user?.avatarUrl;

    return Scaffold(
      appBar: const GradientHeader(title: 'Thông tin cá nhân', showBack: true),
      body: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.formMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundImage:
                        avatarUrl != null && avatarUrl.startsWith('http')
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null
                        ? Text((user?.name ?? '?')[0].toUpperCase())
                        : null,
                  ),
                  AppIconAction(
                    onPressed: _pickAvatar,
                    icon: Icons.camera_alt_outlined,
                    tooltip: 'Cập nhật avatar',
                    filled: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _firstNameController,
              decoration: const InputDecoration(
                labelText: 'Tên',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            TextField(
              controller: _lastNameController,
              decoration: const InputDecoration(
                labelText: 'Họ',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined),
              title: Text(user?.email ?? ''),
              subtitle: Text('Quyền hệ thống: ${user?.role ?? ''}'),
            ),
            if (user?.personnelCode != null || user?.workScopeType != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(user?.personnelCode ?? 'Chưa gán mã nhân sự'),
                subtitle: Text(
                  'Phòng ban: ${user?.departmentCode ?? 'Chưa gán'} • Chức danh: ${user?.jobRoleCode ?? 'Chưa gán'} • Phạm vi: ${user?.workScopeType ?? 'Chưa gán'}',
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.store_outlined),
              title: Text(user?.storeInfo ?? ''),
              subtitle: const Text(
                'Chi nhánh đã chọn sẽ không tự thay đổi được',
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            AppActionRow(
              children: [
                AppSecondaryButton(
                  onPressed: context.watch<AuthProvider>().isLoading
                      ? null
                      : _changePassword,
                  icon: Icons.lock_reset_outlined,
                  label: 'Đổi mật khẩu',
                ),
                AppPrimaryButton(
                  onPressed: _save,
                  icon: Icons.save_outlined,
                  label: 'Lưu',
                  isLoading: context.watch<AuthProvider>().isLoading,
                  loadingLabel: 'Đang lưu...',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(authProvider.errorMessage ?? 'Không đổi được mật khẩu'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    return AlertDialog(
      title: const Text('Đổi mật khẩu'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: AppFormColumn(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _currentController,
                  enabled: !isLoading,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: isLoading
                          ? null
                          : () => setState(
                              () => _obscureCurrent = !_obscureCurrent,
                            ),
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Vui lòng nhập mật khẩu hiện tại'
                      : null,
                ),
                TextFormField(
                  controller: _newController,
                  enabled: !isLoading,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      onPressed: isLoading
                          ? null
                          : () => setState(() => _obscureNew = !_obscureNew),
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      Validators.getPasswordError(value ?? ''),
                ),
                TextFormField(
                  controller: _confirmController,
                  enabled: !isLoading,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Nhập lại mật khẩu mới',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      onPressed: isLoading
                          ? null
                          : () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value != _newController.text
                      ? 'Mật khẩu nhập lại chưa khớp'
                      : null,
                  onFieldSubmitted: (_) => isLoading ? null : _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: isLoading ? null : _submit,
          child: Text(isLoading ? 'Đang đổi...' : 'Đổi mật khẩu'),
        ),
      ],
    );
  }
}
