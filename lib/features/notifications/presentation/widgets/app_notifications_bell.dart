import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_notification_action.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../../../offset_adjustment/domain/offset_adjustment.dart';
import '../providers/app_notifications_provider.dart';

class AppNotificationsBell extends StatelessWidget {
  const AppNotificationsBell({super.key});

  @override
  Widget build(BuildContext context) {
    late final AppNotificationsProvider notifications;
    try {
      notifications = context.watch<AppNotificationsProvider>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!notifications.isEnabled) return const SizedBox.shrink();
    return MenuAnchor(
      menuChildren: [_NotificationsMenu(provider: notifications)],
      builder: (context, controller, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AppNotificationIconButton(
            count: notifications.count,
            tooltip: notifications.count > 0
                ? '${notifications.count} thông báo mới'
                : 'Thông báo',
            onPressed: () async {
              if (controller.isOpen) {
                controller.close();
                return;
              }
              controller.open();
              await notifications.load();
              await notifications.markVisibleNotificationsRead();
            },
          ),
        );
      },
    );
  }
}

class _NotificationsMenu extends StatelessWidget {
  final AppNotificationsProvider provider;

  const _NotificationsMenu({required this.provider});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final menuWidth = width < 460 ? width - 24 : 440.0;
    final maxHeight = MediaQuery.sizeOf(context).height - 120;
    final requests = provider.statementOrderRequests;
    final offsets = provider.offsetAdjustmentRequests;
    final hasNotifications = requests.isNotEmpty || offsets.isNotEmpty;
    return SizedBox(
      width: menuWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(260.0, 560.0).toDouble(),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
          child: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.primary500,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thông báo',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tải lại',
                      onPressed: provider.isLoading
                          ? null
                          : () async {
                              await provider.load();
                              await provider.markVisibleNotificationsRead();
                            },
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: provider.isLoading && !hasNotifications
                      ? const AppListSkeleton(
                          itemCount: 3,
                          showLeading: false,
                          showTrailing: false,
                          itemHeight: 74,
                          scrollable: false,
                        )
                      : !hasNotifications
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SelectableText('Chưa có thông báo.'),
                          ),
                        )
                      : SingleChildScrollView(
                          primary: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (requests.isNotEmpty) ...[
                                if (offsets.isNotEmpty)
                                  const _NotificationSectionTitle(
                                    title: 'Sao kê',
                                  ),
                                for (
                                  var index = 0;
                                  index < requests.length;
                                  index++
                                ) ...[
                                  if (index > 0) const Divider(height: 18),
                                  _StatementOrderNotificationTile(
                                    request: requests[index],
                                    canReview: provider
                                        .canReviewStatementOrderTransfers,
                                    onApprove: () => _handleReview(
                                      context,
                                      provider,
                                      requests[index],
                                      approved: true,
                                    ),
                                    onReject: () => _handleReview(
                                      context,
                                      provider,
                                      requests[index],
                                      approved: false,
                                    ),
                                  ),
                                ],
                              ],
                              if (requests.isNotEmpty && offsets.isNotEmpty)
                                const Divider(height: 18),
                              if (offsets.isNotEmpty) ...[
                                const _NotificationSectionTitle(
                                  title: 'Cấn trừ',
                                ),
                                for (
                                  var index = 0;
                                  index < offsets.length;
                                  index++
                                ) ...[
                                  if (index > 0) const Divider(height: 18),
                                  _OffsetAdjustmentNotificationTile(
                                    request: offsets[index],
                                    onOpen: () =>
                                        _openOffsetAdjustments(context),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openOffsetAdjustments(BuildContext context) {
    MenuController.maybeOf(context)?.close();
    if (GoRouterState.of(context).uri.path == '/offset-adjustments') return;
    context.push('/offset-adjustments');
  }

  Future<void> _handleReview(
    BuildContext context,
    AppNotificationsProvider provider,
    BankStatementOrderTransferRequest request, {
    required bool approved,
  }) async {
    final note = approved ? null : await _showRejectNoteDialog(context);
    if (!approved && note == null) return;
    try {
      if (approved) {
        await provider.approveStatementOrderTransfer(request.id);
      } else {
        await provider.rejectStatementOrderTransfer(request.id, note: note);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approved
                ? 'Chưa xác nhận được yêu cầu.'
                : 'Chưa từ chối được yêu cầu.',
          ),
        ),
      );
    }
  }

  Future<String?> _showRejectNoteDialog(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return showDialog<String?>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Từ chối yêu cầu'),
          content: SelectionArea(
            child: SizedBox(
              width: MediaQuery.of(dialogContext).size.width < 560
                  ? double.maxFinite
                  : 420,
              child: TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú cho người gửi (không bắt buộc)',
                  hintText: 'Ví dụ: Mã đơn chưa đúng, vui lòng kiểm tra lại.',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
            ),
            AppDialogConfirmButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              icon: Icons.close_rounded,
              label: 'Từ chối',
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _NotificationSectionTitle extends StatelessWidget {
  final String title;

  const _NotificationSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _OffsetAdjustmentNotificationTile extends StatelessWidget {
  final OffsetAdjustment request;
  final VoidCallback onOpen;

  const _OffsetAdjustmentNotificationTile({
    required this.request,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.decimalPattern('vi_VN');
    final rejected = request.status == OffsetAdjustmentStatus.rejected;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        rejected ? Icons.error_outline_rounded : _offsetTypeIcon(request.type),
        color: rejected ? AppColors.error : AppColors.warning,
      ),
      title: SelectableText(
        rejected
            ? 'Hồ sơ cấn trừ bị từ chối'
            : request.primaryOrderLabel.isEmpty
            ? OffsetAdjustmentType.label(request.type)
            : request.primaryOrderLabel,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            [
              if (request.storeCode.isNotEmpty) 'SR ${request.storeCode}',
              OffsetAdjustmentType.label(request.type),
              '${money.format(request.amount)} VND',
              if (_submittedTimeText.isNotEmpty) _submittedTimeText,
            ].join(' • '),
          ),
          if (request.primaryOrderLabel.isNotEmpty)
            SelectableText('Đơn hàng: ${request.primaryOrderLabel}'),
          if (rejected) ...[
            const SizedBox(height: 4),
            SelectableText('Lý do: ${_rejectReasonText(request)}'),
            const SelectableText('Cần làm: Mở Cấn trừ để sửa và gửi lại.'),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onOpen,
    );
  }

  String get _submittedTimeText {
    final time = request.submittedAt;
    return time == null
        ? ''
        : DateFormat('HH:mm:ss dd/MM/yyyy').format(time.toLocal());
  }

  String _rejectReasonText(OffsetAdjustment request) {
    final reason = request.rejectReason?.trim() ?? '';
    return reason.isEmpty ? 'Kế toán chưa nhập lý do cụ thể.' : reason;
  }
}

class _StatementOrderNotificationTile extends StatelessWidget {
  final BankStatementOrderTransferRequest request;
  final bool canReview;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const _StatementOrderNotificationTile({
    required this.request,
    required this.canReview,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.decimalPattern('vi_VN');
    final pending = request.status == 'PENDING';
    final rejected = request.status == 'REJECTED';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        rejected ? Icons.error_outline_rounded : Icons.swap_horiz_rounded,
        color: rejected ? AppColors.error : AppColors.warning,
      ),
      title: SelectableText(
        _title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              [
                if (request.storeCode.isNotEmpty) 'SR ${request.storeCode}',
                if (request.statementNumber.isNotEmpty)
                  'Mã sao kê ${request.statementNumber}',
                '${money.format(request.amount)} VND',
              ].join(' • '),
            ),
            SelectableText('Đơn cũ: ${_ordersText(request.oldOrders)}'),
            SelectableText(
              'Đơn đề nghị: ${_ordersText(request.requestedOrders)}',
            ),
            if (_transactionTimeText.isNotEmpty)
              SelectableText('Thời gian giao dịch: $_transactionTimeText'),
            if (_requestTimeText.isNotEmpty)
              SelectableText('Thời gian yêu cầu: $_requestTimeText'),
            if ((request.requestedByEmail ?? '').isNotEmpty)
              SelectableText('Người gửi: ${request.requestedByEmail}'),
            if (rejected) ...[
              const SizedBox(height: 6),
              SelectableText('Lý do: ${_rejectReasonText(request)}'),
              const SelectableText(
                'Cần làm: Kiểm tra lại mã đơn. Nếu giao dịch còn trong ngày, gửi yêu cầu mới; nếu đã qua 00:00, dùng chức năng Cấn trừ.',
              ),
            ],
            if (request.content.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(request.content),
            ],
            if (canReview && pending) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppDialogSecondaryButton(
                    onPressed: onReject,
                    icon: Icons.close_rounded,
                    label: 'Từ chối',
                  ),
                  AppDialogConfirmButton(
                    onPressed: onApprove,
                    icon: Icons.check_rounded,
                    label: 'Xác nhận',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String get _title {
    if (request.status == 'REJECTED') return 'Yêu cầu đổi mã đơn bị từ chối';
    if (request.status == 'APPROVED') return 'Yêu cầu đổi mã đơn đã xác nhận';
    if (canReview) return 'Yêu cầu phê duyệt đổi mã đơn';
    return 'Yêu cầu đổi mã đơn đang chờ duyệt';
  }

  String get _transactionTimeText {
    final time = request.paidAt ?? request.firstSeenAt;
    return time == null
        ? ''
        : DateFormat('HH:mm:ss dd/MM/yyyy').format(time.toLocal());
  }

  String get _requestTimeText {
    final time = request.createdAt;
    return time == null
        ? ''
        : DateFormat('HH:mm:ss dd/MM/yyyy').format(time.toLocal());
  }

  String _ordersText(List<String> orders) => statementOrdersText(orders);

  String _rejectReasonText(BankStatementOrderTransferRequest request) {
    final note = request.reviewNote?.trim() ?? '';
    return note.isEmpty ? 'Kế toán chưa nhập lý do cụ thể.' : note;
  }
}

IconData _offsetTypeIcon(String type) {
  return switch (type) {
    OffsetAdjustmentType.singleOrder => Icons.swap_calls_rounded,
    OffsetAdjustmentType.vnpayQroff => Icons.qr_code_2_rounded,
    OffsetAdjustmentType.zaloPay => Icons.account_balance_wallet_outlined,
    OffsetAdjustmentType.shopeePay => Icons.shopping_bag_outlined,
    _ => Icons.dataset_outlined,
  };
}
