import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
    final color = confirmed ? Colors.green : Colors.orange;
    final title = confirmed
        ? 'Đã xác nhận thanh toán'
        : _statusTitle(confirmation.reason);

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
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
                  Text(
                    title,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  if (confirmation.matchedAmount != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Số tiền: ${amountFormatter.format(confirmation.matchedAmount)} VND',
                    ),
                  ],
                  if (confirmation.matchedStatementNumber != null) ...[
                    const SizedBox(height: 4),
                    Text('Mã sao kê: ${confirmation.matchedStatementNumber}'),
                  ],
                ],
              ),
            ),
          ],
        ),
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
      case 'EXPIRED_VIETNAM_DAY':
        return 'QR da qua ngay';
      default:
        return 'Chưa xác nhận được';
    }
  }
}
