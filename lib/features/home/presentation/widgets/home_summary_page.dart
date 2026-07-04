import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_chips.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../domain/home_summary.dart';
import '../providers/home_summary_provider.dart';

class HomeSummaryPage extends StatelessWidget {
  const HomeSummaryPage({super.key, required this.provider});

  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    final summary = provider.summary;
    final content = _buildSummaryContent(summary);

    return Column(
      key: const Key('home-summary-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSummaryHeader(
          summary: summary,
          selectedDate: provider.selectedDate,
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        HomeSummaryToolbar(
          summary: summary,
          selectedDate: provider.selectedDate,
          isRefreshing: provider.isRefreshing || provider.isInitialLoading,
          onPickDate: () => _pickDate(context),
          onRefresh: provider.canRefresh
              ? () => unawaited(provider.refreshNow())
              : null,
          warningMessage: provider.errorMessage != null && summary != null
              ? provider.errorMessage
              : null,
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        // Keep the metrics dashboard tree stable: header, toolbar, grid, progress.
        ...content,
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Chọn ngày xem dashboard',
      cancelText: 'Hủy',
      confirmText: 'Áp dụng',
    );
    if (picked == null) return;
    await provider.setSelectedDate(picked);
  }

  List<Widget> _buildSummaryContent(HomeSummary? summary) {
    if (provider.isInitialLoading) {
      return [
        _buildStateCard(
          key: const Key('home-summary-loading'),
          child: const AppStatePanel.loading(
            title: 'Đang tải dashboard',
            message: 'Hệ thống đang tổng hợp doanh số và tiến độ báo cáo.',
          ),
        ),
      ];
    }

    if (summary == null && provider.errorMessage != null) {
      return [
        _buildStateCard(
          key: const Key('home-summary-error'),
          child: AppStatePanel.error(
            title: 'Chưa tải được dashboard',
            message: provider.errorMessage,
            actionLabel: 'Thử lại',
            actionIcon: Icons.refresh_rounded,
            onAction: provider.canRefresh
                ? () => unawaited(provider.refreshNow())
                : null,
          ),
        ),
      ];
    }

    if (summary == null) {
      return [
        _buildStateCard(
          key: const Key('home-summary-empty'),
          child: const AppStatePanel.empty(
            title: 'Chưa có dữ liệu dashboard',
            message: 'Dữ liệu sẽ hiển thị ngay khi hệ thống đồng bộ xong.',
          ),
        ),
      ];
    }

    if (summary.isUnavailable) {
      return [
        _buildStateCard(
          key: const Key('home-summary-unavailable'),
          child: AppStatePanel.empty(
            title: 'Dashboard chưa khả dụng cho tài khoản này',
            message: summary.resolvedUnavailableMessage,
          ),
        ),
      ];
    }

    if (!summary.hasMetrics) {
      return [
        _buildStateCard(
          key: const Key('home-summary-no-metrics'),
          child: const AppStatePanel.empty(
            title: 'Chưa có số liệu trong ngày',
            message:
                'Hiện chưa phát sinh đơn hoặc báo cáo hợp lệ trong phạm vi đang xem.',
          ),
        ),
      ];
    }

    return [
      SummaryCardGrid(summary: summary),
      const SizedBox(height: AppLayoutTokens.cardGap),
      ReportProgressPanel(summary: summary),
    ];
  }

  Widget _buildStateCard({required Key key, required Widget child}) {
    return AppSurfaceCard(key: key, child: child);
  }
}

class HomeSummaryHeader extends StatelessWidget {
  const HomeSummaryHeader({
    super.key,
    required this.summary,
    required this.selectedDate,
  });

  final HomeSummary? summary;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    final scopeLabel = summary?.resolvedScopeLabel ?? 'Đang đồng bộ phạm vi';
    final scopeColor = summary?.isUnavailable == true
        ? AppColors.warning
        : AppColors.primary;
    final updatedLabel = summary?.refreshedAt == null
        ? 'Đang cập nhật'
        : 'Cập nhật ${_timeOnlyLabel(summary!.refreshedAt!)}';

