import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../domain/home_summary.dart';
import '../providers/home_summary_provider.dart';

const _unselectedSalesProgressAssigneeValue =
    '__home_summary_unselected_sales_assignee__';

class HomeSummaryPage extends StatelessWidget {
  const HomeSummaryPage({super.key, required this.provider, this.headerAction});

  final HomeSummaryProvider provider;
  final Widget? headerAction;

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
          selectedScope: provider.selectedScope,
          selectedScopeLabel: provider.selectedScopeLabel,
          scopeOptions: provider.scopeOptions,
          selectedStartDate: provider.selectedStartDate,
          selectedEndDate: provider.selectedEndDate,
          isRefreshing: provider.isRefreshing || provider.isInitialLoading,
          onScopeChanged: provider.scopeOptions.length > 1
              ? (value) => unawaited(provider.setSelectedScope(value))
              : null,
          onDateRangeChanged: (start, end) =>
              unawaited(provider.setSelectedDateRange(start, end)),
          onRefresh: provider.canRefresh
              ? () => unawaited(provider.refreshNow())
              : null,
          warningMessage: provider.errorMessage != null && summary != null
              ? provider.errorMessage
              : null,
          action: headerAction,
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        // Keep the metrics dashboard tree stable: header, overview, KPI grids.
        ...content,
      ],
    );
  }

  List<Widget> _buildSummaryContent(HomeSummary? summary) {
    if (provider.isInitialLoading) {
      return [
        _buildStateCard(
          key: const Key('home-summary-loading'),
          child: const AppStatePanel.loading(
            title: 'Đang tải dashboard',
            message: 'Hệ thống đang tổng hợp số liệu theo phạm vi đã chọn.',
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
      ReportProgressPanel(summary: summary, provider: provider),
      const SizedBox(height: AppLayoutTokens.sectionGap),
      if (summary.salesAvailable) ...[
        const _SummarySectionHeader(
          key: Key('home-sales-section-header'),
          title: 'Bán hàng',
          icon: Icons.storefront_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(height: 10),
        const _SummarySubsectionHeader(title: 'Doanh số'),
        const SizedBox(height: 8),
        SummaryCardGrid(summary: summary),
        const SizedBox(height: 14),
        const _SummarySubsectionHeader(title: 'Hành vi then chốt'),
        const SizedBox(height: 8),
        SalesBehaviorSummaryCardGrid(summary: summary),
      ],
      if (summary.financeAvailable) ...[
        const SizedBox(height: AppLayoutTokens.sectionGap),
        const _SummarySectionHeader(
          key: Key('home-finance-section-header'),
          title: 'Tài chính',
          icon: Icons.account_balance_outlined,
          color: AppColors.success,
        ),
        const SizedBox(height: 10),
        FinanceSummaryCardGrid(summary: summary),
      ],
    ];
  }

  Widget _buildStateCard({required Key key, required Widget child}) {
    return AppSurfaceCard(key: key, child: child);
  }
}

class _SummarySectionHeader extends StatelessWidget {
  const _SummarySectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: AppRadius.allSm,
          ),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppTextStyles.headingS.copyWith(
            color: AppColors.textPrimaryOf(context),
          ),
        ),
      ],
    );
  }
}

