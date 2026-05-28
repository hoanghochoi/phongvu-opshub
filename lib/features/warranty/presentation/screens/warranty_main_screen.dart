import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';
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
        onTap: () => context.push('/warranty'),
      ),
      AppFeatureAction(
        icon: Icons.search_rounded,
        title: 'Xem lại hình ảnh',
        description: 'Tìm theo biên nhận',
        color: const Color(0xFF0F766E),
        onTap: () => context.push('/check-warranty'),
      ),
    ];

    return Scaffold(
      appBar: GradientHeader(
        title: 'Bảo hành / Sửa chữa',
        showBack: true,
        onBack: onBackToHome,
      ),
      body: AppResponsiveContent(child: AppFeatureSection(actions: actions)),
    );
  }
}
