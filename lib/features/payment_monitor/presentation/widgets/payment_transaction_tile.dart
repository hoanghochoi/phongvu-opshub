import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/info_row.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../providers/payment_monitor_provider.dart';
import '../../domain/map_payment_transaction.dart';

class PaymentTransactionTile extends StatefulWidget {
  final MapPaymentTransaction transaction;
  final NumberFormat amountFormatter;
  final PaymentMonitorRowMessage? rowMessage;
  final bool canReviewTransfer;
  final Future<void> Function(String rawInput) onSaveOrders;
  final Future<bool> Function(String rawInput) onRequestTransfer;
  final Future<void> Function(String requestId) onApproveTransfer;
  final Future<void> Function(String requestId, {String? note})
  onRejectTransfer;
  final Future<List<BankStatementOrderHistoryEntry>> Function() onLoadHistory;

  const PaymentTransactionTile({
    super.key,
    required this.transaction,
    required this.amountFormatter,
    required this.rowMessage,
    required this.canReviewTransfer,
    required this.onSaveOrders,
    required this.onRequestTransfer,
    required this.onApproveTransfer,
    required this.onRejectTransfer,
    required this.onLoadHistory,
  });

  @override
  State<PaymentTransactionTile> createState() => _PaymentTransactionTileState();
}

