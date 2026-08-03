import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_notification_action.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../bank_statement/domain/bank_statement_transaction.dart';
import '../../../offset_adjustment/domain/offset_adjustment.dart';
import '../providers/app_notifications_provider.dart';

class AppNotificationsBell extends StatelessWidget {
  final bool showLabel;

  const AppNotificationsBell({super.key, this.showLabel = false});

  static Future<bool> showPanel(BuildContext context) async {
    late final AppNotificationsProvider notifications;
    try {
      notifications = context.read<AppNotificationsProvider>();
    } on ProviderNotFoundException {
      return false;
    }
    if (!notifications.isEnabled) return false;

    await notifications.load();
    await notifications.markVisibleNotificationsRead();
    if (!context.mounted) return true;

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (sheetContext) {
          final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.86;
          return ChangeNotifierProvider<AppNotificationsProvider>.value(
            value: notifications,
            child: Consumer<AppNotificationsProvider>(
              builder: (context, provider, child) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight),
                    child: AppNotificationsContent(
                      provider: provider,
                      onClose: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
    return true;
  }

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
      menuChildren: [AppNotificationsContent(provider: notifications)],
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
            label: showLabel ? 'Thông báo' : null,
          ),
        );
      },
    );
  }
}

class AppNotificationsContent extends StatelessWidget {
  final AppNotificationsProvider provider;
  final VoidCallback? onClose;
  final bool fullPage;

  const AppNotificationsContent({
    super.key,
    required this.provider,
    this.onClose,
    this.fullPage = false,
  });

