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
          label: 'Tốc độ đọc loa trung bình',
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
                    : Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasError && metrics == null
                      ? AppColors.error.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.24),
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: provider.isLoading ? null : () => provider.load(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 17, color: statusColor),
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

  String _tooltip(
    PaymentDeliveryMetrics? metrics,
    bool isLoading,
    String? errorMessage,
  ) {
    if (errorMessage != null && metrics == null) {
      return 'Chưa tải được tốc độ đọc loa. Bấm để tải lại.';
    }
    if (errorMessage != null) {
      return 'Chưa cập nhật được tốc độ đọc loa. Đang hiển thị dữ liệu gần nhất. Bấm để tải lại.';
    }
    if (metrics == null) {
      return isLoading
          ? 'Đang tải tốc độ đọc loa.'
          : 'Chưa có dữ liệu tốc độ đọc loa. Bấm để tải lại.';
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
                        fontWeight: FontWeight.w700,
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
