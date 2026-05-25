import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/payment_monitor_provider.dart';
import '../../domain/map_payment_transaction.dart';

class PaymentMonitorScreen extends StatefulWidget {
  const PaymentMonitorScreen({super.key});

  @override
  State<PaymentMonitorScreen> createState() => _PaymentMonitorScreenState();
}

class _PaymentMonitorScreenState extends State<PaymentMonitorScreen> {
  final _storeController = TextEditingController();
  final _currencyFormatter = NumberFormat.decimalPattern('vi_VN');

  @override
  void dispose() {
    _storeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final monitor = context.watch<PaymentMonitorProvider>();
    final requiresStoreInput = user?.role == 'SUPER_ADMIN';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'Theo dõi tiền vào', showBack: true),
      body: SafeArea(
        child: AppResponsiveScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            monitor.isActive
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: monitor.isActive
                                ? Colors.green
                                : const Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              monitor.isActive
                                  ? 'Đang chạy nền'
                                  : 'Chưa có phạm vi theo dõi',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: monitor.isEnabled,
                            onChanged: monitor.canMonitorOnThisDevice
                                ? (value) => context
                                      .read<PaymentMonitorProvider>()
                                      .setEnabled(value)
                                : null,
                          ),
                          if (monitor.isLoading)
                            const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'OpsHub PC tự lấy giao dịch MAP đã lưu trên server mỗi 5 giây và đọc mọi giao dịch tiền vào mới, kể cả giao dịch không tạo từ QR trong app.',
                        style: TextStyle(color: Colors.grey[700], height: 1.35),
                      ),
                      if (requiresStoreInput) ...[
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextField(
                          controller: _storeController,
                          decoration: const InputDecoration(
                            labelText: 'Mã showroom cần theo dõi',
                            prefixIcon: Icon(Icons.store_outlined),
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _applyStoreOverride(context),
                        ),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        AppSecondaryButton(
                          onPressed: () => _applyStoreOverride(context),
                          icon: Icons.check_rounded,
                          label: 'Theo dõi showroom này',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (monitor.errorMessage != null) ...[
                const SizedBox(height: 12),
                _StatusCard(
                  icon: Icons.error_outline_rounded,
                  color: Colors.red,
                  title: 'Không kiểm tra được giao dịch',
                  message: monitor.errorMessage!,
                ),
              ],
              const SizedBox(height: 16),
              _StatusCard(
                icon: Icons.schedule_rounded,
                color: const Color(0xFF2563EB),
                title: 'Lần kiểm tra gần nhất',
                message: monitor.lastCheckedAt == null
                    ? 'Chưa kiểm tra'
                    : DateFormat(
                        'HH:mm:ss dd/MM/yyyy',
                      ).format(monitor.lastCheckedAt!),
              ),
              const SizedBox(height: 16),
              _TransactionFilters(monitor: monitor),
              const SizedBox(height: 16),
              Text(
                'Giao dịch gần đây',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[850],
                ),
              ),
              const SizedBox(height: 10),
              if (monitor.latestTransactions.isEmpty)
                const _EmptyTransactions()
              else
                ...monitor.latestTransactions.map(_buildTransactionTile),
            ],
          ),
        ),
      ),
    );
  }

  void _applyStoreOverride(BuildContext context) {
    context.read<PaymentMonitorProvider>().setStoreOverride(
      _storeController.text,
    );
  }

  Widget _buildTransactionTile(MapPaymentTransaction transaction) {
    final displayTime = _toVietnamTime(
      transaction.paidAt ?? transaction.firstSeenAt,
    );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE8F5E9),
          child: Icon(Icons.payments_rounded, color: Colors.green),
        ),
        title: Text(
          '${_currencyFormatter.format(transaction.amount)} VND',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          [
            if (displayTime != null)
              DateFormat('HH:mm:ss dd/MM').format(displayTime),
            if (transaction.content.isNotEmpty) transaction.content,
          ].join(' - '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  DateTime? _toVietnamTime(DateTime? value) {
    if (value == null) return null;
    return value.toUtc().add(const Duration(hours: 7));
  }
}

class _TransactionFilters extends StatelessWidget {
  final PaymentMonitorProvider monitor;

  const _TransactionFilters({required this.monitor});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(context),
                    icon: const Icon(Icons.calendar_month_rounded),
                    label: Text(
                      DateFormat('dd/MM/yyyy').format(monitor.selectedDate),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
                const SizedBox(width: AppLayoutTokens.formInlineGap),
                SizedBox(
                  width: 116,
                  child: DropdownButtonFormField<int>(
                    initialValue: monitor.pageSize,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [10, 20, 50, 100]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              '$value dòng',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      context.read<PaymentMonitorProvider>().setPageSize(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            Row(
              children: [
                IconButton(
                  onPressed: monitor.canGoPreviousPage
                      ? () => context
                            .read<PaymentMonitorProvider>()
                            .previousPage()
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      'Trang ${monitor.pageIndex + 1} - ${monitor.totalTransactions} giao dịch',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: monitor.canGoNextPage
                      ? () => context.read<PaymentMonitorProvider>().nextPage()
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: monitor.selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !context.mounted) return;
    context.read<PaymentMonitorProvider>().setSelectedDate(picked);
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;

  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusBanner(
      icon: icon,
      title: title,
      message: message,
      tone: color == Colors.red ? AppStateTone.error : AppStateTone.info,
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: Text('Chưa có giao dịch trong phiên theo dõi')),
      ),
    );
  }
}
