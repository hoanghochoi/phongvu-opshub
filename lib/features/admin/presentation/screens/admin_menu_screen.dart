import 'package:flutter/material.dart';

import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/gradient_header.dart';

class AdminMenuScreen extends StatelessWidget {
  const AdminMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      AppFeatureAction(
        icon: Icons.people_alt_outlined,
        title: 'Quản lý user',
        description: 'Tài khoản & chi nhánh',
        color: const Color(0xFF2563EB),
        onTap: () => Navigator.of(context).pushNamed('/admin/users'),
      ),
      AppFeatureAction(
        icon: Icons.admin_panel_settings_outlined,
        title: 'Quản lý role',
        description: 'Quyền & phạm vi',
        color: const Color(0xFF7C3AED),
        onTap: () => Navigator.of(context).pushNamed('/admin/roles'),
      ),
      AppFeatureAction(
        icon: Icons.store_mall_directory_outlined,
        title: 'Quản lý store',
        description: 'Chi nhánh & tài khoản CK',
        color: const Color(0xFF059669),
        onTap: () => Navigator.of(context).pushNamed('/admin/stores'),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Quản trị', showBack: true),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: AppFeatureSection(actions: actions),
      ),
    );
  }
}
