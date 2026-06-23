import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/info_row.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/map_payment_transaction.dart';

class PaymentTransactionTile extends StatelessWidget {
  final MapPaymentTransaction transaction;
  final NumberFormat amountFormatter;

  const PaymentTransactionTile({
    super.key,
    required this.transaction,
    required this.amountFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final displayTime = _toVietnamTime(
      transaction.paidAt ?? transaction.firstSeenAt,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = transaction.hasOrders
        ? AppColors.success
        : AppColors.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        side: BorderSide(
          color: borderColor.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: ListTile(
        onTap: () => unawaited(
          showPaymentTransactionDetails(
            context,
            transaction: transaction,
            amountFormatter: amountFormatter,
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: isDark
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.success.withValues(alpha: 0.08),
          child: const Icon(Icons.payments_rounded, color: AppColors.success),
        ),
        title: Text(
          '${amountFormatter.format(transaction.amount)} VND',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (displayTime != null)
              Text(DateFormat('HH:mm:ss dd/MM').format(displayTime)),
            if (transaction.payerLabel.isNotEmpty)
              Text(
                'Người chuyển: ${transaction.payerLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            if (transaction.content.isNotEmpty)
              Text(
                transaction.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

Future<void> showPaymentTransactionDetails(
  BuildContext context, {
  required MapPaymentTransaction transaction,
  required NumberFormat amountFormatter,
}) async {
  final stopwatch = Stopwatch()..start();
  await AppLogger.instance.info(
    'PaymentMonitor',
    'Payment transaction details opening',
    context: {
      if (transaction.transactionNumber.isNotEmpty)
        'transactionNumber': transaction.transactionNumber,
      'storeId': transaction.storeId,
      'hasPayerName': transaction.payerName.isNotEmpty,
      'hasPayerAccount': transaction.payerAccount.isNotEmpty,
    },
  );
  if (!context.mounted) {
    await AppLogger.instance.warn(
      'PaymentMonitor',
      'Payment transaction details opening cancelled',
      context: {
        if (transaction.transactionNumber.isNotEmpty)
          'transactionNumber': transaction.transactionNumber,
        'storeId': transaction.storeId,
        'reason': 'context_unmounted',
      },
    );
    return;
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => PaymentTransactionDetailDialog(
        transaction: transaction,
        amountFormatter: amountFormatter,
      ),
    );
    await AppLogger.instance.info(
      'PaymentMonitor',
      'Payment transaction details closed',
      context: {
        if (transaction.transactionNumber.isNotEmpty)
          'transactionNumber': transaction.transactionNumber,
        'storeId': transaction.storeId,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'PaymentMonitor',
      'Payment transaction details failed',
      error: error,
      stackTrace: stackTrace,
      context: {
        if (transaction.transactionNumber.isNotEmpty)
          'transactionNumber': transaction.transactionNumber,
        'storeId': transaction.storeId,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được chi tiết giao dịch')),
      );
    }
  }
}

class PaymentTransactionDetailDialog extends StatelessWidget {
  final MapPaymentTransaction transaction;
  final NumberFormat amountFormatter;

  const PaymentTransactionDetailDialog({
    super.key,
    required this.transaction,
    required this.amountFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final paidAt = _toVietnamTime(transaction.paidAt);
    final firstSeenAt = _toVietnamTime(transaction.firstSeenAt);
    final status = _statusLabel(transaction);

    return AlertDialog(
      key: const ValueKey('payment-transaction-detail-dialog'),
      title: const Text('Chi tiết giao dịch'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInfoRow(
                  label: 'Người chuyển',
                  value: transaction.payerName,
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Tài khoản',
                  value: transaction.payerAccount,
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Số tiền',
                  value: '${amountFormatter.format(transaction.amount)} VND',
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Thời gian GD',
                  value: paidAt == null
                      ? ''
                      : DateFormat('HH:mm:ss dd/MM/yyyy').format(paidAt),
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Mã giao dịch',
                  value: transaction.transactionNumber,
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Nội dung',
                  value: transaction.content,
                  labelWidth: 132,
                ),
                AppInfoRow(label: 'Trạng thái', value: status, labelWidth: 132),
                AppInfoRow(
                  label: 'Showroom',
                  value: transaction.storeId,
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'OpsHub ghi nhận',
                  value: firstSeenAt == null
                      ? ''
                      : DateFormat('HH:mm:ss dd/MM/yyyy').format(firstSeenAt),
                  labelWidth: 132,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

DateTime? _toVietnamTime(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().add(const Duration(hours: 7));
}

String _statusLabel(MapPaymentTransaction transaction) {
  if (!transaction.successful) return transaction.status;
  if (transaction.status.isEmpty) return 'Thành công';
  if (transaction.status.trim() == '00') return 'Thành công (00)';
  return transaction.status;
}