class _PaymentTransactionTileState extends State<PaymentTransactionTile> {
  late final TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _ordersEditText(widget.transaction.orders),
    );
  }

  @override
  void didUpdateWidget(covariant PaymentTransactionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transaction.id != widget.transaction.id || !_editing) {
      _controller.text = _ordersEditText(widget.transaction.orders);
      _editing = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final displayTime = _toVietnamTime(
      transaction.paidAt ?? transaction.firstSeenAt,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = transaction.hasPendingOrderTransferRequest
        ? AppColors.warning
        : transaction.hasOrders
        ? AppColors.success
        : AppColors.error;

    Widget buildDetails() {
      return InkWell(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        onTap: () => unawaited(
          showPaymentTransactionDetails(
            context,
            transaction: transaction,
            amountFormatter: widget.amountFormatter,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: isDark
                  ? AppColors.success.withValues(alpha: 0.15)
                  : AppColors.success.withValues(alpha: 0.08),
              child: const Icon(
                Icons.payments_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.amountFormatter.format(transaction.amount)} VND',
                    style: AppTextStyles.labelM,
                  ),
                  if (displayTime != null)
                    Text(DateFormat('HH:mm:ss dd/MM').format(displayTime)),
                  if (transaction.storeId.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    AppStatusChip(
                      label: 'Showroom ${transaction.storeId}',
                      color: AppColors.info,
                      maxWidth: 180,
                    ),
                  ],
                  if (transaction.payerLabel.isNotEmpty)
                    Text(
                      'Người chuyển: ${transaction.payerLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM,
                    ),
                  if (transaction.content.isNotEmpty)
                    Text(
                      transaction.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }

    Widget buildOrderEditor() {
      return _PaymentOrderEditor(
        transaction: transaction,
        controller: _controller,
        editing: _editing,
        canReviewTransfer: widget.canReviewTransfer,
        onEdit: () => setState(() => _editing = true),
        onCancel: () {
          _controller.text = _ordersEditText(transaction.orders);
          setState(() => _editing = false);
        },
        onSave: () async {
          await widget.onSaveOrders(_controller.text);
          if (mounted) setState(() => _editing = false);
        },
        onRequestTransfer: () => _showOrderTransferRequestDialog(context),
        onReviewTransfer: () => _showOrderTransferReviewDialog(context),
        onHistory: () => _showHistory(context),
      );
    }

    Widget buildRowMessage({required bool reserveSpace}) {
      return AnimatedOpacity(
        opacity: widget.rowMessage == null ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: widget.rowMessage == null
            ? SizedBox(height: reserveSpace ? 26 : 0)
            : Padding(
                padding: EdgeInsets.only(top: 8, left: reserveSpace ? 0 : 4),
                child: Text(
                  widget.rowMessage!.text,
                  style: AppTextStyles.captionBold.copyWith(
                    color: widget.rowMessage!.success
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
              ),
      );
    }

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderColor: borderColor.withValues(alpha: 0.65),
      borderWidth: 1.2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildDetails(),
                const SizedBox(height: 10),
                buildOrderEditor(),
                buildRowMessage(reserveSpace: false),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildDetails()),
              const SizedBox(width: 12),
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildOrderEditor(),
                    buildRowMessage(reserveSpace: true),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showOrderTransferRequestDialog(BuildContext context) async {
    final controller = TextEditingController(
      text: _ordersEditText(widget.transaction.orderTransferRequestedOrders),
    );
    if (controller.text.isEmpty) {
      controller.text = _ordersEditText(widget.transaction.orders);
    }
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cập nhật mã đơn'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.transaction.statementNumber.isEmpty
                      ? 'Nhập mã đơn hàng mới để gửi Kế toán xác nhận.'
                      : 'Mã sao kê: ${widget.transaction.statementNumber}',
                  style: AppTextStyles.labelM,
                ),
                const SizedBox(height: 12),
                AppTextInput(
                  controller: controller,
                  label: 'Mã đơn hàng mới',
                  hintText: 'Nhập mỗi mã một dòng, hoặc cách bằng dấu phẩy',
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'Đóng',
            ),
            AppDialogConfirmButton(
              onPressed: () async {
                final ok = await widget.onRequestTransfer(controller.text);
                if (ok && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              icon: Icons.send_rounded,
              label: 'Gửi xác nhận',
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showOrderTransferReviewDialog(BuildContext context) async {
    final requestId = widget.transaction.orderTransferRequestId?.trim() ?? '';
    if (requestId.isEmpty) return;
    final noteController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận cập nhật mã đơn'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SelectionArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppInfoRow(
                    label: 'Mã sao kê',
                    value: widget.transaction.statementNumber,
                    labelWidth: 132,
                  ),
                  AppInfoRow(
                    label: 'Đơn hiện tại',
                    value: statementOrdersText(widget.transaction.orders),
                    labelWidth: 132,
                  ),
                  AppInfoRow(
                    label: 'Đơn đề nghị',
                    value: statementOrdersText(
                      widget.transaction.orderTransferRequestedOrders,
                    ),
                    labelWidth: 132,
                  ),
                  AppInfoRow(
                    label: 'Người gửi',
                    value:
                        widget.transaction.orderTransferRequestedByEmail ?? '',
                    labelWidth: 132,
                  ),
                  const SizedBox(height: 12),
                  AppTextInput(
                    controller: noteController,
                    label: 'Lý do từ chối nếu có',
                    minLines: 1,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'Đóng',
            ),
            AppDialogSecondaryButton(
              onPressed: () async {
                await widget.onRejectTransfer(
                  requestId,
                  note: noteController.text,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              icon: Icons.close_rounded,
              label: 'Từ chối',
            ),
            AppDialogConfirmButton(
              onPressed: () async {
                await widget.onApproveTransfer(requestId);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
              icon: Icons.check_rounded,
              label: 'Duyệt',
            ),
          ],
        ),
      );
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _showHistory(BuildContext context) async {
    final statementNumber = widget.transaction.statementNumber.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          statementNumber.isEmpty
              ? 'Lịch sử mã đơn'
              : 'Lịch sử mã đơn $statementNumber',
        ),
        content: SizedBox(
          width: 520,
          child: FutureBuilder<List<BankStatementOrderHistoryEntry>>(
            future: widget.onLoadHistory(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const AppStatePanel.loading(
                  title: 'Đang tải lịch sử mã đơn',
                  compact: true,
                );
              }
              if (snapshot.hasError) {
                return const AppStatePanel.error(
                  title: 'Chưa tải được lịch sử mã đơn',
                  message: 'Vui lòng thử lại sau ít phút.',
                  compact: true,
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const AppStatePanel.empty(
                  title: 'Chưa có lịch sử chỉnh sửa',
                  message: 'Các lần cập nhật mã đơn sẽ xuất hiện tại đây.',
                  icon: Icons.history_rounded,
                  compact: true,
                );
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SelectionArea(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final item = rows[index];
                      final createdAt = _toVietnamTime(item.createdAt);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            createdAt == null
                                ? 'Cập nhật mã đơn'
                                : DateFormat(
                                    'HH:mm:ss dd/MM/yyyy',
                                  ).format(createdAt),
                            style: AppTextStyles.labelM,
                          ),
                          const SizedBox(height: 4),
                          Text('Từ: ${statementOrdersText(item.oldOrders)}'),
                          Text('Thành: ${statementOrdersText(item.newOrders)}'),
                          if ((item.changedByEmail ?? '').isNotEmpty)
                            Text('Người cập nhật: ${item.changedByEmail}'),
                        ],
                      );
                    },
                    separatorBuilder: (_, _) => const Divider(height: 18),
                    itemCount: rows.length,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Đóng',
          ),
        ],
      ),
    );
  }
}

class _PaymentOrderEditor extends StatelessWidget {
  final MapPaymentTransaction transaction;
  final TextEditingController controller;
  final bool editing;
  final bool canReviewTransfer;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;
  final VoidCallback onRequestTransfer;
  final VoidCallback onReviewTransfer;
  final VoidCallback onHistory;

  const _PaymentOrderEditor({
    required this.transaction,
    required this.controller,
    required this.editing,
    required this.canReviewTransfer,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onRequestTransfer,
    required this.onReviewTransfer,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final blockedReason =
        transaction.orderEditBlockedReason ??
        transaction.orderTransferRequestBlockedReason;
    return DecoratedBox(
      key: const ValueKey('payment-transaction-order-editor'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Đơn hàng', style: AppTextStyles.labelM),
                      if (transaction.isOrderOffsetConfirmed)
                        const AppStatusChip(
                          label: 'Đã cấn trừ',
                          color: AppColors.warning,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: transaction.canRequestOrderTransfer
                      ? 'Cập nhật mã đơn'
                      : transaction.orderTransferRequestBlockedReason ??
                            'Không thể cập nhật mã đơn',
                  onPressed: !editing && transaction.canRequestOrderTransfer
                      ? onRequestTransfer
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                if (canReviewTransfer &&
                    transaction.hasPendingOrderTransferRequest)
                  IconButton(
                    tooltip: 'Phê duyệt cập nhật mã đơn',
                    onPressed: !editing ? onReviewTransfer : null,
                    icon: const Icon(Icons.fact_check_rounded),
                  ),
                IconButton(
                  tooltip: 'Lịch sử chỉnh sửa',
                  onPressed: onHistory,
                  icon: const Icon(Icons.history_rounded),
                ),
                IconButton(
                  tooltip: editing
                      ? 'Lưu mã đơn'
                      : transaction.canEditOrders
                      ? 'Sửa mã đơn'
                      : transaction.orderEditBlockedReason ?? 'Không được sửa',
                  onPressed: editing
                      ? onSave
                      : transaction.canEditOrders
                      ? onEdit
                      : null,
                  icon: Icon(
                    editing ? Icons.check_rounded : Icons.edit_rounded,
                  ),
                ),
                if (editing)
                  IconButton(
                    tooltip: 'Hủy sửa',
                    onPressed: onCancel,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            if (editing)
              AppTextInput(
                controller: controller,
                label: 'Mã đơn hàng',
                hintText: 'Nhập mỗi mã một dòng, hoặc cách bằng dấu phẩy',
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                dense: true,
                minLines: 1,
                maxLines: 3,
              )
            else if (transaction.orders.isEmpty)
              Text(
                bankStatementMissingOrderText,
                style: AppTextStyles.labelM.copyWith(color: AppColors.error),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: transaction.orders
                    .map(
                      (order) =>
                          AppStatusChip(label: order, color: AppColors.success),
                    )
                    .toList(),
              ),
            if (!editing &&
                transaction.hasPendingOrderTransferRequest &&
                transaction.orderTransferRequestedOrders.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  const AppStatusChip(
                    label: 'Chờ Kế toán xác nhận',
                    color: AppColors.warning,
                  ),
                  ...transaction.orderTransferRequestedOrders.map(
                    (order) =>
                        AppStatusChip(label: order, color: AppColors.warning),
                  ),
                ],
              ),
            ],
            if (!editing && blockedReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                blockedReason!,
                style: AppTextStyles.captionBold.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ],
          ],
        ),
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
      if (transaction.statementNumber.isNotEmpty)
        'statementNumber': transaction.statementNumber,
      if (transaction.transactionNumber.isNotEmpty)
        'transactionNumber': transaction.transactionNumber,
      'storeId': transaction.storeId,
      'hasPayerName': transaction.payerName.isNotEmpty,
      'hasPayerAccount': transaction.payerAccount.isNotEmpty,
      'orderCount': transaction.orders.length,
    },
  );
  if (!context.mounted) {
    await AppLogger.instance.warn(
      'PaymentMonitor',
      'Payment transaction details opening cancelled',
      context: {
        if (transaction.statementNumber.isNotEmpty)
          'statementNumber': transaction.statementNumber,
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
        if (transaction.statementNumber.isNotEmpty)
          'statementNumber': transaction.statementNumber,
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
        if (transaction.statementNumber.isNotEmpty)
          'statementNumber': transaction.statementNumber,
        if (transaction.transactionNumber.isNotEmpty)
          'transactionNumber': transaction.transactionNumber,
        'storeId': transaction.storeId,
        'durationMs': stopwatch.elapsedMilliseconds,
      },
    );
    if (context.mounted) {
      AppToast.show(
        context,
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
    final orderUpdatedAt = _toVietnamTime(transaction.orderUpdatedAt);
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
                  label: 'Mã sao kê',
                  value: transaction.statementNumber,
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Đơn hàng',
                  value: statementOrdersText(transaction.orders),
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Nguồn đơn',
                  value: _orderSourceLabel(transaction.orderSource),
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Người cập nhật',
                  value: transaction.orderUpdatedByEmail ?? '',
                  labelWidth: 132,
                ),
                AppInfoRow(
                  label: 'Cập nhật đơn lúc',
                  value: orderUpdatedAt == null
                      ? ''
                      : DateFormat(
                          'HH:mm:ss dd/MM/yyyy',
                        ).format(orderUpdatedAt),
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
        AppDialogCancelButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Đóng',
        ),
      ],
    );
  }
}

String _ordersEditText(List<String> orders) => orders.join('\n');

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

String _orderSourceLabel(String? source) {
  switch (source?.toUpperCase()) {
    case 'AUTO':
      return 'Tự động';
    case 'MANUAL':
      return 'Thủ công';
    case 'OFFSET':
      return 'Cấn trừ';
    default:
      return '';
  }
}
