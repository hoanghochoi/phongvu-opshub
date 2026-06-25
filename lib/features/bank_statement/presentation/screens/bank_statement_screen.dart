import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/bank_statement_transaction.dart';
import '../providers/bank_statement_provider.dart';
import '../widgets/bank_statement_transaction_details.dart';

const double _localBreakpoint = 800;
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
                    title: 'Export CSV',
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
    _showOrderTransferOverlay();
    await provider.loadPendingOrderTransferRequests();
  }

  void _showOrderTransferOverlay() {
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
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
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
                    const SizedBox(height: 10),
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
                    _DateRangeButton(
                      startDate: widget.provider.startDate,
                      endDate: widget.provider.endDate,
                      onChanged: widget.provider.setDateRange,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: widget.provider.limit,
                            decoration: const InputDecoration(
                              labelText: 'Số dòng',
                              border: OutlineInputBorder(),
                            ),
                            items: const [10, 20, 50, 100]
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text('$value dòng'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                widget.provider.setLimit(value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppPrimaryButton(
                            onPressed: widget.provider.canSearch
                                ? widget.provider.search
                                : null,
                            icon: Icons.search_rounded,
                            label: 'Tìm',
                            isLoading: widget.provider.isLoading,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StoreFilterButton(provider: widget.provider),
                    ),
                    const SizedBox(width: 10),
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
                    const SizedBox(width: 10),
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
                const SizedBox(height: 10),
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
                    const SizedBox(width: 10),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DateRangeButton(
                        startDate: widget.provider.startDate,
                        endDate: widget.provider.endDate,
                        onChanged: widget.provider.setDateRange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<int>(
                        initialValue: widget.provider.limit,
                        decoration: const InputDecoration(
                          labelText: 'Số dòng',
                          border: OutlineInputBorder(),
                        ),
                        items: const [10, 20, 50, 100]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value dòng'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) widget.provider.setLimit(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 140,
                      child: AppPrimaryButton(
                        onPressed: widget.provider.canSearch
                            ? widget.provider.search
                            : null,
                        icon: Icons.search_rounded,
                        label: 'Tìm',
                        isLoading: widget.provider.isLoading,
                      ),
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
  final BankStatementProvider provider;

  const _StoreFilterButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    final label = provider.allStores
        ? 'Tất cả SR'
        : provider.selectedStoreIds.isEmpty
        ? 'Mã showroom'
        : provider.selectedStoreIds.join(', ');
    return InkWell(
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      onTap: () => _openStoreDialog(context),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Mã showroom',
          prefixIcon: Icon(Icons.store_outlined),
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }

  Future<void> _openStoreDialog(BuildContext context) async {
    var allStores = provider.allStores;
    final selected = provider.selectedStoreIds.toSet();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isSmallScreen = MediaQuery.of(context).size.width < 460;
          return AlertDialog(
            title: const Text('Chọn showroom'),
            content: SizedBox(
              width: isSmallScreen ? double.maxFinite : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (provider.canUseAllStores)
                      CheckboxListTile(
                        value: allStores,
                        onChanged: (value) {
                          setState(() {
                            allStores = value == true;
                            if (allStores) selected.clear();
                          });
                        },
                        title: const Text('Tất cả SR'),
                      ),
                    ...provider.stores.map(
                      (store) => CheckboxListTile(
                        value: selected.contains(store.storeId),
                        onChanged: allStores
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    selected.add(store.storeId);
                                  } else {
                                    selected.remove(store.storeId);
                                  }
                                });
                              },
                        title: Text(store.displayName),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  provider.setStoreSelection(
                    allStores: allStores,
                    ids: selected,
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Áp dụng'),
              ),
            ],
          );
        },
      ),
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

  bool get _hasExplicitRange => startDate != null && endDate != null;

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _getLabelText() {
    final formatter = DateFormat('dd/MM/yyyy');
    final todayStart = _todayStart();

    if (!_hasExplicitRange) {
      return 'Hôm nay';
    }

    final startStr = formatter.format(startDate!);
    final endStr = formatter.format(endDate!);

    if (startStr == endStr) {
      final today = formatter.format(todayStart);
      final yesterday = DateFormat(
        'dd/MM/yyyy',
      ).format(DateTime.now().subtract(const Duration(days: 1)));
      if (startStr == today) return 'Hôm nay';
      if (startStr == yesterday) return 'Hôm qua';
      return startStr;
    }

    // Check presets
    final now = DateTime.now();

    final s = DateTime(startDate!.year, startDate!.month, startDate!.day);
    final e = DateTime(endDate!.year, endDate!.month, endDate!.day);

    if (e.difference(s).inDays == 6 && e.isAtSameMomentAs(todayStart)) {
      return '7 ngày qua';
    }
    if (e.difference(s).inDays == 29 && e.isAtSameMomentAs(todayStart)) {
      return '30 ngày qua';
    }
    if (s.year == now.year &&
        s.month == now.month &&
        s.day == 1 &&
        e.isAtSameMomentAs(todayStart)) {
      return 'Tháng này';
    }

    return '$startStr → $endStr';
  }

  @override
  Widget build(BuildContext context) {
    final label = _getLabelText();
    return InkWell(
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      onTap: () async {
        final result = await showDialog<Map<String, DateTime?>>(
          context: context,
          builder: (context) => _DateRangeDialog(
            initialStart: _hasExplicitRange ? startDate : null,
            initialEnd: _hasExplicitRange ? endDate : null,
          ),
        );
        if (result != null) {
          if (result.containsKey('clear')) {
            onChanged(null, null);
          } else {
            onChanged(result['start'], result['end']);
          }
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Khoảng thời gian',
          constraints: const BoxConstraints(minHeight: 52),
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.calendar_today_outlined),
          suffixIcon: !_hasExplicitRange
              ? const Icon(Icons.arrow_drop_down_rounded, size: 28)
              : IconButton(
                  tooltip: 'Xóa bộ lọc',
                  onPressed: () => onChanged(null, null),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
  }
}

class _DateRangeDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;

  const _DateRangeDialog({this.initialStart, this.initialEnd});

  @override
  State<_DateRangeDialog> createState() => _DateRangeDialogState();
}

class _DateRangeDialogState extends State<_DateRangeDialog> {
  DateTime? _start;
  DateTime? _end;

  bool get _hasExplicitRange => _start != null && _end != null;

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
  }

  void _setPreset(String preset) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case 'today':
        setState(() {
          _start = todayStart;
          _end = todayStart;
        });
        break;
      case 'yesterday':
        final yesterday = todayStart.subtract(const Duration(days: 1));
        setState(() {
          _start = yesterday;
          _end = yesterday;
        });
        break;
      case '7days':
        setState(() {
          _start = todayStart.subtract(const Duration(days: 6));
          _end = todayStart;
        });
        break;
      case '30days':
        setState(() {
          _start = todayStart.subtract(const Duration(days: 29));
          _end = todayStart;
        });
        break;
      case 'thisMonth':
        setState(() {
          _start = DateTime(now.year, now.month, 1);
          _end = todayStart;
        });
        break;
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final todayStart = _todayStart();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _hasExplicitRange
          ? DateTimeRange(start: _start!, end: _end!)
          : DateTimeRange(start: todayStart, end: todayStart),
      helpText: 'Chọn khoảng ngày',
      cancelText: 'Hủy',
      confirmText: 'Chọn',
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }

  bool _isPresetActive(String preset) {
    final now = DateTime.now();
    final todayStart = _todayStart();
    final s = _hasExplicitRange
        ? DateTime(_start!.year, _start!.month, _start!.day)
        : todayStart;
    final e = _hasExplicitRange
        ? DateTime(_end!.year, _end!.month, _end!.day)
        : todayStart;

    switch (preset) {
      case 'today':
        return s.isAtSameMomentAs(todayStart) && e.isAtSameMomentAs(todayStart);
      case 'yesterday':
        final yesterday = todayStart.subtract(const Duration(days: 1));
        return s.isAtSameMomentAs(yesterday) && e.isAtSameMomentAs(yesterday);
      case '7days':
        return e.difference(s).inDays == 6 && e.isAtSameMomentAs(todayStart);
      case '30days':
        return e.difference(s).inDays == 29 && e.isAtSameMomentAs(todayStart);
      case 'thisMonth':
        return s.year == now.year &&
            s.month == now.month &&
            s.day == 1 &&
            e.isAtSameMomentAs(todayStart);
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd/MM/yyyy');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text(
        'Chọn khoảng thời gian',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chọn nhanh:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPresetChip('Hôm nay', 'today'),
                _buildPresetChip('Hôm qua', 'yesterday'),
                _buildPresetChip('7 ngày qua', '7days'),
                _buildPresetChip('30 ngày qua', '30days'),
                _buildPresetChip('Tháng này', 'thisMonth'),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Khoảng ngày đã chọn:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickCustomRange,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDark ? AppColors.neutral700 : AppColors.neutral300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasExplicitRange
                            ? '${formatter.format(_start!)} → ${formatter.format(_end!)}'
                            : 'Hôm nay',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        if (_hasExplicitRange)
          TextButton(
            onPressed: () => Navigator.of(context).pop({'clear': null}),
            child: const Text(
              'Xóa lọc',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({'start': _start, 'end': _end});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary500,
            foregroundColor: Colors.white,
          ),
          child: const Text('Áp dụng'),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, String presetKey) {
    final active = _isPresetActive(presetKey);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => _setPreset(presetKey),
      selectedColor: AppColors.primary500.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: active
            ? AppColors.primary500
            : (isDark ? Colors.white : AppColors.neutral800),
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
      ),
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
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: AppSecondaryButton(
                      onPressed: provider.canSearch && !provider.isExporting
                          ? () => _handleExport(context)
                          : null,
                      icon: Icons.download_rounded,
                      label: _exportLabel,
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
            const SizedBox(width: 10),
            SizedBox(
              width: 150,
              child: AppSecondaryButton(
                onPressed: provider.canSearch && !provider.isExporting
                    ? () => _handleExport(context)
                    : null,
                icon: Icons.download_rounded,
                label: _exportLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  String get _exportLabel {
    if (provider.isExporting) return 'Đang export';
    return provider.selectedIds.isEmpty ? 'Export CSV' : 'Export đã chọn';
  }

  Future<void> _handleExport(BuildContext context) async {
    if (provider.hasExportDateRangeLimitViolation) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Không thể export'),
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
      child: IconButton(
        tooltip: count > 0
            ? '$count yêu cầu cập nhật mã đơn'
            : 'Yêu cầu cập nhật mã đơn',
        onPressed: onPressed,
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.notifications_none_rounded),
            if (count > 0)
              Positioned(
                right: -8,
                top: -8,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderTransferRequestsBubble extends StatelessWidget {
  final double width;
  final double maxHeight;
  final NumberFormat money;
  final VoidCallback onClose;
  final void Function(String message) onActionError;

  const _OrderTransferRequestsBubble({
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
            child: Consumer<BankStatementProvider>(
              builder: (context, provider, _) {
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
        return AlertDialog(
          title: Text('Lịch sử đơn hàng ${transaction.transactionNumber}'),
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
                    label: const Text('Gửi ACC'),
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
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;
  final VoidCallback onRequestTransfer;
  final VoidCallback onHistory;

  const _OrderEditor({
    required this.transaction,
    required this.controller,
    required this.editing,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onRequestTransfer,
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
                    label: 'Chờ ACC xác nhận',
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