    return AppSurfaceCard(
      key: const Key('home-summary-header'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trang chủ vận hành',
                style: AppTextStyles.headingM.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary?.resolvedScopeDetail ??
                    'Theo dõi doanh số, đơn hàng và tiến độ báo cáo trong ngày theo đúng phạm vi hiện tại.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          );
          final chips = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              AppStatusChip(label: scopeLabel, color: scopeColor),
              AppInfoChip(
                Icons.calendar_today_outlined,
                _dateLabel(selectedDate),
                color: AppColors.neutral700,
              ),
              AppInfoChip(
                Icons.schedule_outlined,
                updatedLabel,
                color: AppColors.neutral700,
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 12), chips],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 20),
              Flexible(child: chips),
            ],
          );
        },
      ),
    );
  }
}

class HomeSummaryToolbar extends StatelessWidget {
  const HomeSummaryToolbar({
    super.key,
    required this.summary,
    required this.selectedDate,
    required this.isRefreshing,
    required this.onPickDate,
    required this.onRefresh,
    required this.warningMessage,
  });

  final HomeSummary? summary;
  final DateTime selectedDate;
  final bool isRefreshing;
  final VoidCallback onPickDate;
  final VoidCallback? onRefresh;
  final String? warningMessage;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('home-summary-toolbar'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final scopeLabel = summary?.resolvedScopeLabel ?? 'Toàn hệ thống';
          final buttons = [
            _ScopeSelectorPill(label: scopeLabel, compact: compact),
            HomeSummaryDatePicker(
              selectedDate: selectedDate,
              compact: compact,
              onPressed: onPickDate,
            ),
            HomeSummaryRefreshButton(
              compact: compact,
              isRefreshing: isRefreshing,
              onPressed: onRefresh,
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? AppActionRow(
                      desktopAlignment: MainAxisAlignment.start,
                      children: buttons,
                    )
                  : Wrap(spacing: 12, runSpacing: 12, children: buttons),
              if (warningMessage != null) ...[
                const SizedBox(height: 12),
                AppStatusBanner(
                  icon: Icons.sync_problem_rounded,
                  title: 'Đang hiển thị dữ liệu gần nhất',
                  message: warningMessage!,
                  tone: AppStateTone.warning,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ScopeSelectorPill extends StatelessWidget {
  const _ScopeSelectorPill({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      key: const Key('home-summary-scope-pill'),
      constraints: BoxConstraints(
        minHeight: 40,
        maxWidth: compact ? double.infinity : 220,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.primarySurfaceOf(context),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(
            Icons.public_rounded,
            size: 18,
            color: AppColors.primaryOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.primaryOf(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: AppColors.primaryOf(context),
          ),
        ],
      ),
    );

    if (compact) return content;
    return SizedBox(width: 220, child: content);
  }
}

class HomeSummaryDatePicker extends StatelessWidget {
  const HomeSummaryDatePicker({
    super.key,
    required this.selectedDate,
    required this.compact,
    required this.onPressed,
  });

  final DateTime selectedDate;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppSecondaryButton(
      key: const Key('home-summary-date-picker'),
      onPressed: onPressed,
      icon: Icons.calendar_month_rounded,
      label: _dateLabel(selectedDate),
      expand: compact,
    );
  }
}

class HomeSummaryRefreshButton extends StatelessWidget {
  const HomeSummaryRefreshButton({
    super.key,
    required this.compact,
    required this.isRefreshing,
    required this.onPressed,
  });

  final bool compact;
  final bool isRefreshing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppSecondaryButton(
      key: const Key('home-summary-refresh-button'),
      onPressed: onPressed,
      icon: Icons.refresh_rounded,
      label: 'Làm mới',
      isLoading: isRefreshing,
      loadingLabel: 'Đang tải',
      expand: compact,
    );
  }
}

class SummaryCardGrid extends StatelessWidget {
  const SummaryCardGrid({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'revenue',
        icon: Icons.payments_outlined,
        title: 'Doanh số trong ngày',
        value: formatVndAmount(summary.totalRevenue),
        trend: const SummaryTrend.neutral('Đang theo dõi'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalOrders',
        icon: Icons.shopping_bag_outlined,
        title: 'Tổng số đơn hợp lệ',
        value: _integerLabel(summary.totalOrders),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'conversionRate',
        icon: Icons.percent_rounded,
        title: summary.resolvedCoverageLabel,
        value: _percentLabel(summary.coverageRate),
        trend: SummaryTrend.coverage(summary.coverageRate),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'totalReports',
        icon: Icons.description_outlined,
        title: 'Tổng số báo cáo hợp lệ',
        value: _integerLabel(summary.totalReports),
        trend: const SummaryTrend.neutral('không đổi'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'reportedOrders',
        icon: Icons.task_alt_rounded,
        title: 'Số đơn đã báo cáo',
        value: _integerLabel(summary.reportedOrders),
        trend: const SummaryTrend.neutral('không đổi'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'unreportedOrders',
        icon: Icons.assignment_late_outlined,
        title: 'Số đơn chưa báo cáo',
        value: _integerLabel(summary.unreportedOrders),
        trend: summary.unreportedOrders > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1120
            ? 6
            : width >= 900
            ? 3
            : width >= 620
            ? 2
            : 1;
        final gap = AppLayoutTokens.cardGap;
        final itemWidth = (width - (gap * math.max(0, columns - 1))) / columns;

        return Wrap(
          key: const Key('home-summary-grid'),
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.metricKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.trend,
    required this.color,
  });

  final String metricKey;
  final IconData icon;
  final String title;
  final String value;
  final SummaryTrend trend;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trendColor = trend.color;
    return AppSurfaceCard(
      key: Key('home-summary-card-$metricKey'),
      borderColor: color.withValues(alpha: 0.20),
      backgroundColor: color.withValues(alpha: 0.04),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                    AppLayoutTokens.cardRadius,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, color: color, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.headingM.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(trend.icon, size: 15, color: trendColor),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  trend.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.captionBold.copyWith(color: trendColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SummaryTrend {
  const SummaryTrend._({
    required this.label,
    required this.icon,
    required this.tone,
  });

  const SummaryTrend.success(String label)
    : this._(
        label: label,
        icon: Icons.trending_up_rounded,
        tone: SummaryTrendTone.success,
      );

  const SummaryTrend.warning(String label)
    : this._(
        label: label,
        icon: Icons.trending_up_rounded,
        tone: SummaryTrendTone.warning,
      );

  const SummaryTrend.neutral(String label)
    : this._(
        label: label,
        icon: Icons.remove_rounded,
        tone: SummaryTrendTone.neutral,
      );

  factory SummaryTrend.coverage(double coverageRate) {
    if (coverageRate >= 95) return const SummaryTrend.success('đã đủ');
    if (coverageRate <= 0) return const SummaryTrend.warning('chưa phủ');
    return const SummaryTrend.warning('cần bổ sung');
  }

  final String label;
  final IconData icon;
  final SummaryTrendTone tone;

  Color get color {
    return switch (tone) {
      SummaryTrendTone.success => AppColors.success,
      SummaryTrendTone.warning => AppColors.error,
      SummaryTrendTone.neutral => AppColors.neutral600,
    };
  }
}

enum SummaryTrendTone { success, warning, neutral }

class ReportProgressPanel extends StatelessWidget {
  const ReportProgressPanel({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final ratio = summary.totalOrders <= 0
        ? 0.0
        : summary.reportedOrders / summary.totalOrders;
    final progressValue = ratio.clamp(0.0, 1.0);
    final reportedPercent = summary.totalOrders <= 0
        ? 0.0
        : (summary.reportedOrders / summary.totalOrders) * 100;
    final missingPercent = math.max(0.0, 100 - reportedPercent);

    return AppSurfaceCard(
      key: const Key('home-summary-progress-panel'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tiến độ báo cáo',
            style: AppTextStyles.headingS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Theo dõi mức phủ báo cáo trong ngày để đội vận hành biết còn bao nhiêu đơn cần xử lý tiếp.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 680;
              final donut = ReportCoverageDonut(
                coverageRate: summary.coverageRate,
              );
              final legend = _ReportProgressLegend(
                reportedOrders: summary.reportedOrders,
                reportedPercent: reportedPercent,
                unreportedOrders: summary.unreportedOrders,
                missingPercent: missingPercent,
              );
              final bar = _ReportProgressBar(value: progressValue);

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: donut),
                    const SizedBox(height: 16),
                    legend,
                    const SizedBox(height: 16),
                    bar,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  donut,
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: legend,
                    ),
                  ),
                  Expanded(flex: 3, child: bar),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ReportCoverageDonut extends StatelessWidget {
  const ReportCoverageDonut({super.key, required this.coverageRate});

  final double coverageRate;

  @override
  Widget build(BuildContext context) {
    final value = (coverageRate / 100).clamp(0.0, 1.0);
    return SizedBox.square(
      key: const Key('home-summary-progress-donut'),
      dimension: 124,
      child: CustomPaint(
        painter: _CoverageDonutPainter(
          value: value,
          trackColor: AppColors.neutral100,
          valueColor: AppColors.success,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _percentLabel(coverageRate),
                style: AppTextStyles.headingM.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Tỷ lệ phủ',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportProgressLegend extends StatelessWidget {
  const _ReportProgressLegend({
    required this.reportedOrders,
    required this.reportedPercent,
    required this.unreportedOrders,
    required this.missingPercent,
  });

  final int reportedOrders;
  final double reportedPercent;
  final int unreportedOrders;
  final double missingPercent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportLegendRow(
          label: 'Đã báo cáo',
          value:
              '${_integerLabel(reportedOrders)} đơn (${_percentLabel(reportedPercent)})',
          color: AppColors.success,
        ),
        const SizedBox(height: 12),
        _ReportLegendRow(
          label: 'Còn thiếu',
          value:
              '${_integerLabel(unreportedOrders)} đơn (${_percentLabel(missingPercent)})',
          color: AppColors.error,
        ),
      ],
    );
  }
}

class _ReportLegendRow extends StatelessWidget {
  const _ReportLegendRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AppTextStyles.labelS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.labelS.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ReportProgressBar extends StatelessWidget {
  const _ReportProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: AppRadius.allXs,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 12,
            backgroundColor: AppColors.neutral100,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.success),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            _ProgressTick(label: '0%'),
            _ProgressTick(label: '50%'),
            _ProgressTick(label: '100%'),
          ],
        ),
      ],
    );
  }
}

class _ProgressTick extends StatelessWidget {
  const _ProgressTick({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTextStyles.caption.copyWith(
        color: AppColors.textMutedOf(context),
      ),
    );
  }
}

class _CoverageDonutPainter extends CustomPainter {
  const _CoverageDonutPainter({
    required this.value,
    required this.trackColor,
    required this.valueColor,
  });

  final double value;
  final Color trackColor;
  final Color valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.08;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final valuePaint = Paint()
      ..color = valueColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, valuePaint);
  }

  @override
  bool shouldRepaint(covariant _CoverageDonutPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.valueColor != valueColor;
  }
}

class HomeOperationsShortcutCard extends StatelessWidget {
  const HomeOperationsShortcutCard({super.key, required this.actions});

  final List<HomeQuickToolAction> actions;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('home-operations-shortcut'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Công cụ nhanh',
            style: AppTextStyles.headingS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chọn ngày để đổi phạm vi xem, hoặc làm mới khi cần đối soát số liệu mới nhất.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 900
                  ? 4
                  : width >= 620
                  ? 2
                  : 1;
              final gap = AppLayoutTokens.cardGap;
              final itemWidth =
                  (width - (gap * math.max(0, columns - 1))) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: itemWidth,
                      child: _HomeQuickToolTile(action: action),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class HomeQuickToolAction {
  const HomeQuickToolAction({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _HomeQuickToolTile extends StatelessWidget {
  const _HomeQuickToolTile({required this.action});

  final HomeQuickToolAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: ValueKey('home-quick-tool-${action.id}'),
      color: action.color.withValues(alpha: 0.04),
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: AppRadius.allSm,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allSm,
            border: Border.all(color: action.color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.allSm,
                ),
                child: Icon(action.icon, color: action.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textSecondaryOf(context),
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
}

String _dateLabel(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

String _timeOnlyLabel(DateTime value) =>
    DateFormat('HH:mm').format(value.toLocal());

String _integerLabel(int value) => vietnameseMoneyNumberFormat.format(value);

String _percentLabel(double value) {
  final rounded = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  return '$rounded%';
}
