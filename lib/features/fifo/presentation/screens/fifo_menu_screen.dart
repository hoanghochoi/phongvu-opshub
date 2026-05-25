import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        color: const Color(0xFF2563EB),
        onTap: () => Navigator.of(context).pushNamed('/fifo-check'),
      ),
      AppFeatureAction(
        icon: Icons.swap_vert_rounded,
        title: 'Sắp xếp FIFO',
        description: 'Quét hoặc nhập SKU/BIN',
        color: const Color(0xFF4F46E5),
        onTap: () => Navigator.of(context).pushNamed('/sort'),
      ),
      if (isAdmin)
        AppFeatureAction(
          icon: Icons.history_rounded,
          title: 'Lịch sử FIFO',
          description: 'Kiểm tra & sắp xếp',
          color: const Color(0xFF9333EA),
          onTap: () => Navigator.of(context).pushNamed('/fifo-history'),
        ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'FIFO', showBack: true),
      body: AppResponsiveContent(child: AppFeatureSection(actions: actions)),
    );
  }
}
