import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';

class PaymentWaitingCard extends StatelessWidget {
  final bool isChecking;

  const PaymentWaitingCard({super.key, required this.isChecking});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primary600;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đang chờ tiền vào',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Màn hình sẽ tự đổi trạng thái khi tìm thấy giao dịch khớp.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
