import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
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
    final deltaMs = metrics?.deltaMs;
    final trend = metrics?.trend ?? PaymentDeliveryMetricTrend.unknown;
    final trendColor = _trendColor(trend);
    final tooltip = _tooltip(metrics, provider.isLoading);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 146, minHeight: 36),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 17),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      averageMs == null
                          ? 'TB --'
                          : 'TB ${_formatDuration(averageMs)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (deltaMs != null) ...[
                    const SizedBox(width: 5),
                    Icon(_trendIcon(trend), size: 16, color: trendColor),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(math.max(0, deltaMs.abs())),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: trendColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tooltip(PaymentDeliveryMetrics? metrics, bool isLoading) {
    if (metrics == null) {
      return isLoading
          ? 'Đang tải tốc độ đọc loa.'
          : 'Chưa có dữ liệu tốc độ đọc loa.';
    }
    final averageMs = metrics.current.averageMs;
    if (averageMs == null) {
      return 'Chưa có lượt đọc loa hoàn tất trong ${metrics.windowHours} giờ gần nhất.';
    }
    final trendText = switch (metrics.trend) {
      PaymentDeliveryMetricTrend.down => 'Giảm so với kỳ trước.',
      PaymentDeliveryMetricTrend.up => 'Tăng so với kỳ trước.',
      PaymentDeliveryMetricTrend.flat => 'Gần như không đổi so với kỳ trước.',
      PaymentDeliveryMetricTrend.unknown => 'Chưa đủ dữ liệu kỳ trước.',
    };
    return 'Trung bình từ lúc MAP ghi nhận giao dịch đến khi loa xác nhận đã đọc xong: ${_formatDuration(averageMs)}. $trendText';
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
