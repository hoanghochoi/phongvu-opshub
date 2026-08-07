import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../notifications/presentation/providers/app_notifications_provider.dart';
import '../../domain/bank_statement_transaction.dart';
import '../providers/bank_statement_provider.dart';
import '../widgets/bank_statement_transaction_details.dart';

const double _localBreakpoint = 800;
const double _filterGap = AppLayoutTokens.formInlineGap;
const List<AppComboboxOption<String>> _orderStatusOptions = [
  AppComboboxOption(value: 'ALL', label: 'Tất cả giao dịch'),
  AppComboboxOption(value: 'HAS_ORDER', label: 'Đã có đơn hàng'),
  AppComboboxOption(value: 'MISSING_ORDER', label: 'Chưa có đơn hàng'),
  AppComboboxOption(value: 'OFFSET_CONFIRMED', label: 'Giao dịch cấn trừ'),
  AppComboboxOption(value: 'OFFSET_PENDING', label: 'Chờ xác nhận'),
  AppComboboxOption(value: 'UNFOLLOWED', label: 'Đã bỏ theo dõi'),
];

String _formatStatementDateTime(DateTime? value) {
  if (value == null) return 'Không rõ';
  return DateFormat('HH:mm:ss dd/MM/yyyy').format(value.toLocal());
}

class BankStatementScreen extends StatefulWidget {
  const BankStatementScreen({
    super.key,
    this.initialOrderStatus,
    this.autoSearch = false,
  });

  final String? initialOrderStatus;
  final bool autoSearch;

  @override
  State<BankStatementScreen> createState() => _BankStatementScreenState();
}

