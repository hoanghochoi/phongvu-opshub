import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
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
    return Scaffold(
      appBar: GradientHeader(
        title: 'Cấn trừ',
        showBack: true,
        actions: [
          if (provider.canReview)
            _OffsetBell(
              count: provider.pendingTotal,
              onPressed: () {
                provider.setStatus(OffsetAdjustmentStatus.pending);
                provider.search();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SelectionArea(
          child: AppResponsiveContent(
            child: Column(
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
                const SizedBox(height: 10),
                _ListToolbar(provider: provider),
                const SizedBox(height: 10),
                if (provider.isLoading && provider.items.isNotEmpty) ...[
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

  Widget _buildList(OffsetAdjustmentProvider provider) {
    if (provider.isLoading && provider.items.isEmpty) {
      return const AppStatePanel.loading(title: 'Đang tải danh sách cấn trừ');
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
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                _showSnack(context, emptyMessage);
                return;
              }
              Navigator.of(context).pop(text);
            },
            child: const Text('Xác nhận'),
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

class _ActionBar extends StatelessWidget {
  final void Function(String type) onCreate;

  const _ActionBar({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _createButton(
          context,
          OffsetAdjustmentType.singleOrder,
          Icons.swap_calls_rounded,
        ),
        _createButton(
          context,
          OffsetAdjustmentType.vnpayQroff,
          Icons.qr_code_2_rounded,
        ),
        _createButton(
          context,
          OffsetAdjustmentType.zaloPay,
          Icons.account_balance_wallet_outlined,
        ),
        _createButton(
          context,
          OffsetAdjustmentType.shopeePay,
          Icons.shopping_bag_outlined,
        ),
      ],
    );
  }

  Widget _createButton(BuildContext context, String type, IconData icon) {
    return ElevatedButton.icon(
      onPressed: () => onCreate(type),
      icon: Icon(icon),
      label: Text(OffsetAdjustmentType.label(type)),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final OffsetAdjustmentProvider provider;
  final TextEditingController orderController;
  final TextEditingController amountController;

  const _FilterPanel({
    required this.provider,
    required this.orderController,
    required this.amountController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < _breakpoint;
            final fieldWidth = compact ? constraints.maxWidth : 220.0;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: fieldWidth, child: _storeFilter()),
                SizedBox(width: fieldWidth, child: _typeFilter()),
                SizedBox(width: fieldWidth, child: _statusFilter()),
                SizedBox(width: fieldWidth, child: _orderField()),
                SizedBox(width: fieldWidth, child: _amountField()),
                OutlinedButton.icon(
                  onPressed: () => _pickDateRange(context),
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(_dateLabel()),
                ),
                ElevatedButton.icon(
                  onPressed: provider.isLoading
                      ? null
                      : () => provider.search(),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Tìm'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _storeFilter() {
    final selected = provider.allStores || provider.selectedStoreIds.isEmpty
        ? '__ALL__'
        : provider.selectedStoreIds.first;
    return DropdownButtonFormField<String>(
      initialValue: provider.canReview
          ? selected
          : (provider.stores.isEmpty ? null : provider.stores.first.storeId),
      decoration: const InputDecoration(labelText: 'SR'),
      items: [
        if (provider.canReview)
          const DropdownMenuItem(value: '__ALL__', child: Text('Tất cả SR')),
        ...provider.stores.map(
          (store) => DropdownMenuItem(
            value: store.storeId,
            child: Text(store.storeId),
          ),
        ),
      ],
      onChanged: provider.canReview
          ? (value) {
              if (value == null || value == '__ALL__') {
                provider.setStoreSelection(allStores: true, ids: const {});
              } else {
                provider.setStoreSelection(allStores: false, ids: {value});
              }
            }
          : null,
    );
  }

  Widget _typeFilter() {
    return DropdownButtonFormField<String>(
      initialValue: provider.type,
      decoration: const InputDecoration(labelText: 'Loại'),
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
      onChanged: (value) => provider.setType(value ?? 'ALL'),
    );
  }

  Widget _statusFilter() {
    return DropdownButtonFormField<String>(
      initialValue: provider.status,
      decoration: const InputDecoration(labelText: 'Trạng thái'),
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('Tất cả trạng thái')),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.pending,
          child: Text('Chờ ACC xác nhận'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.approved,
          child: Text('ACC đã xác nhận'),
        ),
        DropdownMenuItem(
          value: OffsetAdjustmentStatus.rejected,
          child: Text('ACC từ chối chờ sửa'),
        ),
      ],
      onChanged: (value) => provider.setStatus(value ?? 'ALL'),
    );
  }

  Widget _orderField() {
    return TextField(
      controller: orderController,
      decoration: const InputDecoration(labelText: 'Mã đơn'),
      onChanged: provider.setOrder,
    );
  }

  Widget _amountField() {
    return TextField(
      controller: amountController,
      keyboardType: TextInputType.number,
      inputFormatters: [ThousandsSeparatorInputFormatter()],
      decoration: const InputDecoration(labelText: 'Số tiền'),
      onChanged: provider.setAmount,
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: provider.startDate ?? DateTime(now.year, now.month, now.day),
        end: provider.endDate ?? DateTime(now.year, now.month, now.day),
      ),
    );
    if (picked != null) provider.setDateRange(picked.start, picked.end);
  }

  String _dateLabel() {
    final format = DateFormat('dd/MM/yyyy');
    final start = provider.startDate;
    final end = provider.endDate;
    if (start == null || end == null) return 'Hôm nay';
    return '${format.format(start)} - ${format.format(end)}';
  }
}

class _ListToolbar extends StatelessWidget {
  final OffsetAdjustmentProvider provider;

  const _ListToolbar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${provider.items.length} / ${provider.total} hồ sơ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        side: BorderSide(color: borderColor.withValues(alpha: 0.7), width: 1.3),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
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
                    _InlineInfo(
                      icon: Icons.schedule_rounded,
                      text: submittedText,
                    ),
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
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
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
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
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
              _detail('SR', item.storeCode),
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
              _detail('ACC xử lý', item.reviewedByEmail),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        if (item.canResubmit)
          ElevatedButton.icon(
            onPressed: onResubmit,
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Sửa lại'),
          ),
        if (canReview && item.status == OffsetAdjustmentStatus.pending) ...[
          OutlinedButton.icon(
            onPressed: onReject,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Từ chối'),
          ),
          ElevatedButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Hoàn thành'),
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
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
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
      text: initial?.scanDate ?? _todayText(),
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
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? OffsetAdjustmentType.label(widget.type)
            : 'Sửa ${OffsetAdjustmentType.label(widget.type)}',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSingle) ...[
                _field(_oldOrderController, 'Đơn hàng cũ'),
                _field(_newOrderController, 'Đơn hàng mới'),
              ] else ...[
                _field(_orderController, 'Đơn hàng'),
                _dateField(_scanDateLabel(widget.type)),
                DropdownButtonFormField<String>(
                  initialValue: _editContentKind,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung cần sửa',
                  ),
                  items: OffsetEditContentKind.values
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind,
                          child: Text(OffsetEditContentKind.label(kind)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _editContentKind = value);
                  },
                ),
                _field(_transactionController, 'Mã giao dịch'),
              ],
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorInputFormatter()],
                decoration: const InputDecoration(labelText: 'Số tiền'),
              ),
              _field(_noteController, 'Ghi chú', maxLines: 3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Lưu'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _dateField(String label) {
    return TextField(
      controller: _scanDateController,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: 'Chọn ngày',
          onPressed: _pickScanDate,
          icon: const Icon(Icons.calendar_today_rounded),
        ),
      ),
    );
  }

  Future<void> _pickScanDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDate: _parseDate(_scanDateController.text) ?? now,
    );
    if (picked == null) return;
    _scanDateController.text = _formatDate(picked);
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

  String _todayText() => _formatDate(DateTime.now());

  String _formatDate(DateTime value) {
    String two(int part) => part.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  DateTime? _parseDate(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

class _OffsetBell extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _OffsetBell({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Hồ sơ chờ ACC xác nhận',
          onPressed: onPressed,
          icon: const Icon(Icons.notifications_none_rounded),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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

String _scanDateLabel(String type) {
  return switch (type) {
    OffsetAdjustmentType.vnpayQroff => 'Ngày quét QR',
    OffsetAdjustmentType.zaloPay => 'Ngày quét Zalo Pay',
    OffsetAdjustmentType.shopeePay => 'Ngày quét Shopee Pay',
    _ => 'Ngày quét',
  };
}
