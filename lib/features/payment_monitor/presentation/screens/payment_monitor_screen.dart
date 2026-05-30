import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_chips.dart';
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
      appBar: const GradientHeader(title: 'Theo dõi tiền vào', showBack: true),
      body: SafeArea(
        child: AppResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            monitor.isSpeakerEnabled
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            color: monitor.isSpeakerEnabled
                                ? AppColors.success
                                : AppColors.neutral500,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              monitor.isSpeakerEnabled
                                  ? 'Đang đọc loa khi có tiền vào'
                                  : 'Đã tắt đọc loa',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: monitor.isSpeakerEnabled,
                            onChanged: monitor.canMonitorOnThisDevice
                                ? (value) => context
                                      .read<PaymentMonitorProvider>()
                                      .setSpeakerEnabled(value)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _SyncStatusPill(monitor: monitor),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Máy này tự cập nhật giao dịch tiền vào mỗi 5 giây. Khi bật đọc loa, giao dịch mới sẽ được đọc thành tiếng; khi tắt, danh sách vẫn cập nhật bình thường.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.25,
                          fontSize: 13,
                        ),
                      ),
                      if (requiresStoreInput) ...[
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextField(
                          controller: _storeController,
                          decoration: const InputDecoration(
                            labelText: 'Mã showroom cần xem',
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
                          label: 'Xem showroom này',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (monitor.speakerError != null) ...[
                const SizedBox(height: 12),
                _SpeakerErrorCard(
                  error: monitor.speakerError!,
                  amountText:
                      '${_currencyFormatter.format(monitor.speakerError!.amount)} VND',
                  onRestart: () =>
                      context.read<PaymentMonitorProvider>().restartApp(),
                ),
              ],
              if (monitor.errorMessage != null) ...[
                const SizedBox(height: 12),
                _StatusCard(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.error,
                  title: 'Chưa cập nhật được giao dịch',
                  message: monitor.errorMessage!,
                ),
              ],
              const SizedBox(height: 14),
              _TransactionFilters(monitor: monitor),
              const SizedBox(height: 16),
              Text(
                'Giao dịch tiền vào',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Stack(
                  children: [
                    monitor.latestTransactions.isEmpty
                        ? const _EmptyTransactions()
                        : ListView.builder(
                            itemCount: monitor.latestTransactions.length,
                            itemBuilder: (context, index) => _buildTransactionTile(
                              monitor.latestTransactions[index],
                            ),
                          ),
                    if (monitor.isLoading)
                      Positioned.fill(
                        child: Container(
                          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = transaction.hasOrders
        ? AppColors.success
        : AppColors.error;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        side: BorderSide(
          color: borderColor.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDark
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.success.withValues(alpha: 0.08),
          child: const Icon(Icons.payments_rounded, color: AppColors.success),
        ),
        title: Text(
          '${_currencyFormatter.format(transaction.amount)} VND',
          style: const TextStyle(fontWeight: FontWeight.w700),
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

class _SyncStatusPill extends StatelessWidget {
  final PaymentMonitorProvider monitor;

  const _SyncStatusPill({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final color = monitor.isActive ? AppColors.success : AppColors.neutral500;
    final baseLabel = monitor.isLoading
        ? 'Đang cập nhật giao dịch'
        : monitor.isActive
        ? 'Giao dịch tự cập nhật'
        : monitor.hasMonitorScope
        ? 'Đang chuẩn bị cập nhật'
        : 'Chọn showroom để cập nhật';

    final lastCheckedAt = monitor.lastCheckedAt;
    final lastCheckedText = lastCheckedAt == null
        ? 'chưa cập nhật'
        : DateFormat('HH:mm:ss dd/MM/yyyy').format(lastCheckedAt);
    final label = monitor.isActive || monitor.isLoading
        ? '$baseLabel • $lastCheckedText'
        : baseLabel;

    return AppStatusPill(
      icon: Icons.sync_rounded,
      label: label,
      color: color,
      isLoading: monitor.isLoading,
    );
  }
}

class _TransactionFilters extends StatelessWidget {
  final PaymentMonitorProvider monitor;

  const _TransactionFilters({required this.monitor});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < AppLayoutTokens.compactBreakpoint;

        if (isMobile) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DateDropdown(
                          label: 'Từ ngày',
                          date: monitor.rangeStartDate,
                          firstDate: DateTime(2024),
                          lastDate: monitor.rangeEndDate,
                          onPicked: (date) {
                            context.read<PaymentMonitorProvider>().setDateRange(
                              date,
                              monitor.rangeEndDate,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DateDropdown(
                          label: 'Đến ngày',
                          date: monitor.rangeEndDate,
                          firstDate: monitor.rangeStartDate,
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          onPicked: (date) {
                            context.read<PaymentMonitorProvider>().setDateRange(
                              monitor.rangeStartDate,
                              date,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: monitor.pageSize,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Số dòng hiển thị',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
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
                            'Trang ${monitor.pageIndex + 1} - ${monitor.totalTransactions} GD',
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppLayoutTokens.cardPadding),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DateDropdown(
                        label: 'Từ ngày',
                        date: monitor.rangeStartDate,
                        firstDate: DateTime(2024),
                        lastDate: monitor.rangeEndDate,
                        onPicked: (date) {
                          context.read<PaymentMonitorProvider>().setDateRange(
                            date,
                            monitor.rangeEndDate,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateDropdown(
                        label: 'Đến ngày',
                        date: monitor.rangeEndDate,
                        firstDate: monitor.rangeStartDate,
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        onPicked: (date) {
                          context.read<PaymentMonitorProvider>().setDateRange(
                            monitor.rangeStartDate,
                            date,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<int>(
                        initialValue: monitor.pageSize,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
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
      },
    );
  }
}

/// A single date dropdown: displays the date in dd/MM/yyyy format,
/// tapping it opens [showDatePicker].
class _DateDropdown extends StatelessWidget {
  final String label;
  final DateTime date;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onPicked;

  const _DateDropdown({
    required this.label,
    required this.date,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: label,
          cancelText: 'Hủy',
          confirmText: 'Chọn',
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          constraints: const BoxConstraints(minHeight: 52),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_month_rounded, size: 20),
        ),
        child: Text(
          DateFormat('dd/MM/yyyy').format(date),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    );
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

class _SpeakerErrorCard extends StatelessWidget {
  final PaymentSpeakerError error;
  final String amountText;
  final VoidCallback onRestart;

  const _SpeakerErrorCard({
    required this.error,
    required this.amountText,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.error.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.volume_off_rounded, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Loa đọc tiền vào đang lỗi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$amountText - ${error.message}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: AppSecondaryButton(
                  onPressed: onRestart,
                  icon: Icons.restart_alt_rounded,
                  label: 'Khởi động lại app',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return const AppStatePanel.empty(
      title: 'Chưa có giao dịch trong khoảng ngày đã chọn',
      icon: Icons.receipt_long_outlined,
    );
  }
}
