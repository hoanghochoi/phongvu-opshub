import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_cards.dart';

class FifoHistoryTabBar extends StatelessWidget {
  final TabController controller;

  const FifoHistoryTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: controller,
        labelColor: AppColors.surface,
        unselectedLabelColor: isDark
            ? AppColors.neutral300
            : AppColors.neutral700,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: AppColors.primary,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'Kiểm tra FIFO'),
          Tab(text: 'Sắp xếp FIFO'),
        ],
      ),
    );
  }
}