  @override
  Widget build(BuildContext context) {
    if (fullPage) {
      return _FullPageNotificationsInbox(
        provider: provider,
        onReload: _reload,
        onApprove: (request) =>
            _handleReview(context, provider, request, approved: true),
        onReject: (request) =>
            _handleReview(context, provider, request, approved: false),
        onOpenOffsetAdjustments: () => _openOffsetAdjustments(context),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final menuWidth = width < 460 ? width - 24 : 440.0;
    final maxHeight = MediaQuery.sizeOf(context).height - 120;
    final requests = provider.statementOrderRequests;
    final offsets = provider.offsetAdjustmentRequests;
    final hasNotifications = requests.isNotEmpty || offsets.isNotEmpty;
    final notificationList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requests.isNotEmpty) ...[
          if (offsets.isNotEmpty)
            const _NotificationSectionTitle(title: 'Sao kê'),
          for (var index = 0; index < requests.length; index++) ...[
            if (index > 0) const Divider(height: 18),
            _StatementOrderNotificationTile(
              request: requests[index],
              canReview: provider.canReviewStatementOrderTransfers,
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
          const _NotificationSectionTitle(title: 'Cấn trừ'),
          for (var index = 0; index < offsets.length; index++) ...[
            if (index > 0) const Divider(height: 18),
            _OffsetAdjustmentNotificationTile(
              request: offsets[index],
              onOpen: () => _openOffsetAdjustments(context),
            ),
          ],
        ],
      ],
    );
    final body = provider.isLoading && !hasNotifications
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
            child: Center(child: SelectableText('Chưa có thông báo.')),
          )
        : SingleChildScrollView(primary: false, child: notificationList);
    final content = Padding(
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
                  child: Text('Thông báo', style: AppTextStyles.headingS),
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
                if (onClose != null)
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(child: body),
          ],
        ),
      ),
    );
    return SizedBox(
      width: menuWidth,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight.clamp(260.0, 560.0).toDouble(),
        ),
        child: content,
      ),
    );
  }

  Future<void> _reload() async {
    await provider.load();
    await provider.markVisibleNotificationsRead();
  }

  void _openOffsetAdjustments(BuildContext context) {
    final router = GoRouter.of(context);
    final path = GoRouterState.of(context).uri.path;
    MenuController.maybeOf(context)?.close();
    onClose?.call();
    if (path == '/offset-adjustments') return;
    router.push('/offset-adjustments');
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
      AppToast.show(
        context,
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
        builder: (dialogContext) => AppDirtyFormGuard(
          source: 'notifications.reject_request',
          child: AlertDialog(
            title: const Text('Từ chối yêu cầu'),
            content: SelectionArea(
              child: SizedBox(
                width: MediaQuery.of(dialogContext).size.width < 560
                    ? double.maxFinite
                    : 420,
                child: AppTextInput(
                  controller: controller,
                  label: 'Ghi chú cho người gửi (không bắt buộc)',
                  hintText: 'Ví dụ: Mã đơn chưa đúng, vui lòng kiểm tra lại.',
                  maxLines: 4,
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
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _FullPageNotificationsInbox extends StatelessWidget {
  final AppNotificationsProvider provider;
  final Future<void> Function() onReload;
  final Future<void> Function(BankStatementOrderTransferRequest) onApprove;
  final Future<void> Function(BankStatementOrderTransferRequest) onReject;
  final VoidCallback onOpenOffsetAdjustments;

  const _FullPageNotificationsInbox({
    required this.provider,
    required this.onReload,
    required this.onApprove,
    required this.onReject,
    required this.onOpenOffsetAdjustments,
  });

  @override
  Widget build(BuildContext context) {
    final requests = provider.statementOrderRequests;
    final offsets = provider.offsetAdjustmentRequests;
    final hasNotifications = requests.isNotEmpty || offsets.isNotEmpty;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NotificationsInboxHeader(
              isLoading: provider.isLoading,
              onReload: onReload,
            ),
            const SizedBox(height: AppLayoutTokens.cardGap),
            if (provider.isLoading && !hasNotifications)
              const _NotificationListCard(
                child: AppListSkeleton(
                  itemCount: 3,
                  showLeading: false,
                  showTrailing: false,
                  itemHeight: 92,
                  scrollable: false,
                ),
              )
            else if (!hasNotifications)
              const _NotificationListCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: SelectableText('Chưa có thông báo.')),
                ),
              )
            else ...[
              for (final request in requests) ...[
                _FullPageStatementNotificationCard(
                  request: request,
                  canReview: provider.canReviewStatementOrderTransfers,
                  onApprove: () => onApprove(request),
                  onReject: () => onReject(request),
                ),
                const SizedBox(height: AppLayoutTokens.cardGap),
              ],
              for (var index = 0; index < offsets.length; index++) ...[
                _FullPageOffsetNotificationCard(
                  request: offsets[index],
                  onOpen: onOpenOffsetAdjustments,
                ),
                if (index < offsets.length - 1)
                  const SizedBox(height: AppLayoutTokens.cardGap),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationsInboxHeader extends StatelessWidget {
  final bool isLoading;
  final Future<void> Function() onReload;

  const _NotificationsInboxHeader({
    required this.isLoading,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) => _NotificationListCard(
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.infoSurface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text('Thông báo', style: AppTextStyles.labelL)),
        AppIconAction(
          tooltip: 'Tải lại thông báo',
          icon: Icons.refresh_rounded,
          filled: false,
          onPressed: isLoading ? null : onReload,
        ),
      ],
    ),
  );
}

class _NotificationListCard extends StatelessWidget {
  final Widget child;

  const _NotificationListCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
    decoration: BoxDecoration(
      color: AppColors.cardOf(context),
      border: Border.all(color: AppColors.borderOf(context)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: SelectionArea(child: child),
  );
}

class _FullPageStatementNotificationCard extends StatelessWidget {
  final BankStatementOrderTransferRequest request;
  final bool canReview;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const _FullPageStatementNotificationCard({
    required this.request,
    required this.canReview,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final pending = request.status == 'PENDING';
    final rejected = request.status == 'REJECTED';
    final money = NumberFormat.decimalPattern('vi_VN');
    final canAct = canReview && pending;
    final title = rejected
        ? 'Yêu cầu đổi mã đơn bị từ chối'
        : request.status == 'APPROVED'
        ? 'Yêu cầu đổi mã đơn đã xác nhận'
        : canReview
        ? 'Yêu cầu phê duyệt đổi mã đơn'
        : 'Yêu cầu đổi mã đơn đang chờ duyệt';
    final statusLabel = rejected
        ? 'Bị từ chối'
        : request.status == 'APPROVED'
        ? 'Đã xử lý'
        : 'Chờ duyệt';
    final tone = rejected
        ? _NotificationTone.error
        : pending
        ? _NotificationTone.warning
        : _NotificationTone.neutral;
    final detail = [
      if (request.storeCode.isNotEmpty) 'Showroom ${request.storeCode}',
      if (request.statementNumber.isNotEmpty)
        'Mã sao kê ${request.statementNumber}',
      '${money.format(request.amount)} VND',
    ].join(' • ');
    return _NotificationListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIconTile(tone: tone),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.labelM),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(
                        detail,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _NotificationStatus(tone: tone, label: statusLabel),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            'Đơn cũ: ${statementOrdersText(request.oldOrders)} → Đơn đề nghị: ${statementOrdersText(request.requestedOrders)}',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          if (rejected) ...[
            const SizedBox(height: 8),
            SelectableText(
              'Cần làm: Kiểm tra lại mã đơn. Nếu giao dịch còn trong ngày, gửi yêu cầu mới; nếu đã qua 00:00, dùng chức năng Cấn trừ.',
              style: AppTextStyles.bodyM.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
          if (request.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(request.content, style: AppTextStyles.bodyM),
          ],
          if (canAct) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 96,
                  child: AppSecondaryButton(
                    onPressed: onReject,
                    icon: Icons.close_rounded,
                    label: 'Từ chối',
                    expand: false,
                    size: AppButtonSize.medium,
                    foregroundColor: AppColors.textPrimaryOf(context),
                    borderColor: AppColors.borderOf(context),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: AppPrimaryButton(
                    onPressed: onApprove,
                    icon: Icons.check_rounded,
                    label: 'Xác nhận',
                    size: AppButtonSize.medium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FullPageOffsetNotificationCard extends StatelessWidget {
  final OffsetAdjustment request;
  final VoidCallback onOpen;

  const _FullPageOffsetNotificationCard({
    required this.request,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final rejected = request.status == OffsetAdjustmentStatus.rejected;
    final money = NumberFormat.decimalPattern('vi_VN');
    final detail = [
      if (request.storeCode.isNotEmpty) 'Showroom ${request.storeCode}',
      OffsetAdjustmentType.label(request.type),
      '${money.format(request.amount)} VND',
    ].join(' • ');
    return Semantics(
      button: true,
      label: 'Mở hồ sơ cấn trừ',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: _NotificationListCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIconTile(
                tone: rejected
                    ? _NotificationTone.error
                    : _NotificationTone.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rejected
                          ? 'Hồ sơ cấn trừ bị từ chối'
                          : request.primaryOrderLabel.isEmpty
                          ? OffsetAdjustmentType.label(request.type)
                          : request.primaryOrderLabel,
                      style: AppTextStyles.labelM,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      detail,
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    if (rejected) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        'Cần làm: Mở Cấn trừ để sửa và gửi lại.',
                        style: AppTextStyles.bodyM.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _NotificationStatus(
                tone: rejected
                    ? _NotificationTone.error
                    : _NotificationTone.warning,
                label: rejected ? 'Bị từ chối' : 'Chờ xử lý',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NotificationTone { neutral, warning, error }

class _NotificationIconTile extends StatelessWidget {
  final _NotificationTone tone;

  const _NotificationIconTile({required this.tone});

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _NotificationTone.error => AppColors.errorSurface,
      _NotificationTone.warning => AppColors.warningSurface,
      _NotificationTone.neutral => AppColors.infoSurface,
    };
    final iconColor = switch (tone) {
      _NotificationTone.error => AppColors.error,
      _NotificationTone.warning => AppColors.warning,
      _NotificationTone.neutral => AppColors.info,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.swap_horiz_rounded, color: iconColor, size: 22),
    );
  }
}

class _NotificationStatus extends StatelessWidget {
  final _NotificationTone tone;
  final String label;

  const _NotificationStatus({required this.tone, required this.label});

  @override
  Widget build(BuildContext context) {
    final background = switch (tone) {
      _NotificationTone.error => AppColors.errorSurface,
      _NotificationTone.warning => AppColors.warningSurface,
      _NotificationTone.neutral => AppColors.chipBackground,
    };
    final foreground = switch (tone) {
      _NotificationTone.error => AppColors.error,
      _NotificationTone.warning => AppColors.warning,
      _NotificationTone.neutral => AppColors.textSecondaryOf(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelS.copyWith(color: foreground),
      ),
    );
  }
}

class _NotificationSectionTitle extends StatelessWidget {
  final String title;

  const _NotificationSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(title, style: AppTextStyles.labelL),
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
        style: AppTextStyles.labelM,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            [
              if (request.storeCode.isNotEmpty) 'Showroom ${request.storeCode}',
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
      title: SelectableText(_title, style: AppTextStyles.labelM),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              [
                if (request.storeCode.isNotEmpty)
                  'Showroom ${request.storeCode}',
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
