import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/widgets/info_row.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/bank_statement_transaction.dart';

class BankStatementTransactionDetailsLauncher extends StatelessWidget {
  final BankStatementTransaction transaction;
  final NumberFormat amountFormatter;
  final Widget child;

  const BankStatementTransactionDetailsLauncher({
    super.key,
    required this.transaction,
    required this.amountFormatter,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Xem chi tiết giao dịch',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => unawaited(
          showBankStatementTransactionDetails(
            context,
            transaction: transaction,
            amountFormatter: amountFormatter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: child),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.open_in_new_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showBankStatementTransactionDetails(
  BuildContext context, {
  required BankStatementTransaction transaction,
  required NumberFormat amountFormatter,
}) async {
  final stopwatch = Stopwatch()..start();
  final logContext = <String, Object?>{
    if (transaction.id.isNotEmpty) 'transactionId': transaction.id,
    if (transaction.statementNumber.isNotEmpty)
      'statementNumber': transaction.statementNumber,
    if (transaction.transactionNumber.isNotEmpty)
      'transactionNumber': transaction.transactionNumber,
    'storeId': transaction.storeId,
    'hasPayerName': (transaction.payerName ?? '').trim().isNotEmpty,
    'hasPayerAccount': (transaction.payerAccount ?? '').trim().isNotEmpty,
    'orderCount': transaction.orders.length,
  };
  await AppLogger.instance.info(
    'BankStatement',
    'Bank statement transaction details opening',
    context: logContext,
  );
  if (!context.mounted) {
    await AppLogger.instance.warn(
      'BankStatement',
      'Bank statement transaction details opening cancelled',
      context: {...logContext, 'reason': 'context_unmounted'},
    );
    return;
  }

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => BankStatementTransactionDetailDialog(
        transaction: transaction,
        amountFormatter: amountFormatter,
      ),
    );
    await AppLogger.instance.info(
      'BankStatement',
      'Bank statement transaction details closed',
      context: {...logContext, 'durationMs': stopwatch.elapsedMilliseconds},
    );
  } catch (error, stackTrace) {
    await AppLogger.instance.error(
      'BankStatement',
      'Bank statement transaction details failed',
      error: error,
      stackTrace: stackTrace,
      context: {...logContext, 'durationMs': stopwatch.elapsedMilliseconds},
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được chi tiết giao dịch')),
      );
    }
  }
}

class BankStatementTransactionDetailDialog extends StatelessWidget {
  final BankStatementTransaction transaction;
  final NumberFormat amountFormatter;

  const BankStatementTransactionDetailDialog({
    super.key,
    required this.transaction,
    required this.amountFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final paidAt = _toVietnamTime(transaction.paidAt);
    final firstSeenAt = _toVietnamTime(transaction.firstSeenAt);
    final orderUpdatedAt = _toVietnamTime(transaction.orderUpdatedAt);

    return AlertDialog(
      key: const ValueKey('bank-statement-transaction-detail-dialog'),
      title: const Text('Chi tiết giao dịch sao kê'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppInfoRow(
                  label: 'Người chuyển',
                  value: transaction.payerName?.trim() ?? '',
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Tài khoản',
                  value: transaction.payerAccount?.trim() ?? '',
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Số tiền',
                  value: '${amountFormatter.format(transaction.amount)} VND',
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Thời gian GD',
                  value: _formatDate(paidAt),
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Mã sao kê',
                  value: transaction.statementNumber,
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Nội dung',
                  value: transaction.content,
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Trạng thái',
                  value: _statusLabel(transaction.status),
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Showroom',
                  value: transaction.storeId,
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Đơn hàng',
                  value: transaction.orders.join(', '),
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Nguồn đơn',
                  value: _orderSourceLabel(transaction.orderSource),
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Người cập nhật đơn',
                  value: transaction.orderUpdatedByEmail?.trim() ?? '',
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'Cập nhật đơn lúc',
                  value: _formatDate(orderUpdatedAt),
                  labelWidth: 142,
                ),
                AppInfoRow(
                  label: 'OpsHub ghi nhận',
                  value: _formatDate(firstSeenAt),
                  labelWidth: 142,
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

String _formatDate(DateTime? value) =>
    value == null ? '' : DateFormat('HH:mm:ss dd/MM/yyyy').format(value);

DateTime? _toVietnamTime(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().add(const Duration(hours: 7));
}

String _statusLabel(String? status) {
  final value = status?.trim() ?? '';
  if (value == '00') return 'Thành công (00)';
  return value;
}

String _orderSourceLabel(String? source) {
  switch (source?.trim().toUpperCase()) {
    case 'AUTO':
      return 'Tự động từ MAP';
    case 'MANUAL':
      return 'Chỉnh sửa thủ công';
    default:
      return source?.trim() ?? '';
  }
}
