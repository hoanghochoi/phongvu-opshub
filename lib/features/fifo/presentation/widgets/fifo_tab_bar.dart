import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_layout.dart';

class FifoHistoryTabBar extends StatelessWidget {
  final TabController controller;

  const FifoHistoryTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        labelColor: AppColors.surface,
        unselectedLabelColor: isDark
            ? AppColors.neutral300
            : AppColors.neutral700,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          gradient: const LinearGradient(
            colors: [AppColors.info, AppColors.sky500],
          ),
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
