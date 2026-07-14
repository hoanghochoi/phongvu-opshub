import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/offset_adjustment.dart';
import '../providers/offset_adjustment_provider.dart';

const _breakpoint = 720.0;

String _storeOptionLabel(String storeId, String storeName) {
  final code = storeId.trim().toUpperCase();
  final name = storeName.trim();
  if (name.isEmpty || name.toUpperCase() == code) return code;
  return '$code - $name';
}

class OffsetAdjustmentScreen extends StatefulWidget {
  const OffsetAdjustmentScreen({super.key});

  @override
  State<OffsetAdjustmentScreen> createState() => _OffsetAdjustmentScreenState();
}

class _OffsetAdjustmentScreenState extends State<OffsetAdjustmentScreen> {
  final _orderController = TextEditingController();
  final _amountController = TextEditingController();
  final _money = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().user;
      context.read<OffsetAdjustmentProvider>().initialize(user);
    });
  }

  @override
  void dispose() {
    _orderController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _refreshScreen() async {
    final provider = context.read<OffsetAdjustmentProvider>();
    await Future.wait([
      provider.search(page: provider.page),
      provider.loadPendingTotal(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OffsetAdjustmentProvider>();
    _syncControllers(provider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final compact = width < 520;
        return SelectionArea(
          child: compact
              ? AppResponsiveScrollView(
                  onRefresh: _refreshScreen,
                  refreshLogSource: 'OffsetAdjustment',
                  refreshLogContext: () => {
                    'page': provider.page,
                    'itemCount': provider.items.length,
                    'hasSearched': provider.hasSearched,
                  },
                  child: _workspace(provider, compact),
                )
              : AppResponsiveContent(
                  onRefresh: _refreshScreen,
                  refreshLogSource: 'OffsetAdjustment',
                  refreshLogContext: () => {
                    'page': provider.page,
                    'itemCount': provider.items.length,
                    'hasSearched': provider.hasSearched,
                  },
                  child: _workspace(provider, compact),
                ),
        );
      },
    );
  }

  Widget _workspace(OffsetAdjustmentProvider provider, bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionBar(onCreate: _showCreateDialog),
        const SizedBox(height: 10),
        _FilterPanel(
          provider: provider,
          orderController: _orderController,
          amountController: _amountController,
        ),
        if (provider.errorMessage != null) ...[
          const SizedBox(height: 10),
          AppStatusBanner(
            icon: Icons.error_outline_rounded,
            title: 'Chưa thực hiện được',
            message: provider.errorMessage!,
            tone: AppStateTone.error,
          ),
        ],
        if (provider.successMessage != null) ...[
          const SizedBox(height: 10),
          AppStatusBanner(
            icon: Icons.check_circle_outline_rounded,
            title: 'Đã cập nhật',
            message: provider.successMessage!,
            tone: AppStateTone.success,
          ),
        ],
        if (provider.isLoading && provider.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 10),
        if (compact)
          _buildList(provider, shrinkWrap: true)
        else
          Expanded(child: _buildList(provider)),
      ],
    );
  }

  Widget _buildList(
    OffsetAdjustmentProvider provider, {
    bool shrinkWrap = false,
  }) {
    if (provider.isLoading && provider.items.isEmpty) {
      return const AppListSkeleton(
        itemCount: 5,
        showLeading: false,
        itemHeight: 112,
      );
    }
    if (!provider.hasSearched) {
      return const AppStatePanel.empty(
        icon: Icons.swap_horiz_rounded,
        title: 'Chưa có dữ liệu',
        message: 'Chọn bộ lọc để tải hồ sơ cấn trừ.',
      );
    }
    if (provider.items.isEmpty) {
      return const AppStatePanel.empty(
        icon: Icons.inbox_outlined,
        title: 'Không có hồ sơ cấn trừ',
        message: 'Chưa có hồ sơ phù hợp với bộ lọc hiện tại.',
      );
    }
    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      itemCount: provider.items.length,
      itemBuilder: (context, index) {
        final item = provider.items[index];
        return _OffsetCard(
          item: item,
          money: _money,
          onTap: () => _showDetails(item),
        );
      },
    );
  }

  void _syncControllers(OffsetAdjustmentProvider provider) {
    if (_orderController.text != (provider.order ?? '')) {
      _orderController.text = provider.order ?? '';
    }
    final amount = provider.amount == null
        ? ''
        : _money.format(int.parse(provider.amount!));
    if (_amountController.text != amount) {
      _amountController.text = amount;
    }
  }

  Future<void> _showCreateDialog(
    String type, {
    OffsetAdjustment? initial,
  }) async {
    final provider = context.read<OffsetAdjustmentProvider>();
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDirtyFormGuard(
        source: 'offset_adjustment.editor',
        child: _OffsetInputDialog(
          type: type,
          initial: initial,
          money: _money,
          onSubmit: (input) {
            if (initial == null) return provider.create(input);
            return provider.resubmit(initial.id, input);
          },
        ),
      ),
    );
  }

  Future<void> _showDetails(OffsetAdjustment item) async {
    final provider = context.read<OffsetAdjustmentProvider>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OffsetDetailDialog(
        item: item,
        money: _money,
        canReview: provider.canReview,
        onComplete: () async {
          final ctCode = item.type == OffsetAdjustmentType.vnpayQroff
              ? await _promptText(
                  context: dialogContext,
                  title: 'Nhập Mã CT',
                  label: 'Mã CT',
                  emptyMessage: 'Vui lòng nhập Mã CT.',
                )
              : '';
          if (ctCode == null) return;
          final error = await provider.complete(item.id, ctCode: ctCode);
          if (!dialogContext.mounted) return;
          if (error == null) {
            Navigator.of(dialogContext).pop();
          } else {
            _showSnack(dialogContext, error);
          }
        },
        onReject: () async {
          final reason = await _promptText(
            context: dialogContext,
            title: 'Lý do từ chối',
            label: 'Lý do',
            emptyMessage: 'Vui lòng nhập lý do từ chối.',
            maxLines: 3,
          );
          if (reason == null) return;
          final error = await provider.reject(item.id, reason);
          if (!dialogContext.mounted) return;
          if (error == null) {
            Navigator.of(dialogContext).pop();
          } else {
            _showSnack(dialogContext, error);
          }
        },
        onResubmit: () {
          Navigator.of(dialogContext).pop();
          _showCreateDialog(item.type, initial: item);
        },
      ),
    );
  }

  Future<String?> _promptText({
    required BuildContext context,
    required String title,
    required String label,
    required String emptyMessage,
    int maxLines = 1,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AppDirtyFormGuard(
        source: 'offset_adjustment.prompt',
        child: AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: math.max(
              240.0,
              math.min(MediaQuery.sizeOf(context).width - 48, 520.0),
            ),
            child: AppTextInput(
              controller: controller,
              label: label,
              autofocus: true,
              maxLines: maxLines,
            ),
          ),
          actions: [
            AppDialogCancelButton(onPressed: () => Navigator.of(context).pop()),
            AppDialogConfirmButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  _showSnack(context, emptyMessage);
                  return;
                }
                Navigator.of(context).pop(text);
              },
              label: 'Xác nhận',
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(BuildContext context, String message) {
    AppToast.show(context, SnackBar(content: Text(message)));
  }
}