class _SummarySubsectionHeader extends StatelessWidget {
  const _SummarySubsectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTextStyles.labelM.copyWith(
        color: AppColors.textSecondaryOf(context),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class HomeSummaryHeader extends StatelessWidget {
  const HomeSummaryHeader({
    super.key,
    required this.summary,
    required this.selectedScope,
    required this.selectedScopeLabel,
    required this.scopeOptions,
    required this.selectedStartDate,
    required this.selectedEndDate,
    required this.isRefreshing,
    required this.onScopeChanged,
    required this.onDateRangeChanged,
    required this.onRefresh,
    required this.warningMessage,
    this.action,
  });

  final HomeSummary? summary;
  final String selectedScope;
  final String selectedScopeLabel;
  final List<HomeSummaryScopeOption> scopeOptions;
  final DateTime? selectedStartDate;
  final DateTime? selectedEndDate;
  final bool isRefreshing;
  final ValueChanged<String>? onScopeChanged;
  final void Function(DateTime? start, DateTime? end) onDateRangeChanged;
  final VoidCallback? onRefresh;
  final String? warningMessage;
  final Widget? action;

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
            ],
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ScopeSelectorPill(
                label: selectedScopeLabel.isEmpty
                    ? scopeLabel
                    : selectedScopeLabel,
                selectedScope: selectedScope,
                options: scopeOptions,
                compact: false,
                dense: true,
                color: scopeColor,
                onSelected: onScopeChanged,
              ),
              SizedBox(
                key: const Key('home-summary-date-range'),
                width: compact ? double.infinity : 244,
                child: AppDateRangeDropdown(
                  label: 'Ngày',
                  start: selectedStartDate,
                  end: selectedEndDate,
                  onChanged: onDateRangeChanged,
                  showEmptyRangeHelperText: compact,
                  now: () => DateTime.now(),
                ),
              ),
              _HeaderActionPill(
                key: const Key('home-summary-refresh-button'),
                icon: Icons.schedule_outlined,
                label: updatedLabel,
                tooltip: 'Làm mới dashboard',
                isLoading: isRefreshing,
                onTap: onRefresh,
              ),
              if (action != null) action!,
            ],
          );

          final headerRow = compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleBlock, const SizedBox(height: 12), controls],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 20),
                    Flexible(child: controls),
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerRow,
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
  const _ScopeSelectorPill({
    required this.label,
    required this.selectedScope,
    required this.options,
    required this.compact,
    this.dense = false,
    this.color,
    required this.onSelected,
  });

  final String label;
  final String selectedScope;
  final List<HomeSummaryScopeOption> options;
  final bool compact;
  final bool dense;
  final Color? color;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final canSelect = options.length > 1 && onSelected != null;
    final effectiveColor = color ?? AppColors.primaryOf(context);
    final content = Container(
      key: const Key('home-summary-scope-pill'),
      constraints: BoxConstraints(
        minHeight: dense ? 30 : 40,
        maxWidth: compact
            ? double.infinity
            : dense
            ? 180
            : 220,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 9 : 14,
        vertical: dense ? 5 : 9,
      ),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.08),
        borderRadius: AppRadius.allSm,
        border: dense ? null : Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Icon(
            Icons.public_rounded,
            size: dense ? 14 : 18,
            color: effectiveColor,
          ),
          SizedBox(width: dense ? 5 : 8),
          if (compact)
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dense ? 112 : 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (canSelect) ...[
            SizedBox(width: dense ? 5 : 8),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: dense ? 16 : 18,
              color: effectiveColor,
            ),
          ],
        ],
      ),
    );

    final child = canSelect
        ? PopupMenuButton<String>(
            key: const Key('home-summary-scope-menu'),
            tooltip: 'Chọn phạm vi dashboard',
            initialValue: selectedScope,
            onSelected: onSelected,
            itemBuilder: (context) => [
              for (final option in options)
                PopupMenuItem<String>(
                  value: option.value,
                  child: Row(
                    children: [
                      Icon(
                        option.value == selectedScope
                            ? Icons.check_rounded
                            : Icons.public_rounded,
                        size: 18,
                        color: option.value == selectedScope
                            ? AppColors.primaryOf(context)
                            : AppColors.textMutedOf(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(option.label)),
                    ],
                  ),
                ),
            ],
            child: content,
          )
        : content;

    if (compact) return child;
    if (dense) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: child,
      );
    }
    return SizedBox(width: 220, child: child);
  }
}

