import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/info_row.dart';
import '../../domain/entities/vietqr_transfer.dart';

class PaymentSuccessPanel extends StatelessWidget {
  final VietQrPaymentConfirmation confirmation;
  final NumberFormat amountFormatter;

  const PaymentSuccessPanel({
    super.key,
    required this.confirmation,
    required this.amountFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final payer = _payerLabel();

    return AppSurfaceCard(
      backgroundColor: AppColors.success.withValues(alpha: 0.08),
      borderColor: AppColors.success.withValues(alpha: 0.20),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 92,
          ),
          const SizedBox(height: 10),
          Text(
            'Đã nhận thanh toán',
            textAlign: TextAlign.center,
            style: AppTextStyles.headingM.copyWith(color: AppColors.success),
          ),
          const SizedBox(height: AppLayoutTokens.formFieldGap),
          if (payer.isNotEmpty)
            AppInfoRow(label: 'Người chuyển', value: payer, labelWidth: 118),
          if (confirmation.matchedAmount != null)
            AppInfoRow(
              label: 'Đã nhận',
              value:
                  '${amountFormatter.format(confirmation.matchedAmount)} VND',
              labelWidth: 118,
            ),
          if (confirmation.matchedTransactionContent != null)
            AppInfoRow(
              label: 'Nội dung',
              value: confirmation.matchedTransactionContent!,
              labelWidth: 118,
            ),
          if (confirmation.matchedStatementNumber != null)
            AppInfoRow(
              label: 'Mã sao kê',
              value: confirmation.matchedStatementNumber!,
              labelWidth: 118,
            ),
          if (confirmation.matchedTranTime != null)
            AppInfoRow(
              label: 'Thời gian',
              value: DateFormat(
                'HH:mm dd/MM/yyyy',
              ).format(confirmation.matchedTranTime!.toLocal()),
              labelWidth: 118,
            ),
        ],
      ),
    );
  }

  String _payerLabel() {
    final parts = [
      confirmation.matchedPayerName,
      confirmation.matchedPayerAccount,
    ].where((value) => value != null && value.trim().isNotEmpty).cast<String>();
    return parts.join(' - ');
  }
}