class _ActionBar extends StatelessWidget {
  final void Function(String type) onCreate;

  const _ActionBar({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 960
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final buttonWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _createButton(
              context,
              OffsetAdjustmentType.singleOrder,
              Icons.swap_calls_rounded,
              buttonWidth,
            ),
            _createButton(
              context,
              OffsetAdjustmentType.vnpayQroff,
              Icons.qr_code_2_rounded,
              buttonWidth,
            ),
            _createButton(
              context,
              OffsetAdjustmentType.zaloPay,
              Icons.account_balance_wallet_outlined,
              buttonWidth,
            ),
            _createButton(
              context,
              OffsetAdjustmentType.shopeePay,
              Icons.shopping_bag_outlined,
              buttonWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _createButton(
    BuildContext context,
    String type,
    IconData icon,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: AppPrimaryButton(
        onPressed: () => onCreate(type),
        icon: icon,
        label: OffsetAdjustmentType.label(type),
      ),
    );
  }
}

class _FilterPanel extends StatefulWidget {
  final OffsetAdjustmentProvider provider;
  final TextEditingController orderController;
  final TextEditingController amountController;

  const _FilterPanel({
    required this.provider,
    required this.orderController,
    required this.amountController,
  });

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('offset-adjustment-filter-card'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = AppLayoutTokens.formInlineGap;
          final isMobile = constraints.maxWidth < 520;
          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _isExpanded = !_isExpanded),
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
                        Text('Bộ lọc cấn trừ', style: AppTextStyles.labelM),
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
                  const Divider(height: 22),
                  _storeFilter(),
                  const SizedBox(height: gap),
                  _typeFilter(),
                  const SizedBox(height: gap),
                  _statusFilter(),
                  const SizedBox(height: gap),
                  _orderField(),
                  const SizedBox(height: gap),
                  _amountField(),
                  const SizedBox(height: gap),
                  AppDateRangeDropdown(
                    label: 'Ngày',
                    start: widget.provider.startDate,
                    end: widget.provider.endDate,
                    onChanged: widget.provider.setDateRange,
                    showEmptyRangeHelperText: false,
                  ),
                  const SizedBox(height: gap),
                  _OffsetLimitDropdown(provider: widget.provider),
                ],
                const SizedBox(height: gap),
                _FilterActions(provider: widget.provider),
                const SizedBox(height: gap),
                _OffsetListControls(provider: widget.provider),
              ],
            );
          }

          final columns = constraints.maxWidth >= 1040
              ? 4
              : constraints.maxWidth >= _breakpoint
              ? 3
              : constraints.maxWidth >= 520
              ? 2
              : 1;
          final fieldWidth =
              (constraints.maxWidth - (gap * (columns - 1))) / columns;
          final filters = Wrap(
            spacing: gap,
            runSpacing: gap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: fieldWidth, child: _storeFilter()),
              SizedBox(width: fieldWidth, child: _typeFilter()),
              SizedBox(width: fieldWidth, child: _statusFilter()),
              SizedBox(width: fieldWidth, child: _orderField()),
              SizedBox(width: fieldWidth, child: _amountField()),
              SizedBox(
                width: fieldWidth,
                child: AppDateRangeDropdown(
                  label: 'Ngày',
                  start: widget.provider.startDate,
                  end: widget.provider.endDate,
                  onChanged: widget.provider.setDateRange,
                  showEmptyRangeHelperText: false,
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _OffsetLimitDropdown(provider: widget.provider),
              ),
              SizedBox(
                width: fieldWidth,
                child: _FilterActions(provider: widget.provider),
              ),
            ],
          );
          return Column(
            children: [
              filters,
              const SizedBox(height: gap),
              _OffsetListControls(provider: widget.provider),
            ],
          );
        },
      ),
    );
  }

  Widget _storeFilter() {
    if (!widget.provider.canReview && widget.provider.stores.length <= 1) {
      return InputDecorator(
        decoration: appInputDecoration(
          label: 'Showroom',
          icon: Icons.storefront_outlined,
        ),
        child: Text(
          widget.provider.stores.isEmpty
              ? 'Chưa được gán Showroom'
              : widget.provider.stores.first.storeId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return AppCombobox<String>.multi(
      label: 'Showroom',
      icon: Icons.storefront_outlined,
      values: widget.provider.selectedStoreIds,
      emptyLabel: widget.provider.canReview
          ? 'Tất cả showroom'
          : 'Tất cả showroom được gán',
      options: widget.provider.stores
          .map(
            (store) => AppComboboxOption<String>(
              value: store.storeId,
              label: _storeOptionLabel(store.storeId, store.storeName),
              subtitle: store.storeName.trim().isEmpty ? null : store.storeName,
              searchKeywords: [store.storeId, store.storeName],
            ),
          )
          .toList(growable: false),
      onMultiChanged: (ids) => widget.provider.setStoreSelection(
        allStores: widget.provider.canReview && ids.isEmpty,
        ids: ids,
      ),
    );
  }

  Widget _typeFilter() {
    return AppCombobox<String>.single(
      value: widget.provider.type,
      label: 'Loại',
      icon: Icons.category_outlined,
      options: const [
        AppComboboxOption(value: 'ALL', label: 'Tất cả loại'),
        AppComboboxOption(
          value: OffsetAdjustmentType.singleOrder,
          label: 'Cấn trừ đơn',
        ),
        AppComboboxOption(
          value: OffsetAdjustmentType.vnpayQroff,
          label: 'VNPAY QROFF',
        ),
        AppComboboxOption(
          value: OffsetAdjustmentType.zaloPay,
          label: 'Zalo Pay',
        ),
        AppComboboxOption(
          value: OffsetAdjustmentType.shopeePay,
          label: 'Shopee Pay',
        ),
      ],
      allowClear: false,
      onChanged: (value) => widget.provider.setType(value ?? 'ALL'),
    );
  }

  Widget _statusFilter() {
    return AppCombobox<String>.single(
      value: widget.provider.status,
      label: 'Trạng thái',
      icon: Icons.flag_outlined,
      options: const [
        AppComboboxOption(value: 'ALL', label: 'Tất cả trạng thái'),
        AppComboboxOption(
          value: OffsetAdjustmentStatus.pending,
          label: 'Chờ Kế toán xác nhận',
        ),
        AppComboboxOption(
          value: OffsetAdjustmentStatus.approved,
          label: 'Kế toán đã xác nhận',
        ),
        AppComboboxOption(
          value: OffsetAdjustmentStatus.rejected,
          label: 'Kế toán từ chối chờ sửa',
        ),
      ],
      allowClear: false,
      onChanged: (value) => widget.provider.setStatus(value ?? 'ALL'),
    );
  }

  Widget _orderField() {
    return AppTextInput(
      controller: widget.orderController,
      label: 'Mã đơn',
      icon: Icons.tag_rounded,
      onChanged: widget.provider.setOrder,
    );
  }

  Widget _amountField() {
    return AppTextInput(
      controller: widget.amountController,
      keyboardType: TextInputType.number,
      inputFormatters: [ThousandsSeparatorInputFormatter()],
      label: 'Số tiền',
      icon: Icons.payments_outlined,
      onChanged: widget.provider.setAmount,
    );
  }
}

class _OffsetLimitDropdown extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _OffsetLimitDropdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppCombobox<int>.single(
      value: provider.limit,
      label: 'Số dòng',
      icon: Icons.format_list_numbered_rounded,
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

class _OffsetListControls extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _OffsetListControls({required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppPaginationControls(
      pageIndex: provider.page,
      totalItems: provider.total,
      itemLabel: 'hồ sơ',
      onPrevious: !provider.isLoading && provider.canGoPrevious
          ? provider.previousPage
          : null,
      onNext: !provider.isLoading && provider.canGoNext
          ? provider.nextPage
          : null,
      onRefresh: () => provider.search(page: provider.page),
      isRefreshing: provider.isLoading,
    );
  }
}

class _FilterActions extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _FilterActions({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppPrimaryButton(
            onPressed: provider.isLoading ? null : provider.search,
            icon: Icons.search_rounded,
            label: 'Tìm',
            isLoading: provider.isLoading,
          ),
        ),
        const SizedBox(width: AppLayoutTokens.formInlineGap),
        Expanded(child: _ExportMenuButton(provider: provider)),
      ],
    );
  }
}

