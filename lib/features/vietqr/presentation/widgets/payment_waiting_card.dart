import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';

class PaymentWaitingCard extends StatelessWidget {
  final bool isChecking;

  const PaymentWaitingCard({super.key, required this.isChecking});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primary600;

    return AppSurfaceCard(
      backgroundColor: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.20),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: isChecking
                ? const CircularProgressIndicator(strokeWidth: 2.4)
                : const Icon(Icons.sync_rounded, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang chờ tiền vào',
                  style: AppTextStyles.labelM.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Màn hình sẽ tự đổi trạng thái khi tìm thấy giao dịch khớp.',
                  style: AppTextStyles.bodyM,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
