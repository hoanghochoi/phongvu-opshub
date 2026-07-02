import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class FifoMenuScreen extends StatelessWidget {
  const FifoMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final role = user?.role ?? '';
    final canUseFifo = user?.canUseFeature('FIFO') == true;
    final canImportInventory = user?.canUseFeature('FIFO_IMPORT') == true;
    final canViewHistory = canUseFifo && User.isAdminRole(role);
    final actions = [
      if (canUseFifo)
        AppFeatureAction(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Kiểm tra FIFO',
          description: 'Tra cứu thứ tự FIFO',
          color: AppColors.info,
          onTap: () => context.push('/fifo-check'),
        ),
      if (canUseFifo)
        AppFeatureAction(
          icon: Icons.swap_vert_rounded,
          title: 'Sắp xếp FIFO',
          description: 'Quét hoặc nhập SKU/BIN',
          color: AppColors.indigo600,
          onTap: () => context.push('/sort'),
        ),
      if (canImportInventory)
        AppFeatureAction(
          icon: Icons.upload_file_outlined,
          title: 'Cập nhật tồn kho',
          description: 'Import Excel cho FIFO',
          color: AppColors.amber500,
          onTap: () => context.push('/fifo/inventory-import'),
        ),
      if (canViewHistory)
        AppFeatureAction(
          icon: Icons.history_rounded,
          title: 'Lịch sử FIFO',
          description: 'Kiểm tra & sắp xếp',
          color: AppColors.purple600,
          onTap: () => context.push('/fifo-history'),
        ),
    ];

    if (actions.isEmpty) {
      return const Center(child: Text('Chưa có tính năng FIFO được bật.'));
    }
    return AppResponsiveContent(child: AppFeatureSection(actions: actions));
  }
}