class _ExportMenuButton extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _ExportMenuButton({required this.provider});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.dataset_outlined),
          onPressed: provider.isExporting
              ? null
              : () => provider.exportCsv(type: 'ALL'),
          child: const Text('Tất cả loại'),
        ),
        for (final type in OffsetAdjustmentType.values)
          MenuItemButton(
            leadingIcon: Icon(_typeIcon(type)),
            onPressed: provider.isExporting
                ? null
                : () => provider.exportCsv(type: type),
            child: Text(OffsetAdjustmentType.label(type)),
          ),
      ],
      builder: (context, controller, child) {
        return AppSecondaryButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: Icons.download_rounded,
          label: 'Xuất file',
          isLoading: provider.isExporting,
          loadingLabel: 'Đang xuất',
        );
      },
    );
  }
}

class _OffsetCard extends StatelessWidget {
  final OffsetAdjustment item;
  final NumberFormat money;
  final VoidCallback onTap;

  const _OffsetCard({
    required this.item,
    required this.money,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = _statusColor(item.status);
    final submittedAt = item.submittedAt;
    final submittedText = submittedAt == null
        ? ''
        : DateFormat('HH:mm dd/MM/yyyy').format(submittedAt.toLocal());
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderColor: borderColor.withValues(alpha: 0.7),
      borderWidth: 1.3,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusChip(
                label: OffsetAdjustmentType.label(item.type),
                color: AppColors.info,
              ),
              AppStatusChip(
                label: OffsetAdjustmentStatus.label(item.status),
                color: borderColor,
              ),
              if (item.isSingleOrder && item.singleOrderReuseCount != null)
                AppStatusChip(
                  label: '${item.singleOrderReuseCount} lần',
                  color: AppColors.warning,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.primaryOrderLabel.isEmpty
                ? 'Chưa có mã đơn'
                : item.primaryOrderLabel,
            style: AppTextStyles.labelL,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              _InlineInfo(
                icon: Icons.storefront_outlined,
                text: item.storeCode,
              ),
              _InlineInfo(
                icon: Icons.payments_outlined,
                text: money.format(item.amount),
              ),
              if (submittedText.isNotEmpty)
                _InlineInfo(icon: Icons.schedule_rounded, text: submittedText),
              if ((item.transactionCode ?? '').isNotEmpty)
                _InlineInfo(
                  icon: Icons.confirmation_number_outlined,
                  text: item.transactionCode!,
                ),
            ],
          ),
          if ((item.rejectReason ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.rejectReason!,
              style: AppTextStyles.labelM.copyWith(color: AppColors.warning),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.neutral500),
        const SizedBox(width: 4),
        Text(text, style: AppTextStyles.labelS),
      ],
    );
  }
}

