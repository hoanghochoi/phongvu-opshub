import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_state_widgets.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.shadow.withValues(alpha: 0.54),
      child: const Center(
        child: AppStatePanel.loading(
          title: 'Đang kiểm tra FIFO',
          compact: true,
        ),
      ),
    );
  }
}
