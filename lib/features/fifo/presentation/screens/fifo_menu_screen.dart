import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class FifoMenuScreen extends StatelessWidget {
  const FifoMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.user?.role ?? '';
    final isAdmin = role == 'ADMIN' || role == 'SUPER_ADMIN';
    final actions = [
      AppFeatureAction(
        icon: Icons.qr_code_scanner_rounded,
        title: 'Kiểm tra FIFO',
        description: 'Tra cứu thứ tự FIFO',
        color: AppColors.info,
        onTap: () => context.push('/fifo-check'),
      ),
      AppFeatureAction(
        icon: Icons.swap_vert_rounded,
        title: 'Sắp xếp FIFO',
        description: 'Quét hoặc nhập SKU/BIN',
        color: AppColors.indigo600,
        onTap: () => context.push('/sort'),
      ),
      if (isAdmin)
        AppFeatureAction(
          icon: Icons.history_rounded,
          title: 'Lịch sử FIFO',
          description: 'Kiểm tra & sắp xếp',
          color: AppColors.purple600,
          onTap: () => context.push('/fifo-history'),
        ),
    ];

    return Scaffold(
      appBar: const GradientHeader(title: 'FIFO', showBack: true),
      body: AppResponsiveContent(child: AppFeatureSection(actions: actions)),
    );
  }
}
