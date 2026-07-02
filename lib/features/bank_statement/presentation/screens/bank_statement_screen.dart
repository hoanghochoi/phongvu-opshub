import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../notifications/presentation/providers/app_notifications_provider.dart';
import '../../domain/bank_statement_transaction.dart';
import '../providers/bank_statement_provider.dart';
import '../widgets/bank_statement_transaction_details.dart';

const double _localBreakpoint = 800;
const double _filterGap = AppLayoutTokens.formInlineGap;
const List<DropdownMenuItem<String>> _orderStatusItems = [
  DropdownMenuItem(value: 'ALL', child: Text('Tất cả giao dịch')),
  DropdownMenuItem(value: 'HAS_ORDER', child: Text('Đã có đơn hàng')),
  DropdownMenuItem(value: 'MISSING_ORDER', child: Text('Chưa có đơn hàng')),
  DropdownMenuItem(value: 'OFFSET_CONFIRMED', child: Text('Giao dịch cấn trừ')),
  DropdownMenuItem(value: 'OFFSET_PENDING', child: Text('Chờ xác nhận')),
];

String _formatStatementDateTime(DateTime? value) {
  if (value == null) return 'Không rõ';
  return DateFormat('HH:mm:ss dd/MM/yyyy').format(value.toLocal());
}

class BankStatementScreen extends StatefulWidget {
  const BankStatementScreen({super.key});

  @override
  State<BankStatementScreen> createState() => _BankStatementScreenState();
}