class _HeaderActionPill extends StatelessWidget {
  const _HeaderActionPill({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    final color = enabled
        ? AppColors.neutral700
        : AppColors.textMutedOf(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.transparent,
        borderRadius: AppRadius.allSm,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.allSm,
          child: Container(
            constraints: const BoxConstraints(minHeight: 30),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.chipBackground,
              borderRadius: AppRadius.allSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: isLoading
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryOf(context),
                        )
                      : Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 5),
                Text(
                  isLoading ? 'Đang tải' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: AppTextStyles.labelS.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        title: 'Doanh số tổng',
        value: formatCompactVndAmount(summary.totalRevenue),
        trend: const SummaryTrend.neutral('Theo đơn cache'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalOrders',
        icon: Icons.shopping_bag_outlined,
        title: 'Số đơn bán',
        value: _integerLabel(summary.totalOrders),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'averageOrderValue',
        icon: Icons.show_chart_rounded,
        title: 'Trung bình đơn hàng',
        value: formatCompactVndAmount(summary.averageOrderValue),
        trend: const SummaryTrend.neutral('Doanh số/đơn'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'completedRevenue',
        icon: Icons.verified_outlined,
        title: 'Doanh số hoàn thành',
        value: formatCompactVndAmount(summary.completedRevenue),
        trend: const SummaryTrend.success('đã sync'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'pendingRevenue',
        icon: Icons.pending_actions_outlined,
        title: 'Pending',
        value: formatCompactVndAmount(summary.pendingRevenue),
        trend: summary.pendingRevenue > 0
            ? const SummaryTrend.warning('chưa hoàn thành')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warning,
      ),
      SummaryCard(
        metricKey: 'conversionRate',
        icon: Icons.swap_horiz_rounded,
        title: 'Tỉ lệ chuyển đổi',
        value: _percentLabel(summary.conversionRate),
        trend: SummaryTrend.conversion(summary.conversionRate),
        color: AppColors.secondary,
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-summary-grid'),
      cards: cards,
    );
  }
}

class SalesBehaviorSummaryCardGrid extends StatelessWidget {
  const SalesBehaviorSummaryCardGrid({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'notPurchasedReports',
        icon: Icons.person_search_outlined,
        title: 'Số khách chưa mua',
        value: _integerLabel(summary.notPurchasedReports),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.secondary,
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
      SummaryCard(
        metricKey: 'coverageRate',
        icon: Icons.percent_rounded,
        title: summary.resolvedCoverageLabel,
        value: _percentLabel(summary.coverageRate),
        trend: SummaryTrend.coverage(summary.coverageRate),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'consultedSolutionRate',
        icon: Icons.psychology_alt_outlined,
        title: 'Tỉ lệ 3 giải pháp',
        value: _percentLabel(summary.consultedSolutionRate),
        trend: SummaryTrend.yesRate(summary.consultedSolutionRate),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'experiencedRate',
        icon: Icons.touch_app_outlined,
        title: 'Tỉ lệ trải nghiệm',
        value: _percentLabel(summary.experiencedRate),
        trend: SummaryTrend.yesRate(summary.experiencedRate),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'zaloRate',
        icon: Icons.qr_code_2_outlined,
        title: 'Tỉ lệ Zalo OA',
        value: _percentLabel(summary.zaloRate),
        trend: SummaryTrend.yesRate(summary.zaloRate),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'appDownloadRate',
        icon: Icons.download_for_offline_outlined,
        title: 'Tỉ lệ tải App',
        value: _percentLabel(summary.appDownloadRate),
        trend: SummaryTrend.yesRate(summary.appDownloadRate),
        color: AppColors.secondary,
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-sales-behavior-summary-grid'),
      cards: cards,
    );
  }
}

class FinanceSummaryCardGrid extends StatelessWidget {
  const FinanceSummaryCardGrid({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'totalTransferredAmount',
        icon: Icons.account_balance_wallet_outlined,
        title: 'Tổng số tiền chuyển khoản',
        value: formatCompactVndAmount(summary.totalTransferredAmount),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalStatements',
        icon: Icons.receipt_long_outlined,
        title: 'Tổng số sao kê',
        value: _integerLabel(summary.totalStatements),
        trend: const SummaryTrend.neutral('Trong ngày'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithOrder',
        icon: Icons.task_alt_rounded,
        title: 'Tổng sao kê có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithOrder),
        trend: const SummaryTrend.success('đã đối chiếu'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithoutOrder',
        icon: Icons.assignment_late_outlined,
        title: 'Tổng sao kê chưa có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithoutOrder),
        trend: summary.totalStatementsWithoutOrder > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warning,
      ),
      SummaryCard(
        metricKey: 'statementOrderRate',
        icon: Icons.percent_rounded,
        title: 'Tỉ lệ sao kê có đơn hàng',
        value: _percentLabel(summary.statementOrderRate),
        trend: SummaryTrend.statementOrder(summary.statementOrderRate),
        color: AppColors.info,
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-finance-summary-grid'),
      cards: cards,
    );
  }
}

class _SummaryMetricGrid extends StatelessWidget {
  const _SummaryMetricGrid({required this.gridKey, required this.cards});

  final Key gridKey;
  final List<SummaryCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final desiredColumns = width >= 1120
            ? cards.length
            : width >= 900
            ? 3
            : width >= 320
            ? 2
            : 1;
        final columns = math.min(desiredColumns, cards.length);
        final gap = AppLayoutTokens.cardGap;
        final itemWidth = (width - (gap * math.max(0, columns - 1))) / columns;

        return Wrap(
          key: gridKey,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(
                width: itemWidth,
                height: width >= 620 ? 138 : 146,
                child: card,
              ),
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
          const Spacer(),
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
    if (coverageRate <= 0) return const SummaryTrend.warning('chưa báo cáo');
    return const SummaryTrend.warning('cần bổ sung');
  }

  factory SummaryTrend.conversion(double conversionRate) {
    if (conversionRate >= 50) return const SummaryTrend.success('chốt tốt');
    if (conversionRate <= 0) return const SummaryTrend.warning('chưa có đơn');
    return const SummaryTrend.warning('cần cải thiện');
  }

  factory SummaryTrend.yesRate(double rate) {
    if (rate >= 80) return const SummaryTrend.success('đang tốt');
    if (rate <= 0) return const SummaryTrend.warning('chưa có');
    return const SummaryTrend.warning('cần cải thiện');
  }

  factory SummaryTrend.statementOrder(double statementOrderRate) {
    if (statementOrderRate >= 95) {
      return const SummaryTrend.success('đã đối chiếu');
    }
    if (statementOrderRate <= 0) {
      return const SummaryTrend.warning('chưa có đơn');
    }
    return const SummaryTrend.warning('cần đối chiếu');
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
  const ReportProgressPanel({
    super.key,
    required this.summary,
    required this.provider,
  });

  final HomeSummary summary;
  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    final reportedPercent = summary.totalOrders <= 0
        ? 0.0
        : (summary.reportedOrders / summary.totalOrders) * 100;
    final missingPercent = math.max(0.0, 100 - reportedPercent);
    final reportPanel = summary.salesAvailable
        ? _ProgressDonutPanel(
            panelKey: const Key('home-report-progress-panel'),
            title: 'Tiến độ báo cáo',
            percentage: summary.coverageRate,
            color: AppColors.success,
            legend: _ReportProgressLegend(
              reportedOrders: summary.reportedOrders,
              reportedPercent: reportedPercent,
              unreportedOrders: summary.unreportedOrders,
              missingPercent: missingPercent,
            ),
          )
        : null;
    final statementPanel = summary.financeAvailable
        ? _ProgressDonutPanel(
            panelKey: const Key('home-statement-progress-panel'),
            title: 'Tiến độ sao kê',
            percentage: summary.statementOrderRate,
            color: AppColors.info,
            legend: Column(
              children: [
                _ReportLegendRow(
                  label: 'Có đơn hàng',
                  value:
                      '${_integerLabel(summary.totalStatementsWithOrder)} sao kê',
                  color: AppColors.success,
                ),
                const SizedBox(height: 8),
                _ReportLegendRow(
                  label: 'Chưa có đơn',
                  value:
                      '${_integerLabel(summary.totalStatementsWithoutOrder)} sao kê',
                  color: AppColors.error,
                ),
              ],
            ),
          )
        : null;
    final personalPanel =
        summary.salesAvailable &&
            (summary.personalSalesProgress.isApplicable ||
                summary.salesProgressAssignees.isNotEmpty)
        ? _SalesProgressPanel(
            panelKey: const Key('home-sales-progress-panel'),
            title: 'Tổng quan cá nhân',
            progress: summary.personalSalesProgress,
            rangeLabel: summary.startDate == summary.endDate
                ? 'Ngày'
                : 'Khoảng chọn',
            keyPrefix: 'home-sales-progress',
            color: AppColors.violet600,
            assignees: summary.salesProgressAssignees,
            selectedAssigneeId: summary.selectedSalesProgressUserId,
            emptyMessage: summary.selectedSalesProgressUserId == null
                ? 'Chọn SA để hiển thị chỉ số'
                : null,
            onAssigneeChanged: provider.isLoading || provider.isRefreshing
                ? null
                : (userId) =>
                      unawaited(provider.setSelectedSalesProgressUser(userId)),
          )
        : null;
    final scopePanel =
        summary.salesAvailable && summary.scopeSalesProgress.isApplicable
        ? _SalesProgressPanel(
            panelKey: const Key('home-scope-sales-progress-panel'),
            title: _scopeSalesProgressTitle(summary),
            progress: summary.scopeSalesProgress,
            rangeLabel: summary.startDate == summary.endDate
                ? 'Ngày'
                : 'Khoảng chọn',
            keyPrefix: 'home-scope-sales-progress',
            color: AppColors.primary,
          )
        : null;
    final panels = <Widget>[
      if (reportPanel != null) reportPanel,
      if (statementPanel != null) statementPanel,
      if (personalPanel != null) personalPanel,
      if (scopePanel != null) scopePanel,
    ];

    return AppSurfaceCard(
      key: const Key('home-summary-progress-panel'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng quan',
            style: AppTextStyles.headingS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (panels.isEmpty) return const SizedBox.shrink();
              final gap = 16.0;
              if (constraints.maxWidth >= 1040 &&
                  reportPanel != null &&
                  statementPanel != null &&
                  personalPanel != null &&
                  scopePanel != null) {
                return SizedBox(
                  height: 330,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: reportPanel),
                            SizedBox(width: gap),
                            Expanded(child: statementPanel),
                          ],
                        ),
                      ),
                      SizedBox(width: gap),
                      Expanded(child: personalPanel),
                      SizedBox(width: gap),
                      Expanded(child: scopePanel),
                    ],
                  ),
                );
              }
              final hasSalesProgressPanels =
                  summary.salesAvailable &&
                  (personalPanel != null || scopePanel != null);
              final minReadablePanelWidth = hasSalesProgressPanels
                  ? 420.0
                  : 280.0;
              final fullRowWidth =
                  panels.length * minReadablePanelWidth +
                  gap * math.max(0, panels.length - 1);
              final columns = constraints.maxWidth >= fullRowWidth
                  ? panels.length
                  : constraints.maxWidth >= 720
                  ? math.min(2, panels.length)
                  : 1;
              final width =
                  (constraints.maxWidth - gap * math.max(0, columns - 1)) /
                  math.max(1, columns);
              final height = constraints.maxWidth >= 980
                  ? 300.0
                  : constraints.maxWidth >= 620
                  ? 292.0
                  : 300.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final panel in panels)
                    SizedBox(width: width, height: height, child: panel),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static String _scopeSalesProgressTitle(HomeSummary summary) {
    final scope = summary.scope.trim().toUpperCase();
    final label = summary.resolvedScopeLabel.toLowerCase();
    if (scope == 'ALL') {
      return 'Tổng quan toàn hệ thống';
    }
    if (scope == 'OWN') return 'Tổng quan Cửa hàng';
    if (label.contains('miền')) return 'Tổng quan Miền';
    if (label.contains('vùng')) return 'Tổng quan Vùng';
    if (label.contains('showroom') ||
        label.contains('cửa hàng') ||
        label.contains('sr')) {
      return 'Tổng quan Cửa hàng';
    }
    return 'Tổng quan Miền/Vùng/Cửa hàng';
  }
}

class _ProgressDonutPanel extends StatelessWidget {
  const _ProgressDonutPanel({
    required this.panelKey,
    required this.title,
    required this.percentage,
    required this.color,
    required this.legend,
  });

  final Key panelKey;
  final String title;
  final double percentage;
  final Color color;
  final Widget legend;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: panelKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: AppTextStyles.labelM),
          const SizedBox(height: 10),
          _ProgressDonut(
            key: title == 'Tiến độ báo cáo'
                ? const Key('home-summary-progress-donut')
                : const Key('home-statement-progress-donut'),
            percentage: percentage,
            color: color,
            dimension: 92,
          ),
          const SizedBox(height: 12),
          legend,
        ],
      ),
    );
  }
}

