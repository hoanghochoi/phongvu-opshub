import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_buttons.dart';

Future<bool> showLogoutConfirmationDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.logout_rounded, color: AppColors.error),
      title: const Text('Xác nhận đăng xuất'),
      content: const Text(
        'Bạn có chắc chắn muốn đăng xuất khỏi OpsHub? Bạn sẽ cần đăng nhập lại để tiếp tục làm việc trên thiết bị này.',
      ),
      actions: [
        AppDialogCancelButton(
          label: 'Ở lại',
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        AppDialogConfirmButton(
          icon: Icons.logout_rounded,
          label: 'Đăng xuất',
          backgroundColor: AppColors.error,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