class _BankStatementScreenState extends State<BankStatementScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _statementNumberFocus.addListener(
      () => _handleFilterFocus('statement_number', _statementNumberFocus),
    );
    _orderFocus.addListener(() => _handleFilterFocus('order', _orderFocus));
    _amountFocus.addListener(() => _handleFilterFocus('amount', _amountFocus));
    _contentFocus.addListener(
      () => _handleFilterFocus('content', _contentFocus),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeFromRoute());
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleFocusedFilterVisibility();
  }

  Future<void> _initializeFromRoute() async {
    final user = context.read<AuthProvider>().user;
    final provider = context.read<BankStatementProvider>();
    await provider.initialize(user);
    final initialOrderStatus = widget.initialOrderStatus?.trim().toUpperCase();
    if (initialOrderStatus == null ||
        !_orderStatusOptions.any((item) => item.value == initialOrderStatus)) {
      return;
    }
    provider.setOrderStatus(initialOrderStatus);
    await AppLogger.instance.info(
      'BankStatement',
      'Bank statement route filter applied',
      context: {
        'orderStatus': initialOrderStatus,
        'autoSearch': widget.autoSearch,
        'source': 'home_finance_card',
      },
    );
    if (widget.autoSearch) {
      await provider.search();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _handleFilterFocus(String filter, FocusNode focusNode) {
    if (!focusNode.hasFocus) return;
    _scheduleFocusedFilterVisibility(filter: filter, focusNode: focusNode);
  }

  void _scheduleFocusedFilterVisibility({
    String? filter,
    FocusNode? focusNode,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusedFilter = filter ?? _focusedFilterName;
      final focusedNode = focusNode ?? _focusedFilterNode;
      if (focusedFilter == null ||
          focusedNode == null ||
          !focusedNode.hasFocus ||
          MediaQuery.sizeOf(context).width >= _localBreakpoint ||
          _keyboardInset <= 0) {
        return;
      }
      unawaited(_keepFocusedFilterVisible(focusedFilter, focusedNode));
    });
  }

  String? get _focusedFilterName {
    if (_statementNumberFocus.hasFocus) return 'statement_number';
    if (_orderFocus.hasFocus) return 'order';
    if (_amountFocus.hasFocus) return 'amount';
    if (_contentFocus.hasFocus) return 'content';
    return null;
  }

  FocusNode? get _focusedFilterNode {
    if (_statementNumberFocus.hasFocus) return _statementNumberFocus;
    if (_orderFocus.hasFocus) return _orderFocus;
    if (_amountFocus.hasFocus) return _amountFocus;
    if (_contentFocus.hasFocus) return _contentFocus;
    return null;
  }

  double get _keyboardInset {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  Future<void> _keepFocusedFilterVisible(
    String filter,
    FocusNode focusNode,
  ) async {
    final focusContext = focusNode.context;
    if (!mounted || focusContext == null) return;
    final stopwatch = Stopwatch()..start();
    final bottomInset = _keyboardInset;
    unawaited(
      AppLogger.instance.info(
        'BankStatement',
        'Bank statement keyboard avoidance started',
        context: {'filter': filter, 'bottomInset': bottomInset.round()},
      ),
    );
    try {
      await Scrollable.ensureVisible(
        focusContext,
        alignment: 0.2,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      await AppLogger.instance.info(
        'BankStatement',
        'Bank statement keyboard avoidance succeeded',
        context: {
          'filter': filter,
          'bottomInset': bottomInset.round(),
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'BankStatement',
        'Bank statement keyboard avoidance failed',
        error: error,
        stackTrace: stackTrace,
        context: {'filter': filter, 'bottomInset': bottomInset.round()},
      );
    }
  }

  Future<void> _refreshScreen() async {
    final provider = context.read<BankStatementProvider>();
    await Future.wait([
      provider.refreshCurrentPage(),
      provider.loadPendingOrderTransferRequests(silent: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BankStatementProvider>();
    _syncControllers(provider);

    return SelectionArea(
      child: AppResponsiveContent(
        onRefresh: _refreshScreen,
        refreshLogSource: 'BankStatement',
        refreshLogContext: () => {
          'page': provider.page,
          'transactionCount': provider.transactions.length,
          'hasSearched': provider.hasSearched,
          'canSearch': provider.canSearch,
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final header = _buildHeader(provider);
            if (constraints.maxWidth < _localBreakpoint) {
              return CustomScrollView(
                key: const Key('bank-statement-mobile-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: header),
                  ..._buildMobileList(provider),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(child: _buildList(provider)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BankStatementProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            icon: PhosphorIconsRegular.warningCircle,
            title: 'Chưa tải được sao kê',
            message: provider.errorMessage!,
            tone: AppStateTone.error,
          ),
        ],
        if (provider.exportMessage != null) ...[
          const SizedBox(height: 10),
          AppStatusBanner(
            icon: PhosphorIconsRegular.downloadSimple,
            title: 'Xuất file',
            message: provider.exportMessage!,
            tone: AppStateTone.info,
          ),
        ],
        if (provider.batchMessage != null) ...[
          const SizedBox(height: 10),
          AppStatusBanner(
            icon: provider.batchMessage!.success
                ? PhosphorIconsRegular.checkCircle
                : PhosphorIconsRegular.warningCircle,
            title: provider.batchMessage!.success
                ? 'Đã cập nhật theo dõi'
                : 'Chưa bỏ theo dõi được',
            message: provider.batchMessage!.text,
            tone: provider.batchMessage!.success
                ? AppStateTone.success
                : AppStateTone.error,
          ),
        ],
        if (provider.isLoading && provider.transactions.isNotEmpty) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  List<Widget> _buildMobileList(BankStatementProvider provider) {
    if (provider.isLoading && provider.transactions.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: AppListSkeleton(
            itemCount: 5,
            showLeading: false,
            itemHeight: 124,
            scrollable: false,
          ),
        ),
      ];
    }
    if (!provider.hasSearched) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppStatePanel.empty(
            title: 'Chọn filter rồi bấm Tìm để tải giao dịch',
            icon: PhosphorIconsRegular.fileMagnifyingGlass,
          ),
        ),
      ];
    }
    if (provider.transactions.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppStatePanel.empty(
            title: 'Không có giao dịch khớp filter',
            icon: PhosphorIconsRegular.receipt,
          ),
        ),
      ];
    }
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _StatementCard(
            key: ValueKey(provider.transactions[index].id),
            transaction: provider.transactions[index],
            money: _money,
          ),
          childCount: provider.transactions.length,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String>) return null;
            final index = provider.transactions.indexWhere(
              (transaction) => transaction.id == key.value,
            );
            return index < 0 ? null : index;
          },
        ),
      ),
    ];
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
        icon: PhosphorIconsRegular.fileMagnifyingGlass,
      );
    }
    if (provider.transactions.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Không có giao dịch khớp filter',
        icon: PhosphorIconsRegular.receipt,
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: provider.transactions.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = provider.transactions.indexWhere(
          (transaction) => transaction.id == key.value,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        return _StatementCard(
          key: ValueKey(provider.transactions[index].id),
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

  Future<void> _runSearch({required bool collapseOnMobile}) async {
    await widget.provider.search();
    if (!mounted || !_isExpanded || !collapseOnMobile) return;
    setState(() => _isExpanded = false);
    await AppLogger.instance.info(
      'BankStatement',
      'Bank statement mobile filters collapsed after search',
      context: {'source': 'filter_panel'},
    );
  }

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
                        const Icon(PhosphorIconsRegular.funnel),
                        const SizedBox(width: 8),
                        Text('Bộ lọc tìm kiếm', style: AppTextStyles.labelM),
                        const Spacer(),
                        Icon(
                          _isExpanded
                              ? PhosphorIconsRegular.caretUp
                              : PhosphorIconsRegular.caretDown,
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
                    icon: PhosphorIconsRegular.receipt,
                    onChanged: widget.provider.setStatementNumber,
                    onSubmitted: (_) => _runSearch(collapseOnMobile: isMobile),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.orderController,
                    focusNode: widget.orderFocus,
                    label: 'Mã đơn hàng',
                    icon: PhosphorIconsRegular.tag,
                    onChanged: widget.provider.setOrder,
                    onSubmitted: (_) => _runSearch(collapseOnMobile: isMobile),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.amountController,
                    focusNode: widget.amountFocus,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsSeparatorInputFormatter()],
                    label: 'Số tiền',
                    icon: PhosphorIconsRegular.money,
                    onChanged: widget.provider.setAmount,
                    onSubmitted: (_) => _runSearch(collapseOnMobile: isMobile),
                  ),
                  const SizedBox(height: _filterGap),
                  AppTextInput(
                    controller: widget.contentController,
                    focusNode: widget.contentFocus,
                    label: 'Nội dung chuyển khoản',
                    icon: PhosphorIconsRegular.note,
                    onChanged: widget.provider.setContent,
                    onSubmitted: (_) => _runSearch(collapseOnMobile: isMobile),
                  ),
                  const SizedBox(height: _filterGap),
                  AppCombobox<String>.single(
                    value: widget.provider.orderStatus,
                    label: 'Trạng thái',
                    icon: PhosphorIconsRegular.flag,
                    options: _orderStatusOptions,
                    allowClear: false,
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
                  _FilterActionButtons(
                    provider: widget.provider,
                    onSearch: () => _runSearch(collapseOnMobile: isMobile),
                  ),
                ],
                const Divider(height: 22),
                _StatementListControls(provider: widget.provider),
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
                      icon: PhosphorIconsRegular.receipt,
                      onChanged: widget.provider.setStatementNumber,
                      onSubmitted: (_) =>
                          _runSearch(collapseOnMobile: isMobile),
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppTextInput(
                      controller: widget.orderController,
                      focusNode: widget.orderFocus,
                      label: 'Mã đơn hàng',
                      icon: PhosphorIconsRegular.tag,
                      onChanged: widget.provider.setOrder,
                      onSubmitted: (_) =>
                          _runSearch(collapseOnMobile: isMobile),
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
                      icon: PhosphorIconsRegular.money,
                      onChanged: widget.provider.setAmount,
                      onSubmitted: (_) =>
                          _runSearch(collapseOnMobile: isMobile),
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
                      icon: PhosphorIconsRegular.note,
                      onChanged: widget.provider.setContent,
                      onSubmitted: (_) =>
                          _runSearch(collapseOnMobile: isMobile),
                    ),
                  ),
                  const SizedBox(width: _filterGap),
                  Expanded(
                    child: AppCombobox<String>.single(
                      value: widget.provider.orderStatus,
                      label: 'Trạng thái',
                      icon: PhosphorIconsRegular.flag,
                      options: _orderStatusOptions,
                      allowClear: false,
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
                    child: _FilterActionButtons(
                      provider: widget.provider,
                      onSearch: () => _runSearch(collapseOnMobile: isMobile),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _filterGap),
              _StatementListControls(provider: widget.provider),
            ],
          ),
        );
      },
    );
  }
}

