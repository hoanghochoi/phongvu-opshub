import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../domain/entities/vietqr_transfer.dart';

class PaymentConfirmationCard extends StatelessWidget {
  final VietQrPaymentConfirmation confirmation;
  final NumberFormat amountFormatter;

  const PaymentConfirmationCard({
    super.key,
    required this.confirmation,
    required this.amountFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final confirmed = confirmation.confirmed;
    final color = confirmed ? AppColors.success : AppColors.warning;
    final title = confirmed
        ? 'Đã xác nhận thanh toán'
        : _statusTitle(confirmation.reason);

    return AppSurfaceCard(
      backgroundColor: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.20),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            confirmed ? Icons.check_circle_rounded : Icons.info_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelM.copyWith(color: color)),
                if (confirmation.matchedAmount != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Số tiền: ${amountFormatter.format(confirmation.matchedAmount)} VND',
                    style: AppTextStyles.bodyM,
                  ),
                ],
                if (confirmation.matchedStatementNumber != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Mã sao kê: ${confirmation.matchedStatementNumber}',
                    style: AppTextStyles.bodyM,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusTitle(String reason) {
    switch (reason) {
      case 'NO_MATCH':
        return 'Chưa thấy giao dịch khớp';
      case 'MULTIPLE_MATCHES':
        return 'Cần kiểm tra thủ công';
      case 'MISSING_MATCH_FIELDS':
        return 'Thiếu dữ liệu để tự xác nhận';
      case 'EXPIRED_VIETNAM_15M':
        return 'QR đã hết hạn 15 phút';
      case 'EXPIRED_VIETNAM_DAY':
        return 'QR đã hết hạn';
      default:
        return 'Chưa xác nhận được';
    }
  }
}
