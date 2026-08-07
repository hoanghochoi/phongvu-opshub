import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
        icon: PhosphorIconsRegular.imageSquare,
        title: 'Lưu hình ảnh',
        description: 'Ghi nhận bảo hành/sửa chữa',
        color: AppColors.successOf(context),
        onTap: () => context.push('/warranty'),
      ),
      AppFeatureAction(
        icon: PhosphorIconsRegular.magnifyingGlass,
        title: 'Xem lại hình ảnh',
        description: 'Tìm theo biên nhận',
        color: AppColors.secondaryOf(context),
        onTap: () => context.push('/check-warranty'),
      ),
    ];

    return AppResponsiveScrollView(
      onRefresh: AppRefreshCallbacks.noop,
      refreshLogSource: 'Warranty',
      refreshLogContext: () => {'actionCount': actions.length},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFeatureSection(title: 'Tác vụ bảo hành', actions: actions),
        ],
      ),
    );
  }
}