class _StatementListControls extends StatelessWidget {
  final BankStatementProvider provider;

  const _StatementListControls({required this.provider});

  @override
  Widget build(BuildContext context) {
    final selectedVisibleCount = provider.transactions
        .where((item) => provider.selectedIds.contains(item.id))
        .length;
    final partiallySelected =
        selectedVisibleCount > 0 && !provider.allVisibleSelected;
    final selectionControl = Row(
      children: [
        Checkbox(
          tristate: true,
          value: partiallySelected ? null : provider.allVisibleSelected,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged:
              provider.transactions.isEmpty ||
                  provider.isBatchUpdatingOrderTracking
              ? null
              : (value) => provider.toggleAllVisible(value == true),
        ),
        Expanded(
          child: Text(
            '${provider.selectedIds.length} chọn / ${provider.total} giao dịch',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: AppTextStyles.labelM,
          ),
        ),
      ],
    );
    final pageControls = AppPaginationControls(
      pageIndex: provider.page,
      totalItems: provider.total,
      itemLabel: 'giao dịch',
      onPrevious: provider.canGoPrevious ? provider.previousPage : null,
      onNext: provider.canGoNext ? provider.nextPage : null,
      onRefresh: provider.hasSearched && provider.canSearch
          ? provider.refreshCurrentPage
          : null,
      isRefreshing: provider.isLoading,
    );
    final batchAction = provider.canReviewOrderTransfers
        ? AppSecondaryButton(
            onPressed: provider.canBatchUnfollow
                ? () => _confirmBatchUnfollow(context)
                : null,
            icon: PhosphorIconsRegular.eyeSlash,
            label: 'Bỏ theo dõi đã chọn',
            isLoading: provider.isBatchUpdatingOrderTracking,
            loadingLabel: 'Đang cập nhật',
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              selectionControl,
              if (batchAction != null) ...[
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                batchAction,
              ],
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              pageControls,
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 200, child: selectionControl),
            if (batchAction != null) ...[
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              SizedBox(width: 200, child: batchAction),
            ],
            const SizedBox(width: AppLayoutTokens.formInlineGap),
            Expanded(child: pageControls),
          ],
        );
      },
    );
  }

  Future<void> _confirmBatchUnfollow(BuildContext context) async {
    final count = provider.selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bỏ theo dõi giao dịch đã chọn'),
        content: Text(
          'Bỏ theo dõi $count giao dịch? Thao tác chỉ thực hiện khi tất cả giao dịch còn hợp lệ.',
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: PhosphorIconsRegular.eyeSlash,
            label: 'Bỏ theo dõi',
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.batchUnfollowSelected();
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
        const AppComboboxOption<String>(
          value: _allStoresValue,
          label: 'Tất cả showroom',
        ),
      ...provider.stores.map(
        (store) => AppComboboxOption<String>(
          value: store.storeId,
          label: store.displayName,
          searchKeywords: [store.storeId, store.storeName],
        ),
      ),
    ];
    final values = provider.allStores
        ? {_allStoresValue}
        : provider.selectedStoreIds;
    return AppCombobox<String>.multi(
      label: 'Showroom',
      values: values,
      options: options,
      emptyLabel: 'Showroom được gán',
      icon: PhosphorIconsRegular.storefront,
      onMultiChanged: (selected) {
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
      showEmptyRangeHelperText: false,
    );
  }
}

