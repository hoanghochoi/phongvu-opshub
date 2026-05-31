import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _picker = ImagePicker();

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
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final success = await context.read<AuthProvider>().uploadAvatar(image.path);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<AuthProvider>().errorMessage ??
                'Không cập nhật được avatar',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const _ChangePasswordDialog(),
    );
    if (!mounted || changed != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã đổi mật khẩu'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _save() async {
    final success = await context.read<AuthProvider>().updateProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Đã lưu thông tin cá nhân'
              : context.read<AuthProvider>().errorMessage ?? 'Không lưu được',
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
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
            OutlinedButton.icon(
              onPressed: context.watch<AuthProvider>().isLoading
                  ? null
                  : _changePassword,
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Đổi mật khẩu'),
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppPrimaryButton(
              onPressed: _save,
              icon: Icons.save_outlined,
              label: 'Lưu',
              isLoading: context.watch<AuthProvider>().isLoading,
              loadingLabel: 'Đang lưu...',
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
        backgroundColor: Colors.red,
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
