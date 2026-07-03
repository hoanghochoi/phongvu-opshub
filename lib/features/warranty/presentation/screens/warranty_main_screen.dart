import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_feature_grid.dart';
import '../../../../app/widgets/app_layout.dart';

class WarrantyMainScreen extends StatelessWidget {
  const WarrantyMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      AppFeatureAction(
        icon: Icons.add_photo_alternate_rounded,
        title: 'Lưu hình ảnh',
        description: 'Ghi nhận BH/SC',
        color: AppColors.success,
        onTap: () => context.push('/warranty'),
      ),
      AppFeatureAction(
        icon: Icons.search_rounded,
        title: 'Xem lại hình ảnh',
        description: 'Tìm theo biên nhận',
        color: AppColors.teal600,
        onTap: () => context.push('/check-warranty'),
      ),
    ];

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFeatureSection(title: 'Tác vụ BH / SC', actions: actions),
        ],
      ),
    );
  }
}
