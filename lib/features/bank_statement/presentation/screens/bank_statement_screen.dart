import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_notification_action.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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

class BankStatementScreen extends StatefulWidget {
  const BankStatementScreen({super.key});

  @override
  State<BankStatementScreen> createState() => _BankStatementScreenState();
}

class _BankStatementScreenState extends State<BankStatementScreen> {
  final _orderController = TextEditingController();
  final _amountController = TextEditingController();
  final _contentController = TextEditingController();
  final _orderFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _contentFocus = FocusNode();
  final _money = NumberFormat.decimalPattern('vi_VN');
  final _orderTransferBellLink = LayerLink();
  OverlayEntry? _orderTransferOverlay;

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
    _hideOrderTransferRequests();
    _orderController.dispose();
    _amountController.dispose();
    _contentController.dispose();
    _orderFocus.dispose();
    _amountFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankStatementProvider>();
    _syncControllers(provider);

    return Scaffold(
      appBar: GradientHeader(
        title: 'Sao kê',
        showBack: true,
        actions: [
          if (provider.canReviewOrderTransfers)
            _OrderTransferBell(
              count: provider.pendingOrderTransferTotal,
              link: _orderTransferBellLink,
              onPressed: () => _toggleOrderTransferRequests(provider),
            ),
        ],
      ),
      body: SafeArea(
        child: SelectionArea(
          child: AppResponsiveContent(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FilterPanel(
                  provider: provider,
                  orderController: _orderController,
                  amountController: _amountController,
                  contentController: _contentController,
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
                _StatementToolbar(provider: provider),
                const SizedBox(height: 10),
                if (provider.isLoading && provider.transactions.isNotEmpty) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 10),
                ],
                Expanded(child: _buildList(provider)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(BankStatementProvider provider) {
    if (provider.isLoading && provider.transactions.isEmpty) {
      return const AppStatePanel.loading(title: 'Đang tải sao kê');
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

  Future<void> _toggleOrderTransferRequests(
    BankStatementProvider provider,
  ) async {
    if (_orderTransferOverlay != null) {
      _hideOrderTransferRequests();
      return;
    }
    _showOrderTransferOverlay(provider);
    await provider.loadPendingOrderTransferRequests();
  }

  void _showOrderTransferOverlay(BankStatementProvider provider) {
    final overlay = Overlay.of(context);
    _orderTransferOverlay = OverlayEntry(
      builder: (overlayContext) {
        final screenSize = MediaQuery.sizeOf(overlayContext);
        final bubbleWidth = math.max(
          240.0,
          math.min(440.0, screenSize.width - 24),
        );
        final bubbleHeight = math.max(
          260.0,
          math.min(520.0, screenSize.height - 120),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hideOrderTransferRequests,
              ),
            ),
            CompositedTransformFollower(
              link: _orderTransferBellLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(-8, 8),
              child: _OrderTransferRequestsBubble(
                provider: provider,
                width: bubbleWidth,
                maxHeight: bubbleHeight,
                money: _money,
                onClose: _hideOrderTransferRequests,
                onActionError: _showSnack,
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(_orderTransferOverlay!);
  }

  void _hideOrderTransferRequests() {
    _orderTransferOverlay?.remove();
    _orderTransferOverlay = null;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _FilterPanel extends StatefulWidget {
  final BankStatementProvider provider;
  final TextEditingController orderController;
  final TextEditingController amountController;
  final TextEditingController contentController;
  final FocusNode orderFocus;
  final FocusNode amountFocus;
  final FocusNode contentFocus;

  const _FilterPanel({
    required this.provider,
    required this.orderController,
    required this.amountController,
    required this.contentController,
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
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
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
                          const Text(
                            'Bộ lọc tìm kiếm',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
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
                    TextField(
                      controller: widget.orderController,
                      focusNode: widget.orderFocus,
                      decoration: const InputDecoration(
                        labelText: 'Mã đơn hàng',
                        prefixIcon: Icon(Icons.tag_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: widget.provider.setOrder,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                    const SizedBox(height: _filterGap),
                    TextField(
                      controller: widget.amountController,
                      focusNode: widget.amountFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Số tiền',
                        prefixIcon: Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: widget.provider.setAmount,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                    const SizedBox(height: _filterGap),
                    TextField(
                      controller: widget.contentController,
                      focusNode: widget.contentFocus,
                      decoration: const InputDecoration(
                        labelText: 'Nội dung chuyển khoản',
                        prefixIcon: Icon(Icons.notes_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: widget.provider.setContent,
                      onSubmitted: (_) => widget.provider.search(),
                    ),
                    const SizedBox(height: _filterGap),
                    DropdownButtonFormField<String>(
                      initialValue: widget.provider.orderStatus,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái',
                        border: OutlineInputBorder(),
                      ),
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
            ),
          );
        }

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StoreFilterButton(provider: widget.provider),
                    ),
                    const SizedBox(width: _filterGap),
                    Expanded(
                      child: TextField(
                        controller: widget.orderController,
                        focusNode: widget.orderFocus,
                        decoration: const InputDecoration(
                          labelText: 'Mã đơn hàng',
                          prefixIcon: Icon(Icons.tag_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: widget.provider.setOrder,
                        onSubmitted: (_) => widget.provider.search(),
                      ),
                    ),
                    const SizedBox(width: _filterGap),
                    Expanded(
                      child: TextField(
                        controller: widget.amountController,
                        focusNode: widget.amountFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsSeparatorInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Số tiền',
                          prefixIcon: Icon(Icons.payments_outlined),
                          border: OutlineInputBorder(),
                        ),
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
                      child: TextField(
                        controller: widget.contentController,
                        focusNode: widget.contentFocus,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung chuyển khoản',
                          prefixIcon: Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: widget.provider.setContent,
                        onSubmitted: (_) => widget.provider.search(),
                      ),
                    ),
                    const SizedBox(width: _filterGap),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: widget.provider.orderStatus,
                        decoration: const InputDecoration(
                          labelText: 'Trạng thái',
                          border: OutlineInputBorder(),
                        ),
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
    return DropdownButtonFormField<int>(
      initialValue: provider.limit,
      decoration: const InputDecoration(
        labelText: 'Số dòng',
        border: OutlineInputBorder(),
      ),
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
              style: const TextStyle(fontWeight: FontWeight.w700),
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
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }
    await provider.exportCsv();
  }
}

class _OrderTransferBell extends StatelessWidget {
  final int count;
  final LayerLink link;
  final VoidCallback onPressed;

  const _OrderTransferBell({
    required this.count,
    required this.link,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: link,
      child: AppNotificationIconButton(
        count: count,
        tooltip: count > 0
            ? '$count yêu cầu cập nhật mã đơn'
            : 'Yêu cầu cập nhật mã đơn',
        onPressed: onPressed,
      ),
    );
  }
}

class _OrderTransferRequestsBubble extends StatelessWidget {
  final BankStatementProvider provider;
  final double width;
  final double maxHeight;
  final NumberFormat money;
  final VoidCallback onClose;
  final void Function(String message) onActionError;

  const _OrderTransferRequestsBubble({
    required this.provider,
    required this.width,
    required this.maxHeight,
    required this.money,
    required this.onClose,
    required this.onActionError,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
            child: AnimatedBuilder(
              animation: provider,
              builder: (context, _) {
                final requests = provider.pendingOrderTransferRequests;
                return Column(
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
                            'Yêu cầu cập nhật mã đơn',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tải lại',
                          onPressed: provider.isLoadingOrderTransferRequests
                              ? null
                              : () =>
                                    provider.loadPendingOrderTransferRequests(),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                        IconButton(
                          tooltip: 'Đóng',
                          onPressed: onClose,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child:
                          provider.isLoadingOrderTransferRequests &&
                              requests.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : requests.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Text(
                                  'Không có yêu cầu chờ xác nhận.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: requests.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 18),
                              itemBuilder: (context, index) {
                                final request = requests[index];
                                return _OrderTransferRequestTile(
                                  request: request,
                                  money: money,
                                  onApprove: () async {
                                    try {
                                      await provider
                                          .approveOrderTransferRequest(
                                            request.id,
                                          );
                                    } catch (_) {
                                      onActionError(
                                        'Chưa xác nhận được yêu cầu.',
                                      );
                                    }
                                  },
                                  onReject: () async {
                                    try {
                                      await provider.rejectOrderTransferRequest(
                                        request.id,
                                      );
                                    } catch (_) {
                                      onActionError(
                                        'Chưa từ chối được yêu cầu.',
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderTransferRequestTile extends StatelessWidget {
  final BankStatementOrderTransferRequest request;
  final NumberFormat money;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const _OrderTransferRequestTile({
    required this.request,
    required this.money,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = request.createdAt;
    final createdText = createdAt == null
        ? ''
        : DateFormat('HH:mm dd/MM/yyyy').format(createdAt.toLocal());
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.swap_horiz_rounded, color: AppColors.warning),
      title: Text(
        '${_ordersText(request.oldOrders)} → ${_ordersText(request.requestedOrders)}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                request.storeCode,
                money.format(request.amount),
                if (createdText.isNotEmpty) createdText,
              ].join(' • '),
            ),
            if ((request.requestedByEmail ?? '').isNotEmpty)
              Text('Người gửi: ${request.requestedByEmail}'),
            if (request.content.isNotEmpty)
              Text(
                request.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Không xác nhận'),
                ),
                ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Xác nhận'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _ordersText(List<String> orders) =>
      orders.isEmpty ? 'NULL' : orders.join(', ');
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
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              side: BorderSide(
                color: borderColor.withValues(alpha: 0.65),
                width: 1.3,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
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
                          child: _TransactionDetails(
                            tx: tx,
                            money: widget.money,
                          ),
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
                              style: TextStyle(
                                color: message.success
                                    ? AppColors.success
                                    : AppColors.error,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            side: BorderSide(
              color: borderColor.withValues(alpha: 0.65),
              width: 1.3,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
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
                        onRequestTransfer: () =>
                            _showOrderTransferRequestDialog(
                              context,
                              provider,
                              tx,
                            ),
                        onReviewTransfer: () => _showOrderTransferReviewDialog(
                          context,
                          provider,
                          tx,
                        ),
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
                                  style: TextStyle(
                                    color: message.success
                                        ? AppColors.success
                                        : AppColors.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                    child: Center(child: CircularProgressIndicator()),
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  String _ordersText(List<String> orders) =>
      orders.isEmpty ? 'NULL' : orders.join(', ');

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
                  child: TextField(
                    controller: requestController,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Mã đơn hàng mới',
                      hintText: 'Nhập mỗi mã một dòng, hoặc cách bằng dấu phẩy',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            final ok = await provider.requestOrderTransfer(
                              transaction.id,
                              requestController.text,
                            );
                            if (ok && dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            } else if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Gửi Kế toán'),
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
                  await provider.rejectOrderTransferRequest(requestId);
                }
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
              content: SizedBox(
                width: MediaQuery.of(context).size.width < 560
                    ? double.maxFinite
                    : 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _reviewLine('SR', transaction.storeId),
                    _reviewLine('Mã giao dịch', transaction.transactionNumber),
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Đóng'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : () => review(approved: false),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Từ chối'),
                ),
                ElevatedButton.icon(
                  onPressed: saving ? null : () => review(approved: true),
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: const Text('Xác nhận'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reviewLine(String label, String value) {
    final text = value.trim().isEmpty ? 'NULL' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
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
            if (tx.transactionNumber.isNotEmpty) 'GD: ${tx.transactionNumber}',
            if (time != null)
              DateFormat('HH:mm:ss dd/MM/yyyy').format(time.toLocal()),
            if (tx.payerLabel.isNotEmpty) tx.payerLabel,
          ].join(' • '),
          style: TextStyle(
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
                      const Text(
                        'Đơn hàng',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
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
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Nhập mỗi mã một dòng, hoặc cách bằng dấu phẩy',
                  border: OutlineInputBorder(),
                ),
              )
            else if (transaction.orders.isEmpty)
              Text(
                'NULL',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w800,
                ),
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
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
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
