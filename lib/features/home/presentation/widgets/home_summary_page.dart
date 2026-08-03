import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_buttons.dart';
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
    this.greetingSubtitle,
    this.greetingNow,
  });

  final HomeSummaryProvider provider;
  final Widget? headerAction;
  final Widget? footer;
  final String? greetingName;
  final String? greetingSubtitle;
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
          greetingSubtitle: greetingSubtitle,
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
              : summary?.resolvedFreshnessWarning,
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
        const _SummarySubsectionHeader(title: 'Doanh số (đã bao gồm VAT)'),
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
    return Text(
      title,
      style: AppTextStyles.headingS.copyWith(
        color: AppColors.textPrimaryOf(context),
        fontWeight: FontWeight.w600,
      ),
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
        fontWeight: FontWeight.w600,
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
    this.greetingSubtitle,
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
  final String? greetingSubtitle;
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
    final fallbackScopeLabel =
        summary?.resolvedScopeLabel ?? 'Đang đồng bộ phạm vi';
    final scopeLabel = selectedScopeLabel.trim().isEmpty
        ? fallbackScopeLabel
        : selectedScopeLabel.trim();
    final updatedLabel = summary?.refreshedAt == null
        ? 'Đang cập nhật'
        : 'Cập nhật ${_timeOnlyLabel(summary!.refreshedAt!)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        final controls = _HomeScopeDateControl(
          selectedScope: selectedScope,
          selectedScopeLabel: selectedScopeLabel.isEmpty
              ? scopeLabel
              : selectedScopeLabel,
          scopeOptions: scopeOptions,
          selectedStartDate: selectedStartDate,
          selectedEndDate: selectedEndDate,
          onScopeChanged: onScopeChanged,
          onDateRangeChanged: onDateRangeChanged,
          action: action,
          builder: (context, open) => mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 96,
                          child: _HomeHeaderChip(
                            label: 'Phạm vi: ${_shortScopeLabel(scopeLabel)}',
                            onTap: open,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: _HomeHeaderChip(
                            label:
                                'Ngày: ${_homeRangeShortLabel(selectedStartDate, selectedEndDate)}',
                            onTap: open,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 112,
                      child: _HomeHeaderChip(
                        key: const Key('home-summary-refresh-button'),
                        label: updatedLabel,
                        onTap: onRefresh,
                        busy: isRefreshing,
                      ),
                    ),
                  ],
                )
              : Semantics(
                  button: true,
                  label: 'Chọn phạm vi và khoảng thời gian',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('home-summary-scope-date-trigger'),
                      onTap: open,
                      borderRadius: AppRadius.allControl,
                      child: Container(
                        key: const Key('home-summary-scope-pill'),
                        width: 360,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.raisedOf(context),
                          border: Border.all(color: AppColors.neutral200),
                          borderRadius: AppRadius.allControl,
                        ),
                        child: Text(
                          '${_shortScopeLabel(scopeLabel)}  ·  ${_homeRangeShortLabel(selectedStartDate, selectedEndDate)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelS.copyWith(
                            color: AppColors.neutral700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
        final visualHeader = mobile
            ? Container(
                key: const Key('home-summary-header'),
                height: 204,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.raisedOf(context),
                  border: Border.all(color: AppColors.borderOf(context)),
                  borderRadius: AppRadius.allLg,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow.withValues(alpha: 0.08),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _HomeSummaryAvatar(name: greetingName),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greetingLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.headingS.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                greetingSubtitle ?? scopeLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
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
                    SizedBox(width: double.infinity, child: controls),
                  ],
                ),
              )
            : SizedBox(
                key: const Key('home-summary-header'),
                height: 64,
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 26,
                              child: Text(
                                'Trang chủ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.pageTitle.copyWith(
                                  color: AppColors.textPrimaryOf(context),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 16,
                              child: Text(
                                'Tổng quan theo phạm vi được phân quyền',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyS.copyWith(
                                  color: AppColors.neutral500,
                                  height: 16 / 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    controls,
                  ],
                ),
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            visualHeader,
            if (warningMessage != null) ...[
              const SizedBox(height: 12),
              AppStatusBanner(
                icon: Icons.sync_problem_rounded,
                title: 'Đang hiển thị dữ liệu gần nhất',
                message: warningMessage!,
                tone: AppStateTone.warning,
                actionLabel: isRefreshing ? 'Đang thử lại…' : 'Thử lại',
                actionBusy: isRefreshing,
                onAction: onRefresh,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HomeScopeDateControl extends StatelessWidget {
  const _HomeScopeDateControl({
    required this.selectedScope,
    required this.selectedScopeLabel,
    required this.scopeOptions,
    required this.selectedStartDate,
    required this.selectedEndDate,
    required this.onScopeChanged,
    required this.onDateRangeChanged,
    required this.builder,
    this.action,
  });

  final String selectedScope;
  final String selectedScopeLabel;
  final List<HomeSummaryScopeOption> scopeOptions;
  final DateTime? selectedStartDate;
  final DateTime? selectedEndDate;
  final ValueChanged<String>? onScopeChanged;
  final void Function(DateTime? start, DateTime? end) onDateRangeChanged;
  final Widget Function(BuildContext context, VoidCallback open) builder;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final canSelect = scopeOptions.length > 1 && onScopeChanged != null;
    final selectedValue =
        scopeOptions.any((option) => option.value == selectedScope)
        ? selectedScope
        : null;
    return MenuAnchor(
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: WidgetStatePropertyAll(2),
      ),
      builder: (context, controller, _) => builder(context, () {
        if (!controller.isOpen) controller.open();
      }),
      menuChildren: [
        Material(
          color: AppColors.raisedOf(context),
          child: SizedBox(
            width: 720,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 320,
                    child: AppCombobox<String>.single(
                      key: const Key('home-summary-scope-combobox'),
                      label: 'Phạm vi',
                      value: selectedValue,
                      icon: Icons.store_outlined,
                      dense: true,
                      enabled: canSelect,
                      allowClear: false,
                      emptyLabel: selectedScopeLabel,
                      maxMenuHeight: 320,
                      options: [
                        for (final option in scopeOptions)
                          AppComboboxOption<String>(
                            value: option.value,
                            label: option.label,
                            subtitle: _ScopeSelectorField._scopeOptionSubtitle(
                              option,
                            ),
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
                              if (value != null) onScopeChanged?.call(value);
                            }
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: AppDateRangeDropdown(
                      label: 'Ngày',
                      start: selectedStartDate,
                      end: selectedEndDate,
                      onChanged: onDateRangeChanged,
                      showEmptyRangeHelperText: false,
                      now: DateTime.now,
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeHeaderChip extends StatelessWidget {
  const _HomeHeaderChip({
    super.key,
    required this.label,
    this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutral50,
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: AppRadius.allSm,
        child: Container(
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: busy
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    color: AppColors.textSecondaryOf(context),
                    height: 18 / 13,
                  ),
                ),
        ),
      ),
    );
  }
}

String _shortScopeLabel(String label) {
  final trimmed = label.trim();
  return trimmed.isEmpty ? 'Showroom được phân quyền' : trimmed;
}

String _homeRangeShortLabel(DateTime? start, DateTime? end) {
  if (start == null && end == null) return 'Tất cả ngày';
  final startLabel = start == null ? null : DateFormat('dd/MM').format(start);
  final endLabel = end == null ? null : DateFormat('dd/MM').format(end);
  if (startLabel != null && startLabel == endLabel) return startLabel;
  return [startLabel, endLabel].whereType<String>().join(' - ');
}

class _HomeSummaryAvatar extends StatelessWidget {
  const _HomeSummaryAvatar({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    return Semantics(
      label: 'Tài khoản $trimmed',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primarySurfaceOf(context),
          borderRadius: AppRadius.allMd,
        ),
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: Text(
              initial,
              style: AppTextStyles.headingS.copyWith(
                color: AppColors.primaryOf(context),
              ),
            ),
          ),
        ),
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
    required this.width,
    required this.onSelected,
  });

  final String label;
  final String selectedScope;
  final List<HomeSummaryScopeOption> options;
  final bool fillWidth;
  final double width;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final canSelect = options.length > 1 && onSelected != null;
    final selectedValue = options.any((option) => option.value == selectedScope)
        ? selectedScope
        : null;
    return SizedBox(
      key: const Key('home-summary-scope-pill'),
      width: fillWidth ? double.infinity : width,
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

class SummaryCardGrid extends StatelessWidget {
  const SummaryCardGrid({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'revenue',
        icon: Icons.payments_outlined,
        title: 'Giá trị bán (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.totalRevenue),
        trend: const SummaryTrend.neutral('Theo đơn hàng ERP'),
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
        title: 'Trung bình đơn hàng (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.averageOrderValue),
        trend: const SummaryTrend.neutral('Giá trị/đơn'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'completedRevenue',
        icon: Icons.verified_outlined,
        title: 'Hoàn thành (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.completedRevenue),
        trend: const SummaryTrend.success('Đã hoàn tất'),
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'pendingRevenue',
        icon: Icons.pending_actions_outlined,
        title: 'Chờ hoàn thành (đã bao gồm VAT)',
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
        title: 'Khách doanh nghiệp (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.businessCustomerRevenue),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'personalCustomerRevenue',
        icon: Icons.person_outline_rounded,
        title: 'Khách cá nhân (đã bao gồm VAT)',
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
        metricKey: 'totalStatementsTracked',
        icon: Icons.visibility_outlined,
        title: 'Sao kê đang theo dõi',
        value: _integerLabel(summary.totalStatementsTracked),
        trend: const SummaryTrend.neutral('Dùng để tính tỷ lệ'),
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'totalStatementsUnfollowed',
        icon: Icons.visibility_off_outlined,
        title: 'Sao kê đã bỏ theo dõi',
        value: _integerLabel(summary.totalStatementsUnfollowed),
        trend: const SummaryTrend.neutral('Không tính đối chiếu đơn'),
        color: AppColors.neutral500,
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
        final maxColumns = width >= 960
            ? math.min(6, cards.length)
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
                        height: width >= 600 ? 104 : 120,
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
    return [
      for (var start = 0; start < cards.length; start += columns)
        cards.sublist(
          math.min(start, cards.length),
          math.min(start + columns, cards.length),
        ),
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
    final lowerText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.headingM.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          trend.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelS.copyWith(
            color: AppColors.textMutedOf(context),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    return AppSurfaceCard(
      key: Key('home-summary-card-$metricKey'),
      borderColor: AppColors.borderOf(context),
      backgroundColor: AppColors.raisedOf(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryCardTextAction(
            key: Key('home-summary-card-$metricKey-title-action'),
            onTap: onTextTap,
            tooltip: textTapTooltip,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondaryOf(context),
                fontWeight: FontWeight.w600,
                height: 16 / 13,
              ),
            ),
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
  HomeSummaryDetailsPage<HomeNotPurchasedReportDetail>? _notPurchasedPage;
  HomeSummaryDetailsPage<HomeUnreportedOrderDetail>? _unreportedPage;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  String? _initialError;
  String? _loadMoreError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    unawaited(_loadSelectedPage());
  }

  HomeSummaryDetailsPage<Object>? get _selectedPage => switch (_selectedTab) {
    _SalesBehaviorDetailTab.notPurchased => _notPurchasedPage,
    _SalesBehaviorDetailTab.unreported => _unreportedPage,
  };

  void _selectTab(_SalesBehaviorDetailTab tab) {
    if (_selectedTab == tab) return;
    _loadGeneration += 1;
    setState(() {
      _selectedTab = tab;
      _isInitialLoading = false;
      _isLoadingMore = false;
      _initialError = null;
      _loadMoreError = null;
    });
    if (_selectedPage == null) unawaited(_loadSelectedPage());
  }

  Future<void> _loadSelectedPage({bool loadMore = false}) async {
    final requestedTab = _selectedTab;
    final currentPage = _selectedPage;
    if (loadMore &&
        (currentPage == null || !currentPage.hasNextPage || _isLoadingMore)) {
      return;
    }
    final generation = ++_loadGeneration;
    setState(() {
      _isInitialLoading = !loadMore && currentPage == null;
      _isLoadingMore = loadMore;
      if (loadMore) {
        _loadMoreError = null;
      } else {
        _initialError = null;
      }
    });
    try {
      switch (requestedTab) {
        case _SalesBehaviorDetailTab.notPurchased:
          final page = await widget.provider.fetchNotPurchasedDetails(
            source: 'not_purchased_card',
            cursor: loadMore ? _notPurchasedPage?.nextCursor : null,
          );
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _notPurchasedPage = loadMore
                ? _notPurchasedPage!.append(page)
                : page;
          });
        case _SalesBehaviorDetailTab.unreported:
          final page = await widget.provider.fetchUnreportedOrderDetails(
            source: 'unreported_orders_card',
            cursor: loadMore ? _unreportedPage?.nextCursor : null,
          );
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _unreportedPage = loadMore ? _unreportedPage!.append(page) : page;
          });
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (loadMore) {
          _loadMoreError =
              'Chưa tải được phần tiếp theo. Vui lòng kiểm tra kết nối và thử lại.';
        } else {
          _initialError =
              'Chưa tải được danh sách. Vui lòng kiểm tra kết nối và thử lại.';
        }
      });
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DetailTabPill(
                    key: const Key('home-sales-behavior-tab-not-purchased'),
                    label: 'Khách chưa mua',
                    count: _notPurchasedPage?.total,
                    selected:
                        _selectedTab == _SalesBehaviorDetailTab.notPurchased,
                    onTap: () =>
                        _selectTab(_SalesBehaviorDetailTab.notPurchased),
                  ),
                  _DetailTabPill(
                    key: const Key('home-sales-behavior-tab-unreported'),
                    label: 'Đơn chưa báo cáo',
                    count: _unreportedPage?.total,
                    selected:
                        _selectedTab == _SalesBehaviorDetailTab.unreported,
                    onTap: () => _selectTab(_SalesBehaviorDetailTab.unreported),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildSelectedContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedContent() {
    if (_isInitialLoading && _selectedPage == null) {
      return const AppStatePanel.loading(
        title: 'Đang tải chi tiết',
        message: 'Hệ thống đang lấy danh sách theo phạm vi hiện tại.',
      );
    }
    if (_initialError != null && _selectedPage == null) {
      return AppStatePanel.error(
        key: const Key('home-details-initial-error'),
        title: 'Chưa tải được chi tiết',
        message: _initialError,
        actionLabel: 'Thử lại',
        onAction: _loadSelectedPage,
      );
    }
    final page = _selectedPage;
    if (page == null) return const SizedBox.shrink();
    return _SalesBehaviorDetailsTable(
      notPurchasedPage: _selectedTab == _SalesBehaviorDetailTab.notPurchased
          ? _notPurchasedPage
          : null,
      unreportedPage: _selectedTab == _SalesBehaviorDetailTab.unreported
          ? _unreportedPage
          : null,
      isLoadingMore: _isLoadingMore,
      loadMoreError: _loadMoreError,
      onLoadMore: () => _loadSelectedPage(loadMore: true),
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
  HomeSummaryDetailsPage<HomeInstallmentNeedDetail>? _page;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  String? _initialError;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPage());
  }

  Future<void> _loadPage({bool loadMore = false}) async {
    if (loadMore && (_page == null || !_page!.hasNextPage || _isLoadingMore)) {
      return;
    }
    setState(() {
      _isInitialLoading = !loadMore && _page == null;
      _isLoadingMore = loadMore;
      if (loadMore) {
        _loadMoreError = null;
      } else {
        _initialError = null;
      }
    });
    try {
      final page = await widget.provider.fetchInstallmentNeedDetails(
        source: 'installment_need_card',
        cursor: loadMore ? _page?.nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        _page = loadMore ? _page!.append(page) : page;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (loadMore) {
          _loadMoreError =
              'Chưa tải được phần tiếp theo. Vui lòng kiểm tra kết nối và thử lại.';
        } else {
          _initialError =
              'Chưa tải được danh sách. Vui lòng kiểm tra kết nối và thử lại.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
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
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isInitialLoading && _page == null) {
      return const AppStatePanel.loading(
        title: 'Đang tải chi tiết',
        message: 'Hệ thống đang lấy danh sách nhu cầu trả góp.',
      );
    }
    if (_initialError != null && _page == null) {
      return AppStatePanel.error(
        key: const Key('home-installment-details-initial-error'),
        title: 'Chưa tải được chi tiết',
        message: _initialError,
        actionLabel: 'Thử lại',
        onAction: _loadPage,
      );
    }
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    return _InstallmentNeedDetailsTable(
      page: page,
      isLoadingMore: _isLoadingMore,
      loadMoreError: _loadMoreError,
      onLoadMore: () => _loadPage(loadMore: true),
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
    required this.notPurchasedPage,
    required this.unreportedPage,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  final HomeSummaryDetailsPage<HomeNotPurchasedReportDetail>? notPurchasedPage;
  final HomeSummaryDetailsPage<HomeUnreportedOrderDetail>? unreportedPage;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final isNotPurchased = notPurchasedPage != null;
    final rowCount = isNotPurchased
        ? notPurchasedPage!.items.length
        : unreportedPage!.items.length;
    final total = isNotPurchased
        ? notPurchasedPage!.total
        : unreportedPage!.total;
    final hasNextPage = isNotPurchased
        ? notPurchasedPage!.hasNextPage
        : unreportedPage!.hasNextPage;
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
          child: AppTwoAxisScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: isNotPurchased ? 940 : 820),
              child: isNotPurchased
                  ? _NotPurchasedDetailsDataTable(rows: notPurchasedPage!.items)
                  : _UnreportedOrdersDetailsDataTable(
                      rows: unreportedPage!.items,
                    ),
            ),
          ),
        ),
        _DetailsLoadMoreFooter(
          hasNextPage: hasNextPage,
          isLoading: isLoadingMore,
          errorMessage: loadMoreError,
          onLoadMore: onLoadMore,
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
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên nhân viên')),
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
        DataColumn(label: Text('Mã showroom')),
        DataColumn(label: Text('Tên nhân viên')),
        DataColumn(label: Text('Mã đơn hàng')),
        DataColumn(label: Text('Giá trị đơn (đã bao gồm VAT)')),
        DataColumn(label: Text('Thời gian bán')),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(_valueOrEmpty(row.storeCode))),
              DataCell(Text(_valueOrEmpty(row.salesName))),
              DataCell(Text(row.orderCode)),
              DataCell(Text(_valueOrEmpty(formatVndAmount(row.grandTotal)))),
              DataCell(Text(_dateTimeLabel(row.soldAt))),
            ],
          ),
      ],
    );
  }
}

class _InstallmentNeedDetailsTable extends StatelessWidget {
  const _InstallmentNeedDetailsTable({
    required this.page,
    required this.isLoadingMore,
    required this.loadMoreError,
    required this.onLoadMore,
  });

  final HomeSummaryDetailsPage<HomeInstallmentNeedDetail> page;
  final bool isLoadingMore;
  final String? loadMoreError;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final rows = page.items;
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
          _detailCountLabel(rows.length, page.total),
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: AppTwoAxisScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 820),
              child: _InstallmentNeedDetailsDataTable(rows: rows),
            ),
          ),
        ),
        _DetailsLoadMoreFooter(
          hasNextPage: page.hasNextPage,
          isLoading: isLoadingMore,
          errorMessage: loadMoreError,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}

class _DetailsLoadMoreFooter extends StatelessWidget {
  const _DetailsLoadMoreFooter({
    required this.hasNextPage,
    required this.isLoading,
    required this.errorMessage,
    required this.onLoadMore,
  });

  final bool hasNextPage;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasNextPage && errorMessage == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (errorMessage != null) ...[
            Expanded(
              child: Text(
                errorMessage!,
                key: const Key('home-details-load-more-error'),
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ),
            const SizedBox(width: 12),
          ],
          AppSecondaryButton(
            key: const Key('home-details-load-more-button'),
            onPressed: isLoading ? null : onLoadMore,
            icon: Icons.expand_more_rounded,
            label: 'Xem thêm',
            isLoading: isLoading,
            loadingLabel: 'Đang tải thêm',
            expand: false,
            height: AppButtonMetrics.compactActionHeight,
          ),
        ],
      ),
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
        DataColumn(label: Text('Tên nhân viên')),
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
    final reported = summary.totalOrders <= 0
        ? 0.0
        : summary.reportedOrders / summary.totalOrders * 100;
    final cards = <_AnalyticsCardSpec>[
      if (summary.salesAvailable)
        _AnalyticsCardSpec(
          compactHeight: 248,
          expandedHeight: 200,
          card: _AnalyticsDonutCard(
            cardKey: const Key('home-report-progress-panel'),
            title: 'Tiến độ báo cáo',
            subtitle:
                'Đã báo cáo ${summary.reportedOrders}/${summary.totalOrders} đơn',
            percentage: summary.coverageRate,
            color: AppColors.primary,
            primaryLegend: 'Đã báo cáo · ${summary.reportedOrders} đơn',
            secondaryLegend: 'Cần xử lý · ${summary.unreportedOrders} đơn',
            primaryPercent: reported,
          ),
        ),
      if (summary.financeAvailable)
        _AnalyticsCardSpec(
          compactHeight: 248,
          expandedHeight: 200,
          card: _AnalyticsDonutCard(
            cardKey: const Key('home-statement-progress-panel'),
            title: 'Tiến độ sao kê',
            subtitle: 'Đối chiếu sao kê với đơn hàng',
            percentage: summary.statementOrderRate,
            color: AppColors.success,
            primaryLegend:
                'Có đơn · ${summary.totalStatementsWithOrder} sao kê',
            secondaryLegend:
                'Chưa có đơn · ${summary.totalStatementsWithoutOrder} sao kê',
            primaryPercent: summary.statementOrderRate,
          ),
        ),
      if (summary.salesAvailable &&
          (summary.personalSalesProgress.isApplicable ||
              summary.salesProgressAssignees.isNotEmpty))
        _AnalyticsCardSpec(
          compactHeight: summary.salesProgressAssignees.isEmpty ? 208 : 266,
          expandedHeight: 264,
          card: _AnalyticsPeriodCard(
            cardKey: const Key('home-sales-progress-panel'),
            title: 'Tổng quan cá nhân',
            subtitle: summary.selectedSalesProgressUserId == null
                ? 'Chọn nhân viên để so sánh chỉ tiêu'
                : 'Tiến độ theo nhân viên đã chọn',
            color: AppColors.violet600,
            progress: summary.personalSalesProgress,
            assignees: summary.salesProgressAssignees,
            selectedAssigneeId: summary.selectedSalesProgressUserId,
            onAssigneeChanged: provider.isLoading || provider.isRefreshing
                ? null
                : (id) => unawaited(provider.setSelectedSalesProgressUser(id)),
          ),
        ),
      if (summary.salesAvailable && summary.scopeSalesProgress.isApplicable)
        _AnalyticsCardSpec(
          compactHeight: 208,
          expandedHeight: 264,
          card: _AnalyticsPeriodCard(
            cardKey: const Key('home-scope-sales-progress-panel'),
            title: _scopeSalesProgressTitle(summary),
            subtitle: summary.scopeSalesProgress.hasTarget
                ? 'Tiến độ theo phạm vi được phân quyền'
                : 'Thiếu chỉ tiêu: ${summary.scopeSalesProgress.missingStoreCodes.join(', ')}',
            color: AppColors.primary,
            progress: summary.scopeSalesProgress,
          ),
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        // Figma 1819:16547 reserves a 896px inner analytics grid: two 440px
        // cards with a 16px gutter. Do not stretch charts across wide desktop
        // dashboard whitespace.
        final boardWidth = compact
            ? constraints.maxWidth
            : math.min(constraints.maxWidth, 896.0);
        final columns = boardWidth >= 760 ? 2 : 1;
        final gap = 16.0;
        final width = (boardWidth - gap * (columns - 1)) / columns;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: boardWidth,
            child: Column(
              key: const Key('home-summary-progress-panel'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  compact ? 'Tổng quan' : 'Tiến độ hoạt động',
                  style: compact
                      ? AppTextStyles.headingS
                      : AppTextStyles.pageTitle,
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Báo cáo, sao kê và tiến độ chỉ tiêu theo phạm vi hiện tại.',
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 16 : 18),
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final spec in cards)
                      SizedBox(
                        width: width,
                        height: compact
                            ? spec.compactHeight
                            : spec.expandedHeight,
                        child: _AnalyticsCompactScope(
                          compact: compact,
                          child: spec.card,
                        ),
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

class _AnalyticsDonutCard extends StatelessWidget {
  const _AnalyticsDonutCard({
    required this.cardKey,
    required this.title,
    required this.subtitle,
    required this.percentage,
    required this.color,
    required this.primaryLegend,
    required this.secondaryLegend,
    required this.primaryPercent,
  });
  final Key cardKey;
  final String title, subtitle, primaryLegend, secondaryLegend;
  final double percentage, primaryPercent;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final compact = _AnalyticsCompactScope.of(context);
    return compact
        ? Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 280,
              height: 248,
              child: _CompactDonutCard(
                cardKey: cardKey,
                title: title,
                percentage: percentage,
                color: color,
                primaryLegend: primaryLegend,
                secondaryLegend: secondaryLegend,
              ),
            ),
          )
        : _AnalyticsCard(
            cardKey: cardKey,
            title: title,
            subtitle: subtitle,
            child: Row(
              children: [
                _ProgressDonut(
                  key: title == 'Tiến độ báo cáo'
                      ? const Key('home-summary-progress-donut')
                      : const Key('home-statement-progress-donut'),
                  percentage: percentage,
                  color: color,
                  dimension: 100,
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AnalyticsLegend(label: primaryLegend, color: color),
                      const SizedBox(height: 10),
                      _AnalyticsLegend(
                        label: secondaryLegend,
                        color: AppColors.warning,
                      ),
                      const SizedBox(height: 18),
                      _AnalyticsBar(value: primaryPercent, color: color),
                      const SizedBox(height: 8),
                      Text(
                        '${_percentLabel(primaryPercent)} hoàn tất',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
  }
}

class _AnalyticsPeriodCard extends StatelessWidget {
  const _AnalyticsPeriodCard({
    required this.cardKey,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.progress,
    this.assignees = const [],
    this.selectedAssigneeId,
    this.onAssigneeChanged,
  });
  final Key cardKey;
  final String title, subtitle;
  final Color color;
  final HomeSalesProgress progress;
  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final ValueChanged<String?>? onAssigneeChanged;
  @override
  Widget build(BuildContext context) {
    final compact = _AnalyticsCompactScope.of(context);
    return compact
        ? _CompactGoalCard(
            cardKey: cardKey,
            title: title,
            progress: progress,
            assignees: assignees,
            selectedAssigneeId: selectedAssigneeId,
            onAssigneeChanged: onAssigneeChanged,
          )
        : _AnalyticsCard(
            cardKey: cardKey,
            title: title,
            subtitle: subtitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (assignees.isNotEmpty) ...[
                  SizedBox(
                    width: 260,
                    height: 48,
                    child: _SalesProgressAssigneeDropdown(
                      assignees: assignees,
                      selectedAssigneeId: selectedAssigneeId,
                      onChanged: onAssigneeChanged,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Expanded(
                  child: Row(
                    children: [
                      _AnalyticsPeriod(
                        key: cardKey == const Key('home-sales-progress-panel')
                            ? const Key('home-analytics-sales-range')
                            : const Key('home-analytics-scope-range'),
                        label: 'Ngày',
                        period: progress.range,
                        color: color,
                      ),
                      const SizedBox(width: 18),
                      _AnalyticsPeriod(
                        key: cardKey == const Key('home-sales-progress-panel')
                            ? const Key('home-analytics-sales-week')
                            : const Key('home-analytics-scope-week'),
                        label: 'Tuần',
                        period: progress.week,
                        color: color,
                      ),
                      const SizedBox(width: 18),
                      _AnalyticsPeriod(
                        key: cardKey == const Key('home-sales-progress-panel')
                            ? const Key('home-analytics-sales-month')
                            : const Key('home-analytics-scope-month'),
                        label: 'Tháng',
                        period: progress.month,
                        color: color,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
  }
}

class _AnalyticsCompactScope extends InheritedWidget {
  const _AnalyticsCompactScope({required this.compact, required super.child});

  final bool compact;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AnalyticsCompactScope>()
          ?.compact ??
      false;

  @override
  bool updateShouldNotify(_AnalyticsCompactScope oldWidget) =>
      compact != oldWidget.compact;
}

class _AnalyticsCardSpec {
  const _AnalyticsCardSpec({
    required this.card,
    required this.compactHeight,
    required this.expandedHeight,
  });

  final Widget card;
  final double compactHeight;
  final double expandedHeight;
}

class _CompactDonutCard extends StatelessWidget {
  const _CompactDonutCard({
    required this.cardKey,
    required this.title,
    required this.percentage,
    required this.color,
    required this.primaryLegend,
    required this.secondaryLegend,
  });

  final Key cardKey;
  final String title, primaryLegend, secondaryLegend;
  final double percentage;
  final Color color;

  @override
  Widget build(BuildContext context) => Material(
    key: cardKey,
    color: AppColors.raisedOf(context),
    borderRadius: AppRadius.allLg,
    child: Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral200),
        borderRadius: AppRadius.allLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.labelM),
          const SizedBox(height: 8),
          SizedBox(
            height: 116,
            child: Center(
              child: _ProgressDonut(
                key: title == 'Tiến độ báo cáo'
                    ? const Key('home-summary-progress-donut')
                    : const Key('home-statement-progress-donut'),
                percentage: percentage,
                color: color,
                dimension: 96,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _CompactLegend(
            label: primaryLegend.split(' · ').first,
            value: _percentLabel(percentage),
            color: color,
          ),
          const SizedBox(height: 5),
          _CompactLegend(
            label: secondaryLegend.split(' · ').first,
            value: _percentLabel(100 - percentage),
            color: AppColors.error,
          ),
        ],
      ),
    ),
  );
}

class _CompactLegend extends StatelessWidget {
  const _CompactLegend({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label, value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 20,
    child: Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyCompact.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
        Text(value, style: AppTextStyles.labelSmallSubtle),
      ],
    ),
  );
}

class _CompactGoalCard extends StatelessWidget {
  const _CompactGoalCard({
    required this.cardKey,
    required this.title,
    required this.progress,
    required this.assignees,
    required this.selectedAssigneeId,
    required this.onAssigneeChanged,
  });

  final Key cardKey;
  final String title;
  final HomeSalesProgress progress;
  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final ValueChanged<String?>? onAssigneeChanged;

  @override
  Widget build(BuildContext context) {
    final period = progress.range;
    final percent = period.percentage ?? 0;
    return Material(
      key: cardKey,
      color: AppColors.raisedOf(context),
      borderRadius: AppRadius.allLg,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.neutral200),
          borderRadius: AppRadius.allLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('$title · Ngày', style: AppTextStyles.labelM),
                ),
                Text(
                  _percentLabel(percent),
                  style: AppTextStyles.labelSmallSubtle.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            if (assignees.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 260,
                height: 48,
                child: _SalesProgressAssigneeDropdown(
                  assignees: assignees,
                  selectedAssigneeId: selectedAssigneeId,
                  onChanged: onAssigneeChanged,
                ),
              ),
            ],
            const SizedBox(height: 10),
            const _CompactPeriodTabs(),
            const SizedBox(height: 10),
            _CompactGoalBar(value: percent),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatCompactVndAmount(period.actual),
                    style: AppTextStyles.bodyCompact.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
                Text(
                  period.target == null
                      ? 'Chưa thiết lập'
                      : formatCompactVndAmount(period.target!),
                  style: AppTextStyles.labelSmallSubtle,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactPeriodTabs extends StatelessWidget {
  const _CompactPeriodTabs();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 48,
    child: Row(
      children: [
        Expanded(child: Center(child: Text('Ngày'))),
        Expanded(child: Center(child: Text('Tuần'))),
        Expanded(child: Center(child: Text('Tháng'))),
      ],
    ),
  );
}

class _CompactGoalBar extends StatelessWidget {
  const _CompactGoalBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        Container(
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.neutral200,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        Container(
          height: 14,
          width: constraints.maxWidth * (value.clamp(0, 100) / 100),
          decoration: BoxDecoration(
            color: AppColors.success,
            borderRadius: BorderRadius.circular(7),
          ),
        ),
      ],
    ),
  );
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.cardKey,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final Key cardKey;
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    key: cardKey,
    color: AppColors.raisedOf(context),
    borderRadius: AppRadius.allCardFigma,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral200),
        borderRadius: AppRadius.allCardFigma,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.headingS),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class _AnalyticsLegend extends StatelessWidget {
  const _AnalyticsLegend({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ),
    ],
  );
}

class _AnalyticsBar extends StatelessWidget {
  const _AnalyticsBar({required this.value, required this.color});
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Stack(
      children: [
        Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.primary100,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        Container(
          height: 12,
          width: c.maxWidth * (value.clamp(0, 100) / 100),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    ),
  );
}

class _AnalyticsPeriod extends StatelessWidget {
  const _AnalyticsPeriod({
    super.key,
    required this.label,
    required this.period,
    required this.color,
  });
  final String label;
  final HomeSalesProgressPeriod period;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final p = period.percentage ?? 0;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 10),
          _AnalyticsBar(value: p, color: color),
          const SizedBox(height: 8),
          Text(
            _percentLabel(p),
            style: AppTextStyles.headingS.copyWith(color: color),
          ),
          Text(
            period.target == null
                ? 'Chưa thiết lập'
                : '${formatCompactVndAmount(period.actual)}/${formatCompactVndAmount(period.target!)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

String _scopeSalesProgressTitle(HomeSummary summary) {
  final scope = summary.scope.trim().toUpperCase();
  final label = summary.resolvedScopeLabel.toLowerCase();
  if (scope == 'ALL') return 'Tổng quan toàn hệ thống';
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