class _LimitDropdown extends StatelessWidget {
  final BankStatementProvider provider;

  const _LimitDropdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppCombobox<int>.single(
      value: provider.limit,
      label: 'Số dòng',
      icon: PhosphorIconsRegular.listNumbers,
      options: const [10, 20, 50, 100]
          .map((value) => AppComboboxOption(value: value, label: '$value dòng'))
          .toList(),
      allowClear: false,
      onChanged: (value) {
        if (value != null) provider.setLimit(value);
      },
    );
  }
}

class _FilterActionButtons extends StatelessWidget {
  final BankStatementProvider provider;
  final Future<void> Function()? onSearch;

  const _FilterActionButtons({required this.provider, this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppPrimaryButton(
            onPressed: provider.canSearch
                ? (onSearch ?? provider.search)
                : null,
            icon: PhosphorIconsRegular.magnifyingGlass,
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

class _ExportButton extends StatelessWidget {
  final BankStatementProvider provider;

  const _ExportButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppSecondaryButton(
      onPressed: provider.canSearch && !provider.isExporting
          ? () => _handleExport(context)
          : null,
      icon: PhosphorIconsRegular.downloadSimple,
      label: _exportLabel,
    );
  }

  String get _exportLabel {
    if (provider.isExporting) return 'Đang xuất';
    return provider.selectedIds.isEmpty ? 'Xuất file' : 'Xuất đã chọn';
  }

  Future<void> _handleExport(BuildContext context) async {
    if (provider.hasExportDateRangeLimitViolation) {
      await showDialog<bool>(
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
    await provider.exportXlsx();
  }
}

class _StatementCard extends StatefulWidget {
  final BankStatementTransaction transaction;
  final NumberFormat money;

  const _StatementCard({
    super.key,
    required this.transaction,
    required this.money,
  });

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
    if (oldWidget.transaction.id != widget.transaction.id) {
      _editing = false;
      _controller.text = _ordersEditText(widget.transaction.orders);
    } else if (!_editing &&
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
    final message = provider.rowMessage(tx.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _localBreakpoint;

        if (isMobile) {
          return AppSurfaceCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: provider.selectedIds.contains(tx.id),
                      onChanged: provider.isBatchUpdatingOrderTracking
                          ? null
                          : (value) =>
                                provider.toggleSelected(tx.id, value == true),
                    ),
                    Expanded(
                      child: BankStatementTransactionDetailsLauncher(
                        transaction: tx,
                        amountFormatter: widget.money,
                        child: _TransactionDetails(
                          tx: tx,
                          money: widget.money,
                          incomeTypeUpdating: provider.isUpdatingIncomeType(
                            tx.id,
                          ),
                          onIncomeTypeSelected: (incomeType) {
                            unawaited(
                              provider.updateIncomeType(tx.id, incomeType),
                            );
                          },
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
                  busy:
                      provider.isUpdatingOrders(tx.id) ||
                      provider.isUpdatingOrderTracking(tx.id),
                  canReviewTransfer: provider.canReviewOrderTransfers,
                  onEdit: () => setState(() => _editing = true),
                  onCancel: () {
                    _controller.text = _ordersEditText(tx.orders);
                    setState(() => _editing = false);
                  },
                  onSave: () async {
                    final saved = await provider.updateOrders(
                      tx.id,
                      _controller.text,
                    );
                    if (mounted && saved) setState(() => _editing = false);
                  },
                  onToggleTracking: () => unawaited(
                    provider.updateOrderTracking(
                      tx.id,
                      tx.isFollowing ? 'UNFOLLOWED' : 'FOLLOWING',
                    ),
                  ),
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
                                  ? AppColors.successOf(context)
                                  : AppColors.errorOf(context),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        return AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: provider.selectedIds.contains(tx.id),
                onChanged: provider.isBatchUpdatingOrderTracking
                    ? null
                    : (value) => provider.toggleSelected(tx.id, value == true),
              ),
              Expanded(
                child: BankStatementTransactionDetailsLauncher(
                  transaction: tx,
                  amountFormatter: widget.money,
                  child: _TransactionDetails(
                    tx: tx,
                    money: widget.money,
                    incomeTypeUpdating: provider.isUpdatingIncomeType(tx.id),
                    onIncomeTypeSelected: (incomeType) {
                      unawaited(provider.updateIncomeType(tx.id, incomeType));
                    },
                  ),
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
                      busy:
                          provider.isUpdatingOrders(tx.id) ||
                          provider.isUpdatingOrderTracking(tx.id),
                      canReviewTransfer: provider.canReviewOrderTransfers,
                      onEdit: () => setState(() => _editing = true),
                      onCancel: () {
                        _controller.text = _ordersEditText(tx.orders);
                        setState(() => _editing = false);
                      },
                      onSave: () async {
                        final saved = await provider.updateOrders(
                          tx.id,
                          _controller.text,
                        );
                        if (mounted && saved) {
                          setState(() => _editing = false);
                        }
                      },
                      onToggleTracking: () => unawaited(
                        provider.updateOrderTracking(
                          tx.id,
                          tx.isFollowing ? 'UNFOLLOWED' : 'FOLLOWING',
                        ),
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
                                      ? AppColors.successOf(context)
                                      : AppColors.errorOf(context),
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
                          leading: const Icon(
                            PhosphorIconsRegular.clockCounterClockwise,
                          ),
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

  Future<void> _showOrderTransferReviewDialog(
    BuildContext context,
    BankStatementProvider provider,
    BankStatementTransaction transaction,
  ) async {
    final requestId = transaction.orderTransferRequestId?.trim() ?? '';
    if (requestId.isEmpty) {
      AppToast.show(
        context,
        const SnackBar(content: Text('Chưa tìm thấy yêu cầu cần duyệt.')),
      );
      return;
    }
    final rejectNoteController = TextEditingController();
    try {
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          var saving = false;
          return AppDirtyFormGuard(
            source: 'bank_statement.order_transfer_review',
            child: StatefulBuilder(
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
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop(true);
                    }
                  } catch (_) {
                    if (dialogContext.mounted) {
                      AppToast.show(
                        dialogContext,
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
                          _reviewLine('Showroom', transaction.storeId),
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
                            _ordersText(
                              transaction.orderTransferRequestedOrders,
                            ),
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
                      icon: PhosphorIconsRegular.x,
                      label: 'Từ chối',
                    ),
                    AppDialogConfirmButton(
                      onPressed: saving ? null : () => review(approved: true),
                      icon: PhosphorIconsRegular.check,
                      label: 'Xác nhận',
                      isLoading: saving,
                    ),
                  ],
                );
              },
            ),
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
  final bool incomeTypeUpdating;
  final ValueChanged<String> onIncomeTypeSelected;

  const _TransactionDetails({
    required this.tx,
    required this.money,
    required this.incomeTypeUpdating,
    required this.onIncomeTypeSelected,
  });

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
              color: AppColors.accentOf(context),
              fontSize: pillFontSize,
            ),
            _StatementPill(
              label: tx.storeId.isEmpty ? 'Không rõ' : tx.storeId,
              color: AppColors.infoOf(context),
              fontSize: pillFontSize,
            ),
            _StatementPill(
              label: '${money.format(tx.amount)} VND',
              color: AppColors.successOf(context),
              fontSize: pillFontSize,
            ),
            _IncomeTypePill(
              transaction: tx,
              fontSize: pillFontSize,
              isUpdating: incomeTypeUpdating,
              onSelected: onIncomeTypeSelected,
            ),
            _StatementPill(
              label: 'Thành công',
              color: AppColors.successOf(context),
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

class _IncomeTypePill extends StatelessWidget {
  final BankStatementTransaction transaction;
  final double fontSize;
  final bool isUpdating;
  final ValueChanged<String> onSelected;

  const _IncomeTypePill({
    required this.transaction,
    required this.fontSize,
    required this.isUpdating,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final color = transaction.isPartnerInternal
        ? AppColors.warningOf(context)
        : AppColors.infoOf(context);
    if (!transaction.canEditIncomeType) {
      return _StatementPill(
        label: transaction.incomeTypeLabel,
        color: color,
        fontSize: fontSize,
      );
    }
    return Semantics(
      button: true,
      label: 'Loại giao dịch ${transaction.incomeTypeLabel}. Nhấn để thay đổi.',
      child: PopupMenuButton<String>(
        key: Key('bank-statement-income-type-${transaction.id}'),
        enabled: !isUpdating,
        tooltip: isUpdating
            ? 'Đang đổi loại giao dịch'
            : 'Thay đổi loại giao dịch',
        initialValue: transaction.incomeType,
        onSelected: onSelected,
        itemBuilder: (context) => [
          _incomeTypeMenuItem(
            value: 'SALES',
            label: 'Bán hàng',
            selected: !transaction.isPartnerInternal,
          ),
          _incomeTypeMenuItem(
            value: 'PARTNER_INTERNAL',
            label: 'Đối tác/Nội bộ',
            selected: transaction.isPartnerInternal,
          ),
        ],
        child: AppStatusPill(
          icon: PhosphorIconsRegular.caretDown,
          label: transaction.incomeTypeLabel,
          color: color,
          isLoading: isUpdating,
          height: 30,
        ),
      ),
    );
  }

  PopupMenuItem<String> _incomeTypeMenuItem({
    required String value,
    required String label,
    required bool selected,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? PhosphorIconsRegular.check : PhosphorIconsRegular.circle,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _OrderEditor extends StatelessWidget {
  final BankStatementTransaction transaction;
  final TextEditingController controller;
  final bool editing;
  final bool busy;
  final bool canReviewTransfer;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;
  final VoidCallback onToggleTracking;
  final VoidCallback onReviewTransfer;
  final VoidCallback onHistory;

  const _OrderEditor({
    required this.transaction,
    required this.controller,
    required this.editing,
    required this.busy,
    required this.canReviewTransfer,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onToggleTracking,
    required this.onReviewTransfer,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
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
                      Text(
                        'Đơn hàng',
                        style: AppTextStyles.labelM.copyWith(
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (transaction.isOrderOffsetConfirmed)
                        AppStatusChip(
                          label: 'Đã cấn trừ',
                          color: AppColors.warningOf(context),
                        ),
                    ],
                  ),
                ),
                if (transaction.canManageOrderTracking)
                  IconButton(
                    tooltip: transaction.isFollowing
                        ? 'Bỏ theo dõi giao dịch'
                        : 'Theo dõi lại giao dịch',
                    onPressed:
                        !editing &&
                            !busy &&
                            !transaction.hasPendingOrderTransferRequest
                        ? onToggleTracking
                        : null,
                    icon: Icon(
                      transaction.isFollowing
                          ? PhosphorIconsRegular.eyeSlash
                          : PhosphorIconsRegular.eye,
                    ),
                  ),
                if (canReviewTransfer &&
                    transaction.hasPendingOrderTransferRequest)
                  IconButton(
                    tooltip: 'Phê duyệt cập nhật mã đơn',
                    onPressed: !editing && !busy ? onReviewTransfer : null,
                    icon: const Icon(PhosphorIconsRegular.clipboardText),
                  ),
                IconButton(
                  tooltip: 'Lịch sử chỉnh sửa',
                  onPressed: busy ? null : onHistory,
                  icon: const Icon(PhosphorIconsRegular.clockCounterClockwise),
                ),
                IconButton(
                  tooltip: busy
                      ? 'Đang kiểm tra trạng thái đơn hàng'
                      : editing
                      ? 'Lưu mã đơn'
                      : transaction.canEditOrders && transaction.isFollowing
                      ? 'Cập nhật mã đơn'
                      : !transaction.isFollowing
                      ? 'Giao dịch đang Bỏ theo dõi. Vui lòng Theo dõi lại trước khi cập nhật mã đơn.'
                      : transaction.orderEditBlockedReason ?? 'Không được sửa',
                  onPressed: busy
                      ? null
                      : editing
                      ? onSave
                      : transaction.canEditOrders && transaction.isFollowing
                      ? onEdit
                      : null,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          editing
                              ? PhosphorIconsRegular.check
                              : PhosphorIconsRegular.pencilSimple,
                        ),
                ),
                if (editing)
                  IconButton(
                    tooltip: 'Hủy sửa',
                    onPressed: busy ? null : onCancel,
                    icon: const Icon(PhosphorIconsRegular.x),
                  ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppStatusChip(
                label: transaction.isFollowing
                    ? 'Đang theo dõi'
                    : 'Đã bỏ theo dõi',
                color: transaction.isFollowing
                    ? AppColors.infoOf(context)
                    : AppColors.textMutedOf(context),
              ),
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
                style: AppTextStyles.labelM.copyWith(
                  color: AppColors.errorOf(context),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: transaction.orders
                    .map(
                      (order) => AppStatusChip(
                        label: order,
                        color: AppColors.successOf(context),
                      ),
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
                  AppStatusChip(
                    label: 'Chờ Kế toán xác nhận',
                    color: AppColors.warningOf(context),
                  ),
                  ...transaction.orderTransferRequestedOrders.map(
                    (order) => AppStatusChip(
                      label: order,
                      color: AppColors.warningOf(context),
                    ),
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
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.warningOf(context),
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