class _ProgressDonut extends StatelessWidget {
  const _ProgressDonut({
    super.key,
    required this.percentage,
    required this.color,
    required this.dimension,
  });

  final double? percentage;
  final Color color;
  final double dimension;

  @override
  Widget build(BuildContext context) {
    final display = percentage == null ? '--' : _percentLabel(percentage!);
    return SizedBox.square(
      dimension: dimension,
      child: CustomPaint(
        painter: _CoverageDonutPainter(
          value: ((percentage ?? 0) / 100).clamp(0.0, 1.0),
          trackColor: AppColors.neutral100,
          valueColor: color,
        ),
        child: Center(
          child: Text(
            display,
            style: AppTextStyles.labelL.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesProgressPanel extends StatelessWidget {
  const _SalesProgressPanel({
    required this.panelKey,
    required this.title,
    required this.progress,
    required this.rangeLabel,
    required this.keyPrefix,
    required this.color,
    this.assignees = const [],
    this.selectedAssigneeId,
    this.emptyMessage,
    this.onAssigneeChanged,
  });

  final Key panelKey;
  final String title;
  final HomeSalesProgress progress;
  final String rangeLabel;
  final String keyPrefix;
  final Color color;
  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final String? emptyMessage;
  final ValueChanged<String?>? onAssigneeChanged;

  @override
  Widget build(BuildContext context) {
    final resolvedEmptyMessage = emptyMessage?.trim();
    final showEmptyPrompt =
        !progress.isApplicable &&
        resolvedEmptyMessage != null &&
        resolvedEmptyMessage.isNotEmpty;
    return Container(
      key: panelKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, textAlign: TextAlign.center, style: AppTextStyles.labelM),
          if (assignees.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SalesProgressAssigneeDropdown(
              assignees: assignees,
              selectedAssigneeId: selectedAssigneeId,
              onChanged: onAssigneeChanged,
            ),
          ],
          const SizedBox(height: 10),
          if (showEmptyPrompt)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_rounded, size: 28, color: color),
                      const SizedBox(height: 8),
                      Text(
                        resolvedEmptyMessage,
                        key: const Key('home-sales-progress-empty-guidance'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.textMutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SalesProgressPeriodView(
                      keyPrefix: keyPrefix,
                      keySuffix: 'range',
                      label: rangeLabel,
                      period: progress.range,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SalesProgressPeriodView(
                      keyPrefix: keyPrefix,
                      keySuffix: 'week',
                      label: 'Tuần',
                      period: progress.week,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SalesProgressPeriodView(
                      keyPrefix: keyPrefix,
                      keySuffix: 'month',
                      label: 'Tháng',
                      period: progress.month,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          if (!showEmptyPrompt && !progress.hasTarget) ...[
            const SizedBox(height: 8),
            Text(
              progress.missingStoreCodes.isEmpty
                  ? 'Chưa có chỉ tiêu để tính tiến độ.'
                  : 'Thiếu chỉ tiêu: ${progress.missingStoreCodes.join(', ')}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _SalesProgressAssigneeDropdown extends StatelessWidget {
  const _SalesProgressAssigneeDropdown({
    required this.assignees,
    required this.selectedAssigneeId,
    required this.onChanged,
  });

  static const int searchThreshold = 10;

  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = selectedAssigneeId == null
        ? null
        : assignees
              .where((assignee) => assignee.userId == selectedAssigneeId)
              .firstOrNull;
    final value = selected?.userId ?? _unselectedSalesProgressAssigneeValue;
    if (assignees.length > searchThreshold) {
      return _SalesProgressAssigneeSearchButton(
        assignees: assignees,
        selectedAssignee: selected,
        onChanged: onChanged,
      );
    }
    return Container(
      key: const Key('home-sales-progress-assignee-dropdown'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context).withValues(alpha: 0.7),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: AppRadius.allSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          dropdownColor: AppColors.overlayOf(context),
          borderRadius: AppRadius.allMd,
          style: AppTextStyles.labelS.copyWith(
            color: AppColors.textPrimaryOf(context),
          ),
          onChanged: onChanged == null
              ? null
              : (value) => onChanged!(
                  value == _unselectedSalesProgressAssigneeValue ? null : value,
                ),
          items: [
            DropdownMenuItem<String>(
              value: _unselectedSalesProgressAssigneeValue,
              child: Row(
                children: [
                  const Icon(Icons.person_off_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chưa chọn SA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            for (final assignee in assignees)
              DropdownMenuItem<String>(
                value: assignee.userId,
                child: Row(
                  children: [
                    const Icon(Icons.person_search_rounded, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _assigneeLabel(assignee),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  static String _assigneeLabel(HomeSalesProgressAssignee assignee) {
    final stores = assignee.storeCodes.join(', ');
    if (stores.isEmpty) return assignee.label;
    return '${assignee.label} - $stores';
  }
}

class _SalesProgressAssigneeSearchButton extends StatelessWidget {
  const _SalesProgressAssigneeSearchButton({
    required this.assignees,
    required this.selectedAssignee,
    required this.onChanged,
  });

  final List<HomeSalesProgressAssignee> assignees;
  final HomeSalesProgressAssignee? selectedAssignee;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('home-sales-progress-assignee-dropdown'),
      color: AppColors.cardOf(context).withValues(alpha: 0.7),
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: onChanged == null ? null : () => _openSearch(context),
        borderRadius: AppRadius.allSm,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: AppRadius.allSm,
          ),
          child: Row(
            children: [
              const Icon(Icons.person_search_rounded, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selectedAssignee == null
                      ? 'Chưa chọn SA'
                      : _SalesProgressAssigneeDropdown._assigneeLabel(
                          selectedAssignee!,
                        ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.search_rounded, size: 17),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSearch(BuildContext context) async {
    final selectedUserId = await showDialog<String>(
      context: context,
      barrierColor: AppColors.shadow.withValues(alpha: 0.48),
      builder: (context) {
        return _SalesProgressAssigneeSearchDialog(
          assignees: assignees,
          selectedAssigneeId: selectedAssignee?.userId,
        );
      },
    );
    if (selectedUserId == null) return;
    final nextUserId = selectedUserId == _unselectedSalesProgressAssigneeValue
        ? null
        : selectedUserId;
    if (nextUserId == selectedAssignee?.userId ||
        (nextUserId == null && selectedAssignee == null)) {
      return;
    }
    onChanged?.call(nextUserId);
  }
}

class _SalesProgressAssigneeSearchDialog extends StatefulWidget {
  const _SalesProgressAssigneeSearchDialog({
    required this.assignees,
    required this.selectedAssigneeId,
  });

  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;

  @override
  State<_SalesProgressAssigneeSearchDialog> createState() =>
      _SalesProgressAssigneeSearchDialogState();
}

class _SalesProgressAssigneeSearchDialogState
    extends State<_SalesProgressAssigneeSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAssignees();
    final noAssigneeSelected = widget.selectedAssigneeId == null;
    return Dialog(
      key: const Key('home-sales-progress-assignee-search-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chọn SA',
                      style: AppTextStyles.labelM.copyWith(
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppTextInput(
                key: const Key('home-sales-progress-assignee-search-input'),
                controller: _controller,
                label: 'Tìm nhân viên',
                icon: Icons.search_rounded,
                autofocus: true,
                textInputAction: TextInputAction.search,
                dense: true,
                hintText: 'Tìm theo tên hoặc email',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const Key('home-sales-progress-assignee-option-none'),
                dense: true,
                leading: Icon(
                  noAssigneeSelected
                      ? Icons.check_circle_rounded
                      : Icons.person_off_outlined,
                  color: noAssigneeSelected
                      ? AppColors.success
                      : AppColors.textMutedOf(context),
                ),
                title: const Text('Chưa chọn SA'),
                subtitle: const Text('Chọn SA để hiển thị chỉ số'),
                onTap: () => Navigator.of(
                  context,
                ).pop(_unselectedSalesProgressAssigneeValue),
              ),
              Divider(height: 1, color: AppColors.subtleBorderOf(context)),
              const SizedBox(height: 4),
              Flexible(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'Không tìm thấy SA phù hợp.',
                            style: AppTextStyles.bodyS.copyWith(
                              color: AppColors.textMutedOf(context),
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: AppColors.subtleBorderOf(context),
                        ),
                        itemBuilder: (context, index) {
                          final assignee = filtered[index];
                          final selected =
                              assignee.userId == widget.selectedAssigneeId;
                          return ListTile(
                            key: Key(
                              'home-sales-progress-assignee-option-${assignee.userId}',
                            ),
                            dense: true,
                            leading: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.person_outline_rounded,
                              color: selected
                                  ? AppColors.success
                                  : AppColors.textMutedOf(context),
                            ),
                            title: Text(
                              assignee.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _assigneeSubtitle(assignee),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                Navigator.of(context).pop(assignee.userId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<HomeSalesProgressAssignee> _filteredAssignees() {
    final query = _normalize(_query);
    if (query.isEmpty) return widget.assignees;
    return widget.assignees
        .where((assignee) {
          final haystack = _normalize(
            [
              assignee.label,
              assignee.email,
              assignee.storeCodes.join(' '),
            ].whereType<String>().join(' '),
          );
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  static String _assigneeSubtitle(HomeSalesProgressAssignee assignee) {
    final parts = [
      if (assignee.storeCodes.isNotEmpty) assignee.storeCodes.join(', '),
      if (assignee.email?.isNotEmpty == true) assignee.email!,
    ];
    return parts.join(' - ');
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}

class _SalesProgressPeriodView extends StatelessWidget {
  const _SalesProgressPeriodView({
    required this.keyPrefix,
    required this.keySuffix,
    required this.label,
    required this.period,
    required this.color,
  });

  final String keyPrefix;
  final String keySuffix;
  final String label;
  final HomeSalesProgressPeriod period;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: Key('$keyPrefix-$keySuffix'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ProgressDonut(
            key: Key('$keyPrefix-$keySuffix-donut'),
            percentage: period.percentage,
            color: color,
            dimension: 68,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelS,
          ),
          const SizedBox(height: 2),
          Text(
            key: Key('$keyPrefix-$keySuffix-actual-label'),
            'Đã đạt: ${formatCompactVndAmount(period.actual)}',
            maxLines: 2,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMutedOf(context),
            ),
          ),
          Text(
            key: Key('$keyPrefix-$keySuffix-target-label'),
            period.target == null
                ? 'Chỉ tiêu: Chưa thiết lập'
                : 'Chỉ tiêu: ${formatCompactVndAmount(period.target!)}',
            maxLines: 2,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMutedOf(context),
            ),
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
                'Tỉ lệ báo cáo',
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

extension _FirstOrNullHomeSummaryWidgets<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: compact ? 72 : 96,
              child: Text(
                label,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: compact ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(color: color),
              ),
            ),
          ],
        );
      },
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
                      height: 96,
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
          height: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allSm,
            border: Border.all(color: action.color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                key: ValueKey('home-quick-tool-icon-${action.id}'),
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
                  key: ValueKey('home-quick-tool-content-${action.id}'),
                  mainAxisSize: MainAxisSize.min,
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

String _timeOnlyLabel(DateTime value) =>
    DateFormat('HH:mm').format(value.toLocal());

String _integerLabel(int value) => vietnameseMoneyNumberFormat.format(value);

String _percentLabel(double value) {
  final rounded = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  return '$rounded%';
}
