import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/payment_delivery_metrics.dart';
import '../providers/payment_delivery_metrics_provider.dart';

class PaymentDeliveryMetricsChip extends StatelessWidget {
  const PaymentDeliveryMetricsChip({super.key});

  @override
  Widget build(BuildContext context) {
    late final PaymentDeliveryMetricsProvider provider;
    try {
      provider = context.watch<PaymentDeliveryMetricsProvider>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    if (!provider.shouldShow) return const SizedBox.shrink();

    final metrics = provider.metrics;
    final averageMs = metrics?.current.averageMs;
    final hasError = provider.errorMessage != null;
    final deltaMs = metrics?.deltaMs;
    final trend = metrics?.trend ?? PaymentDeliveryMetricTrend.unknown;
    final statusColor = hasError && metrics == null
        ? AppColors.error
        : AppColors.surface;
    final trendColor = hasError && metrics == null
        ? AppColors.error
        : _trendColor(trend);
    final tooltip = _tooltip(
      metrics,
      provider.isLoading,
      provider.errorMessage,
    );
    final label = hasError && metrics == null
        ? 'TB lỗi'
        : averageMs == null
        ? 'TB --'
        : 'TB ${_formatDuration(averageMs)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: 'Mở lịch sử tốc độ đọc loa',
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 88,
              maxWidth: 156,
              minHeight: 36,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: hasError && metrics == null
                    ? AppColors.error.withValues(alpha: 0.20)
                    : AppColors.surface.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: hasError && metrics == null
                      ? AppColors.error.withValues(alpha: 0.55)
                      : AppColors.surface.withValues(alpha: 0.24),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => _openHistoryDialog(context, provider),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 17,
                          color: statusColor,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                        if (deltaMs != null) ...[
                          const SizedBox(width: 5),
                          Icon(_trendIcon(trend), size: 16, color: trendColor),
                          const SizedBox(width: 2),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatDuration(math.max(0, deltaMs.abs())),
                                maxLines: 1,
                                softWrap: false,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: trendColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                        ],
                        if (provider.isLoading) ...[
                          const SizedBox(width: 5),
                          SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openHistoryDialog(
    BuildContext context,
    PaymentDeliveryMetricsProvider provider,
  ) async {
    await AppLogger.instance.info(
      'PaymentDeliveryMetrics',
      'Payment delivery history dialog opened',
      context: {
        'currentCount': provider.metrics?.current.count,
        'currentAverageMs': provider.metrics?.current.averageMs,
      },
    );
    if (!context.mounted) return;
    unawaited(provider.loadHistory());
    await showDialog<void>(
      context: context,
      builder: (_) =>
          ChangeNotifierProvider<PaymentDeliveryMetricsProvider>.value(
            value: provider,
            child: const _PaymentDeliveryHistoryDialog(),
          ),
    );
    await AppLogger.instance.info(
      'PaymentDeliveryMetrics',
      'Payment delivery history dialog closed',
      context: {'itemCount': provider.historyItems.length},
    );
  }

  String _tooltip(
    PaymentDeliveryMetrics? metrics,
    bool isLoading,
    String? errorMessage,
  ) {
    if (errorMessage != null && metrics == null) {
      return 'Chưa tải được tốc độ đọc loa. Bấm để xem lịch sử hoặc tải lại.';
    }
    if (errorMessage != null) {
      return 'Chưa cập nhật được tốc độ đọc loa. Bấm để xem lịch sử.';
    }
    if (metrics == null) {
      return isLoading
          ? 'Đang tải tốc độ đọc loa.'
          : 'Chưa có dữ liệu tốc độ đọc loa. Bấm để xem lịch sử.';
    }
    final averageMs = metrics.current.averageMs;
    if (averageMs == null) {
      return 'Chưa có lượt loa bắt đầu đọc đo được trong ${metrics.windowHours} giờ gần nhất. Bấm để xem lịch sử.';
    }
    final trendText = switch (metrics.trend) {
      PaymentDeliveryMetricTrend.down => 'Giảm so với kỳ trước.',
      PaymentDeliveryMetricTrend.up => 'Tăng so với kỳ trước.',
      PaymentDeliveryMetricTrend.flat => 'Gần như không đổi so với kỳ trước.',
      PaymentDeliveryMetricTrend.unknown => 'Chưa đủ dữ liệu kỳ trước.',
    };
    return 'Trung bình từ giờ thanh toán ngân hàng đến khi loa bắt đầu đọc: ${_formatDuration(averageMs)}. $trendText Bấm để xem lịch sử.';
  }

  IconData _trendIcon(PaymentDeliveryMetricTrend trend) {
    return switch (trend) {
      PaymentDeliveryMetricTrend.down => Icons.trending_down_rounded,
      PaymentDeliveryMetricTrend.up => Icons.trending_up_rounded,
      PaymentDeliveryMetricTrend.flat => Icons.trending_flat_rounded,
      PaymentDeliveryMetricTrend.unknown => Icons.remove_rounded,
    };
  }

  Color _trendColor(PaymentDeliveryMetricTrend trend) {
    return switch (trend) {
      PaymentDeliveryMetricTrend.down => AppColors.success,
      PaymentDeliveryMetricTrend.up => AppColors.warning,
      PaymentDeliveryMetricTrend.flat => AppColors.neutral100,
      PaymentDeliveryMetricTrend.unknown => AppColors.neutral100,
    };
  }

  static String _formatDuration(int ms) {
    if (ms >= 60000) {
      final minutes = ms ~/ 60000;
      final seconds = ((ms % 60000) / 1000).round();
      return '${minutes}m${seconds.toString().padLeft(2, '0')}s';
    }
    final seconds = ms / 1000;
    if (seconds >= 10) return '${seconds.round()}s';
    return '${seconds.toStringAsFixed(1)}s';
  }
}

class _PaymentDeliveryHistoryDialog extends StatelessWidget {
  const _PaymentDeliveryHistoryDialog();

  @override
  Widget build(BuildContext context) {
    return Consumer<PaymentDeliveryMetricsProvider>(
      builder: (context, provider, _) {
        final size = MediaQuery.sizeOf(context);
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.history_rounded),
              SizedBox(width: 8),
              Expanded(child: Text('Lịch sử đọc loa')),
            ],
          ),
          content: SizedBox(
            width: math.min(size.width - 48, 680),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.min(size.height * 0.65, 540),
              ),
              child: _PaymentDeliveryHistoryContent(provider: provider),
            ),
          ),
          actions: [
            AppDialogSecondaryButton(
              onPressed: provider.isHistoryLoading
                  ? null
                  : () => provider.loadHistory(),
              icon: Icons.refresh_rounded,
              label: 'Tải lại',
            ),
            AppDialogCancelButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Đóng',
            ),
          ],
        );
      },
    );
  }
}