class _BankStatementScreenState extends State<BankStatementScreen> {
  final _statementNumberController = TextEditingController();
  final _orderController = TextEditingController();
  final _amountController = TextEditingController();
  final _contentController = TextEditingController();
  final _statementNumberFocus = FocusNode();
  final _orderFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _contentFocus = FocusNode();
  final _money = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      context.read<BankStatementProvider>().initialize(user);
    });
  }

  @override
  void dispose() {
    _statementNumberController.dispose();
    _orderController.dispose();
    _amountController.dispose();
    _contentController.dispose();
    _statementNumberFocus.dispose();
    _orderFocus.dispose();
    _amountFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankStatementProvider>();
    _syncControllers(provider);

    return SelectionArea(
      child: AppResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatementHeader(provider: provider),
            const SizedBox(height: AppLayoutTokens.sectionGap),
            _FilterPanel(
              provider: provider,
              statementNumberController: _statementNumberController,
              orderController: _orderController,
              amountController: _amountController,
              contentController: _contentController,
              statementNumberFocus: _statementNumberFocus,
              orderFocus: _orderFocus,
              amountFocus: _amountFocus,
              contentFocus: _contentFocus,
            ),
            if (provider.errorMessage != null) ...[
              const SizedBox(height: 10),
              AppStatusBanner(
                icon: Icons.error_outline_rounded,
                title: 'Chưa tải được sao kê',
                message: provider.errorMessage!,
                tone: AppStateTone.error,
              ),
            ],
            if (provider.exportMessage != null) ...[
              const SizedBox(height: 10),
              AppStatusBanner(
                icon: Icons.download_done_rounded,
                title: 'Xuất file',
                message: provider.exportMessage!,
                tone: AppStateTone.info,
              ),
            ],
            const SizedBox(height: 12),
            AppSurfaceCard(
              key: const Key('bank-statement-toolbar'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _StatementToolbar(provider: provider),
            ),
            if (provider.isLoading && provider.transactions.isNotEmpty) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 10),
            Expanded(child: _buildList(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BankStatementProvider provider) {
    if (provider.isLoading && provider.transactions.isEmpty) {
      return const AppListSkeleton(
        itemCount: 5,
        showLeading: false,
        itemHeight: 124,
      );
    }
    if (!provider.hasSearched) {
      return const AppStatePanel.empty(
        title: 'Chọn filter rồi bấm Tìm để tải giao dịch',
        icon: Icons.manage_search_rounded,
      );
    }
    if (provider.transactions.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Không có giao dịch khớp filter',
        icon: Icons.receipt_long_outlined,
      );
    }
    return ListView.builder(
      itemCount: provider.transactions.length,
      itemBuilder: (context, index) {
        return _StatementCard(
          transaction: provider.transactions[index],
          money: _money,
        );
      },
    );
  }

  void _syncControllers(BankStatementProvider provider) {
    void sync(TextEditingController controller, FocusNode focus, String value) {
      if (!focus.hasFocus && controller.text != value) {
        controller.text = value;
      }
    }

    sync(
      _statementNumberController,
      _statementNumberFocus,
      provider.statementNumber ?? '',
    );
    sync(_orderController, _orderFocus, provider.order ?? '');
    String formattedAmount = '';
    if (provider.amount != null) {
      final parsed = int.tryParse(
        provider.amount!.replaceAll(RegExp(r'[^0-9]'), ''),
      );
      if (parsed != null) {
        formattedAmount = NumberFormat.decimalPattern('vi_VN').format(parsed);
      }
    }
    sync(_amountController, _amountFocus, formattedAmount);
    sync(_contentController, _contentFocus, provider.content ?? '');
  }
}

class _StatementHeader extends StatelessWidget {
  final BankStatementProvider provider;

  const _StatementHeader({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scopeLabel = provider.allStores
        ? 'Tất cả SR'
        : provider.selectedStoreIds.isNotEmpty
        ? '${provider.selectedStoreIds.length} SR'
        : 'SR được gán';
    final filterLabel = provider.canSearch
        ? 'Sẵn sàng tìm'
        : 'Chọn 1 filter chính';
    final pendingCount = provider.pendingOrderTransferUnreadCount;

    return AppSurfaceCard(
      key: const Key('bank-statement-header'),
      backgroundColor: AppColors.infoSurface,
      borderColor: AppColors.info.withValues(alpha: 0.24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.tabletBreakpoint;
          final icon = Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: AppColors.info,
            ),
          );
          final textBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sao kê', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                'Tra cứu giao dịch VietinBank theo SR, mã sao kê, đơn hàng, số tiền hoặc nội dung chuyển khoản.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.neutral600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: AppLayoutTokens.cardGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(
                    label: scopeLabel,
                    color: AppColors.info,
                    backgroundColor: AppColors.infoSurface,
                  ),
                  AppStatusChip(
                    label: '${provider.total} giao dịch',
                    color: AppColors.neutral700,
                    backgroundColor: AppColors.neutral100,
                  ),
                  AppStatusChip(
                    label: '${provider.selectedIds.length} đã chọn',
                    color: AppColors.success,
                    backgroundColor: AppColors.successSurface,
                  ),
                  AppStatusChip(
                    label: pendingCount > 0
                        ? '$pendingCount chờ Kế toán'
                        : 'Không có yêu cầu mới',
                    color: pendingCount > 0
                        ? AppColors.warning
                        : AppColors.neutral700,
                    backgroundColor: pendingCount > 0
                        ? AppColors.warningSurface
                        : AppColors.neutral100,
                  ),
                  AppStatusChip(
                    label: filterLabel,
                    color: provider.canSearch
                        ? AppColors.primary
                        : AppColors.warning,
                    backgroundColor: provider.canSearch
                        ? AppColors.primarySurface
                        : AppColors.warningSurface,
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [icon, const SizedBox(height: 14), textBlock],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              icon,
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              Expanded(child: textBlock),
            ],
          );
        },
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  final BankStatementProvider provider;
  final TextEditingController statementNumberController;
  final TextEditingController orderController;
  final TextEditingController amountController;
  final TextEditingController contentController;
  final FocusNode statementNumberFocus;
  final FocusNode orderFocus;
  final FocusNode amountFocus;
  final FocusNode contentFocus;

  const _FilterPanel({
    required this.provider,
    required this.statementNumberController,
    required this.orderController,
    required this.amountController,
    required this.contentController,
    required this.statementNumberFocus,
    required this.orderFocus,
    required this.amountFocus,
    required this.contentFocus,
  });

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _localBreakpoint;

        if (isMobile) {
          return AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  borderRadius: BorderRadius.circular(
                    AppLayoutTokens.cardRadius,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 2,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_alt_outlined),
                        const SizedBox(width: 8),
                        Text('Bộ lọc tìm kiếm', style: AppTextStyles.labelM),
                        const Spacer(),
                        Icon(
                          _isExpanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isExpanded) ...[
                  const Divider(height: 16),
                  _StoreFilterButton(provider: widget.provider),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.statementNumberController,
                    focusNode: widget.statementNumberFocus,
                    label: 'Mã sao kê',
                    icon: Icons.receipt_long_outlined,
                    onChanged: widget.provider.setStatementNumber,
                    onSubmitted: (_) => widget.provider.search(),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.orderController,
                    focusNode: widget.orderFocus,
                    label: 'Mã đơn hàng',
                    icon: Icons.tag_rounded,
                    onChanged: widget.provider.setOrder,
                    onSubmitted: (_) => widget.provider.search(),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.amountController,
                    focusNode: widget.amountFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    label: 'Số tiền',
                    icon: Icons.payments_outlined,
                    onChanged: widget.provider.setAmount,
                    onSubmitted: (_) => widget.provider.search(),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.contentController,
                    focusNode: widget.contentFocus,
                    label: 'Nội dung chuyển khoản',
                    icon: Icons.notes_rounded,
                    onChanged: widget.provider.setContent,
                    onSubmitted: (_) => widget.provider.search(),
                  ),
                  const SizedBox(height: _filterGap),
                  AppSelectField<String>(
                    value: widget.provider.orderStatus,
                    label: 'Trạng thái',
                    icon: Icons.flag_outlined,
                    items: _orderStatusItems,
                    onChanged: (value) {
                      if (value != null) {
                        widget.provider.setOrderStatus(value);
                      }
                    },
                  ),
                  const SizedBox(height: _filterGap),
                  _DateRangeButton(
                    startDate: widget.provider.startDate,
                    endDate: widget.provider.endDate,
                    onChanged: widget.provider.setDateRange,
                  ),
                  const SizedBox(height: _filterGap),
                  _LimitDropdown(provider: widget.provider),
                  const SizedBox(height: _filterGap),
                  _FilterActionButtons(provider: widget.provider),
                ],
              ],
            ),
          );
        }

        return AppSurfaceCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StoreFilterButton(provider: widget.provider),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppTextInput(
                      controller: widget.statementNumberController,
                      focusNode: widget.statementNumberFocus,
                      label: 'Mã sao kê',
                      icon: Icons.receipt_long_outlined,
                      onChanged: widget.provider.setStatementNumber,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppTextInput(
                      controller: widget.orderController,
                      focusNode: widget.orderFocus,
                      label: 'Mã đơn hàng',
                      icon: Icons.tag_rounded,
                      onChanged: widget.provider.setOrder,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppTextInput(
                      controller: widget.amountController,
                      focusNode: widget.amountFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      label: 'Số tiền',
                      icon: Icons.payments_outlined,
                      onChanged: widget.provider.setAmount,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _filterGap),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: AppTextInput(
                      controller: widget.contentController,
                      focusNode: widget.contentFocus,
                      label: 'Nội dung chuyển khoản',
                      icon: Icons.notes_rounded,
                      onChanged: widget.provider.setContent,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppSelectField<String>(
                      value: widget.provider.orderStatus,
                      label: 'Trạng thái',
                      icon: Icons.flag_outlined,
                      items: _orderStatusItems,
                      onChanged: (value) {
                        if (value != null) {
                          widget.provider.setOrderStatus(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _filterGap),
              Row(
                children: [
                  Expanded(
                    child: _DateRangeButton(
                      startDate: widget.provider.startDate,
                      endDate: widget.provider.endDate,
                      onChanged: widget.provider.setDateRange,
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  SizedBox(
                    width: 150,
                    child: _LimitDropdown(provider: widget.provider),
                  ),
                  const SizedBox(width: _filterGap),
                  SizedBox(
                    width: 320,
                    child: _FilterActionButtons(provider: widget.provider),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StoreFilterButton extends StatelessWidget {
  static const _allStoresValue = '__ALL_STORES__';
  final BankStatementProvider provider;

  const _StoreFilterButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final options = [
      if (provider.canUseAllStores)
        const AppFilterOption<String>(
          value: _allStoresValue,
          label: 'Tất cả SR',
        ),
      ...provider.stores.map(
        (store) => AppFilterOption<String>(
          value: store.storeId,
          label: store.displayName,
        ),
      ),
    ];
    final values = provider.allStores
        ? {_allStoresValue}
        : provider.selectedStoreIds;
    return AppMultiSelectFilterDropdown<String>(
      label: 'SR',
      values: values,
      options: options,
      emptyLabel: 'SR được gán',
      icon: Icons.store_outlined,
      onChanged: (selected) {
        if (selected.contains(_allStoresValue)) {
          provider.setStoreSelection(allStores: true, ids: const {});
          return;
        }
        provider.setStoreSelection(allStores: false, ids: selected);
      },
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime? start, DateTime? end) onChanged;

  const _DateRangeButton({
    required this.startDate,
    required this.endDate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppDateRangeDropdown(
      label: 'Ngày',
      start: startDate,
      end: endDate,
      onChanged: onChanged,
    );
  }
}

class _LimitDropdown extends StatelessWidget {
  final BankStatementProvider provider;

  const _LimitDropdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppSelectField<int>(
      value: provider.limit,
      label: 'Số dòng',
      icon: Icons.format_list_numbered_rounded,
      items: const [10, 20, 50, 100]
          .map(
            (value) =>
                DropdownMenuItem(value: value, child: Text('$value dòng')),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) provider.setLimit(value);
      },
    );
  }
}

class _FilterActionButtons extends StatelessWidget {
  final BankStatementProvider provider;

  const _FilterActionButtons({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppPrimaryButton(
            onPressed: provider.canSearch ? provider.search : null,
            icon: Icons.search_rounded,
            label: 'Tìm',
            isLoading: provider.isLoading,
          ),
        ),
        const SizedBox(width: _filterGap),
        Expanded(child: _ExportButton(provider: provider)),
      ],
    );
  }
}

class _StatementToolbar extends StatelessWidget {
  final BankStatementProvider provider;

  const _StatementToolbar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _localBreakpoint;

        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Checkbox(
                    value: provider.allVisibleSelected,
                    onChanged: provider.transactions.isEmpty
                        ? null
                        : (value) => provider.toggleAllVisible(value == true),
                  ),
                  Expanded(
                    child: Text(
                      '${provider.selectedIds.length} chọn / ${provider.total} giao dịch',
                      style: AppTextStyles.labelM,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Trang trước',
                    onPressed: provider.canGoPrevious
                        ? provider.previousPage
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 8),
                  Text('Trang ${provider.page + 1}'),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Trang sau',
                    onPressed: provider.canGoNext ? provider.nextPage : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Checkbox(
              value: provider.allVisibleSelected,
              onChanged: provider.transactions.isEmpty
                  ? null
                  : (value) => provider.toggleAllVisible(value == true),
            ),
            Text(
              '${provider.selectedIds.length} chọn / ${provider.total} giao dịch',
              style: AppTextStyles.labelM,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Trang trước',
              onPressed: provider.canGoPrevious ? provider.previousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('Trang ${provider.page + 1}'),
            IconButton(
              tooltip: 'Trang sau',
              onPressed: provider.canGoNext ? provider.nextPage : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        );
      },
    );
  }
}

class _ExportButton extends StatelessWidget {
  final BankStatementProvider provider;

  const _ExportButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppSecondaryButton(
      onPressed: provider.canSearch && !provider.isExporting
          ? () => _handleExport(context)
          : null,
      icon: Icons.download_rounded,
      label: _exportLabel,
    );
  }

  String get _exportLabel {
    if (provider.isExporting) return 'Đang xuất';
    return provider.selectedIds.isEmpty ? 'Xuất file' : 'Xuất đã chọn';
  }

  Future<void> _handleExport(BuildContext context) async {
    if (provider.hasExportDateRangeLimitViolation) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Không thể xuất file'),
          content: Text(provider.exportDateRangeLimitMessage),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'Đã hiểu',
            ),
          ],
        ),
      );
      return;
    }
    await provider.exportCsv();
  }
}

class _StatementCard extends StatefulWidget {
  final BankStatementTransaction transaction;
  final NumberFormat money;

  const _StatementCard({required this.transaction, required this.money});

  @override
  State<_StatementCard> createState() => _StatementCardState();
}

class _StatementCardState extends State<_StatementCard> {
  late final TextEditingController _controller;
  bool _editing = false;

  String _ordersEditText(List<String> orders) => orders.join('\n');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _ordersEditText(widget.transaction.orders),
    );
  }

  @override
  void didUpdateWidget(covariant _StatementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing &&
        oldWidget.transaction.orders != widget.transaction.orders) {
      _controller.text = _ordersEditText(widget.transaction.orders);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _reloadGlobalNotifications() async {
    if (!mounted) return;
    try {
      await context.read<AppNotificationsProvider>().load(silent: true);
    } on ProviderNotFoundException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankStatementProvider>();
    final tx = widget.transaction;
    final borderColor = tx.hasPendingOrderTransferRequest
        ? AppColors.warning
        : tx.hasOrders
        ? AppColors.success
        : AppColors.error;
    final message = provider.rowMessage(tx.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _localBreakpoint;

        if (isMobile) {
          return AppSurfaceCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            borderColor: borderColor.withValues(alpha: 0.65),
            borderWidth: 1.3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: provider.selectedIds.contains(tx.id),
                      onChanged: (value) =>
                          provider.toggleSelected(tx.id, value == true),
                    ),
                    Expanded(
                      child: BankStatementTransactionDetailsLauncher(
                        transaction: tx,
                        amountFormatter: widget.money,
                        child: _TransactionDetails(tx: tx, money: widget.money),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _OrderEditor(
                  transaction: tx,
                  controller: _controller,
                  editing: _editing,
                  canReviewTransfer: provider.canReviewOrderTransfers,
                  onEdit: () => setState(() => _editing = true),
                  onCancel: () {
                    _controller.text = _ordersEditText(tx.orders);
                    setState(() => _editing = false);
                  },
                  onSave: () async {
                    await provider.updateOrders(tx.id, _controller.text);
                    if (mounted) setState(() => _editing = false);
                  },
                  onRequestTransfer: () =>
                      _showOrderTransferRequestDialog(context, provider, tx),
                  onReviewTransfer: () =>
                      _showOrderTransferReviewDialog(context, provider, tx),
                  onHistory: () => _showHistory(context, provider, tx),
                ),
                AnimatedOpacity(
                  opacity: message == null ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  child: message == null
                      ? const SizedBox(height: 0)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8, left: 10),
                          child: Text(
                            message.text,
                            style: AppTextStyles.labelS.copyWith(
                              color: message.success
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        return AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          borderColor: borderColor.withValues(alpha: 0.65),
          borderWidth: 1.3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: provider.selectedIds.contains(tx.id),
                onChanged: (value) =>
                    provider.toggleSelected(tx.id, value == true),
              ),
              Expanded(
                child: BankStatementTransactionDetailsLauncher(
                  transaction: tx,
                  amountFormatter: widget.money,
                  child: _TransactionDetails(tx: tx, money: widget.money),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _OrderEditor(
                      transaction: tx,
                      controller: _controller,
                      editing: _editing,
                      canReviewTransfer: provider.canReviewOrderTransfers,
                      onEdit: () => setState(() => _editing = true),
                      onCancel: () {
                        _controller.text = _ordersEditText(tx.orders);
                        setState(() => _editing = false);
                      },
                      onSave: () async {
                        await provider.updateOrders(tx.id, _controller.text);
                        if (mounted) setState(() => _editing = false);
                      },
                      onRequestTransfer: () => _showOrderTransferRequestDialog(
                        context,
                        provider,
                        tx,
                      ),
                      onReviewTransfer: () =>
                          _showOrderTransferReviewDialog(context, provider, tx),
                      onHistory: () => _showHistory(context, provider, tx),
                    ),
                    AnimatedOpacity(
                      opacity: message == null ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: message == null
                          ? const SizedBox(height: 26)
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                message.text,
                                style: AppTextStyles.labelS.copyWith(
                                  color: message.success
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showHistory(
    BuildContext context,
    BankStatementProvider provider,
    BankStatementTransaction transaction,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final isSmallScreen = MediaQuery.of(context).size.width < 560;
        final statementNumber = transaction.statementNumber;
        return AlertDialog(
          title: Text(
            statementNumber.isEmpty
                ? 'Lịch sử sao kê'
                : 'Lịch sử sao kê $statementNumber',
          ),
          content: SizedBox(
            width: isSmallScreen ? double.maxFinite : 520,
            child: FutureBuilder<List<BankStatementOrderHistoryEntry>>(
              future: provider.fetchHistory(transaction.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 120,
                    child: AppStatePanel.loading(
                      title: 'Đang tải lịch sử',
                      compact: true,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Text('Chưa tải được lịch sử chỉnh sửa.');
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const Text('Chưa có chỉnh sửa thủ công.');
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: rows
                      .map(
                        (row) => ListTile(
                          leading: const Icon(Icons.history_rounded),
                          title: Text(
                            row.changedByEmail ?? 'Không rõ người sửa',
                          ),
                          subtitle: Text(
                            '${_ordersText(row.oldOrders)} → ${_ordersText(row.newOrders)}\n${row.createdAt == null ? '' : DateFormat('HH:mm:ss dd/MM/yyyy').format(row.createdAt!.toLocal())}',
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Đóng',
            ),
          ],
        );
      },
    );
  }

  String _ordersText(List<String> orders) => statementOrdersText(orders);

  Future<void> _showOrderTransferRequestDialog(
    BuildContext context,
    BankStatementProvider provider,
    BankStatementTransaction transaction,
  ) async {
    final requestController = TextEditingController(
      text: transaction.orderTransferRequestedOrders.isNotEmpty
          ? _ordersEditText(transaction.orderTransferRequestedOrders)
          : _ordersEditText(transaction.orders),
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var saving = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Cập nhật mã đơn'),
                content: SizedBox(
                  width: MediaQuery.of(context).size.width < 560
                      ? double.maxFinite
                      : 420,
                  child: AppTextInput(
                    controller: requestController,
                    label: 'Mã đơn hàng mới',
                    hintText: 'Nhập mỗi mã một dòng, hoặc cách bằng dấu phẩy',
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 6,
                  ),
                ),
                actions: [
                  AppDialogCancelButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                  ),
                  AppDialogConfirmButton(
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            final ok = await provider.requestOrderTransfer(
                              transaction.id,
                              requestController.text,
                            );
                            if (ok && dialogContext.mounted) {
                              await _reloadGlobalNotifications();
                              if (!dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop();
                            } else if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          },
                    icon: Icons.send_rounded,
                    label: 'Gửi Kế toán',
                    isLoading: saving,
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      requestController.dispose();
    }
  }

  Future<void> _showOrderTransferReviewDialog(
    BuildContext context,
    BankStatementProvider provider,
    BankStatementTransaction transaction,
  ) async {
    final requestId = transaction.orderTransferRequestId?.trim() ?? '';
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa tìm thấy yêu cầu cần duyệt.')),
      );
      return;
    }
    final rejectNoteController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var saving = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> review({required bool approved}) async {
                setDialogState(() => saving = true);
                try {
                  if (approved) {
                    await provider.approveOrderTransferRequest(requestId);
                  } else {
                    await provider.rejectOrderTransferRequest(
                      requestId,
                      note: rejectNoteController.text,
                    );
                  }
                  await _reloadGlobalNotifications();
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                } catch (_) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          approved
                              ? 'Chưa xác nhận được yêu cầu.'
                              : 'Chưa từ chối được yêu cầu.',
                        ),
                      ),
                    );
                    setDialogState(() => saving = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Phê duyệt cập nhật mã đơn'),
                content: SelectionArea(
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width < 560
                        ? double.maxFinite
                        : 460,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _reviewLine('SR', transaction.storeId),
                        _reviewLine('Mã sao kê', transaction.statementNumber),
                        _reviewLine(
                          'Số tiền',
                          widget.money.format(transaction.amount),
                        ),
                        _reviewLine(
                          'Đơn hiện tại',
                          _ordersText(transaction.orders),
                        ),
                        _reviewLine(
                          'Đơn đề nghị',
                          _ordersText(transaction.orderTransferRequestedOrders),
                        ),
                        _reviewLine(
                          'Thời gian GD',
                          _formatStatementDateTime(
                            transaction.paidAt ?? transaction.firstSeenAt,
                          ),
                        ),
                        _reviewLine(
                          'Thời gian yêu cầu',
                          _formatStatementDateTime(
                            transaction.orderTransferRequestedAt,
                          ),
                        ),
                        if ((transaction.orderTransferRequestedByEmail ?? '')
                            .isNotEmpty)
                          _reviewLine(
                            'Người gửi',
                            transaction.orderTransferRequestedByEmail!,
                          ),
                        const SizedBox(height: 8),
                        AppTextInput(
                          controller: rejectNoteController,
                          label: 'Ghi chú khi từ chối (không bắt buộc)',
                          hintText:
                              'Ví dụ: Mã đơn chưa đúng, vui lòng kiểm tra lại.',
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  AppDialogCancelButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    label: 'Đóng',
                  ),
                  AppDialogSecondaryButton(
                    onPressed: saving ? null : () => review(approved: false),
                    icon: Icons.close_rounded,
                    label: 'Từ chối',
                  ),
                  AppDialogConfirmButton(
                    onPressed: saving ? null : () => review(approved: true),
                    icon: Icons.check_rounded,
                    label: 'Xác nhận',
                    isLoading: saving,
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      rejectNoteController.dispose();
    }
  }

  Widget _reviewLine(String label, String value) {
    final text = value.trim().isEmpty ? 'Chưa có thông tin' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: AppTextStyles.labelM)),
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  final BankStatementTransaction tx;
  final NumberFormat money;

  const _TransactionDetails({required this.tx, required this.money});

  @override
  Widget build(BuildContext context) {
    final time = tx.paidAt ?? tx.firstSeenAt;
    final contentStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);
    final pillFontSize = contentStyle?.fontSize ?? 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _StatementPill(
              label: 'VietinBank',
              color: AppColors.violet600,
              fontSize: pillFontSize,
            ),
            _StatementPill(
              label: tx.storeId.isEmpty ? 'Không rõ' : tx.storeId,
              color: AppColors.info,
              fontSize: pillFontSize,
            ),
            _StatementPill(
              label: '${money.format(tx.amount)} VND',
              color: AppColors.success,
              fontSize: pillFontSize,
            ),
            _StatementPill(
              label: 'Thành công',
              color: AppColors.success,
              fontSize: pillFontSize,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          tx.content.isEmpty ? 'Không có nội dung chuyển khoản' : tx.content,
          style: contentStyle,
        ),
        const SizedBox(height: 6),
        Text(
          [
            if (tx.statementNumber.isNotEmpty)
              'Mã sao kê: ${tx.statementNumber}',
            if (time != null)
              DateFormat('HH:mm:ss dd/MM/yyyy').format(time.toLocal()),
            if (tx.payerLabel.isNotEmpty) tx.payerLabel,
          ].join(' • '),
          style: AppTextStyles.bodyM.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatementPill extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const _StatementPill({
    required this.label,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusChip(
      label: label,
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }
}

class _OrderEditor extends StatelessWidget {
  final BankStatementTransaction transaction;
  final TextEditingController controller;
  final bool editing;
  final bool canReviewTransfer;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;
  final VoidCallback onRequestTransfer;
  final VoidCallback onReviewTransfer;
  final VoidCallback onHistory;

  const _OrderEditor({
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
    return DecoratedBox(
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
                minLines: 1,
                maxLines: 3,
                dense: true,
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
            if (!editing &&
                !transaction.canEditOrders &&
                transaction.orderEditBlockedReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                transaction.orderEditBlockedReason!,
                style: AppTextStyles.labelS.copyWith(color: AppColors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat formatter = NumberFormat.decimalPattern('vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final cleanString = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanString.isEmpty) {
      return newValue.copyWith(
        text: '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }

    final intValue = int.tryParse(cleanString);
    if (intValue == null) {
      return oldValue;
    }

    final formatted = formatter.format(intValue);

    int digitCountBeforeCursor = 0;
    for (int i = 0; i < newValue.selection.end; i++) {
      if (RegExp(r'[0-9]').hasMatch(newValue.text[i])) {
        digitCountBeforeCursor++;
      }
    }

    int newOffset = 0;
    int digitCount = 0;
    while (newOffset < formatted.length &&
        digitCount < digitCountBeforeCursor) {
      if (RegExp(r'[0-9]').hasMatch(formatted[newOffset])) {
        digitCount++;
      }
      newOffset++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
