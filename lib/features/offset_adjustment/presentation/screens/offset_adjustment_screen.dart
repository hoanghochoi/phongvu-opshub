import 'dart:math' as math;

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
import '../../domain/offset_adjustment.dart';
import '../providers/offset_adjustment_provider.dart';

const _breakpoint = 720.0;

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
              ? AppResponsiveScrollView(child: _workspace(provider, compact))
              : AppResponsiveContent(child: _workspace(provider, compact)),
        );
      },
    );
  }

  Widget _workspace(OffsetAdjustmentProvider provider, bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OffsetHeader(
          key: const Key('offset-adjustment-header'),
          provider: provider,
          onRefresh: provider.isLoading ? null : () => provider.search(),
        ),
        const SizedBox(height: AppLayoutTokens.sectionGap),
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
        const SizedBox(height: 10),
        AppSurfaceCard(
          key: const Key('offset-adjustment-toolbar'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _ListToolbar(provider: provider),
        ),
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
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
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
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OffsetInputDialog(
        type: type,
        initial: initial,
        money: _money,
        onSubmit: (input) {
          if (initial == null) return provider.create(input);
          return provider.resubmit(initial.id, input);
        },
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
      builder: (context) => AlertDialog(
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
    );
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OffsetHeader extends StatelessWidget {
  final OffsetAdjustmentProvider provider;
  final VoidCallback? onRefresh;

  const _OffsetHeader({super.key, required this.provider, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scopeLabel = provider.canReview
        ? provider.selectedStoreIds.isEmpty
              ? 'Tất cả showroom'
              : '${provider.selectedStoreIds.length} showroom'
        : provider.stores.length <= 1
        ? 'Showroom được gán'
        : '${provider.stores.length} showroom được gán';
    final statusLabel = provider.hasSearched
        ? '${provider.items.length}/${provider.total} hồ sơ'
        : 'Chưa tải dữ liệu';
    final pendingLabel = provider.canReview
        ? '${provider.pendingTotal} chờ Kế toán'
        : 'Gửi yêu cầu';
    final filterStatusLabel = provider.status == 'ALL'
        ? 'Tất cả trạng thái'
        : OffsetAdjustmentStatus.label(provider.status);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.subtleBorderOf(context)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.selected,
                borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              ),
              child: const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.teal600,
              ),
            ),
            const SizedBox(width: AppLayoutTokens.formInlineGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Yêu cầu xử lý', style: AppTextStyles.headingS),
                  const SizedBox(height: AppLayoutTokens.cardGap),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppStatusChip(
                        label: scopeLabel,
                        color: AppColors.teal600,
                        backgroundColor: AppColors.selected,
                      ),
                      AppStatusChip(
                        label: statusLabel,
                        color: AppColors.neutral700,
                        backgroundColor: AppColors.neutral100,
                      ),
                      AppStatusChip(
                        label: pendingLabel,
                        color: provider.canReview && provider.pendingTotal > 0
                            ? AppColors.warning
                            : AppColors.primary,
                        backgroundColor:
                            provider.canReview && provider.pendingTotal > 0
                            ? AppColors.warningSurface
                            : AppColors.primarySurface,
                      ),
                      AppStatusChip(
                        label: filterStatusLabel,
                        color: provider.status == OffsetAdjustmentStatus.pending
                            ? AppColors.warning
                            : AppColors.neutral700,
                        backgroundColor: provider.status == 'ALL'
                            ? AppColors.neutral100
                            : AppColors.warningSurface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppLayoutTokens.formInlineGap),
            IconButton.filledTonal(
              tooltip: 'Tải lại',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
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
                const SizedBox(height: gap),
                _FilterActions(provider: widget.provider),
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
                  ),
                ],
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
          return Wrap(
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
                ),
              ),
              SizedBox(
                width: fieldWidth,
                child: _FilterActions(provider: widget.provider),
              ),
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
    return AppMultiSelectFilterDropdown<String>(
      label: 'Showroom',
      icon: Icons.storefront_outlined,
      values: widget.provider.selectedStoreIds,
      emptyLabel: widget.provider.canReview
          ? 'Tất cả showroom'
          : 'Tất cả showroom được gán',
      forceSearch: true,
      options: widget.provider.stores
          .map(
            (store) => AppFilterOption<String>(
              value: store.storeId,
              label: store.storeId,
              subtitle: store.storeName,
            ),
          )
          .toList(growable: false),
      onChanged: (ids) => widget.provider.setStoreSelection(
        allStores: widget.provider.canReview && ids.isEmpty,
        ids: ids,
      ),
    );
  }

  Widget _typeFilter() {
    return AppSelectField<String>(
      value: widget.provider.type,
      label: 'Loại',
      icon: Icons.category_outlined,
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('Tất cả loại')),
        DropdownMenuItem(
          value: OffsetAdjustmentType.singleOrder,
          child: Text('Cấn trừ đơn'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentType.vnpayQroff,
          child: Text('VNPAY QROFF'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentType.zaloPay,
          child: Text('Zalo Pay'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentType.shopeePay,
          child: Text('Shopee Pay'),
        ),
      ],
      onChanged: (value) => widget.provider.setType(value ?? 'ALL'),
    );
  }

  Widget _statusFilter() {
    return AppSelectField<String>(
      value: widget.provider.status,
      label: 'Trạng thái',
      icon: Icons.flag_outlined,
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('Tất cả trạng thái')),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.pending,
          child: Text('Chờ Kế toán xác nhận'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.approved,
          child: Text('Kế toán đã xác nhận'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.rejected,
          child: Text('Kế toán từ chối chờ sửa'),
        ),
      ],
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

class _ListToolbar extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _ListToolbar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        SizedBox(
          width: 220,
          child: Text(
            '${provider.items.length} / ${provider.total} hồ sơ',
            style: AppTextStyles.labelM,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Trang trước',
              onPressed: provider.canGoPrevious ? provider.previousPage : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Text('${provider.page + 1}'),
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
                  child: AppSelectField<String>(
                    value: _editContentKind,
                    label: 'Nội dung cần sửa',
                    icon: Icons.edit_note_rounded,
                    items: OffsetEditContentKind.values
                        .map(
                          (kind) => DropdownMenuItem(
                            value: kind,
                            child: Text(OffsetEditContentKind.label(kind)),
                          ),
                        )
                        .toList(),
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
      Navigator.of(context).pop();
    } else {
      _showSnack(error);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
