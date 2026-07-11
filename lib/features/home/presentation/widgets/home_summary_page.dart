import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_filter_dropdowns.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/formatting/money_formatters.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/home_summary.dart';
import '../providers/home_summary_provider.dart';

class HomeSummaryPage extends StatelessWidget {
  const HomeSummaryPage({
    super.key,
    required this.provider,
    this.headerAction,
    this.footer,
    this.greetingName,
    this.greetingNow,
  });

  final HomeSummaryProvider provider;
  final Widget? headerAction;
  final Widget? footer;
  final String? greetingName;
  final DateTime Function()? greetingNow;

  @override
  Widget build(BuildContext context) {
    final summary = provider.summary;
    final content = _buildSummaryContent(summary);

    final scrollableContent = <Widget>[
      // Keep the metrics dashboard tree stable: overview, KPI grids, footer.
      ...content,
      if (footer != null) ...[
        const SizedBox(height: AppLayoutTokens.cardGap),
        footer!,
      ],
      const SizedBox(height: 20),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final header = HomeSummaryHeader(
          summary: summary,
          greetingName: greetingName,
          greetingNow: greetingNow,
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
        );
        final canOwnScroll =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        final body = canOwnScroll
            ? SingleChildScrollView(
                key: const Key('home-summary-scroll-body'),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: scrollableContent,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: scrollableContent,
              );

        return Column(
          key: const Key('home-summary-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: AppLayoutTokens.cardGap),
            if (canOwnScroll) Expanded(child: body) else body,
          ],
        );
      },
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
        const _SummarySubsectionHeader(title: 'KPI chính'),
        const SizedBox(height: 8),
        MainKpiSummaryCardGrid(summary: summary, provider: provider),
        const SizedBox(height: 14),
        const _SummarySubsectionHeader(title: 'Hành vi then chốt'),
        const SizedBox(height: 8),
        SalesBehaviorSummaryCardGrid(summary: summary, provider: provider),
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
        FinanceSummaryCardGrid(summary: summary, provider: provider),
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

String homeGreetingLabel(String? rawName, {DateTime Function()? now}) {
  final name = _homeGreetingName(rawName);
  final vietnamNow = (now ?? DateTime.now)().toUtc().add(
    const Duration(hours: 7),
  );
  final prefix = switch (vietnamNow.hour) {
    >= 5 && < 12 => 'Chào buổi sáng',
    >= 12 && < 18 => 'Chào buổi chiều',
    _ => 'Chào buổi tối',
  };
  return '$prefix $name';
}

String _homeGreetingName(String? rawName) {
  final trimmed = rawName?.trim();
  if (trimmed == null || trimmed.isEmpty) return 'bạn';
  if (trimmed.contains('@')) return trimmed.split('@').first;
  return trimmed;
}

class HomeSummaryHeader extends StatelessWidget {
  const HomeSummaryHeader({
    super.key,
    required this.summary,
    this.greetingName,
    this.greetingNow,
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
  final String? greetingName;
  final DateTime Function()? greetingNow;
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
    final greetingLabel = homeGreetingLabel(greetingName, now: greetingNow);
    final scopeLabel = summary?.resolvedScopeLabel ?? 'Đang đồng bộ phạm vi';
    final updatedLabel = summary?.refreshedAt == null
        ? 'Đang cập nhật'
        : 'Cập nhật ${_timeOnlyLabel(summary!.refreshedAt!)}';

    return AppSurfaceCard(
      key: const Key('home-summary-header'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final stackControls = constraints.maxWidth < 560;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.headingM.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          );
          final controlChildren = [
            _ScopeSelectorField(
              label: selectedScopeLabel.isEmpty
                  ? scopeLabel
                  : selectedScopeLabel,
              selectedScope: selectedScope,
              options: scopeOptions,
              fillWidth: stackControls,
              onSelected: onScopeChanged,
            ),
            SizedBox(
              key: const Key('home-summary-date-range'),
              width: stackControls ? double.infinity : 244,
              child: AppDateRangeDropdown(
                label: 'Ngày',
                start: selectedStartDate,
                end: selectedEndDate,
                onChanged: onDateRangeChanged,
                showEmptyRangeHelperText: stackControls,
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
          ];
          final controls = stackControls
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: controlChildren,
                )
              : Align(
                  alignment: compact
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < controlChildren.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 8),
                          controlChildren[index],
                        ],
                      ],
                    ),
                  ),
                );

          final headerRow = compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleBlock, const SizedBox(height: 12), controls],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 2, child: titleBlock),
                    const SizedBox(width: 20),
                    Expanded(flex: 5, child: controls),
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