class _PaymentDeliveryHistoryContent extends StatelessWidget {
  final PaymentDeliveryMetricsProvider provider;

  const _PaymentDeliveryHistoryContent({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isHistoryLoading && provider.historyItems.isEmpty) {
      return const AppStatePanel.loading(
        title: 'Đang tải lịch sử đọc loa',
        compact: true,
      );
    }
    if (provider.historyErrorMessage != null && provider.historyItems.isEmpty) {
      return const AppStatePanel.error(
        title: 'Chưa tải được lịch sử đọc loa',
        message: 'Vui lòng thử lại sau ít phút.',
        compact: true,
      );
    }
    if (provider.historyItems.isEmpty) {
      return const AppStatePanel.empty(
        icon: Icons.volume_off_rounded,
        title: 'Chưa có giao dịch đọc loa gần đây',
        message:
            'Khi loa bắt đầu đọc, bị tắt, hoặc lỗi phát, giao dịch sẽ xuất hiện ở đây.',
        compact: true,
      );
    }

    return Column(
      children: [
        if (provider.isHistoryLoading)
          const _HistoryInlineNotice(
            icon: Icons.sync_rounded,
            text: 'Đang cập nhật lịch sử...',
            color: AppColors.info,
          )
        else if (provider.historyErrorMessage != null)
          const _HistoryInlineNotice(
            icon: Icons.error_outline_rounded,
            text:
                'Chưa cập nhật được lịch sử mới. Đang hiển thị dữ liệu gần nhất.',
            color: AppColors.warning,
          ),
        Expanded(
          child: ListView.separated(
            itemCount: provider.historyItems.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _HistoryItemTile(item: provider.historyItems[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _HistoryItemTile extends StatelessWidget {
  static final _moneyFormat = NumberFormat.decimalPattern('vi_VN');
  static final _timeFormat = DateFormat('HH:mm:ss dd/MM/yyyy');

  final PaymentDeliveryHistoryItem item;

  const _HistoryItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final statusText = _statusText(item.status);
    final statusColor = _statusColor(item);
    final errorText = _errorText(item);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.neutral50,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    'SR ${item.storeCode.isEmpty ? '--' : item.storeCode}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SelectableText(
                  '${_moneyFormat.format(item.amount)}đ',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Ngân hàng ghi nhận: ${_formatTime(item.paidAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              'OpsHub thấy: ${_formatTime(item.firstSeenAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              'Bắt đầu đọc: ${_formatTime(item.streamStartedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              'Độ trễ bắt đầu đọc: ${item.bankToStreamStartLatencyMs == null ? '--' : PaymentDeliveryMetricsChip._formatDuration(item.bankToStreamStartLatencyMs!)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (item.playedAt != null) ...[
              const SizedBox(height: 4),
              SelectableText(
                'Đọc xong: ${_formatTime(item.playedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (item.playDurationMs != null) ...[
              const SizedBox(height: 4),
              SelectableText(
                'Thời lượng phát: ${PaymentDeliveryMetricsChip._formatDuration(item.playDurationMs!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 6),
              SelectableText(
                errorText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '--';
    return _timeFormat.format(value);
  }

  String _statusText(String status) {
    return switch (status.trim().toUpperCase()) {
      'PLAYED' => 'Đã đọc',
      'STREAM_STARTED' => 'Đang đọc',
      'SILENCED' => 'Loa chưa bật',
      'FAILED' => 'Lỗi phát',
      'PLAYBACK_FAILED' => 'Lỗi tạm thời',
      _ => 'Chưa rõ',
    };
  }

  Color _statusColor(PaymentDeliveryHistoryItem item) {
    if (item.status.toUpperCase() == 'PLAYED' && !item.hasError) {
      return AppColors.success;
    }
    if (item.status.toUpperCase() == 'STREAM_STARTED') return AppColors.info;
    if (item.status.toUpperCase() == 'SILENCED') return AppColors.neutral500;
    if (item.status.toUpperCase() == 'PLAYED') return AppColors.warning;
    return AppColors.error;
  }

  String? _errorText(PaymentDeliveryHistoryItem item) {
    if (!item.hasError) return null;
    final status = item.errorStatus == null
        ? 'Có lỗi'
        : _statusText(item.errorStatus!);
    final message = item.errorMessage?.trim();
    if (message == null || message.isEmpty) return 'Trạng thái lỗi: $status';
    return 'Trạng thái lỗi: $status - $message';
  }
}

class _HistoryInlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _HistoryInlineNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.neutral700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
