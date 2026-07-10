import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/repositories/auth_repository.dart';
import '../../../auth/domain/entities/store_branch.dart';
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
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');
  late final AuthRepository _authRepository = AuthRepository(ApiClient());
  List<StoreBranch> _superAdminStores = [];
  String? _storeOptionsSessionKey;
  String? _storeOptionsError;
  bool _isLoadingStoreOptions = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final monitor = context.watch<PaymentMonitorProvider>();
    final requiresStoreInput = user?.role == 'SUPER_ADMIN';
    if (requiresStoreInput) _scheduleSuperAdminStoreLoad(user);
    final storeOptions = _storeOptionsFor(user);
    final canUsePaymentSpeaker = monitor.canUsePaymentSpeaker;
    final speakerSelectionNotice = monitor.speakerSelectionNotice;

    return AppResponsiveContent(
      onRefresh: monitor.refreshNow,
      refreshLogSource: 'PaymentMonitor',
      refreshLogContext: () => {
        'transactionCount': monitor.latestTransactions.length,
        'isLoading': monitor.isLoading,
        'hasMonitorScope': monitor.hasMonitorScope,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (canUsePaymentSpeaker ||
              speakerSelectionNotice != null ||
              requiresStoreInput) ...[
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
                    const _SpeakerPowerWarning(),
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
                    if (canUsePaymentSpeaker || speakerSelectionNotice != null)
                      const SizedBox(height: AppLayoutTokens.formFieldGap),
                    _SuperAdminStoreSelector(
                      monitor: monitor,
                      options: storeOptions,
                      isLoading: _isLoadingStoreOptions,
                      errorMessage: _storeOptionsError,
                      onRetry: () => _reloadSuperAdminStores(user),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
          _TransactionFilters(monitor: monitor, storeOptions: storeOptions),
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
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: monitor.latestTransactions.length,
                          itemBuilder: (context, index) {
                            final transaction =
                                monitor.latestTransactions[index];
                            return PaymentTransactionTile(
                              transaction: transaction,
                              amountFormatter: _currencyFormatter,
                              rowMessage: monitor.rowMessages[transaction.id],
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
                              onRejectTransfer: (requestId, {note}) => context
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
    );
  }

  List<AppComboboxOption<String>> _storeOptionsFor(User? user) {
    final stores = user?.role == 'SUPER_ADMIN'
        ? _superAdminStores
        : user?.assignedStores ?? const <StoreBranch>[];
    return stores
        .where((store) => store.storeId.trim().isNotEmpty)
        .map(
          (store) => AppComboboxOption(
            value: store.storeId.trim().toUpperCase(),
            label: _storeLabel(store),
            subtitle: store.regionAreaLabel,
            searchKeywords: [store.storeId, store.storeName],
          ),
        )
        .toList(growable: false);
  }

  void _scheduleSuperAdminStoreLoad(User? user) {
    final key = user?.id?.trim().isNotEmpty == true
        ? user!.id!.trim()
        : user?.email.trim() ?? 'super-admin';
    if (_storeOptionsSessionKey == key || _isLoadingStoreOptions) return;
    _storeOptionsSessionKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reloadSuperAdminStores(user);
    });
  }

  Future<void> _reloadSuperAdminStores(User? user) async {
    if (user?.role != 'SUPER_ADMIN') return;
    setState(() {
      _isLoadingStoreOptions = true;
      _storeOptionsError = null;
    });
    try {
      final stores = await _authRepository.getStores();
      if (!mounted) return;
      setState(() {
        _superAdminStores = stores;
        _isLoadingStoreOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingStoreOptions = false;
        _storeOptionsError =
            'Chưa tải được danh sách showroom. Vui lòng thử lại.';
      });
    }
  }
}

class _SuperAdminStoreSelector extends StatelessWidget {
  final PaymentMonitorProvider monitor;
  final List<AppComboboxOption<String>> options;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _SuperAdminStoreSelector({
    required this.monitor,
    required this.options,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && options.isEmpty) {
      return const AppStatePanel.loading(
        title: 'Đang tải danh sách showroom',
        message: 'Đang lấy danh sách showroom để chọn nơi theo dõi.',
        compact: true,
      );
    }
    if (errorMessage != null && options.isEmpty) {
      return AppStatePanel.error(
        title: 'Chưa tải được danh sách showroom',
        message: errorMessage,
        actionLabel: 'Thử lại',
        actionIcon: Icons.refresh_rounded,
        onAction: onRetry,
        compact: true,
      );
    }
    if (options.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có showroom khả dụng',
        message: 'Tài khoản này chưa có showroom để theo dõi.',
        compact: true,
      );
    }
    return AppCombobox<String>.single(
      label: 'Showroom cần xem',
      icon: Icons.store_outlined,
      value: monitor.storeOverride,
      options: options,
      emptyLabel: 'Chọn showroom cần xem',
      allowClear: false,
      textCapitalization: TextCapitalization.characters,
      onChanged: (value) {
        if (value == null) return;
        context.read<PaymentMonitorProvider>().setStoreOverride(value);
      },
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

class _SpeakerPowerWarning extends StatelessWidget {
  const _SpeakerPowerWarning();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.warningSurface.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.power_settings_new_rounded,
              size: 18,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Khi cần đọc loa, giữ máy mở màn hình và không để Windows sleep để không bỏ lỡ giao dịch.',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionFilters extends StatelessWidget {
  final PaymentMonitorProvider monitor;
  final List<AppComboboxOption<String>> storeOptions;

  const _TransactionFilters({
    required this.monitor,
    required this.storeOptions,
  });

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
                if (storeOptions.isNotEmpty) ...[
                  AppCombobox<String>.multi(
                    label: 'Showroom',
                    values: monitor.selectedStoreIds,
                    options: storeOptions,
                    emptyLabel: 'Showroom được gán',
                    onMultiChanged: context
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
                AppCombobox<int>.single(
                  label: 'Số dòng hiển thị',
                  value: monitor.pageSize,
                  icon: Icons.format_list_numbered_rounded,
                  dense: true,
                  options: _pageSizeOptions,
                  allowClear: false,
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<PaymentMonitorProvider>().setPageSize(value);
                  },
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                AppPaginationControls(
                  pageIndex: monitor.pageIndex,
                  totalItems: monitor.totalTransactions,
                  itemLabel: 'GD',
                  onPrevious: monitor.canGoPreviousPage
                      ? () => context
                            .read<PaymentMonitorProvider>()
                            .previousPage()
                      : null,
                  onNext: monitor.canGoNextPage
                      ? () => context.read<PaymentMonitorProvider>().nextPage()
                      : null,
                  onRefresh: () =>
                      context.read<PaymentMonitorProvider>().refreshNow(),
                  isRefreshing: monitor.isLoading,
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
                  if (storeOptions.isNotEmpty) ...[
                    Expanded(
                      child: AppCombobox<String>.multi(
                        label: 'Showroom',
                        values: monitor.selectedStoreIds,
                        options: storeOptions,
                        emptyLabel: 'Showroom được gán',
                        onMultiChanged: context
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
                    child: AppCombobox<int>.single(
                      label: 'Số dòng',
                      value: monitor.pageSize,
                      dense: true,
                      options: _pageSizeOptions,
                      allowClear: false,
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
              AppPaginationControls(
                pageIndex: monitor.pageIndex,
                totalItems: monitor.totalTransactions,
                itemLabel: 'giao dịch',
                onPrevious: monitor.canGoPreviousPage
                    ? () =>
                          context.read<PaymentMonitorProvider>().previousPage()
                    : null,
                onNext: monitor.canGoNextPage
                    ? () => context.read<PaymentMonitorProvider>().nextPage()
                    : null,
                onRefresh: () =>
                    context.read<PaymentMonitorProvider>().refreshNow(),
                isRefreshing: monitor.isLoading,
              ),
            ],
          ),
        );
      },
    );
  }

  List<AppComboboxOption<int>> get _pageSizeOptions {
    return const [10, 20, 50, 100]
        .map(
          (value) => AppComboboxOption<int>(value: value, label: '$value dòng'),
        )
        .toList(growable: false);
  }
}

String _storeLabel(StoreBranch store) {
  final code = store.storeId.trim().toUpperCase();
  final name = store.storeName.trim();
  if (name.isEmpty || name.toUpperCase() == code) return code;
  return '$code - $name';
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 130) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Chưa có giao dịch',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelM.copyWith(
                  color: AppColors.neutral500,
                ),
              ),
            ),
          );
        }

        return AppStatePanel.empty(
          title: 'Chưa có giao dịch trong khoảng ngày đã chọn',
          icon: Icons.receipt_long_outlined,
          compact: constraints.maxHeight < 180,
        );
      },
    );
  }
}