class _OffsetDetailDialog extends StatelessWidget {
  final OffsetAdjustment item;
  final NumberFormat money;
  final bool canReview;
  final Future<void> Function() onComplete;
  final Future<void> Function() onReject;
  final VoidCallback onResubmit;

  const _OffsetDetailDialog({
    required this.item,
    required this.money,
    required this.canReview,
    required this.onComplete,
    required this.onReject,
    required this.onResubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(OffsetAdjustmentType.label(item.type)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _detail('Trạng thái', OffsetAdjustmentStatus.label(item.status)),
              _detail('Showroom', item.storeCode),
              if (item.isSingleOrder) ...[
                _detail('Đơn hàng cũ', item.oldOrderCode),
                _detail('Đơn hàng mới', item.newOrderCode),
                if (item.singleOrderReuseCount != null)
                  _detail('Số lần cấn trừ', '${item.singleOrderReuseCount}'),
              ] else ...[
                _detail('Đơn hàng', item.orderCode),
                _detail(_scanDateLabel(item.type), item.scanDate),
                _detail(
                  'Nội dung cần sửa',
                  item.editContentKind == null
                      ? null
                      : OffsetEditContentKind.label(item.editContentKind!),
                ),
                _detail('Mã giao dịch', item.transactionCode),
              ],
              _detail('Số tiền', money.format(item.amount)),
              _detail('Mã CT', item.ctCode),
              _detail('Ghi chú', item.note),
              _detail('Lý do từ chối', item.rejectReason),
              _detail('Người nhập', item.createdByEmail),
              _detail('Kế toán xử lý', item.reviewedByEmail),
            ],
          ),
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: () => Navigator.of(context).pop(),
          label: 'Đóng',
        ),
        if (item.canResubmit)
          AppDialogConfirmButton(
            onPressed: onResubmit,
            icon: Icons.edit_rounded,
            label: 'Sửa lại',
          ),
        if (canReview && item.status == OffsetAdjustmentStatus.pending) ...[
          AppDialogSecondaryButton(
            onPressed: onReject,
            icon: Icons.close_rounded,
            label: 'Từ chối',
          ),
          AppDialogConfirmButton(
            onPressed: onComplete,
            icon: Icons.check_rounded,
            label: 'Hoàn thành',
          ),
        ],
      ],
    );
  }

  Widget _detail(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTextStyles.labelM)),
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
  }
}

