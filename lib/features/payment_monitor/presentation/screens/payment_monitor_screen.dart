import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/payment_monitor_provider.dart';
import '../widgets/payment_transaction_tile.dart';

class PaymentMonitorScreen extends StatefulWidget {
  const PaymentMonitorScreen({super.key});

  @override
  State<PaymentMonitorScreen> createState() => _PaymentMonitorScreenState();
}

class _PaymentMonitorScreenState extends State<PaymentMonitorScreen> {
  final _storeController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');

  @override
  void dispose() {
    _storeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final monitor = context.watch<PaymentMonitorProvider>();
    final requiresStoreInput = user?.role == 'SUPER_ADMIN';
    final canUsePaymentSpeaker = monitor.canUsePaymentSpeaker;
    final speakerSelectionNotice = monitor.speakerSelectionNotice;

    return Scaffold(
      appBar: const GradientHeader(title: 'Theo dõi tiền vào', showBack: true),
      body: SafeArea(
        child: AppResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (canUsePaymentSpeaker ||
                  speakerSelectionNotice != null ||
                  requiresStoreInput)
                AppSurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canUsePaymentSpeaker) ...[
                        Row(
                          children: [
                            Icon(
                              monitor.isSpeakerEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              color: monitor.isSpeakerEnabled
                                  ? AppColors.success
                                  : AppColors.neutral500,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                monitor.isSpeakerEnabled
                                    ? 'Đang đọc loa khi có tiền vào'
                                    : 'Đã tắt đọc loa',
                                style: AppTextStyles.titleEmphasis,
                              ),
                            ),
                            Switch.adaptive(
                              value: monitor.isSpeakerEnabled,
                              onChanged: monitor.canMonitorOnThisDevice
                                  ? (value) => context
                                        .read<PaymentMonitorProvider>()
                                        .setSpeakerEnabled(value)
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _SyncStatusPill(monitor: monitor),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Giao dịch mới tự cập nhật theo realtime; nếu mất kết nối, máy sẽ tự kiểm tra lại định kỳ.',
                          style: AppTextStyles.bodyS.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (!canUsePaymentSpeaker &&
                          speakerSelectionNotice != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.volume_off_rounded,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Loa tạm dừng',
                                    style: AppTextStyles.titleEmphasis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    speakerSelectionNotice,
                                    style: AppTextStyles.bodyS.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _SyncStatusPill(monitor: monitor),
                        ),
                      ],
                      if (requiresStoreInput) ...[
                        if (canUsePaymentSpeaker ||
                            speakerSelectionNotice != null)
                          const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppTextInput(
                          controller: _storeController,
                          label: 'Mã showroom cần xem',
                          icon: Icons.store_outlined,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _applyStoreOverride(context),
                        ),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        AppSecondaryButton(
                          onPressed: () => _applyStoreOverride(context),
                          icon: Icons.check_rounded,
                          label: 'Xem showroom này',
                        ),
                      ],
                    ],
                  ),
                ),
              if (canUsePaymentSpeaker && monitor.speakerError != null) ...[
                const SizedBox(height: 12),
                _SpeakerErrorCard(
                  error: monitor.speakerError!,
                  amountText:
                      '${_currencyFormatter.format(monitor.speakerError!.amount)} VND',
                  onRestart: () =>
                      context.read<PaymentMonitorProvider>().restartApp(),
                ),
              ],
              if (monitor.errorMessage != null) ...[
                const SizedBox(height: 12),
                _StatusCard(
                  icon: Icons.error_outline_rounded,
                  tone: AppStateTone.error,
                  title: 'Chưa cập nhật được giao dịch',
                  message: monitor.errorMessage!,
                ),
              ],
              const SizedBox(height: 14),
              _TransactionFilters(monitor: monitor, user: user),
              const SizedBox(height: 16),
              Text(
                'Giao dịch tiền vào',
                style: AppTextStyles.labelL.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  children: [
                    if (monitor.isLoading &&
                        monitor.latestTransactions.isNotEmpty) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: AppLayoutTokens.cardGap),
                    ],
                    Expanded(
                      child: monitor.latestTransactions.isEmpty
                          ? monitor.isLoading
                                ? const AppListSkeleton(
                                    itemCount: 5,
                                    showLeading: false,
                                    itemHeight: 92,
                                  )
                                : const _EmptyTransactions()
                          : ListView.builder(
                              itemCount: monitor.latestTransactions.length,
                              itemBuilder: (context, index) {
                                final transaction =
                                    monitor.latestTransactions[index];
                                return PaymentTransactionTile(
                                  transaction: transaction,
                                  amountFormatter: _currencyFormatter,
                                  rowMessage:
                                      monitor.rowMessages[transaction.id],
                                  canReviewTransfer:
                                      monitor.canReviewOrderTransfers,
                                  onSaveOrders: (rawInput) => context
                                      .read<PaymentMonitorProvider>()
                                      .updateOrders(transaction.id, rawInput),
                                  onRequestTransfer: (rawInput) => context
                                      .read<PaymentMonitorProvider>()
                                      .requestOrderTransfer(
                                        transaction.id,
                                        rawInput,
                                      ),
                                  onApproveTransfer: (requestId) => context
                                      .read<PaymentMonitorProvider>()
                                      .approveOrderTransferRequest(
                                        transaction.id,
                                        requestId,
                                      ),
                                  onRejectTransfer: (requestId, {note}) =>
                                      context
                                          .read<PaymentMonitorProvider>()
                                          .rejectOrderTransferRequest(
                                            transaction.id,
                                            requestId,
                                            note: note,
                                          ),
                                  onLoadHistory: () => context
                                      .read<PaymentMonitorProvider>()
                                      .fetchOrderHistory(transaction.id),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyStoreOverride(BuildContext context) {
    context.read<PaymentMonitorProvider>().setStoreOverride(
      _storeController.text,
    );
  }
}

class _SyncStatusPill extends StatelessWidget {
  final PaymentMonitorProvider monitor;

  const _SyncStatusPill({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final color = monitor.isActive ? AppColors.success : AppColors.neutral500;
    final baseLabel = monitor.isLoading
        ? 'Đang cập nhật giao dịch'
        : monitor.isActive
        ? 'Giao dịch tự cập nhật'
        : monitor.hasMonitorScope
        ? 'Đang chuẩn bị cập nhật'
        : 'Chọn showroom để cập nhật';

    final lastCheckedAt = monitor.lastCheckedAt;
    final lastCheckedText = lastCheckedAt == null
        ? 'chưa cập nhật'
        : DateFormat('HH:mm:ss dd/MM/yyyy').format(lastCheckedAt);
    final label = monitor.isActive || monitor.isLoading
        ? '$baseLabel • $lastCheckedText'
        : baseLabel;

    return AppStatusPill(
      icon: Icons.sync_rounded,
      label: label,
      color: color,
      isLoading: monitor.isLoading,
    );
  }
}

class _TransactionFilters extends StatelessWidget {
  final PaymentMonitorProvider monitor;
  final User? user;

  const _TransactionFilters({required this.monitor, required this.user});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;

        if (isMobile) {
          return AppSurfaceCard(
            child: Column(
              children: [
                if (_storeOptions.isNotEmpty) ...[
                  AppMultiSelectFilterDropdown<String>(
                    label: 'SR',
                    values: monitor.selectedStoreIds,
                    options: _storeOptions,
                    emptyLabel: 'SR được gán',
                    onChanged: context
                        .read<PaymentMonitorProvider>()
                        .setSelectedStoreIds,
                  ),
                  const SizedBox(height: 10),
                ],
                AppDateRangeDropdown(
                  label: 'Ngày',
                  start: monitor.rangeStartDate,
                  end: monitor.rangeEndDate,
                  allowEmptyRange: false,
                  onChanged: (start, end) {
                    final nextStart = start ?? monitor.rangeStartDate;
                    final nextEnd = end ?? start ?? monitor.rangeEndDate;
                    context.read<PaymentMonitorProvider>().setDateRange(
                      nextStart,
                      nextEnd,
                    );
                  },
                ),
                const SizedBox(height: 10),
                AppSelectField<int>(
                  label: 'Số dòng hiển thị',
                  value: monitor.pageSize,
                  icon: Icons.format_list_numbered_rounded,
                  dense: true,
                  items: _pageSizeItems,
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<PaymentMonitorProvider>().setPageSize(value);
                  },
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Row(
                  children: [
                    IconButton(
                      onPressed: monitor.canGoPreviousPage
                          ? () => context
                                .read<PaymentMonitorProvider>()
                                .previousPage()
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Trang ${monitor.pageIndex + 1} - ${monitor.totalTransactions} GD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: AppTextStyles.labelM,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: monitor.canGoNextPage
                          ? () => context
                                .read<PaymentMonitorProvider>()
                                .nextPage()
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    IconButton(
                      tooltip: 'Làm mới',
                      onPressed: monitor.isLoading
                          ? null
                          : () => context
                                .read<PaymentMonitorProvider>()
                                .refreshNow(),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return AppSurfaceCard(
          child: Column(
            children: [
              Row(
                children: [
                  if (_storeOptions.isNotEmpty) ...[
                    Expanded(
                      child: AppMultiSelectFilterDropdown<String>(
                        label: 'SR',
                        values: monitor.selectedStoreIds,
                        options: _storeOptions,
                        emptyLabel: 'SR được gán',
                        onChanged: context
                            .read<PaymentMonitorProvider>()
                            .setSelectedStoreIds,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: AppDateRangeDropdown(
                      label: 'Ngày',
                      start: monitor.rangeStartDate,
                      end: monitor.rangeEndDate,
                      allowEmptyRange: false,
                      onChanged: (start, end) {
                        final nextStart = start ?? monitor.rangeStartDate;
                        final nextEnd = end ?? start ?? monitor.rangeEndDate;
                        context.read<PaymentMonitorProvider>().setDateRange(
                          nextStart,
                          nextEnd,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: AppSelectField<int>(
                      label: 'Số dòng',
                      value: monitor.pageSize,
                      dense: true,
                      items: _pageSizeItems,
                      onChanged: (value) {
                        if (value == null) return;
                        context.read<PaymentMonitorProvider>().setPageSize(
                          value,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              Row(
                children: [
                  IconButton(
                    onPressed: monitor.canGoPreviousPage
                        ? () => context
                              .read<PaymentMonitorProvider>()
                              .previousPage()
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Trang ${monitor.pageIndex + 1} - ${monitor.totalTransactions} giao dịch',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: AppTextStyles.labelM,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: monitor.canGoNextPage
                        ? () =>
                              context.read<PaymentMonitorProvider>().nextPage()
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  IconButton(
                    tooltip: 'Làm mới',
                    onPressed: monitor.isLoading
                        ? null
                        : () => context
                              .read<PaymentMonitorProvider>()
                              .refreshNow(),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<DropdownMenuItem<int>> get _pageSizeItems {
    return const [10, 20, 50, 100]
        .map(
          (value) => DropdownMenuItem<int>(
            value: value,
            child: Text(
              '$value dòng',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        )
        .toList(growable: false);
  }

  List<AppFilterOption<String>> get _storeOptions {
    final stores = user?.assignedStores ?? const [];
    return stores
        .where((store) => store.storeId.trim().isNotEmpty)
        .map(
          (store) => AppFilterOption(
            value: store.storeId.trim().toUpperCase(),
            label: store.displayName,
          ),
        )
        .toList(growable: false);
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final AppStateTone tone;
  final String title;
  final String message;

  const _StatusCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusBanner(
      icon: icon,
      title: title,
      message: message,
      tone: tone,
    );
  }
}

class _SpeakerErrorCard extends StatelessWidget {
  final PaymentSpeakerError error;
  final String amountText;
  final VoidCallback onRestart;

  const _SpeakerErrorCard({
    required this.error,
    required this.amountText,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: AppColors.error.withValues(alpha: 0.08),
      borderColor: AppColors.error.withValues(alpha: 0.20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.volume_off_rounded, color: AppColors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loa đọc tiền vào đang lỗi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$amountText - ${error.message}',
                      style: AppTextStyles.bodyM.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: AppSecondaryButton(
                onPressed: onRestart,
                icon: Icons.restart_alt_rounded,
                label: 'Khởi động lại app',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return const AppStatePanel.empty(
      title: 'Chưa có giao dịch trong khoảng ngày đã chọn',
      icon: Icons.receipt_long_outlined,
    );
  }
}
