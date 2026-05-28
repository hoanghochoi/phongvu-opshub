import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

class FifoHistoryTabBar extends StatelessWidget {
  final TabController controller;

  const FifoHistoryTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? AppColors.neutral300 : AppColors.neutral700,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [AppColors.info, Color(0xFF29B6F6)],
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