class _OffsetInputDialog extends StatefulWidget {
  final String type;
  final OffsetAdjustment? initial;
  final NumberFormat money;
  final Future<String?> Function(OffsetAdjustmentInput input) onSubmit;

  const _OffsetInputDialog({
    required this.type,
    required this.initial,
    required this.money,
    required this.onSubmit,
  });

  @override
  State<_OffsetInputDialog> createState() => _OffsetInputDialogState();
}

class _OffsetInputDialogState extends State<_OffsetInputDialog> {
  late final TextEditingController _oldOrderController;
  late final TextEditingController _newOrderController;
  late final TextEditingController _orderController;
  late final TextEditingController _scanDateController;
  late final TextEditingController _transactionController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  String _editContentKind = OffsetEditContentKind.customer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _oldOrderController = TextEditingController(
      text: initial?.oldOrderCode ?? '',
    );
    _newOrderController = TextEditingController(
      text: initial?.newOrderCode ?? '',
    );
    _orderController = TextEditingController(text: initial?.orderCode ?? '');
    _scanDateController = TextEditingController(
      text: _displayDateText(initial?.scanDate) ?? _todayText(),
    );
    _transactionController = TextEditingController(
      text: initial?.transactionCode ?? '',
    );
    _amountController = TextEditingController(
      text: initial == null || initial.amount <= 0
          ? ''
          : widget.money.format(initial.amount),
    );
    _noteController = TextEditingController(text: initial?.note ?? '');
    _editContentKind =
        initial?.editContentKind ?? OffsetEditContentKind.customer;
  }

  @override
  void dispose() {
    _oldOrderController.dispose();
    _newOrderController.dispose();
    _orderController.dispose();
    _scanDateController.dispose();
    _transactionController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.type == OffsetAdjustmentType.singleOrder;
    final dialogWidth = math.max(
      280.0,
      math.min(MediaQuery.sizeOf(context).width - 48, 760.0),
    );
    final useTwoColumns = dialogWidth >= 640;
    final gap = useTwoColumns ? 12.0 : 0.0;
    final halfWidth = (dialogWidth - gap) / 2;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? OffsetAdjustmentType.label(widget.type)
            : 'Sửa ${OffsetAdjustmentType.label(widget.type)}',
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Wrap(
            spacing: gap,
            runSpacing: 12,
            children: [
              if (isSingle) ...[
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: _field(_oldOrderController, 'Đơn hàng cũ'),
                ),
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: _field(_newOrderController, 'Đơn hàng mới'),
                ),
              ] else ...[
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: _field(_orderController, 'Đơn hàng'),
                ),
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: _dateField(_scanDateLabel(widget.type)),
                ),
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: AppCombobox<String>.single(
                    value: _editContentKind,
                    label: 'Nội dung cần sửa',
                    icon: Icons.edit_note_rounded,
                    options: OffsetEditContentKind.values
                        .map(
                          (kind) => AppComboboxOption(
                            value: kind,
                            label: OffsetEditContentKind.label(kind),
                          ),
                        )
                        .toList(),
                    allowClear: false,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _editContentKind = value);
                      }
                    },
                  ),
                ),
                _dialogField(
                  width: useTwoColumns ? halfWidth : dialogWidth,
                  child: _field(_transactionController, 'Mã giao dịch'),
                ),
              ],
              _dialogField(
                width: useTwoColumns ? halfWidth : dialogWidth,
                child: AppTextInput(
                  controller: _amountController,
                  label: 'Số tiền',
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                ),
              ),
              _dialogField(
                width: dialogWidth,
                child: _field(_noteController, 'Ghi chú', maxLines: 3),
              ),
            ],
          ),
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppDialogConfirmButton(
          onPressed: _saving ? null : _submit,
          icon: Icons.save_rounded,
          label: 'Lưu',
          isLoading: _saving,
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return AppTextInput(
      controller: controller,
      label: label,
      maxLines: maxLines,
    );
  }

  Widget _dialogField({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }

  Widget _dateField(String label) {
    return AppDateTextField(
      controller: _scanDateController,
      label: label,
      onPickDate: _pickScanDate,
    );
  }

  Future<void> _pickScanDate() async {
    final typedDate = appParseDateInput(_scanDateController.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: typedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _scanDateController.text = appFormatDateInput(picked);
    });
  }

  Future<void> _submit() async {
    final amount =
        int.tryParse(
          _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
        ) ??
        0;
    if (amount <= 0) {
      _showSnack('Vui lòng nhập số tiền.');
      return;
    }
    final isSingle = widget.type == OffsetAdjustmentType.singleOrder;
    if (isSingle &&
        _oldOrderController.text.trim() == _newOrderController.text.trim()) {
      _showSnack('Mã đơn cũ và mã đơn mới không được trùng nhau.');
      return;
    }
    if (isSingle &&
        (_oldOrderController.text.trim().isEmpty ||
            _newOrderController.text.trim().isEmpty)) {
      _showSnack('Vui lòng nhập đủ mã đơn.');
      return;
    }
    if (!isSingle &&
        (_orderController.text.trim().isEmpty ||
            _scanDateController.text.trim().isEmpty ||
            _transactionController.text.trim().isEmpty)) {
      _showSnack('Vui lòng nhập đủ thông tin.');
      return;
    }
    setState(() => _saving = true);
    final error = await widget.onSubmit(
      OffsetAdjustmentInput(
        type: widget.type,
        amount: amount,
        oldOrderCode: _oldOrderController.text,
        newOrderCode: _newOrderController.text,
        orderCode: _orderController.text,
        scanDate: _scanDateController.text,
        editContentKind: _editContentKind,
        transactionCode: _transactionController.text,
        note: _noteController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      _showSnack(error);
    }
  }

  void _showSnack(String message) {
    AppToast.show(context, SnackBar(content: Text(message)));
  }

  String _todayText() => appFormatDateInput(DateTime.now());

  String? _displayDateText(String? value) {
    final parsed = value == null ? null : appParseDateInput(value);
    return parsed == null ? null : appFormatDateInput(parsed);
  }
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat formatter = NumberFormat.decimalPattern('vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final formatted = formatter.format(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

Color _statusColor(String status) {
  return switch (status) {
    OffsetAdjustmentStatus.approved => AppColors.success,
    OffsetAdjustmentStatus.rejected => AppColors.warning,
    _ => AppColors.error,
  };
}

IconData _typeIcon(String type) {
  return switch (type) {
    OffsetAdjustmentType.singleOrder => Icons.swap_calls_rounded,
    OffsetAdjustmentType.vnpayQroff => Icons.qr_code_2_rounded,
    OffsetAdjustmentType.zaloPay => Icons.account_balance_wallet_outlined,
    OffsetAdjustmentType.shopeePay => Icons.shopping_bag_outlined,
    _ => Icons.dataset_outlined,
  };
}

String _scanDateLabel(String type) {
  return switch (type) {
    OffsetAdjustmentType.vnpayQroff => 'Ngày quét QR',
    OffsetAdjustmentType.zaloPay => 'Ngày quét Zalo Pay',
    OffsetAdjustmentType.shopeePay => 'Ngày quét Shopee Pay',
    _ => 'Ngày quét',
  };
}
