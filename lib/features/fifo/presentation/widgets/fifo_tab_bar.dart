import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

class FifoHistoryTabBar extends StatelessWidget {
  final TabController controller;

  const FifoHistoryTabBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      labelColor: AppColors.primaryOf(context),
      unselectedLabelColor: AppColors.neutral700Of(context),
      indicatorColor: AppColors.primaryOf(context),
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