class _ScopeSelectorField extends StatelessWidget {
  const _ScopeSelectorField({
    required this.label,
    required this.selectedScope,
    required this.options,
    required this.fillWidth,
    required this.onSelected,
  });

  final String label;
  final String selectedScope;
  final List<HomeSummaryScopeOption> options;
  final bool fillWidth;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final canSelect = options.length > 1 && onSelected != null;
    final selectedValue = options.any((option) => option.value == selectedScope)
        ? selectedScope
        : null;
    return SizedBox(
      key: const Key('home-summary-scope-pill'),
      width: fillWidth ? double.infinity : 232,
      child: AppCombobox<String>.single(
        label: 'Phạm vi',
        value: selectedValue,
        icon: Icons.store_outlined,
        dense: true,
        enabled: canSelect,
        allowClear: false,
        emptyLabel: label,
        maxMenuHeight: 320,
        options: [
          for (final option in options)
            AppComboboxOption<String>(
              value: option.value,
              label: option.label,
              subtitle: _scopeOptionSubtitle(option),
              searchKeywords: [
                option.value,
                option.label,
                option.requestScope,
                option.organizationNodeId ?? '',
              ],
            ),
        ],
        onChanged: canSelect
            ? (value) {
                if (value == null) return;
                onSelected?.call(value);
              }
            : null,
      ),
    );
  }

  static String? _scopeOptionSubtitle(HomeSummaryScopeOption option) {
    final count = option.storeCount;
    if (count == null || count <= 0) return null;
    return '$count showroom';
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
        title: 'Giá trị bán',
        value: formatCompactVndAmount(summary.totalRevenue),
        trend: const SummaryTrend.neutral('Theo đơn cache'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalOrders',
        icon: Icons.shopping_bag_outlined,
        title: 'Đơn bán',
        value: _integerLabel(summary.totalOrders),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'averageOrderValue',
        icon: Icons.show_chart_rounded,
        title: 'Trung bình đơn hàng',
        value: formatCompactVndAmount(summary.averageOrderValue),
        trend: const SummaryTrend.neutral('Giá trị/đơn'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'completedRevenue',
        icon: Icons.verified_outlined,
        title: 'Hoàn thành',
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

class MainKpiSummaryCardGrid extends StatelessWidget {
  const MainKpiSummaryCardGrid({
    super.key,
    required this.summary,
    required this.provider,
  });

  final HomeSummary summary;
  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    final firstRow = [
      SummaryCard(
        metricKey: 'businessCustomerRevenue',
        icon: Icons.business_center_outlined,
        title: 'Khách doanh nghiệp',
        value: formatCompactVndAmount(summary.businessCustomerRevenue),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'personalCustomerRevenue',
        icon: Icons.person_outline_rounded,
        title: 'Khách cá nhân',
        value: formatCompactVndAmount(summary.personalCustomerRevenue),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'examScorePromotionCount',
        icon: Icons.redeem_outlined,
        title: 'CTKM đổi điểm thi',
        value: _integerLabel(summary.examScorePromotionCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'studentPromotionCount',
        icon: Icons.school_outlined,
        title: 'CTKM HSSV',
        value: _integerLabel(summary.studentPromotionCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'installmentNeedCount',
        icon: Icons.request_quote_outlined,
        title: 'Nhu cầu trả góp',
        value: _integerLabel(summary.installmentNeedCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.warning,
        textTapTooltip: 'Xem chi tiết nhu cầu trả góp',
        onTextTap: () => _openInstallmentNeedDetailsDialog(context, provider),
      ),
      SummaryCard(
        metricKey: 'successfulInstallmentCount',
        icon: Icons.verified_user_outlined,
        title: 'Trả góp thành công',
        value: _integerLabel(summary.successfulInstallmentCount),
        trend: const SummaryTrend.success('Có đơn trả góp'),
        color: AppColors.success,
      ),
    ];
    final secondRow = [
      SummaryCard(
        metricKey: 'extendedInsuranceQuantity',
        icon: Icons.health_and_safety_outlined,
        title: 'Bảo hiểm mở rộng',
        value: _integerLabel(summary.extendedInsuranceQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'laptopQuantity',
        icon: Icons.laptop_mac_outlined,
        title: 'Laptop',
        value: _integerLabel(summary.laptopQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'pcQuantity',
        icon: Icons.desktop_windows_outlined,
        title: 'PC bộ',
        value: _integerLabel(summary.pcQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'assembledPcQuantity',
        icon: Icons.memory_outlined,
        title: 'PC ráp',
        value: _integerLabel(summary.assembledPcQuantity),
        trend: const SummaryTrend.neutral('Theo bộ ráp'),
        color: AppColors.warning,
      ),
      SummaryCard(
        metricKey: 'appleQuantity',
        icon: Icons.devices_other_outlined,
        title: 'Apple',
        value: _integerLabel(summary.appleQuantity),
        trend: const SummaryTrend.neutral('iPhone/MacBook/iPad'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'monitorQuantity',
        icon: Icons.monitor_outlined,
        title: 'Màn hình',
        value: _integerLabel(summary.monitorQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'printerQuantity',
        icon: Icons.print_outlined,
        title: 'Máy in',
        value: _integerLabel(summary.printerQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'accessoriesQuantity',
        icon: Icons.cable_outlined,
        title: 'Phụ kiện',
        value: _integerLabel(summary.accessoriesQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.info,
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-main-kpi-summary-grid'),
      cards: [...firstRow, ...secondRow],
    );
  }
}

class SalesBehaviorSummaryCardGrid extends StatelessWidget {
  const SalesBehaviorSummaryCardGrid({
    super.key,
    required this.summary,
    required this.provider,
  });

  final HomeSummary summary;
  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'notPurchasedReports',
        icon: Icons.person_search_outlined,
        title: 'Khách chưa mua',
        value: _integerLabel(summary.notPurchasedReports),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.secondary,
        textTapTooltip: 'Xem chi tiết khách chưa mua',
        onTextTap: () => _openSalesBehaviorDetailsDialog(
          context,
          provider,
          _SalesBehaviorDetailTab.notPurchased,
        ),
      ),
      SummaryCard(
        metricKey: 'unreportedOrders',
        icon: Icons.assignment_late_outlined,
        title: 'Đơn chưa báo cáo',
        value: _integerLabel(summary.unreportedOrders),
        trend: summary.unreportedOrders > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warning,
        textTapTooltip: 'Xem chi tiết đơn chưa báo cáo',
        onTextTap: () => _openSalesBehaviorDetailsDialog(
          context,
          provider,
          _SalesBehaviorDetailTab.unreported,
        ),
      ),
      SummaryCard(
        metricKey: 'reportedOrders',
        icon: Icons.fact_check_outlined,
        title: 'Báo cáo đã mua',
        value: _integerLabel(summary.reportedOrders),
        trend: const SummaryTrend.success('đã ghi nhận'),
        color: AppColors.success,
        textTapTooltip: provider.canOpenSalesReportAdmin
            ? 'Mở Quản trị/Báo cáo bán hàng'
            : null,
        onTextTap: provider.canOpenSalesReportAdmin
            ? () => _openSalesReportAdmin(context, provider)
            : null,
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
  const FinanceSummaryCardGrid({
    super.key,
    required this.summary,
    required this.provider,
  });

  final HomeSummary summary;
  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'totalTransferredAmount',
        icon: Icons.account_balance_wallet_outlined,
        title: 'Tiền chuyển khoản',
        value: formatCompactVndAmount(summary.totalTransferredAmount),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalStatements',
        icon: Icons.receipt_long_outlined,
        title: 'Sao kê',
        value: _integerLabel(summary.totalStatements),
        trend: const SummaryTrend.neutral('Trong ngày'),
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithOrder',
        icon: Icons.task_alt_rounded,
        title: 'Sao kê có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithOrder),
        trend: const SummaryTrend.success('đã đối chiếu'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithoutOrder',
        icon: Icons.assignment_late_outlined,
        title: 'Sao kê chưa có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithoutOrder),
        trend: summary.totalStatementsWithoutOrder > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warning,
        textTapTooltip: provider.canOpenBankStatement
            ? 'Mở Sao kê với bộ lọc chưa có đơn hàng'
            : null,
        onTextTap: provider.canOpenBankStatement
            ? () => _openMissingOrderStatements(context, provider)
            : null,
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
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxColumns = width >= 1040
            ? math.min(7, cards.length)
            : width >= 760
            ? math.min(3, cards.length)
            : math.min(2, cards.length);
        final rows = _balancedRows(cards, maxColumns);
        final gap = AppLayoutTokens.cardGap;

        return Column(
          key: gridKey,
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
              if (rowIndex > 0) SizedBox(height: gap),
              Row(
                children: [
                  for (
                    var columnIndex = 0;
                    columnIndex < rows[rowIndex].length;
                    columnIndex++
                  ) ...[
                    if (columnIndex > 0) SizedBox(width: gap),
                    Expanded(
                      child: SizedBox(
                        height: width >= 620 ? 130 : 146,
                        child: rows[rowIndex][columnIndex],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  static List<List<SummaryCard>> _balancedRows(
    List<SummaryCard> cards,
    int maxColumns,
  ) {
    final columns = math.max(1, math.min(maxColumns, cards.length));
    final rowCount = (cards.length / columns).ceil();
    final baseCount = cards.length ~/ rowCount;
    final extraCount = cards.length % rowCount;
    var index = 0;

    return [
      for (var rowIndex = 0; rowIndex < rowCount; rowIndex++)
        () {
          final rowSize = baseCount + (rowIndex < extraCount ? 1 : 0);
          final row = cards.sublist(index, index + rowSize);
          index += rowSize;
          return row;
        }(),
    ];
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
    this.onTextTap,
    this.textTapTooltip,
  });

  final String metricKey;
  final IconData icon;
  final String title;
  final String value;
  final SummaryTrend trend;
  final Color color;
  final VoidCallback? onTextTap;
  final String? textTapTooltip;

  @override
  Widget build(BuildContext context) {
    final trendColor = trend.color;
    final lowerText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
    );
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
                child: _SummaryCardTextAction(
                  key: Key('home-summary-card-$metricKey-title-action'),
                  onTap: onTextTap,
                  tooltip: textTapTooltip,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelM.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
              if (onTextTap != null) ...[
                const SizedBox(width: 4),
                _SummaryCardTextAction(
                  key: Key('home-summary-card-$metricKey-detail-action'),
                  onTap: onTextTap,
                  tooltip: textTapTooltip,
                  child: Icon(
                    Icons.open_in_new_rounded,
                    key: Key('home-summary-card-$metricKey-detail-icon'),
                    size: 15,
                    color: AppColors.textMutedOf(context),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          _SummaryCardTextAction(
            key: Key('home-summary-card-$metricKey-value-action'),
            onTap: onTextTap,
            tooltip: textTapTooltip,
            child: lowerText,
          ),
        ],
      ),
    );
  }
}

class _SummaryCardTextAction extends StatelessWidget {
  const _SummaryCardTextAction({
    super.key,
    required this.child,
    required this.onTap,
    required this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    final action = Semantics(
      button: true,
      child: Material(
        color: AppColors.transparent,
        borderRadius: AppRadius.allSm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.allSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: child,
          ),
        ),
      ),
    );
    if (tooltip == null) return action;
    return Tooltip(message: tooltip!, child: action);
  }
}

void _openSalesReportAdmin(BuildContext context, HomeSummaryProvider provider) {
  unawaited(
    AppLogger.instance.info(
      'Home',
      'Home reported sales card routed to admin sales reports',
      context: {
        'source': 'reported_orders_card',
        'route': '/admin/sales-reports',
        'startDate': provider.formattedSelectedStartDate,
        'endDate': provider.formattedSelectedEndDate,
        'scopeFilter': provider.selectedScope,
      },
    ),
  );
  context.go('/admin/sales-reports');
}

void _openMissingOrderStatements(
  BuildContext context,
  HomeSummaryProvider provider,
) {
  const route = '/bank-statement?orderStatus=MISSING_ORDER&autoSearch=true';
  unawaited(
    AppLogger.instance.info(
      'Home',
      'Home finance card routed to missing-order statements',
      context: {
        'source': 'total_statements_without_order_card',
        'route': route,
        'startDate': provider.formattedSelectedStartDate,
        'endDate': provider.formattedSelectedEndDate,
        'scopeFilter': provider.selectedScope,
      },
    ),
  );
  context.go(route);
}

void _openInstallmentNeedDetailsDialog(
  BuildContext context,
  HomeSummaryProvider provider,
) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: AppColors.shadow.withValues(alpha: 0.48),
      builder: (context) => _InstallmentNeedDetailsDialog(provider: provider),
    ),
  );
}

enum _SalesBehaviorDetailTab { notPurchased, unreported }

void _openSalesBehaviorDetailsDialog(
  BuildContext context,
  HomeSummaryProvider provider,
  _SalesBehaviorDetailTab initialTab,
) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierColor: AppColors.shadow.withValues(alpha: 0.48),
      builder: (context) => _SalesBehaviorDetailsDialog(
        provider: provider,
        initialTab: initialTab,
      ),
    ),
  );
}

class _SalesBehaviorDetailsDialog extends StatefulWidget {
  const _SalesBehaviorDetailsDialog({
    required this.provider,
    required this.initialTab,
  });

  final HomeSummaryProvider provider;
  final _SalesBehaviorDetailTab initialTab;

  @override
  State<_SalesBehaviorDetailsDialog> createState() =>
      _SalesBehaviorDetailsDialogState();
}

class _SalesBehaviorDetailsDialogState
    extends State<_SalesBehaviorDetailsDialog> {
  late _SalesBehaviorDetailTab _selectedTab;
  late Future<HomeSalesBehaviorDetails> _future;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _future = widget.provider.fetchSalesBehaviorDetails(
      source: _selectedTab == _SalesBehaviorDetailTab.notPurchased
          ? 'not_purchased_card'
          : 'unreported_orders_card',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.min(math.max(screenSize.width - 24, 0.0), 980.0);
    final maxHeight = math.min(math.max(screenSize.height - 24, 0.0), 720.0);
    return Dialog(
      key: const Key('home-sales-behavior-details-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chi tiết Hành vi then chốt',
                      style: AppTextStyles.headingS.copyWith(
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
              FutureBuilder<HomeSalesBehaviorDetails>(
                future: _future,
                builder: (context, snapshot) {
                  final details = snapshot.data;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DetailTabPill(
                        key: const Key('home-sales-behavior-tab-not-purchased'),
                        label: 'Khách chưa mua',
                        count: details?.notPurchasedTotal,
                        selected:
                            _selectedTab ==
                            _SalesBehaviorDetailTab.notPurchased,
                        onTap: () => setState(
                          () => _selectedTab =
                              _SalesBehaviorDetailTab.notPurchased,
                        ),
                      ),
                      _DetailTabPill(
                        key: const Key('home-sales-behavior-tab-unreported'),
                        label: 'Đơn chưa báo cáo',
                        count: details?.unreportedTotal,
                        selected:
                            _selectedTab == _SalesBehaviorDetailTab.unreported,
                        onTap: () => setState(
                          () =>
                              _selectedTab = _SalesBehaviorDetailTab.unreported,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<HomeSalesBehaviorDetails>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppStatePanel.loading(
                        title: 'Đang tải chi tiết',
                        message:
                            'Hệ thống đang lấy danh sách theo phạm vi hiện tại.',
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return AppStatePanel.error(
                        title: 'Chưa tải được chi tiết',
                        message:
                            'Kiểm tra kết nối rồi thử mở lại bảng chi tiết.',
                      );
                    }
                    return _SalesBehaviorDetailsTable(
                      details: snapshot.data!,
                      selectedTab: _selectedTab,
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
}

class _InstallmentNeedDetailsDialog extends StatefulWidget {
  const _InstallmentNeedDetailsDialog({required this.provider});

  final HomeSummaryProvider provider;

  @override
  State<_InstallmentNeedDetailsDialog> createState() =>
      _InstallmentNeedDetailsDialogState();
}

class _InstallmentNeedDetailsDialogState
    extends State<_InstallmentNeedDetailsDialog> {
  late Future<HomeSalesBehaviorDetails> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.provider.fetchSalesBehaviorDetails(
      source: 'installment_need_card',
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.min(math.max(screenSize.width - 24, 0.0), 960.0);
    final maxHeight = math.min(math.max(screenSize.height - 24, 0.0), 680.0);
    return Dialog(
      key: const Key('home-installment-need-details-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.allMd),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chi tiết nhu cầu trả góp',
                      style: AppTextStyles.headingS.copyWith(
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
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<HomeSalesBehaviorDetails>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const AppStatePanel.loading(
                        title: 'Đang tải chi tiết',
                        message: 'Hệ thống đang lấy danh sách nhu cầu trả góp.',
                      );
                    }
                    if (snapshot.hasError || !snapshot.hasData) {
                      return AppStatePanel.error(
                        title: 'Chưa tải được chi tiết',
                        message:
                            'Kiểm tra kết nối rồi thử mở lại bảng chi tiết.',
                      );
                    }
                    return _InstallmentNeedDetailsTable(
                      details: snapshot.data!,
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
}

class _DetailTabPill extends StatelessWidget {
  const _DetailTabPill({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AppColors.primaryOf(context)
        : AppColors.neutral700;
    return Material(
      color: selected
          ? AppColors.primaryOf(context).withValues(alpha: 0.10)
          : AppColors.chipBackground,
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.allSm,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            count == null ? label : '$label (${_integerLabel(count!)})',
            style: AppTextStyles.labelS.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesBehaviorDetailsTable extends StatelessWidget {
  const _SalesBehaviorDetailsTable({
    required this.details,
    required this.selectedTab,
  });

  final HomeSalesBehaviorDetails details;
  final _SalesBehaviorDetailTab selectedTab;

  @override
  Widget build(BuildContext context) {
    final isNotPurchased = selectedTab == _SalesBehaviorDetailTab.notPurchased;
    final rowCount = isNotPurchased
        ? details.notPurchasedReports.length
        : details.unreportedOrders.length;
    final total = isNotPurchased
        ? details.notPurchasedTotal
        : details.unreportedTotal;
    if (rowCount == 0) {
      return const AppStatePanel.empty(
        title: 'Chưa có dòng chi tiết',
        message: 'Không có báo cáo phù hợp với phạm vi và ngày đang xem.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _detailCountLabel(rowCount, total),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Scrollbar(
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: isNotPurchased ? 940 : 660,
                    ),
                    child: isNotPurchased
                        ? _NotPurchasedDetailsDataTable(
                            rows: details.notPurchasedReports,
                          )
                        : _UnreportedOrdersDetailsDataTable(
                            rows: details.unreportedOrders,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NotPurchasedDetailsDataTable extends StatelessWidget {
  const _NotPurchasedDetailsDataTable({required this.rows});

  final List<HomeNotPurchasedReportDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-not-purchased-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã SR')),
        DataColumn(label: Text('Tên SA')),
        DataColumn(label: Text('Tên khách hàng')),
        DataColumn(label: Text('Loại khách hàng')),
        DataColumn(label: Text('Ngành hàng')),
        DataColumn(label: Text('Lý do không mua')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(Text(_valueOrEmpty(row.customerName))),
              DataCell(Text(_valueOrEmpty(row.customerTypeLabel))),
              DataCell(Text(_valueOrEmpty(row.categoryName))),
              DataCell(Text(_valueOrEmpty(row.notPurchasedReasonLabel))),
            ],
          ),
      ],
    );
  }
}

class _UnreportedOrdersDetailsDataTable extends StatelessWidget {
  const _UnreportedOrdersDetailsDataTable({required this.rows});

  final List<HomeUnreportedOrderDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-unreported-orders-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã SR')),
        DataColumn(label: Text('Tên SA')),
        DataColumn(label: Text('Mã đơn hàng')),
        DataColumn(label: Text('Thời gian bán')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(Text(row.orderCode)),
              DataCell(Text(_dateTimeLabel(row.soldAt))),
            ],
          ),
      ],
    );
  }
}

class _InstallmentNeedDetailsTable extends StatelessWidget {
  const _InstallmentNeedDetailsTable({required this.details});

  final HomeSalesBehaviorDetails details;

  @override
  Widget build(BuildContext context) {
    final rows = details.installmentNeedReports;
    if (rows.isEmpty) {
      return const AppStatePanel.empty(
        title: 'Chưa có dòng chi tiết',
        message: 'Không có nhu cầu trả góp trong phạm vi và ngày đang xem.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _detailCountLabel(rows.length, details.installmentNeedTotal),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Scrollbar(
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 820),
                    child: _InstallmentNeedDetailsDataTable(rows: rows),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InstallmentNeedDetailsDataTable extends StatelessWidget {
  const _InstallmentNeedDetailsDataTable({required this.rows});

  final List<HomeInstallmentNeedDetail> rows;

  @override
  Widget build(BuildContext context) {
    return DataTable(
      key: const Key('home-installment-need-details-table'),
      headingTextStyle: AppTextStyles.labelS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w800,
      ),
      dataTextStyle: AppTextStyles.bodyS.copyWith(
        color: AppColors.textPrimaryOf(context),
      ),
      columns: const [
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên SA')),
        DataColumn(label: Text('Đối tác trả góp')),
        DataColumn(label: Text('Thành công')),
        DataColumn(label: Text('Ghi chú')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(
                Text(
                  row.installmentPartnerLabels.isEmpty
                      ? 'Chưa có thông tin'
                      : row.installmentPartnerLabels.join(', '),
                ),
              ),
              DataCell(
                row.successful
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 18,
                      )
                    : Text(
                        'Không',
                        style: AppTextStyles.bodyS.copyWith(
                          color: AppColors.error,
                        ),
                      ),
              ),
              DataCell(Text(_valueOrEmpty(row.note))),
            ],
          ),
      ],
    );
  }
}

String _detailCountLabel(int visible, int total) {
  if (visible >= total) return 'Hiển thị ${_integerLabel(visible)} dòng.';
  return 'Hiển thị ${_integerLabel(visible)}/${_integerLabel(total)} dòng gần nhất.';
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return 'Chưa có thông tin';
  return DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
}

String _valueOrEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? 'Chưa có thông tin' : text;
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng quan',
            style: AppTextStyles.headingS.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
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
                  height: 292,
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
                  ? 286.0
                  : constraints.maxWidth >= 620
                  ? 278.0
                  : 292.0;
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

const double _salesProgressControlSlotHeight = 42;
const double _salesProgressDonutSlotHeight = 72;
const double _salesProgressLabelSlotHeight = 18;
const double _salesProgressMetricSlotHeight = 34;

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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        border: Border.all(color: color.withValues(alpha: 0.16)),
        borderRadius: AppRadius.allMd,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 22,
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelM,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: Center(
              child: _ProgressDonut(
                key: title == 'Tiến độ báo cáo'
                    ? const Key('home-summary-progress-donut')
                    : const Key('home-statement-progress-donut'),
                percentage: percentage,
                color: color,
                dimension: 92,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            child: Align(alignment: Alignment.topCenter, child: legend),
          ),
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
      padding: const EdgeInsets.all(12),
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
          SizedBox(
            height: _salesProgressControlSlotHeight,
            child: assignees.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _SalesProgressAssigneeDropdown(
                        assignees: assignees,
                        selectedAssigneeId: selectedAssigneeId,
                        onChanged: onAssigneeChanged,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
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

  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('home-sales-progress-assignee-dropdown'),
      width: 260,
      child: AppCombobox<String>.single(
        label: 'Nhân viên',
        value: selectedAssigneeId,
        icon: Icons.person_search_rounded,
        dense: true,
        emptyLabel: 'Chưa chọn SA',
        options: assignees
            .map(
              (assignee) => AppComboboxOption(
                value: assignee.userId,
                label: _assigneeLabel(assignee),
                subtitle: _assigneeSubtitle(assignee),
                searchKeywords: [
                  assignee.label,
                  assignee.email ?? '',
                  assignee.storeCodes.join(' '),
                ],
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }

  static String _assigneeLabel(HomeSalesProgressAssignee assignee) {
    final stores = assignee.storeCodes.join(', ');
    if (stores.isEmpty) return assignee.label;
    return '${assignee.label} - $stores';
  }

  static String _assigneeSubtitle(HomeSalesProgressAssignee assignee) {
    final parts = [
      if (assignee.storeCodes.isNotEmpty) assignee.storeCodes.join(', '),
      if (assignee.email?.isNotEmpty == true) assignee.email!,
    ];
    return parts.join(' - ');
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
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: _salesProgressDonutSlotHeight,
            child: Center(
              child: _ProgressDonut(
                key: Key('$keyPrefix-$keySuffix-donut'),
                percentage: period.percentage,
                color: color,
                dimension: 68,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: _salesProgressLabelSlotHeight,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelS,
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _salesProgressMetricSlotHeight,
            child: Center(
              child: Text(
                key: Key('$keyPrefix-$keySuffix-actual-label'),
                'Đã đạt: ${formatCompactVndAmount(period.actual)}',
                maxLines: 2,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textMutedOf(context),
                ),
              ),
            ),
          ),
          SizedBox(
            height: _salesProgressMetricSlotHeight,
            child: Center(
              child: Text(
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: compact ? 66 : 96,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTextStyles.labelS.copyWith(color: color),
                  ),
                ),
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
