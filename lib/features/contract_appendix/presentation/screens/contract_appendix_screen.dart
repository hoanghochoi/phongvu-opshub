import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../domain/contract_appendix.dart';
import '../providers/contract_appendix_provider.dart';

class ContractAppendixScreen extends StatefulWidget {
  const ContractAppendixScreen({super.key});

  @override
  State<ContractAppendixScreen> createState() => _ContractAppendixScreenState();
}

class _ContractAppendixScreenState extends State<ContractAppendixScreen>
    with SingleTickerProviderStateMixin {
  final _orderController = TextEditingController();
  final _historyController = TextEditingController();
  late final TabController _tabController;
  bool _historyLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ContractAppendixProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderController.dispose();
    _historyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContractAppendixProvider>();
    return AppResponsiveScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(tabController: _tabController, onTab: _onTab),
          if (provider.errorMessage != null) ...[
            const SizedBox(height: 12),
            AppStatusBanner(
              icon: Icons.error_outline_rounded,
              title: 'Chưa thực hiện được',
              message: provider.errorMessage!,
              tone: AppStateTone.error,
            ),
          ],
          if (provider.successMessage != null) ...[
            const SizedBox(height: 12),
            AppStatusBanner(
              icon: Icons.check_circle_outline_rounded,
              title: 'Đã cập nhật',
              message: provider.successMessage!,
              tone: AppStateTone.success,
            ),
          ],
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => _tabController.index == 0
                ? _CreateWorkspace(
                    orderController: _orderController,
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
    );
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
        backgroundColor: error ? AppColors.error : AppColors.success,
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

class _Header extends StatelessWidget {
  final TabController tabController;
  final ValueChanged<int> onTab;

  const _Header({required this.tabController, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primarySurfaceOf(context),
                  borderRadius: AppRadius.allMd,
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.primaryOf(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phụ lục hợp đồng',
                      style: AppTextStyles.headingM.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lấy giá bán từ hệ thống, xác định thuế và sao chép bảng '
                      'đã lưu thẳng vào Word.',
                      style: AppTextStyles.bodyM.copyWith(
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TabBar(
            controller: tabController,
            onTap: onTab,
            isScrollable: false,
            tabs: const [
              Tab(text: 'Tạo phụ lục'),
              Tab(text: 'Lịch sử 30 ngày'),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateWorkspace extends StatelessWidget {
  final TextEditingController orderController;
  final ContractAppendixProvider provider;
  final void Function(String message, {bool error}) showToast;

  const _CreateWorkspace({
    required this.orderController,
    required this.provider,
    required this.showToast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OrderCommandBar(
          controller: orderController,
          isLoading: provider.isLookingUp,
          onSubmit: () => _lookup(context),
        ),
        const SizedBox(height: 12),
        if (provider.draft == null)
          const AppSurfaceCard(
            child: AppStatePanel.empty(
              icon: Icons.description_outlined,
              title: 'Chưa có bảng phụ lục',
              message: 'Nhập mã đơn hàng và chọn “Lấy thông tin” để bắt đầu.',
              compact: true,
            ),
          )
        else
          _DocumentWorkspace(provider: provider, showToast: showToast),
      ],
    );
  }

  Future<void> _lookup(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await provider.lookupOrder(orderController.text);
    if (!context.mounted) return;
    showToast(
      ok
          ? provider.successMessage ?? 'Đã lấy thông tin đơn hàng.'
          : provider.errorMessage ?? 'Không lấy được thông tin đơn hàng.',
      error: !ok,
    );
  }
}

class _OrderCommandBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSubmit;

  const _OrderCommandBar({
    required this.controller,
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Row(
        key: const Key('contract-appendix-order-command-row'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextInput(
              key: const Key('contract-appendix-order-input'),
              controller: controller,
              enabled: !isLoading,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              label: 'Mã đơn hàng',
              hintText: 'Nhập mã đơn hàng',
              icon: Icons.search_rounded,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600 ? 132 : 176,
            child: AppPrimaryButton(
              key: const Key('contract-appendix-fetch-button'),
              onPressed: isLoading ? null : onSubmit,
              label: 'Lấy thông tin',
              isLoading: isLoading,
              loadingLabel: 'Đang lấy',
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
          AppStatusBanner(
            icon: Icons.percent_rounded,
            title: 'Cần chọn thuế',
            message:
                'Chưa xác định được thuế cho ${document.unresolvedTaxCount} '
                'sản phẩm. Vui lòng chọn thuế nhập tay trước khi lưu.',
            tone: AppStateTone.warning,
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1080) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: _DesktopEditor(
                      document: document,
                      provider: provider,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 10,
                    child: ContractAppendixPreviewCard(document: document),
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileEditor(document: document, provider: provider),
                const SizedBox(height: 12),
                ContractAppendixPreviewCard(document: document),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppActionRow(
                children: [
                  AppSecondaryButton(
                    key: const Key('contract-appendix-refresh-button'),
                    onPressed: provider.isBusy ? null : () => _refresh(context),
                    icon: Icons.calculate_outlined,
                    label: 'Cập nhật xem trước',
                    isLoading: provider.isRefreshingPreview,
                  ),
                  AppPrimaryButton(
                    key: const Key('contract-appendix-save-button'),
                    onPressed: provider.isBusy ? null : () => _save(context),
                    icon: Icons.save_outlined,
                    label: 'Lưu phụ lục',
                    isLoading: provider.isSaving,
                  ),
                  AppSecondaryButton(
                    key: const Key('contract-appendix-copy-button'),
                    onPressed: provider.canCopy && !provider.isCopying
                        ? () => _copy(context)
                        : null,
                    icon: Icons.copy_all_outlined,
                    label: 'Sao chép bảng',
                    isLoading: provider.isCopying,
                  ),
                ],
              ),
              if (!provider.canCopy) ...[
                const SizedBox(height: 8),
                Text(
                  provider.copyDisabledReason,
                  textAlign: TextAlign.right,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textMutedOf(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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

class _DesktopEditor extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider provider;

  const _DesktopEditor({required this.document, required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: 'Thông tin hàng hóa',
            subtitle: 'Giá, SKU và số lượng được khóa theo đơn hàng.',
            trailing: '${document.items.length} dòng',
          ),
          const SizedBox(height: 12),
          Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FlexColumnWidth(1.25),
              1: FlexColumnWidth(2.6),
              2: FlexColumnWidth(0.65),
              3: FlexColumnWidth(1.0),
              4: FlexColumnWidth(1.3),
              5: FlexColumnWidth(1.15),
            },
            border: TableBorder.all(color: AppColors.borderOf(context)),
            children: [
              _desktopHeader(context),
              for (final item in document.items)
                TableRow(
                  children: [
                    _tableText(context, item.sku),
                    _tableEditor(
                      key: ValueKey('name-${item.sourceLineKey}'),
                      initialValue: item.productName,
                      label: 'Tên hàng hóa',
                      onChanged: (value) =>
                          provider.updateProductName(item.sourceLineKey, value),
                    ),
                    _tableText(
                      context,
                      item.quantity.toString(),
                      align: TextAlign.center,
                    ),
                    _tableEditor(
                      key: ValueKey('unit-${item.sourceLineKey}'),
                      initialValue: item.unit,
                      label: 'ĐVT',
                      onChanged: (value) =>
                          provider.updateUnit(item.sourceLineKey, value),
                    ),
                    _tableText(
                      context,
                      _money(item.finalSellPrice),
                      align: TextAlign.right,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: _TaxField(item: item, provider: provider),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _desktopHeader(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(color: AppColors.primarySurfaceOf(context)),
      children: const [
        _TableHeader('SKU'),
        _TableHeader('Tên hàng hóa'),
        _TableHeader('SL'),
        _TableHeader('ĐVT'),
        _TableHeader('Giá đã VAT'),
        _TableHeader('Thuế'),
      ],
    );
  }
}

class _MobileEditor extends StatelessWidget {
  final ContractAppendixDocument document;
  final ContractAppendixProvider provider;

  const _MobileEditor({required this.document, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'Thông tin hàng hóa',
          subtitle: 'Có thể sửa tên hàng và đơn vị tính.',
          trailing: '${document.items.length} dòng',
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < document.items.length; index++) ...[
          if (index > 0) const SizedBox(height: 10),
          _MobileItemCard(item: document.items[index], provider: provider),
        ],
      ],
    );
  }
}

class _MobileItemCard extends StatelessWidget {
  final ContractAppendixItem item;
  final ContractAppendixProvider provider;

  const _MobileItemCard({required this.item, required this.provider});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: ValueKey('contract-appendix-item-${item.sourceLineKey}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primarySurfaceOf(context),
                foregroundColor: AppColors.primaryOf(context),
                child: Text('${item.position}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('SKU ${item.sku}', style: AppTextStyles.labelM),
              ),
              _TaxSourceChip(item: item),
            ],
          ),
          const SizedBox(height: 12),
          _EditableValueField(
            key: ValueKey('mobile-name-${item.sourceLineKey}'),
            initialValue: item.productName,
            maxLines: 3,
            label: 'Tên hàng hóa',
            onChanged: (value) =>
                provider.updateProductName(item.sourceLineKey, value),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LockedValue(
                  label: 'Số lượng',
                  value: item.quantity.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _EditableValueField(
                  key: ValueKey('mobile-unit-${item.sourceLineKey}'),
                  initialValue: item.unit,
                  label: 'Đơn vị tính',
                  onChanged: (value) =>
                      provider.updateUnit(item.sourceLineKey, value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LockedValue(
            label: 'Giá đã VAT',
            value: '${_money(item.finalSellPrice)} VNĐ',
          ),
          const SizedBox(height: 10),
          _TaxField(item: item, provider: provider),
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
    if (!item.canEnterManualTax) {
      return _LockedValue(label: 'Thuế hệ thống', value: item.vatLabel);
    }
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

class _TaxSourceChip extends StatelessWidget {
  final ContractAppendixItem item;

  const _TaxSourceChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final manual = item.taxSource == 'MANUAL';
    final missing = item.isTaxMissing;
    final color = missing
        ? AppColors.warning
        : manual
        ? AppColors.warning
        : AppColors.success;
    final label = missing
        ? 'Thiếu thuế'
        : manual
        ? 'Thuế nhập tay'
        : 'Thuế hệ thống';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.allPill,
      ),
      child: Text(
        label,
        style: AppTextStyles.captionBold.copyWith(color: color),
      ),
    );
  }
}

class _LockedValue extends StatelessWidget {
  final String label;
  final String value;

  const _LockedValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return AppReadOnlyField(value: value, label: label, maxLines: 2);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? trailing;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.headingS),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTextStyles.labelS.copyWith(
              color: AppColors.primaryOf(context),
            ),
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;

  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.labelS,
      ),
    );
  }
}

Widget _tableText(
  BuildContext context,
  String value, {
  TextAlign align = TextAlign.left,
}) {
  return Padding(
    padding: const EdgeInsets.all(6),
    child: Text(
      value,
      textAlign: align,
      style: AppTextStyles.bodyS.copyWith(
        color: AppColors.textSecondaryOf(context),
      ),
    ),
  );
}

Widget _tableEditor({
  required Key key,
  required String initialValue,
  required String label,
  required ValueChanged<String> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.all(4),
    child: _EditableValueField(
      key: key,
      initialValue: initialValue,
      label: label,
      onChanged: onChanged,
      maxLines: label == 'Tên hàng hóa' ? 3 : 1,
      dense: true,
    ),
  );
}

class _EditableValueField extends StatefulWidget {
  final String initialValue;
  final String label;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool dense;

  const _EditableValueField({
    super.key,
    required this.initialValue,
    required this.label,
    required this.onChanged,
    this.maxLines = 1,
    this.dense = false,
  });

  @override
  State<_EditableValueField> createState() => _EditableValueFieldState();
}

class _EditableValueFieldState extends State<_EditableValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _EditableValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue == oldWidget.initialValue ||
        _controller.text == widget.initialValue) {
      return;
    }
    _controller
      ..text = widget.initialValue
      ..selection = TextSelection.collapsed(offset: widget.initialValue.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTextInput(
      controller: _controller,
      label: widget.label,
      onChanged: widget.onChanged,
      maxLines: widget.maxLines,
      minLines: 1,
      dense: widget.dense,
    );
  }
}

class ContractAppendixPreviewCard extends StatelessWidget {
  final ContractAppendixDocument document;

  const ContractAppendixPreviewCard({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(
            title: 'Xem trước bảng Word',
            subtitle: 'Kéo ngang để xem đủ 7 cột.',
            trailing: document.isFinalized ? 'Đã lưu' : 'Chưa lưu',
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: math
                .min(520, 190 + (document.items.length * 64))
                .toDouble(),
            child: AppTwoAxisScrollView(
              child: ContractAppendixPreviewTable(document: document),
            ),
          ),
        ],
      ),
    );
  }
}

class ContractAppendixPreviewTable extends StatelessWidget {
  final ContractAppendixDocument document;

  const ContractAppendixPreviewTable({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    const widths = <int, TableColumnWidth>{
      0: FixedColumnWidth(48),
      1: FixedColumnWidth(320),
      2: FixedColumnWidth(58),
      3: FixedColumnWidth(72),
      4: FixedColumnWidth(140),
      5: FixedColumnWidth(76),
      6: FixedColumnWidth(150),
    };
    return SizedBox(
      width: 864,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Table(
            columnWidths: widths,
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: AppColors.neutral900),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: AppColors.errorSurface),
                children: const [
                  _PreviewCell('STT', header: true),
                  _PreviewCell('Tên hàng hóa', header: true),
                  _PreviewCell('SL', header: true),
                  _PreviewCell('ĐVT', header: true),
                  _PreviewCell('Đơn giá (VNĐ)\nChưa VAT', header: true),
                  _PreviewCell('GTGT', header: true),
                  _PreviewCell('Thành tiền (VNĐ)\nChưa VAT', header: true),
                ],
              ),
              for (final item in document.items)
                TableRow(
                  children: [
                    _PreviewCell('${item.position}', center: true),
                    _PreviewCell(item.productName),
                    _PreviewCell('${item.quantity}', center: true),
                    _PreviewCell(item.unit, center: true),
                    _PreviewCell(
                      _moneyOrDash(item.unitPriceBeforeVat),
                      right: true,
                    ),
                    _PreviewCell(item.vatLabel, center: true),
                    _PreviewCell(_moneyOrDash(item.lineBeforeVat), right: true),
                  ],
                ),
            ],
          ),
          _PreviewSummaryRow(
            label: 'Tổng cộng',
            value: _moneyOrDash(document.totalBeforeVat),
          ),
          _PreviewSummaryRow(
            label: 'Thuế GTGT',
            value: _moneyOrDash(document.totalVatAmount),
          ),
          _PreviewSummaryRow(
            label: 'Tổng giá trị hợp đồng (đã bao gồm thuế GTGT)',
            value: _moneyOrDash(document.totalAfterVat),
            emphasized: true,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral900),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.xs),
              ),
            ),
            child: Text(
              document.amountInWords == null
                  ? 'Bằng chữ: Chưa đủ dữ liệu để tính.'
                  : 'Bằng chữ: ${document.amountInWords}',
              style: AppTextStyles.labelM,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCell extends StatelessWidget {
  final String text;
  final bool header;
  final bool center;
  final bool right;

  const _PreviewCell(
    this.text, {
    this.header = false,
    this.center = false,
    this.right = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      child: Text(
        text,
        textAlign: center
            ? TextAlign.center
            : right
            ? TextAlign.right
            : TextAlign.left,
        style: header ? AppTextStyles.labelS : AppTextStyles.bodyS,
      ),
    );
  }
}

class _PreviewSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _PreviewSummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = emphasized ? AppColors.errorSurface : null;
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: const Border(
          left: BorderSide(color: AppColors.neutral900),
          right: BorderSide(color: AppColors.neutral900),
          bottom: BorderSide(color: AppColors.neutral900),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelM,
              ),
            ),
          ),
          Container(width: 1, height: 42, color: AppColors.neutral900),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelM,
              ),
            ),
          ),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSurfaceCard(
          child: Row(
            key: const Key('contract-appendix-history-command-row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextInput(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(context),
                  label: 'Tìm theo mã đơn',
                  icon: Icons.search_rounded,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 600 ? 112 : 150,
                child: AppPrimaryButton(
                  onPressed: provider.isLoadingHistory
                      ? null
                      : () => _search(context),
                  label: 'Tìm kiếm',
                  isLoading: provider.isLoadingHistory,
                  loadingLabel: 'Đang tìm',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (provider.isLoadingHistory && provider.history.isEmpty)
          const AppSurfaceCard(
            child: AppStatePanel.loading(
              title: 'Đang tải lịch sử',
              compact: true,
            ),
          )
        else if (provider.history.isEmpty)
          const AppSurfaceCard(
            child: AppStatePanel.empty(
              icon: Icons.history_rounded,
              title: 'Chưa có phụ lục trong 30 ngày',
              message: 'Các phụ lục đã lưu sẽ xuất hiện tại đây.',
              compact: true,
            ),
          )
        else ...[
          for (var index = 0; index < provider.history.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _HistoryCard(
              item: provider.history[index],
              onOpen: () => openDetail(provider.history[index].id),
              busy: provider.isLoadingHistoryDetail,
            ),
          ],
          const SizedBox(height: 10),
          AppSurfaceCard(
            child: AppPaginationControls(
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
          ),
        ],
      ],
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
        : DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt!.toLocal());
    return AppSurfaceCard(
      onTap: busy ? null : onOpen,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySurfaceOf(context),
              borderRadius: AppRadius.allMd,
            ),
            child: Icon(
              Icons.description_outlined,
              color: AppColors.primaryOf(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.orderCode,
                  style: AppTextStyles.labelL,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$date · ${item.itemCount} sản phẩm',
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_money(item.totalAfterVat)} VNĐ',
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.success,
                  ),
                ),
                if (item.manualTaxItemCount > 0)
                  Text(
                    '${item.manualTaxItemCount} dòng dùng thuế nhập tay',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Xem phụ lục',
            onPressed: busy ? null : onOpen,
            icon: const Icon(Icons.chevron_right_rounded),
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
                          'Phụ lục ${document.orderCode}',
                          style: AppTextStyles.headingS,
                          maxLines: 1,
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
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppTwoAxisScrollView(
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
                      icon: Icons.copy_all_outlined,
                      label: 'Sao chép bảng',
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
