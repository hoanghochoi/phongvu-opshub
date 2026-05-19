import 'package:flutter/material.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/gradient_header.dart';

class WarrantyMainScreen extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const WarrantyMainScreen({super.key, this.onBackToHome});

  @override
  Widget build(BuildContext context) {
    final actions = [
      AppFeatureAction(
        icon: Icons.add_photo_alternate_rounded,
        title: 'Lưu hình ảnh',
        description: 'Ghi nhận BH/SC',
        color: const Color(0xFF16A34A),
        onTap: () => Navigator.of(context).pushNamed('/warranty'),
      ),
      AppFeatureAction(
        icon: Icons.search_rounded,
        title: 'Xem lại hình ảnh',
        description: 'Tìm theo biên nhận',
        color: const Color(0xFF0F766E),
        onTap: () => Navigator.of(context).pushNamed('/check-warranty'),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: GradientHeader(
        title: 'Bảo hành / Sửa chữa',
        showBack: onBackToHome == null,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: AppFeatureSection(actions: actions),
      ),
    );
  }
}
