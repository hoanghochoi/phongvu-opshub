import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

class FifoHistoryTabBar extends StatelessWidget {
  final TabController controller;

  const FifoHistoryTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TabBar(
      controller: controller,
      labelColor: AppColors.primary,
      unselectedLabelColor: isDark
          ? AppColors.neutral300
          : AppColors.neutral700,
      indicatorColor: AppColors.primary,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Theme.of(context).dividerColor,
      tabs: const [
        Tab(text: 'Kiểm tra'),
        Tab(text: 'Sắp xếp'),
      ],
    );
  }
}
