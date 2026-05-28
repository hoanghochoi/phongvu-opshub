import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
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
