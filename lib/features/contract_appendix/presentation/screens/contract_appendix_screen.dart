import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_pagination.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../domain/contract_appendix.dart';
import '../providers/contract_appendix_provider.dart';

/// Contract Appendix follows the approved OPS-209 R2 node map.
///
/// The shell (rail/sidebar/top bar) remains owned by [AppShell]. This screen
/// owns the R2 command card, state feedback, ERP preview/editor, and history
/// surface so the same interaction works in standalone widget tests and in
/// the authenticated route.
class ContractAppendixScreen extends StatefulWidget {
  const ContractAppendixScreen({super.key});

  @override
  State<ContractAppendixScreen> createState() => _ContractAppendixScreenState();
}

class _ContractAppendixScreenState extends State<ContractAppendixScreen>
    with SingleTickerProviderStateMixin {
  final _orderController = TextEditingController();
  final _historyController = TextEditingController();
  final _orderFocusNode = FocusNode();
  late final TabController _tabController;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ContractAppendixProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderController.dispose();
    _historyController.dispose();
    _orderFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContractAppendixProvider>();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: AppColors.canvasOf(context),
      child: AppResponsiveScrollView(
        maxWidth: AppLayoutTokens.commandWorkspaceMaxWidth,
        padding: _pagePadding(viewportWidth),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          key: const Key('contract-appendix-workspace'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(
              key: const Key('contract-appendix-workspace-header'),
              tabController: _tabController,
              onTab: _onTab,
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => _tabController.index == 0
                  ? _CreateWorkspace(
                      orderController: _orderController,
                      orderFocusNode: _orderFocusNode,
                      provider: provider,
                      showToast: _showToast,
                    )
                  : _HistoryWorkspace(
                      searchController: _historyController,
                      provider: provider,
                      showToast: _showToast,
                      openDetail: _openHistoryDetail,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static EdgeInsets _pagePadding(double width) {
    if (width < AppLayoutTokens.compactBreakpoint) {
      return const EdgeInsets.fromLTRB(16, 8, 16, 24);
    }
    if (width >= AppLayoutTokens.commandWorkspaceMaxWidth) {
      return const EdgeInsets.fromLTRB(32, 16, 32, 24);
    }
    return const EdgeInsets.fromLTRB(24, 16, 24, 24);
  }

  void _onTab(int index) {
    if (index != 1 || _historyLoaded) return;
    _historyLoaded = true;
    context.read<ContractAppendixProvider>().loadHistory(page: 0);
  }

  void _showToast(String message, {bool error = false}) {
    AppToast.show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? AppColors.errorOf(context)
            : AppColors.successOf(context),
      ),
    );
  }

  Future<void> _openHistoryDetail(String id) async {
    final provider = context.read<ContractAppendixProvider>();
    final ok = await provider.openHistoryDetail(id);
    if (!mounted) return;
    if (!ok || provider.historyDetail == null) {
      _showToast(provider.errorMessage ?? 'Chưa mở được phụ lục.', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider.value(
        value: provider,
        child: _HistoryDetailDialog(showToast: _showToast),
      ),
    );
    provider.clearHistoryDetail();
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final TabController tabController;
  final ValueChanged<int> onTab;

  const _WorkspaceHeader({
    super.key,
    required this.tabController,
    required this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Phụ lục hợp đồng',
            style: AppTextStyles.headingM.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
        _ViewTabBar(controller: tabController, onTab: onTab),
      ],
    );
  }
}

class _ViewTabBar extends StatelessWidget {
  final TabController controller;
  final ValueChanged<int> onTab;

  const _ViewTabBar({required this.controller, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: AppRadius.allMd,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ViewTab(
                label: 'Tạo mới',
                selected: controller.index == 0,
                onTap: () {
                  controller.animateTo(0);
                  onTab(0);
                },
              ),
              _ViewTab(
                label: 'Lịch sử',
                selected: controller.index == 1,
                onTap: () {
                  controller.animateTo(1);
                  onTab(1);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ViewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? AppColors.primaryOf(context)
        : AppColors.textSecondaryOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.primarySurfaceOf(context)
            : AppColors.transparent,
        borderRadius: AppRadius.allMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              label,
              style: AppTextStyles.labelS.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateWorkspace extends StatelessWidget {
  final TextEditingController orderController;
  final FocusNode orderFocusNode;
  final ContractAppendixProvider provider;
  final void Function(String message, {bool error}) showToast;

  const _CreateWorkspace({
    required this.orderController,
    required this.orderFocusNode,
    required this.provider,
    required this.showToast,
  });

  @override
  Widget build(BuildContext context) {
    final hasDraft = provider.draft != null;
    final showEmptyPreview =
        !hasDraft && !provider.isLookingUp && provider.errorMessage == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrderCommandArea(
          controller: orderController,
          focusNode: orderFocusNode,
          provider: provider,
          onAdd: () => _addOrder(context),
          onFetch: () => _fetch(context),
          onReset: () => _confirmReset(context),
        ),
        if (provider.isLookingUp) ...[
          const SizedBox(height: 12),
          const _R2StatusCard(
            tone: _R2StatusTone.info,
            title: 'Đang lấy dữ liệu đơn hàng',
            message:
                'Đang xử lý các đơn theo thứ tự bạn thêm. Không hiển thị bảng một phần.',
          ),
        ] else if (provider.errorMessage != null) ...[
          const SizedBox(height: 12),
          _R2StatusCard(
            tone: _isValidationError(provider.errorMessage!)
                ? _R2StatusTone.warning
                : _R2StatusTone.error,
            title: _isValidationError(provider.errorMessage!)
                ? 'Cần kiểm tra danh sách'
                : 'Không thể lấy thông tin',
            message: _friendlyError(provider.errorMessage!),
          ),
        ],
        if (showEmptyPreview) ...[
          const SizedBox(height: 12),
          const _EmptyPreviewCard(),
        ],
        if (hasDraft) ...[
          const SizedBox(height: 12),
          _DocumentWorkspace(provider: provider, showToast: showToast),
        ],
      ],
    );
  }

  void _addOrder(BuildContext context) {
    final ok = provider.addOrderCode(orderController.text);
    if (ok) {
      orderController.clear();
      if (context.mounted) orderFocusNode.requestFocus();
      return;
    }
    if (context.mounted) orderFocusNode.requestFocus();
  }

  Future<void> _fetch(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await provider.fetchOrders();
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Chọn lại đơn hàng?'),
        content: const Text(
          'Tập đơn hiện tại và bản nháp sẽ được đặt lại. Bản đã lưu vẫn còn trong lịch sử.',
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            label: 'Hủy',
          ),
          SizedBox(
            width: 112,
            height: 40,
            child: AppPrimaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              label: 'Chọn lại',
              size: AppButtonSize.small,
              height: 40,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      provider.resetOrderSelection();
      orderController.clear();
      orderFocusNode.requestFocus();
    }
  }
}

class _OrderCommandArea extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ContractAppendixProvider provider;
  final VoidCallback onAdd;
  final VoidCallback onFetch;
  final VoidCallback onReset;

  const _OrderCommandArea({
    required this.controller,
    required this.focusNode,
    required this.provider,
    required this.onAdd,
    required this.onFetch,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        final wide = constraints.maxWidth >= 1000;
        final command = _OrderCommandCard(
          controller: controller,
          focusNode: focusNode,
          provider: provider,
          compact: compact,
          onAdd: onAdd,
          onFetch: onFetch,
          onReset: onReset,
        );
        if (!wide) return command;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 710, child: command),
            const SizedBox(width: 24),
            Expanded(flex: 392, child: _OrderSummaryCard(provider: provider)),
          ],
        );
      },
    );
  }
}

class _OrderCommandCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ContractAppendixProvider provider;
  final bool compact;
  final VoidCallback onAdd;
  final VoidCallback onFetch;
  final VoidCallback onReset;

  const _OrderCommandCard({
    required this.controller,
    required this.focusNode,
    required this.provider,
    required this.compact,
    required this.onAdd,
    required this.onFetch,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final locked = provider.isOrderSelectionLocked;
    final busy = provider.isLookingUp;
    final selected = provider.selectedOrderCodes;
    final validationError =
        provider.errorMessage != null &&
        _isValidationError(provider.errorMessage!);
    final input = AppTextInput(
      key: const Key('contract-appendix-order-input'),
      controller: controller,
      focusNode: focusNode,
      enabled: !locked && !busy,
      readOnly: locked || busy,
      autocorrect: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onAdd(),
      label: 'Mã đơn hàng',
      hintText: 'DH-240819-001',
      suffixIcon: Icon(
        PhosphorIconsRegular.magnifyingGlass,
        size: 20,
        color: AppColors.textSecondaryOf(context),
      ),
      fixedHeight: 48,
      dense: true,
      borderColor: validationError ? AppColors.errorOf(context) : null,
    );
    final addButton = SizedBox(
      width: compact ? 108 : 112,
      height: 48,
      child: AppSecondaryButton(
        key: const Key('contract-appendix-add-order-button'),
        onPressed: locked || busy ? null : onAdd,
        label: 'Thêm đơn',
        size: AppButtonSize.medium,
        height: 48,
        radius: AppRadius.md,
        padding: EdgeInsets.zero,
      ),
    );
    final fetchButton = SizedBox(
      width: compact ? double.infinity : 180,
      height: 48,
      child: AppPrimaryButton(
        key: const Key('contract-appendix-fetch-button'),
        onPressed: busy
            ? null
            : locked
            ? onReset
            : provider.canFetchOrders
            ? onFetch
            : null,
        label: busy
            ? 'Đang lấy thông tin…'
            : locked
            ? 'Chọn lại đơn hàng'
            : 'Lấy thông tin (${selected.length} đơn)',
        isLoading: busy,
        loadingLabel: 'Đang lấy thông tin…',
        size: AppButtonSize.medium,
        height: 48,
        radius: AppRadius.md,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
    return AppSurfaceCard(
      key: const Key('contract-appendix-order-command-row'),
      padding: EdgeInsets.all(compact ? 15 : 19),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'DỮ LIỆU NGUỒN',
            style: AppTextStyles.captionBold.copyWith(
              color: AppColors.primaryOf(context),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tạo phụ lục hợp đồng',
            style: AppTextStyles.headingM.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontSize: compact ? 20 : 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            compact
                ? 'Thêm tối đa 10 đơn hàng trước khi lấy thông tin.'
                : 'Thêm tối đa 10 đơn hàng theo đúng thứ tự bạn nhập trước khi bấm lấy thông tin.',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          if (compact) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: input),
                const SizedBox(width: 8),
                addButton,
              ],
            ),
            const SizedBox(height: 8),
            fetchButton,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: input),
                const SizedBox(width: 12),
                addButton,
                const SizedBox(width: 12),
                fetchButton,
              ],
            ),
          const SizedBox(height: 16),
          Text(
            'Đơn đã chọn  ${selected.length}/${ContractAppendixProvider.maxOrderCodes}',
            style: AppTextStyles.labelS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OrderChipWrap(
              orderCodes: selected,
              locked: locked || busy,
              onRemove: provider.removeOrderCode,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final ContractAppendixProvider provider;

  const _OrderSummaryCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final locked = provider.isOrderSelectionLocked;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(19),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.lockKey,
                size: 24,
                color: locked
                    ? AppColors.successOf(context)
                    : AppColors.textMutedOf(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  locked ? 'Tập đơn đã khóa' : 'Tập đơn đang chọn',
                  style: AppTextStyles.labelL.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${provider.selectedOrderCodes.length}/${ContractAppendixProvider.maxOrderCodes} đơn • ${locked ? 'đã khóa.' : 'chưa lấy thông tin.'}',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          if (provider.selectedOrderCodes.isEmpty)
            Text(
              'Danh sách sẽ hiển thị tại đây.',
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textMutedOf(context),
              ),
            )
          else
            Column(
              children: [
                for (final code in provider.selectedOrderCodes) ...[
                  _LockedOrderPill(code: code),
                  const SizedBox(height: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _OrderChipWrap extends StatelessWidget {
  final List<String> orderCodes;
  final bool locked;
  final bool Function(String) onRemove;

  const _OrderChipWrap({
    required this.orderCodes,
    required this.locked,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final code in orderCodes)
          _OrderChip(
            key: ValueKey('contract-appendix-order-chip-$code'),
            code: code,
            locked: locked,
            onRemove: () => onRemove(code),
          ),
      ],
    );
  }
}

class _OrderChip extends StatelessWidget {
  final String code;
  final bool locked;
  final VoidCallback onRemove;

  const _OrderChip({
    super.key,
    required this.code,
    required this.locked,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final selected = !locked;
    return Container(
      constraints: const BoxConstraints(minHeight: 32, minWidth: 104),
      padding: const EdgeInsets.only(left: 11, right: 4),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primarySurfaceOf(context)
            : AppColors.neutral100Of(context),
        border: Border.all(
          color: selected
              ? AppColors.primaryOf(context)
              : AppColors.borderOf(context),
        ),
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelS.copyWith(
                color: selected
                    ? AppColors.primaryOf(context)
                    : AppColors.textSecondaryOf(context),
              ),
            ),
          ),
          if (!locked)
            SizedBox(
              width: 28,
              height: 32,
              child: IconButton(
                tooltip: 'Xóa $code',
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: Icon(
                  PhosphorIconsRegular.x,
                  size: 18,
                  color: AppColors.primaryOf(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LockedOrderPill extends StatelessWidget {
  final String code;

  const _LockedOrderPill({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: AppColors.neutral100Of(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: AppRadius.allPill,
      ),
      child: Text(
        code,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.labelS.copyWith(
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }
}

class _EmptyPreviewCard extends StatelessWidget {
  const _EmptyPreviewCard();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('contract-appendix-empty-preview'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      radius: AppRadius.lg,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Xem trước phụ lục',
              style: AppTextStyles.labelL.copyWith(
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ),
          const SizedBox(height: 48),
          Icon(
            PhosphorIconsRegular.info,
            size: 24,
            color: AppColors.textSecondaryOf(context),
          ),
          const SizedBox(height: 16),
          Text(
            'Bảng sẽ xuất hiện sau khi lấy thông tin',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Thành tiền từng dòng sẽ lấy chính xác từ tổng dòng hệ thống bán hàng.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textMutedOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

enum _R2StatusTone { info, warning, error }

class _R2StatusCard extends StatelessWidget {
  final _R2StatusTone tone;
  final String title;
  final String message;

  const _R2StatusCard({
    required this.tone,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final (surface, foreground, icon) = switch (tone) {
      _R2StatusTone.info => (
        AppColors.infoSurfaceOf(context),
        AppColors.infoOf(context),
        PhosphorIconsRegular.info,
      ),
      _R2StatusTone.warning => (
        AppColors.warningSurfaceOf(context),
        AppColors.warningOf(context),
        PhosphorIconsRegular.warningCircle,
      ),
      _R2StatusTone.error => (
        AppColors.errorSurfaceOf(context),
        AppColors.errorOf(context),
        PhosphorIconsRegular.warningCircle,
      ),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(color: surface, borderRadius: AppRadius.allMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.labelM.copyWith(color: foreground),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentWorkspace extends StatelessWidget {
  final ContractAppendixProvider provider;
  final void Function(String message, {bool error}) showToast;

  const _DocumentWorkspace({required this.provider, required this.showToast});

  @override
  Widget build(BuildContext context) {
    final document = provider.draft!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (document.unresolvedTaxCount > 0) ...[
          _R2StatusCard(
            tone: _R2StatusTone.warning,
            title: 'Cần chọn thuế',
            message:
                'Chưa xác định được thuế cho ${document.unresolvedTaxCount} sản phẩm. Chọn thuế nhập tay trước khi lưu.',
          ),
          const SizedBox(height: 12),
        ],
        ContractAppendixPreviewCard(document: document, provider: provider),
        const SizedBox(height: 12),
        _DocumentActions(provider: provider, showToast: showToast),
      ],
    );
  }
}

class _DocumentActions extends StatelessWidget {
  final ContractAppendixProvider provider;
  final void Function(String message, {bool error}) showToast;

  const _DocumentActions({required this.provider, required this.showToast});

  @override
  Widget build(BuildContext context) {
    final busy = provider.isBusy || provider.isCopying;
    return AppSurfaceCard(
      key: const Key('contract-appendix-actions'),
      padding: const EdgeInsets.all(12),
      radius: AppRadius.lg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final children = [
            AppSecondaryButton(
              key: const Key('contract-appendix-refresh-button'),
              onPressed: busy ? null : () => _refresh(context),
              icon: PhosphorIconsRegular.arrowsClockwise,
              label: 'Cập nhật bảng',
              isLoading: provider.isRefreshingPreview,
              loadingLabel: 'Đang cập nhật',
              size: AppButtonSize.medium,
              height: 48,
              expand: !compact,
            ),
            AppPrimaryButton(
              key: const Key('contract-appendix-save-button'),
              onPressed: busy ? null : () => _save(context),
              icon: PhosphorIconsRegular.floppyDisk,
              label: 'Lưu phụ lục',
              isLoading: provider.isSaving,
              loadingLabel: 'Đang lưu',
              size: AppButtonSize.medium,
              height: 48,
            ),
            AppSecondaryButton(
              key: const Key('contract-appendix-copy-button'),
              onPressed: provider.canCopy && !provider.isCopying
                  ? () => _copy(context)
                  : null,
              icon: PhosphorIconsRegular.copy,
              label: 'Sao chép Word',
              isLoading: provider.isCopying,
              loadingLabel: 'Đang sao chép',
              size: AppButtonSize.medium,
              height: 48,
              expand: !compact,
            ),
          ];
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      children[i],
                    ],
                    if (!provider.canCopy) ...[
                      const SizedBox(height: 8),
                      Text(
                        provider.copyDisabledReason,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: children[i]),
                    ],
                  ],
                );
        },
      ),
    );
  }

  Future<void> _refresh(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await provider.refreshPreview();
    if (!context.mounted) return;
    showToast(
      ok
          ? provider.successMessage ?? 'Đã cập nhật bảng xem trước.'
          : provider.errorMessage ?? 'Chưa cập nhật được bảng.',
      error: !ok,
    );
  }

  Future<void> _save(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await provider.saveCurrent();
    if (!context.mounted) return;
    showToast(
      ok
          ? provider.successMessage ?? 'Đã lưu phụ lục.'
          : provider.errorMessage ?? 'Chưa lưu được phụ lục.',
      error: !ok,
    );
  }

  Future<void> _copy(BuildContext context) async {
    final ok = await provider.copySaved();
    if (!context.mounted) return;
    showToast(
      ok
          ? provider.successMessage ?? 'Đã sao chép bảng.'
          : provider.errorMessage ?? 'Chưa sao chép được bảng.',
      error: !ok,
    );
  }
}

class ContractAppendixPreviewCard extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider? provider;

  const ContractAppendixPreviewCard({
    super.key,
    required this.document,
    this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        return AppSurfaceCard(
          key: const Key('contract-appendix-preview-card'),
          padding: EdgeInsets.fromLTRB(
            compact ? 15 : 19,
            compact ? 15 : 19,
            compact ? 15 : 19,
            compact ? 18 : 19,
          ),
          radius: AppRadius.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Xem trước phụ lục',
                      style: AppTextStyles.labelL.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.successSurfaceOf(context),
                      borderRadius: AppRadius.allPill,
                    ),
                    child: Text(
                      '${document.orderCodes.length} đơn • đã khóa',
                      style: AppTextStyles.captionBold.copyWith(
                        color: AppColors.successOf(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                compact
                    ? 'Dữ liệu đã đối soát; tên hàng, ĐVT và số lượng đang khóa.'
                    : 'Bảng Word 6 cột • thành tiền từng dòng lấy từ tổng dòng hệ thống bán hàng • phần tổng luôn khớp.',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 16),
              if (compact)
                _MobilePreview(document: document, provider: provider)
              else
                _DesktopPreview(document: document, provider: provider),
            ],
          ),
        );
      },
    );
  }
}

class _MobilePreview extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider? provider;

  const _MobilePreview({required this.document, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < document.items.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _MobilePreviewLine(
            key: ValueKey(
              'contract-appendix-item-${document.items[index].sourceLineKey}',
            ),
            item: document.items[index],
            provider: provider,
          ),
        ],
        const SizedBox(height: 16),
        Divider(height: 1, color: AppColors.subtleBorderOf(context)),
        const SizedBox(height: 12),
        _TotalAfterVat(document: document),
        const SizedBox(height: 8),
        _AmountInWords(document: document),
      ],
    );
  }
}

class _MobilePreviewLine extends StatelessWidget {
  final ContractAppendixItem item;
  final ContractAppendixProvider? provider;

  const _MobilePreviewLine({
    super.key,
    required this.item,
    required this.provider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neutral50Of(context),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LockedPreviewValue(
                  value: item.productName,
                  label: 'Tên hàng hóa',
                  textStyle: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _moneyOrDash(item.lineAfterVat),
                textAlign: TextAlign.right,
                style: AppTextStyles.labelL.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'SL ${item.quantity}  •  ',
                style: AppTextStyles.bodyCompact.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              Flexible(
                child: _LockedPreviewValue(
                  value: item.unit,
                  label: 'Đơn vị tính',
                  textStyle: AppTextStyles.bodyCompact.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          if (item.canEnterManualTax && provider != null) ...[
            const SizedBox(height: 8),
            _TaxField(item: item, provider: provider!),
          ],
        ],
      ),
    );
  }
}

class _DesktopPreview extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider? provider;

  const _DesktopPreview({required this.document, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContractAppendixPreviewTable(document: document, provider: provider),
        if (document.items.any((item) => item.canEnterManualTax) &&
            provider != null) ...[
          const SizedBox(height: 12),
          for (final item in document.items.where(
            (item) => item.canEnterManualTax,
          )) ...[
            _TaxField(item: item, provider: provider!),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class ContractAppendixPreviewTable extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider? provider;

  const ContractAppendixPreviewTable({
    super.key,
    required this.document,
    this.provider,
  });

  @override
  Widget build(BuildContext context) {
    const widths = <int, TableColumnWidth>{
      0: FlexColumnWidth(0.65),
      1: FlexColumnWidth(4.6),
      2: FlexColumnWidth(0.9),
      3: FlexColumnWidth(0.7),
      4: FlexColumnWidth(1.8),
      5: FlexColumnWidth(2.0),
    };
    return Column(
      key: const Key('contract-appendix-preview-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: widths,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder.all(color: AppColors.borderOf(context)),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: AppColors.primarySurfaceOf(context),
              ),
              children: const [
                _R2TableCell('STT', header: true, center: true),
                _R2TableCell('Tên hàng', header: true, wrap: true),
                _R2TableCell('ĐVT', header: true, center: true),
                _R2TableCell('SL', header: true, center: true),
                _R2TableCell('Đơn giá', header: true, center: true),
                _R2TableCell('Thành tiền', header: true, center: true),
              ],
            ),
            for (final item in document.items)
              TableRow(
                decoration: BoxDecoration(
                  color: AppColors.neutral50Of(context),
                ),
                children: [
                  _R2TableCell('${item.position}', center: true),
                  _R2TableCell(
                    item.productName,
                    wrap: true,
                    locked: true,
                    lockLabel: 'Tên hàng hóa',
                  ),
                  _R2TableCell(
                    item.unit,
                    center: true,
                    locked: true,
                    lockLabel: 'Đơn vị tính',
                  ),
                  _R2TableCell('${item.quantity}', center: true),
                  _R2TableCell(
                    _moneyOrDash(item.unitPriceBeforeVat),
                    center: true,
                  ),
                  _R2TableCell(_moneyOrDash(item.lineAfterVat), center: true),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        _WordPreviewSummary(document: document),
      ],
    );
  }
}

class _R2TableCell extends StatelessWidget {
  final String text;
  final bool header;
  final bool center;
  final bool wrap;
  final bool locked;
  final String? lockLabel;

  const _R2TableCell(
    this.text, {
    this.header = false,
    this.center = false,
    this.wrap = false,
    this.locked = false,
    this.lockLabel,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle =
        (header ? AppTextStyles.captionBold : AppTextStyles.bodyCompact)
            .copyWith(
              color: header
                  ? AppColors.primaryOf(context)
                  : AppColors.textSecondaryOf(context),
            );
    final textWidget = Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      softWrap: wrap,
      textWidthBasis: TextWidthBasis.parent,
      maxLines: wrap ? null : (header ? 2 : 3),
      overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
      style: textStyle,
    );
    final content = locked
        ? Semantics(
            label: '${lockLabel ?? text}: $text (đang khóa)',
            readOnly: true,
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: center
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    PhosphorIconsRegular.lockSimple,
                    size: 13,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(child: textWidget),
              ],
            ),
          )
        : textWidget;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: content,
    );
  }
}

class _LockedPreviewValue extends StatelessWidget {
  final String value;
  final String label;
  final TextStyle? textStyle;

  const _LockedPreviewValue({
    required this.value,
    required this.label,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value (đang khóa)',
      readOnly: true,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              PhosphorIconsRegular.lockSimple,
              size: 14,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              softWrap: true,
              style: textStyle ?? AppTextStyles.bodyS,
            ),
          ),
        ],
      ),
    );
  }
}

class _WordPreviewSummary extends StatelessWidget {
  final ContractAppendixDocument document;

  const _WordPreviewSummary({required this.document});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          _WordPreviewSummaryRow(
            label: 'Tổng cộng',
            value: _moneyOrDash(document.totalBeforeVat),
          ),
          _WordPreviewSummaryRow(
            label: 'Thuế GTGT',
            value: _moneyOrDash(document.totalVatAmount),
          ),
          _WordPreviewSummaryRow(
            label: 'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)',
            value: _moneyOrDash(document.totalAfterVat),
            emphasized: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _AmountInWords(document: document),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordPreviewSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _WordPreviewSummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = emphasized
        ? AppColors.primarySurfaceOf(context)
        : AppColors.neutral50Of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyCompact.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.bodyCompact.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxField extends StatelessWidget {
  final ContractAppendixItem item;
  final ContractAppendixProvider provider;

  const _TaxField({required this.item, required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppCombobox<int>.single(
      key: ValueKey('tax-${item.sourceLineKey}-${item.vatRateBps}'),
      value: item.vatRateBps,
      label: item.taxSource == 'MANUAL' ? 'Thuế nhập tay' : 'Chọn thuế',
      helperText: item.taxSource == 'MANUAL' ? 'Thuế nhập tay' : null,
      hintText: 'Chọn mức thuế',
      dense: true,
      allowClear: false,
      options: [
        for (final rate in ContractAppendixProvider.manualVatRates)
          AppComboboxOption(value: rate, label: '${rate ~/ 100}%'),
      ],
      onChanged: (value) =>
          provider.updateManualVatRate(item.sourceLineKey, value),
    );
  }
}

class _TotalAfterVat extends StatelessWidget {
  final ContractAppendixDocument document;

  const _TotalAfterVat({required this.document});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Tổng sau VAT',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
        Text(
          _moneyOrDash(document.totalAfterVat),
          textAlign: TextAlign.right,
          style: AppTextStyles.headingS.copyWith(
            color: AppColors.primaryOf(context),
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _AmountInWords extends StatelessWidget {
  final ContractAppendixDocument document;

  const _AmountInWords({required this.document});

  @override
  Widget build(BuildContext context) {
    return Text(
      key: const Key('contract-appendix-amount-in-words'),
      document.amountInWords == null
          ? 'Bằng chữ: Chưa đủ dữ liệu để tính.'
          : 'Bằng chữ: ${document.amountInWords}',
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textSecondaryOf(context),
      ),
    );
  }
}

class _HistoryWorkspace extends StatelessWidget {
  final TextEditingController searchController;
  final ContractAppendixProvider provider;
  final void Function(String message, {bool error}) showToast;
  final ValueChanged<String> openDetail;

  const _HistoryWorkspace({
    required this.searchController,
    required this.provider,
    required this.showToast,
    required this.openDetail,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('contract-appendix-history-surface'),
      padding: const EdgeInsets.all(15),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Lịch sử phụ lục',
            style: AppTextStyles.headingM.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chỉ hiển thị bản đã lưu trong 30 ngày.',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final input = AppTextInput(
                key: const Key('contract-appendix-history-search-input'),
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(context),
                label: 'Tìm theo mã đơn',
                hintText: 'DH-240819-001',
                suffixIcon: Icon(
                  PhosphorIconsRegular.magnifyingGlass,
                  size: 20,
                  color: AppColors.textSecondaryOf(context),
                ),
                fixedHeight: 48,
                dense: true,
              );
              final button = SizedBox(
                width: compact ? double.infinity : 132,
                height: 48,
                child: AppPrimaryButton(
                  onPressed: provider.isLoadingHistory
                      ? null
                      : () => _search(context),
                  label: 'Tìm kiếm',
                  isLoading: provider.isLoadingHistory,
                  loadingLabel: 'Đang tìm',
                  size: AppButtonSize.medium,
                  height: 48,
                ),
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [input, const SizedBox(height: 8), button],
                    )
                  : Row(
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 12),
                        button,
                      ],
                    );
            },
          ),
          const SizedBox(height: 16),
          if (provider.isLoadingHistory && provider.history.isEmpty)
            const _HistoryStateCard(
              icon: PhosphorIconsRegular.spinnerGap,
              title: 'Đang tải lịch sử',
              message: 'Đang lấy các phụ lục đã lưu.',
            )
          else if (provider.history.isEmpty)
            const _HistoryStateCard(
              icon: PhosphorIconsRegular.clockCounterClockwise,
              title: 'Chưa có phụ lục trong 30 ngày',
              message: 'Các phụ lục đã lưu sẽ xuất hiện tại đây.',
            )
          else ...[
            for (var index = 0; index < provider.history.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _HistoryCard(
                item: provider.history[index],
                onOpen: () => openDetail(provider.history[index].id),
                busy: provider.isLoadingHistoryDetail,
              ),
            ],
            const SizedBox(height: 12),
            AppPaginationControls(
              pageIndex: provider.historyPage,
              totalItems: provider.historyTotal,
              itemLabel: 'phụ lục',
              onPrevious: provider.canGoHistoryPrevious
                  ? () => provider.loadHistory(page: provider.historyPage - 1)
                  : null,
              onNext: provider.historyHasMore
                  ? () => provider.loadHistory(page: provider.historyPage + 1)
                  : null,
              onRefresh: () => provider.loadHistory(page: provider.historyPage),
              isRefreshing: provider.isLoadingHistory,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _search(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await provider.loadHistory(
      query: searchController.text,
      page: 0,
    );
    if (!context.mounted || ok) return;
    showToast(provider.errorMessage ?? 'Chưa tải được lịch sử.', error: true);
  }
}

class _HistoryStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _HistoryStateCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.neutral50Of(context),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: AppColors.textSecondaryOf(context)),
          const SizedBox(height: 12),
          Text(title, style: AppTextStyles.labelM),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final ContractAppendixHistoryItem item;
  final VoidCallback onOpen;
  final bool busy;

  const _HistoryCard({
    required this.item,
    required this.onOpen,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final date = item.createdAt == null
        ? 'Không rõ thời gian'
        : DateFormat('dd/MM/yyyy').format(item.createdAt!.toLocal());
    final codes = item.orderCodes.isNotEmpty
        ? item.orderCodes.join(' · ')
        : item.orderCode;
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neutral50Of(context),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIconsRegular.fileText,
                size: 20,
                color: AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  codes,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${item.orderCodes.length} đơn hàng • $date • ${_money(item.totalAfterVat)}',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 92,
              height: 48,
              child: AppSecondaryButton(
                onPressed: busy ? null : onOpen,
                label: 'Xem',
                size: AppButtonSize.medium,
                height: 48,
                radius: AppRadius.md,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryDetailDialog extends StatelessWidget {
  final void Function(String message, {bool error}) showToast;

  const _HistoryDetailDialog({required this.showToast});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContractAppendixProvider>();
    final document = provider.historyDetail!;
    final media = MediaQuery.sizeOf(context);
    final codes = document.orderCodes.isNotEmpty
        ? document.orderCodes.join(' · ')
        : document.orderCode;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: math.min(1120, media.width - 32),
        height: math.min(760, media.height - 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phụ lục $codes',
                          style: AppTextStyles.headingS,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Bản đã lưu · chỉ đọc',
                          style: AppTextStyles.bodyS.copyWith(
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsRegular.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: ContractAppendixPreviewTable(document: document),
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppDialogCancelButton(
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'Đóng',
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 190,
                    child: AppPrimaryButton(
                      onPressed: provider.isCopying
                          ? null
                          : () => _copy(context, provider),
                      icon: PhosphorIconsRegular.copy,
                      label: 'Sao chép Word',
                      isLoading: provider.isCopying,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(
    BuildContext context,
    ContractAppendixProvider provider,
  ) async {
    final ok = await provider.copyHistoryDetail();
    if (!context.mounted) return;
    showToast(
      ok
          ? provider.successMessage ?? 'Đã sao chép bảng.'
          : provider.errorMessage ?? 'Chưa sao chép được bảng.',
      error: !ok,
    );
  }
}

String _money(int value) => vietnameseMoneyNumberFormat.format(value);

String _moneyOrDash(int? value) =>
    value == null ? '—' : vietnameseMoneyNumberFormat.format(value);

bool _isValidationError(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('đã có') ||
      normalized.contains('tối đa') ||
      normalized.contains('vui lòng nhập');
}

String _friendlyError(String message) {
  final trimmed = message.trim();
  if (trimmed.isEmpty) return 'Vui lòng kiểm tra danh sách và thử lại.';
  return trimmed;
}
