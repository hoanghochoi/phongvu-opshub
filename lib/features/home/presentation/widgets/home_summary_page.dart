import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
import 'home_summary_header_layout.dart';

part 'home_summary_metric_sections.dart';
part 'home_summary_detail_sections.dart';

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
        final pageChildren = <Widget>[
          header,
          SizedBox(
            height: constraints.maxWidth >= 1100
                ? AppLayoutTokens.homeWideHeaderBodyGap
                : AppLayoutTokens.cardGap,
          ),
          // Header and metrics share one scroll surface so the greeting/filter
          // card never remains pinned above the dashboard body.
          ...content,
          if (footer != null) ...[
            const SizedBox(height: AppLayoutTokens.cardGap),
            footer!,
          ],
          const SizedBox(height: 20),
        ];
        final page = Column(
          key: const Key('home-summary-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: pageChildren,
        );
        final canOwnScroll =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
        if (!canOwnScroll) return page;
        return SingleChildScrollView(
          key: const Key('home-summary-scroll-body'),
          physics: const AlwaysScrollableScrollPhysics(),
          child: page,
        );
      },
    );
  }

  List<Widget> _buildSummaryContent(HomeSummary? summary) {
    if (provider.isInitialLoading) {
      return [
        AppLoadingBanner(
          key: const Key('home-summary-loading'),
          message: 'Đang tải dữ liệu dashboard…',
          trailingLabel: 'Đang tải',
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
            actionIcon: PhosphorIconsRegular.arrowClockwise,
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
        const _SummarySubsectionHeader(
          title: 'Doanh số',
          description:
              'Doanh thu, đơn hàng và hiệu quả chuyển đổi theo phạm vi đã chọn.',
          large: true,
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        SummaryCardGrid(summary: summary),
        const SizedBox(height: AppLayoutTokens.sectionGap),
        const _SummarySubsectionHeader(title: 'KPI chính'),
        const SizedBox(height: AppLayoutTokens.cardGap),
        MainKpiSummaryCardGrid(summary: summary, provider: provider),
        const SizedBox(height: AppLayoutTokens.sectionGap),
        const _SummarySubsectionHeader(title: 'Hành vi then chốt'),
        const SizedBox(height: AppLayoutTokens.cardGap),
        SalesBehaviorSummaryCardGrid(summary: summary, provider: provider),
      ],
      if (summary.financeAvailable) ...[
        const SizedBox(height: AppLayoutTokens.sectionGap),
        const _SummarySectionHeader(
          key: Key('home-finance-section-header'),
          title: 'Tài chính',
          description:
              'Chỉ hiển thị khi tài khoản được phép xem tài chính; có thể mở Sao kê theo phạm vi.',
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
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
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: Key('home-section-header-$title'),
      height: 47,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.pageTitle.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
              height: 15 / 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummarySubsectionHeader extends StatelessWidget {
  const _SummarySubsectionHeader({
    required this.title,
    this.description,
    this.large = false,
  });

  final String title;
  final String? description;
  final bool large;

  @override
  Widget build(BuildContext context) {
    if (!large) {
      return Text(
        title,
        style: AppTextStyles.labelM.copyWith(
          color: AppColors.textPrimaryOf(context),
        ),
      );
    }
    return SizedBox(
      height: 47,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.pageTitle.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textSecondaryOf(context),
                height: 15 / 13,
              ),
            ),
          ],
        ],
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
        ? 'Cập nhật lúc --'
        : 'Cập nhật lúc ${_timeOnlyLabel(summary!.refreshedAt!)}';

    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        final controls = _HomeInlineFilters(
          availableWidth: math.max(0.0, constraints.maxWidth - 38),
          mobile: mobile,
          selectedScope: selectedScope,
          selectedScopeLabel: selectedScopeLabel.isEmpty
              ? scopeLabel
              : selectedScopeLabel,
          scopeOptions: scopeOptions,
          selectedStartDate: selectedStartDate,
          selectedEndDate: selectedEndDate,
          onScopeChanged: onScopeChanged,
          onDateRangeChanged: onDateRangeChanged,
          updatedLabel: updatedLabel,
          isRefreshing: isRefreshing,
          onRefresh: onRefresh,
          action: action,
        );
        final visualHeader = mobile
            ? Container(
                key: const Key('home-summary-header'),
                height: 288,
                padding: const EdgeInsets.all(17),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
            : Container(
                key: const Key('home-summary-header'),
                height: 146,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
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
                    SizedBox(
                      height: 48,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _HomeSummaryAvatar(name: greetingName),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  greetingLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.headingS.copyWith(
                                    color: AppColors.textPrimaryOf(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  greetingSubtitle ?? scopeLabel,
                                  maxLines: 1,
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
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: 40, child: controls),
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
                icon: PhosphorIconsRegular.warning,
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

class _HomeInlineFilters extends StatelessWidget {
  const _HomeInlineFilters({
    required this.availableWidth,
    required this.mobile,
    required this.selectedScope,
    required this.selectedScopeLabel,
    required this.scopeOptions,
    required this.selectedStartDate,
    required this.selectedEndDate,
    required this.onScopeChanged,
    required this.onDateRangeChanged,
    required this.updatedLabel,
    required this.isRefreshing,
    required this.onRefresh,
    this.action,
  });

  final double availableWidth;
  final bool mobile;
  final String selectedScope;
  final String selectedScopeLabel;
  final List<HomeSummaryScopeOption> scopeOptions;
  final DateTime? selectedStartDate;
  final DateTime? selectedEndDate;
  final ValueChanged<String>? onScopeChanged;
  final void Function(DateTime? start, DateTime? end) onDateRangeChanged;
  final String updatedLabel;
  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Widget scopeControl(double width) => SizedBox(
      key: const Key('home-summary-scope-control'),
      width: width,
      child: _HomeInlineScopeDropdown(
        width: width,
        selectedScope: selectedScope,
        selectedScopeLabel: selectedScopeLabel,
        scopeOptions: scopeOptions,
        onScopeChanged: onScopeChanged,
      ),
    );

    Widget dateControl(double width) => SizedBox(
      key: const Key('home-summary-date-control'),
      width: width,
      child: KeyedSubtree(
        key: const Key('home-summary-date-range'),
        child: AppDateRangeDropdown(
          label: 'Khoảng ngày',
          start: selectedStartDate,
          end: selectedEndDate,
          onChanged: onDateRangeChanged,
          showEmptyRangeHelperText: false,
          inlineSurfaceStyle: true,
          now: DateTime.now,
        ),
      ),
    );

    final updateControl = _HomeHeaderChip(
      key: const Key('home-summary-refresh-button'),
      label: updatedLabel,
      onTap: onRefresh,
      busy: isRefreshing,
      leadingIcon: PhosphorIconsRegular.info,
      maxWidth: mobile ? availableWidth : null,
    );
    if (mobile) {
      final metadataControl = SizedBox(
        width: math.min(171, availableWidth),
        child: updateControl,
      );
      return Column(
        key: const Key('home-summary-controls'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          scopeControl(availableWidth),
          const SizedBox(height: 8),
          dateControl(availableWidth),
          const SizedBox(height: 8),
          if (action == null)
            Align(alignment: Alignment.centerLeft, child: metadataControl)
          else
            Row(
              children: [
                Expanded(child: updateControl),
                const SizedBox(width: 8),
                SizedBox(width: 152, child: action!),
              ],
            ),
        ],
      );
    }

    final layout = HomeSummaryHeaderLayout.desktop(
      availableWidth: availableWidth,
      hasAction: action != null,
    );

    return Row(
      key: const Key('home-summary-controls'),
      children: [
        scopeControl(layout.scopeWidth),
        const SizedBox(width: HomeSummaryHeaderLayout.gap),
        dateControl(layout.dateWidth),
        const SizedBox(width: HomeSummaryHeaderLayout.gap),
        SizedBox(width: layout.updateWidth, child: updateControl),
        if (action != null) ...[
          const SizedBox(width: HomeSummaryHeaderLayout.gap),
          SizedBox(width: HomeSummaryHeaderLayout.actionWidth, child: action!),
        ],
      ],
    );
  }
}

class _HomeInlineScopeDropdown extends StatelessWidget {
  const _HomeInlineScopeDropdown({
    required this.width,
    required this.selectedScope,
    required this.selectedScopeLabel,
    required this.scopeOptions,
    required this.onScopeChanged,
  });

  final double width;
  final String selectedScope;
  final String selectedScopeLabel;
  final List<HomeSummaryScopeOption> scopeOptions;
  final ValueChanged<String>? onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final canSelect = scopeOptions.length > 1 && onScopeChanged != null;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final menuWidth = math.min(
      math.max(width, 220.0),
      math.max(0.0, viewportWidth - 32),
    );
    return MenuAnchor(
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(0, 4),
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: WidgetStatePropertyAll(2),
      ),
      builder: (context, controller, _) => SizedBox(
        width: width,
        child: _HomeHeaderChip(
          key: const Key('home-summary-scope-trigger'),
          label: 'Phạm vi: ${_shortScopeLabel(selectedScopeLabel)}',
          onTap: canSelect ? controller.open : null,
          showCaret: canSelect,
          maxWidth: width,
        ),
      ),
      menuChildren: [
        Material(
          key: const Key('home-summary-scope-menu'),
          color: AppColors.raisedOf(context),
          child: SizedBox(
            width: menuWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in scopeOptions)
                  MenuItemButton(
                    onPressed: canSelect
                        ? () => onScopeChanged?.call(option.value)
                        : null,
                    leadingIcon: Icon(
                      option.value == selectedScope
                          ? PhosphorIconsRegular.check
                          : PhosphorIconsRegular.storefront,
                      size: 18,
                      color: option.value == selectedScope
                          ? AppColors.primaryOf(context)
                          : AppColors.textSecondaryOf(context),
                    ),
                    child: SizedBox(
                      width: math.max(0.0, menuWidth - 64),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyM,
                          ),
                          if (_ScopeSelectorField._scopeOptionSubtitle(option)
                              case final subtitle?)
                            Text(
                              subtitle,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
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
    this.leadingIcon,
    this.showCaret = false,
    this.maxWidth,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final IconData? leadingIcon;
  final bool showCaret;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final icon = busy ? PhosphorIconsRegular.spinnerGap : leadingIcon;
    final textMaxWidth = maxWidth == null
        ? double.infinity
        : math
              .max(
                0,
                maxWidth! - 24 - (icon == null ? 0 : 24) - (showCaret ? 24 : 0),
              )
              .toDouble();
    final chip = Material(
      color: AppColors.chipBackgroundOf(context),
      borderRadius: AppRadius.allSm,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: AppRadius.allSm,
        child: Container(
          height: 40,
          constraints: maxWidth == null
              ? null
              : BoxConstraints(maxWidth: maxWidth!),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 8),
              ],
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: textMaxWidth),
                  child: Text(
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
              if (showCaret) ...[
                const SizedBox(width: 8),
                Icon(
                  PhosphorIconsRegular.caretDown,
                  size: 16,
                  color: AppColors.textSecondaryOf(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Semantics(button: onTap != null, label: label, child: chip);
  }
}

String _shortScopeLabel(String label) {
  final trimmed = label.trim();
  return trimmed.isEmpty ? 'Showroom được phân quyền' : trimmed;
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
        icon: PhosphorIconsRegular.storefront,
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
        icon: PhosphorIconsRegular.magnifyingGlass,
        title: 'Khách chưa mua',
        value: _integerLabel(summary.notPurchasedReports),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.secondaryOf(context),
        textTapTooltip: 'Xem chi tiết khách chưa mua',
        onTextTap: () => _openSalesBehaviorDetailsDialog(
          context,
          provider,
          _SalesBehaviorDetailTab.notPurchased,
        ),
      ),
      SummaryCard(
        metricKey: 'unreportedOrders',
        icon: PhosphorIconsRegular.clockCounterClockwise,
        title: 'Đơn chưa báo cáo',
        value: _integerLabel(summary.unreportedOrders),
        trend: summary.unreportedOrders > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warningOf(context),
        textTapTooltip: 'Xem chi tiết đơn chưa báo cáo',
        onTextTap: () => _openSalesBehaviorDetailsDialog(
          context,
          provider,
          _SalesBehaviorDetailTab.unreported,
        ),
      ),
      SummaryCard(
        metricKey: 'reportedOrders',
        icon: PhosphorIconsRegular.receipt,
        title: 'Báo cáo đã mua',
        value: _integerLabel(summary.reportedOrders),
        trend: const SummaryTrend.success('đã ghi nhận'),
        color: AppColors.successOf(context),
        textTapTooltip: provider.canOpenSalesReportAdmin
            ? 'Mở Quản trị/Báo cáo bán hàng'
            : null,
        onTextTap: provider.canOpenSalesReportAdmin
            ? () => _openSalesReportAdmin(context, provider)
            : null,
      ),
      SummaryCard(
        metricKey: 'coverageRate',
        icon: PhosphorIconsRegular.shieldCheck,
        title: summary.resolvedCoverageLabel,
        value: _percentLabel(summary.coverageRate),
        trend: SummaryTrend.coverage(summary.coverageRate),
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'consultedSolutionRate',
        icon: PhosphorIconsRegular.squaresFour,
        title: 'Tỉ lệ 3 giải pháp',
        value: _percentLabel(summary.consultedSolutionRate),
        trend: SummaryTrend.yesRate(summary.consultedSolutionRate),
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'experiencedRate',
        icon: PhosphorIconsRegular.info,
        title: 'Tỉ lệ trải nghiệm',
        value: _percentLabel(summary.experiencedRate),
        trend: SummaryTrend.yesRate(summary.experiencedRate),
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'zaloRate',
        icon: PhosphorIconsRegular.bell,
        title: 'Tỉ lệ Zalo OA',
        value: _percentLabel(summary.zaloRate),
        trend: SummaryTrend.yesRate(summary.zaloRate),
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'appDownloadRate',
        icon: PhosphorIconsRegular.downloadSimple,
        title: 'Tỉ lệ tải App',
        value: _percentLabel(summary.appDownloadRate),
        trend: SummaryTrend.yesRate(summary.appDownloadRate),
        color: AppColors.secondaryOf(context),
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-sales-behavior-summary-grid'),
      cards: cards,
      wideColumns: 4,
      rowHeights: const [136, 136],
      expandedRowHeights: const [146],
      mediumRowHeights: const [136],
      compactRowHeights: const [184],
      showComparisons: true,
      useRootViewportBreakpoints: true,
      comparisons: summary.comparisons,
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
        icon: PhosphorIconsRegular.currencyCircleDollar,
        title: 'Tiền chuyển khoản',
        value: formatCompactVndAmount(summary.totalTransferredAmount),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'totalStatements',
        icon: PhosphorIconsRegular.receipt,
        title: 'Sao kê',
        value: _integerLabel(summary.totalStatements),
        trend: const SummaryTrend.neutral('Trong ngày'),
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'totalStatementsTracked',
        icon: PhosphorIconsRegular.eye,
        title: 'Sao kê đang theo dõi',
        value: _integerLabel(summary.totalStatementsTracked),
        trend: const SummaryTrend.neutral('Dùng để tính tỷ lệ'),
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'totalStatementsUnfollowed',
        icon: PhosphorIconsRegular.eyeSlash,
        title: 'Sao kê đã bỏ theo dõi',
        value: _integerLabel(summary.totalStatementsUnfollowed),
        trend: const SummaryTrend.neutral('Không tính đối chiếu đơn'),
        color: AppColors.textMutedOf(context),
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithOrder',
        icon: PhosphorIconsRegular.notepad,
        title: 'Sao kê có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithOrder),
        trend: const SummaryTrend.success('đã đối chiếu'),
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'totalStatementsWithoutOrder',
        icon: PhosphorIconsRegular.warningCircle,
        title: 'Sao kê chưa có đơn hàng',
        value: _integerLabel(summary.totalStatementsWithoutOrder),
        trend: summary.totalStatementsWithoutOrder > 0
            ? const SummaryTrend.warning('cần xử lý')
            : const SummaryTrend.success('đã đủ'),
        color: AppColors.warningOf(context),
        textTapTooltip: provider.canOpenBankStatement
            ? 'Mở Sao kê với bộ lọc chưa có đơn hàng'
            : null,
        onTextTap: provider.canOpenBankStatement
            ? () => _openMissingOrderStatements(context, provider)
            : null,
      ),
      SummaryCard(
        metricKey: 'statementOrderRate',
        icon: PhosphorIconsRegular.arrowsLeftRight,
        title: 'Tỉ lệ sao kê có đơn hàng',
        value: _percentLabel(summary.statementOrderRate),
        trend: SummaryTrend.statementOrder(summary.statementOrderRate),
        color: AppColors.infoOf(context),
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-finance-summary-grid'),
      cards: cards,
      wideColumns: 5,
      rowHeights: const [164],
      expandedRowHeights: const [146],
      mediumRowHeights: const [136],
      compactRowHeights: const [184],
    );
  }
}

class _SummaryMetricGrid extends StatelessWidget {
  const _SummaryMetricGrid({
    required this.gridKey,
    required this.cards,
    this.wideColumns = 6,
    this.rowHeights,
    this.expandedRowHeights,
    this.mediumRowHeights,
    this.compactRowHeights,
    this.showComparisons = false,
    this.useRootViewportBreakpoints = false,
    this.comparisons,
  });

  final Key gridKey;
  final List<SummaryCard> cards;
  final int wideColumns;
  final List<double>? rowHeights;
  final List<double>? expandedRowHeights;
  final List<double>? mediumRowHeights;
  final List<double>? compactRowHeights;
  final bool showComparisons;
  final bool useRootViewportBreakpoints;
  final HomeSummaryComparisons? comparisons;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final view = View.of(context);
        final viewportWidth = view.physicalSize.width / view.devicePixelRatio;
        // The approved expanded/wide Home frames classify Sales grids from
        // the root viewport because the AppShell narrows their content lane.
        // Compact and medium layouts stay content-width-driven so Sales and
        // Finance cross the mobile breakpoint together. Extremely narrow
        // content must fall back to one card per row.
        final breakpointWidth =
            useRootViewportBreakpoints &&
                viewportWidth >= AppLayoutTokens.tabletBreakpoint
            ? viewportWidth
            : width;
        final maxColumns = width < 320
            ? 1
            : breakpointWidth >= AppLayoutTokens.desktopBreakpoint
            ? math.min(wideColumns, cards.length)
            : breakpointWidth >= AppLayoutTokens.tabletBreakpoint
            ? math.min(3, cards.length)
            : breakpointWidth >= AppLayoutTokens.compactBreakpoint
            ? 1
            : math.min(2, cards.length);
        final rows = _balancedRows(cards, maxColumns);
        const gap = 16.0;
        final rowHeightsForWidth =
            breakpointWidth >= AppLayoutTokens.desktopBreakpoint
            ? rowHeights
            : breakpointWidth >= AppLayoutTokens.tabletBreakpoint
            ? expandedRowHeights
            : breakpointWidth >= AppLayoutTokens.compactBreakpoint
            ? mediumRowHeights
            : compactRowHeights;
        final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
        final comparisonHeightAdjustment = showComparisons
            ? 120.0 * (textScale.clamp(1.0, 2.0) - 1.0)
            : 0.0;

        final grid = Column(
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
                        height:
                            (rowHeightsForWidth == null
                                ? 136
                                : rowHeightsForWidth[math.min(
                                    rowIndex,
                                    rowHeightsForWidth.length - 1,
                                  )]) +
                            comparisonHeightAdjustment,
                        child: rows[rowIndex][columnIndex],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
        if (!showComparisons) return grid;
        return _HomeComparisonScope(comparisons: comparisons, child: grid);
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
    this.helperText,
    this.onTextTap,
    this.textTapTooltip,
  });

  final String metricKey;
  final IconData icon;
  final String title;
  final String value;
  final SummaryTrend trend;
  final Color color;
  final String? helperText;
  final VoidCallback? onTextTap;
  final String? textTapTooltip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final comparisonScope = _HomeComparisonScope.maybeOf(context);
        final showComparisons = comparisonScope != null;
        final comparisonMetricKey = metricKey == 'revenue'
            ? 'totalRevenue'
            : metricKey;
        final comparisons = comparisonScope?.comparisons?.forMetric(
          comparisonMetricKey,
        );
        final compact =
            constraints.hasBoundedHeight && constraints.maxHeight < 120;
        final dense =
            constraints.hasBoundedHeight && constraints.maxHeight < 160;
        final iconDimension = compact
            ? 28.0
            : dense
            ? 32.0
            : 36.0;
        final iconSize = compact
            ? 18.0
            : dense
            ? 22.0
            : 24.0;
        if (compact) {
          return AppSurfaceCard(
            key: Key('home-summary-card-$metricKey'),
            borderColor: AppColors.borderOf(context),
            backgroundColor: AppColors.raisedOf(context),
            padding: const EdgeInsets.all(8),
            radius: AppRadius.lg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: iconDimension,
                  height: iconDimension,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.infoSurfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    key: Key('home-summary-card-$metricKey-icon'),
                    color: AppColors.primaryOf(context),
                    size: iconSize,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                          style: AppTextStyles.labelS.copyWith(
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _SummaryCardTextAction(
                        key: Key('home-summary-card-$metricKey-value-action'),
                        onTap: onTextTap,
                        tooltip: textTapTooltip,
                        child: _SummaryValueRow(
                          value: value,
                          trend: trend,
                          showTrend: !showComparisons,
                          style: AppTextStyles.labelM.copyWith(
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                      if (showComparisons) ...[
                        const SizedBox(height: 2),
                        _SummaryPeriodComparisons(
                          metricKey: metricKey,
                          comparisons: comparisons,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return AppSurfaceCard(
          key: Key('home-summary-card-$metricKey'),
          borderColor: AppColors.borderOf(context),
          backgroundColor: AppColors.raisedOf(context),
          padding: EdgeInsets.all(
            compact
                ? 8
                : dense
                ? 12
                : 16,
          ),
          radius: AppRadius.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: iconDimension,
                    height: iconDimension,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.infoSurfaceOf(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      key: Key('home-summary-card-$metricKey-icon'),
                      color: AppColors.primaryOf(context),
                      size: iconSize,
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  Expanded(
                    child: _SummaryCardTextAction(
                      key: Key('home-summary-card-$metricKey-title-action'),
                      onTap: onTextTap,
                      tooltip: textTapTooltip,
                      child: Text(
                        title,
                        maxLines: dense ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelM.copyWith(
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: compact
                    ? 6
                    : dense
                    ? 8
                    : 12,
              ),
              _SummaryCardTextAction(
                key: Key('home-summary-card-$metricKey-value-action'),
                onTap: onTextTap,
                tooltip: textTapTooltip,
                child: _SummaryValueRow(
                  value: value,
                  trend: trend,
                  showTrend: !showComparisons,
                  style: AppTextStyles.headingS.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              if (!compact)
                if (showComparisons) ...[
                  SizedBox(height: dense ? 4 : 12),
                  _SummaryPeriodComparisons(
                    metricKey: metricKey,
                    comparisons: comparisons,
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    helperText ?? _summaryCardHelperText(trend),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyS.copyWith(
                      color: AppColors.textSecondaryOf(context),
                      height: 18 / 13,
                    ),
                  ),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _HomeComparisonScope extends InheritedWidget {
  const _HomeComparisonScope({required this.comparisons, required super.child});

  final HomeSummaryComparisons? comparisons;

  static _HomeComparisonScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomeComparisonScope>();

  @override
  bool updateShouldNotify(_HomeComparisonScope oldWidget) =>
      comparisons != oldWidget.comparisons;
}

class _SummaryPeriodComparisons extends StatelessWidget {
  const _SummaryPeriodComparisons({
    required this.metricKey,
    required this.comparisons,
    this.compact = false,
  });

  final String metricKey;
  final HomeSummaryMetricComparisons? comparisons;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const unavailable = HomeSummaryComparisonMetric.unavailable();
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    return SizedBox(
      key: Key('home-summary-card-$metricKey-comparisons'),
      height: textScale <= 1 ? (compact ? 28 : 36) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SummaryComparisonRow(
            key: Key('home-summary-card-$metricKey-t-minus-1'),
            metricKey: metricKey,
            icon: PhosphorIconsRegular.clockCounterClockwise,
            shortLabel: 'T−1',
            semanticLabel: 'Tháng liền trước',
            metric: comparisons?.previousMonth ?? unavailable,
            source: comparisons?.previousMonthSource ?? 'UNAVAILABLE',
            compact: compact,
          ),
          SizedBox(height: compact ? 2 : 4),
          _SummaryComparisonRow(
            key: Key('home-summary-card-$metricKey-n-minus-1'),
            metricKey: metricKey,
            icon: PhosphorIconsRegular.arrowsLeftRight,
            shortLabel: 'N−1',
            semanticLabel: 'Cùng kỳ năm trước',
            metric: comparisons?.previousYear ?? unavailable,
            source: comparisons?.previousYearSource ?? 'UNAVAILABLE',
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _SummaryComparisonRow extends StatefulWidget {
  const _SummaryComparisonRow({
    super.key,
    required this.metricKey,
    required this.icon,
    required this.shortLabel,
    required this.semanticLabel,
    required this.metric,
    required this.source,
    required this.compact,
  });

  final String metricKey;
  final IconData icon;
  final String shortLabel;
  final String semanticLabel;
  final HomeSummaryComparisonMetric metric;
  final String source;
  final bool compact;

  @override
  State<_SummaryComparisonRow> createState() => _SummaryComparisonRowState();
}

class _SummaryComparisonRowState extends State<_SummaryComparisonRow> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();
  final FocusNode _sourceFocusNode = FocusNode();

  @override
  void dispose() {
    _sourceFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) {
      _tooltipKey.currentState?.ensureTooltipVisible();
      return;
    }
    Tooltip.dismissAllToolTips();
  }

  @override
  Widget build(BuildContext context) {
    final value = _comparisonMetricText(widget.metricKey, widget.metric);
    final sourceLabel = _comparisonSourceLabel(widget.source);
    return Tooltip(
      key: _tooltipKey,
      message: 'Nguồn: $sourceLabel',
      child: FocusableActionDetector(
        focusNode: _sourceFocusNode,
        onFocusChange: _handleFocusChange,
        child: Semantics(
          label: '${widget.semanticLabel}: $value. Nguồn: $sourceLabel',
          container: true,
          excludeSemantics: true,
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(10) <= 10
                ? (widget.compact ? 13 : 16)
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.icon,
                  size: 12,
                  color: AppColors.textSecondaryOf(context),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.shortLabel,
                  style: AppTextStyles.labelSmallSubtle.copyWith(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 9,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      value,
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmallSubtle.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
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

String _comparisonSourceLabel(String source) => switch (source) {
  'OPSHUB' => 'OpsHub',
  'CSV' => 'Tệp CSV đã kích hoạt',
  'HYBRID_CSV' => 'OpsHub kết hợp tệp CSV',
  _ => 'Chưa xác định',
};

const _comparisonMoneyMetrics = {
  'revenue',
  'totalRevenue',
  'averageOrderValue',
  'completedRevenue',
  'pendingRevenue',
  'businessCustomerRevenue',
  'personalCustomerRevenue',
};

const _comparisonPercentMetrics = {
  'conversionRate',
  'coverageRate',
  'consultedSolutionRate',
  'experiencedRate',
  'zaloRate',
  'appDownloadRate',
};

String _comparisonMetricText(
  String metricKey,
  HomeSummaryComparisonMetric metric,
) {
  if (metric.isUnavailable) return 'Chưa có dữ liệu';
  if (metric.isNew) return 'Mới';
  final rawValue = metric.value ?? 0;
  final value = _comparisonMoneyMetrics.contains(metricKey)
      ? formatCompactVndAmount(rawValue)
      : _comparisonPercentMetrics.contains(metricKey)
      ? _percentLabel(rawValue.toDouble())
      : _integerLabel(rawValue.round());
  final delta = metric.deltaPercent ?? 0;
  final direction = delta > 0
      ? '↑'
      : delta < 0
      ? '↓'
      : '';
  final absolute = delta.abs();
  final deltaNumber = absolute
      .toStringAsFixed(absolute % 1 == 0 ? 0 : 1)
      .replaceAll('.', ',');
  return '$value · $direction$deltaNumber%';
}

class _SummaryValueRow extends StatelessWidget {
  const _SummaryValueRow({
    required this.value,
    required this.trend,
    required this.style,
    this.showTrend = true,
  });

  final String value;
  final SummaryTrend trend;
  final TextStyle style;
  final bool showTrend;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(value, maxLines: 1, softWrap: false, style: style),
              if (showTrend) ...[
                const SizedBox(width: 8),
                _SummaryTrendPill(trend: trend),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _summaryCardHelperText(SummaryTrend trend) {
  return switch (trend.tone) {
    SummaryTrendTone.success => 'Theo báo cáo',
    SummaryTrendTone.warning => 'Cần theo dõi',
    SummaryTrendTone.neutral => trend.label,
  };
}

class _SummaryTrendPill extends StatelessWidget {
  const _SummaryTrendPill({required this.trend});

  final SummaryTrend trend;

  @override
  Widget build(BuildContext context) {
    final isWarning = trend.tone == SummaryTrendTone.warning;
    final background = isWarning
        ? AppColors.warningSurfaceOf(context)
        : AppColors.successSurfaceOf(context);
    final foreground = isWarning
        ? AppColors.warningOf(context)
        : AppColors.secondaryOf(context);
    return LayoutBuilder(
      builder: (context, _) => Container(
        key: Key('home-summary-card-${trend.label}-trend-pill'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.allPill,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              trend.label,
              maxLines: 1,
              softWrap: false,
              style: AppTextStyles.labelSmallSubtle.copyWith(color: foreground),
            ),
          ),
        ),
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
                    icon: const Icon(PhosphorIconsRegular.x, size: 20),
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
                    icon: const Icon(PhosphorIconsRegular.x, size: 20),
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

class SummaryTrend {
  const SummaryTrend._({
    required this.label,
    required this.icon,
    required this.tone,
  });

  const SummaryTrend.success(String label)
    : this._(
        label: label,
        icon: PhosphorIconsRegular.trendUp,
        tone: SummaryTrendTone.success,
      );

  const SummaryTrend.warning(String label)
    : this._(
        label: label,
        icon: PhosphorIconsRegular.trendUp,
        tone: SummaryTrendTone.warning,
      );

  const SummaryTrend.neutral(String label)
    : this._(
        label: label,
        icon: PhosphorIconsRegular.minus,
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
    return _ApprovedReportProgressPanel(summary: summary, provider: provider);

    // Retained below temporarily for provider/consumer migration proof; the
    // approved proposal path above is the only runtime visual path.
    // ignore: dead_code
    final reported = summary.totalOrders <= 0
        ? 0.0
        : summary.reportedOrders / summary.totalOrders * 100;
    final progressCards = <_AnalyticsCardSpec>[
      if (summary.salesAvailable)
        _AnalyticsCardSpec(
          compactHeight: 248,
          expandedHeight: 248,
          card: _AnalyticsDonutCard(
            cardKey: const Key('home-report-progress-panel'),
            title: 'Tiến độ báo cáo',
            subtitle:
                'Đã báo cáo ${summary.reportedOrders}/${summary.totalOrders} đơn',
            percentage: summary.coverageRate,
            color: AppColors.successOf(context),
            primaryLegend: 'Đã báo cáo · ${summary.reportedOrders} đơn',
            secondaryLegend: 'Chưa báo cáo · ${summary.unreportedOrders} đơn',
            primaryPercent: reported,
          ),
        ),
      if (summary.financeAvailable)
        _AnalyticsCardSpec(
          compactHeight: 248,
          expandedHeight: 248,
          card: _AnalyticsDonutCard(
            cardKey: const Key('home-statement-progress-panel'),
            title: 'Tiến độ sao kê',
            subtitle: 'Đối chiếu sao kê với đơn hàng',
            percentage: summary.statementOrderRate,
            color: AppColors.infoOf(context),
            primaryLegend:
                'Có đơn · ${summary.totalStatementsWithOrder} sao kê',
            secondaryLegend:
                'Chưa có đơn · ${summary.totalStatementsWithoutOrder} sao kê',
            primaryPercent: summary.statementOrderRate,
          ),
        ),
    ];
    final goalCards = <_AnalyticsCardSpec>[
      if (summary.salesAvailable &&
          (summary.personalSalesProgress.isApplicable ||
              summary.salesProgressAssignees.isNotEmpty))
        _AnalyticsCardSpec(
          compactHeight: summary.salesProgressAssignees.isEmpty ? 208 : 266,
          expandedHeight: summary.salesProgressAssignees.isEmpty ? 208 : 264,
          card: _AnalyticsPeriodCard(
            cardKey: const Key('home-sales-progress-panel'),
            title: 'Doanh số cá nhân',
            compactTitle: 'Doanh số cá nhân',
            subtitle: summary.selectedSalesProgressUserId == null
                ? 'Chọn nhân viên để so sánh chỉ tiêu'
                : 'Tiến độ theo nhân viên đã chọn',
            color: AppColors.accentOf(context),
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
          expandedHeight: 208,
          card: _AnalyticsPeriodCard(
            cardKey: const Key('home-scope-sales-progress-panel'),
            title: 'Doanh số theo phạm vi',
            compactTitle: 'Doanh số theo phạm vi',
            subtitle: summary.scopeSalesProgress.hasTarget
                ? 'Tiến độ theo phạm vi được phân quyền'
                : 'Thiếu chỉ tiêu: ${summary.scopeSalesProgress.missingStoreCodes.join(', ')}',
            color: AppColors.primaryOf(context),
            progress: summary.scopeSalesProgress,
          ),
        ),
    ];
    if (progressCards.isEmpty && goalCards.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // The responsive Home frames use the full content width at each
        // desktop breakpoint (896px at 1024, 982px at 1280, 1180px at
        // 1920). Keep the 16px gutter and let each chart card grow with the
        // available viewport instead of freezing the 896px specimen width.
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final boundedParentWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : viewportWidth;
        final boardWidth = math.min(
          AppLayoutTokens.contentMaxWidth,
          math.max(0.0, math.min(boundedParentWidth, viewportWidth)),
        );
        final compact = boardWidth < AppLayoutTokens.compactBreakpoint;
        // Desktop/expanded uses one Goal Progress slot beside the two rings;
        // compact and medium stack both approved personal/scope goal states.
        final visibleGoalCards = boardWidth >= 880
            ? goalCards.take(1)
            : goalCards;
        final cards = [...progressCards, ...visibleGoalCards];
        final columns = boardWidth >= 880 ? 3 : 1;
        final gap = 16.0;
        final width = columns == 1
            ? boardWidth
            : (boardWidth - gap * (columns - 1)) / columns;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: boardWidth,
            child: Column(
              key: const Key('home-summary-progress-panel'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

class _ApprovedReportProgressPanel extends StatelessWidget {
  const _ApprovedReportProgressPanel({
    required this.summary,
    required this.provider,
  });

  final HomeSummary summary;
  final HomeSummaryProvider provider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final boundedWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : viewportWidth;
        final boardWidth = math.min(
          AppLayoutTokens.salesReportMaxWidth,
          math.min(viewportWidth, boundedWidth),
        );
        final twoColumns = boardWidth >= 880;
        final wide = boardWidth >= 1100;
        const gap = 16.0;
        final singleColumnInset = !twoColumns;
        final horizontalPadding = wide ? 40.0 : (singleColumnInset ? 2.0 : 0.0);
        final contentWidth = math.max(0.0, boardWidth - horizontalPadding);
        final columns = twoColumns ? 2 : 1;
        final cardWidth = columns == 1
            ? contentWidth
            : (contentWidth - gap) / columns;
        final cards = <_OverviewCardSpec>[
          if (summary.salesAvailable)
            _OverviewCardSpec(
              card: _OverviewProgressCard(
                cardKey: const Key('home-report-progress-panel'),
                title: 'Tiến độ báo cáo',
                percentage: summary.coverageRate,
                completedLabel: 'Đã báo cáo',
                completedValue: '${summary.reportedOrders} đơn',
                missingLabel: 'Còn thiếu',
                missingValue: '${summary.unreportedOrders} đơn',
                color: AppColors.successOf(context),
                surfaceColor: AppColors.homeOverviewSuccessSurfaceOf(context),
                borderColor: AppColors.homeOverviewSuccessBorderOf(context),
                trackColor: AppColors.homeOverviewSuccessTrackOf(context),
              ),
            ),
          if (summary.financeAvailable)
            _OverviewCardSpec(
              card: _OverviewProgressCard(
                cardKey: const Key('home-statement-progress-panel'),
                title: 'Tiến độ sao kê',
                percentage: summary.statementOrderRate,
                completedLabel: 'Có đơn hàng',
                completedValue: '${summary.totalStatementsWithOrder} sao kê',
                missingLabel: 'Chưa có đơn',
                missingValue: '${summary.totalStatementsWithoutOrder} sao kê',
                color: AppColors.infoOf(context),
                surfaceColor: AppColors.homeOverviewInfoSurfaceOf(context),
                borderColor: AppColors.homeOverviewInfoBorderOf(context),
                trackColor: AppColors.homeOverviewInfoTrackOf(context),
              ),
            ),
          if (summary.salesAvailable)
            _OverviewCardSpec(
              gapAfter: 12,
              card: _OverviewGoalCard(
                cardKey: const Key('home-sales-progress-panel'),
                title: 'Tổng quan cá nhân',
                color: AppColors.accentOf(context),
                progress: summary.personalSalesProgress,
                keyPrefix: 'sales',
                surfaceColor: AppColors.homeOverviewPersonalSurfaceOf(context),
                borderColor: AppColors.homeOverviewPersonalBorderOf(context),
                compactLayout: boardWidth < 600,
                assignees: summary.salesProgressAssignees,
                selectedAssigneeId: summary.selectedSalesProgressUserId,
                showAssignee: summary.salesProgressAssignees.isNotEmpty,
                onAssigneeChanged: provider.isLoading || provider.isRefreshing
                    ? null
                    : (id) =>
                          unawaited(provider.setSelectedSalesProgressUser(id)),
              ),
            ),
          if (summary.salesAvailable)
            _OverviewCardSpec(
              card: _OverviewGoalCard(
                cardKey: const Key('home-scope-sales-progress-panel'),
                title: 'Tổng quan Cửa hàng',
                color: AppColors.primaryOf(context),
                progress: summary.scopeSalesProgress,
                keyPrefix: 'scope',
                surfaceColor: AppColors.homeOverviewScopeSurfaceOf(context),
                borderColor: AppColors.homeOverviewScopeBorderOf(context),
                compactLayout: boardWidth < 600,
                missingStoreCodes: summary.scopeSalesProgress.missingStoreCodes,
              ),
            ),
        ];
        if (cards.isEmpty) return const SizedBox.shrink();

        return Material(
          key: const Key('home-summary-progress-panel'),
          color: AppColors.homeOverviewSurfaceOf(context),
          borderRadius: AppRadius.allCardFigma,
          child: Container(
            width: boardWidth,
            padding: EdgeInsets.only(
              top: 16,
              bottom: singleColumnInset ? 16 : 24,
            ),
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: AppColors.homeOverviewBorderOf(context),
              ),
              borderRadius: AppRadius.allCardFigma,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: boardWidth < 600 ? 16 : 24,
                  ),
                  child: Text('Tổng quan', style: AppTextStyles.headingM),
                ),
                SizedBox(height: singleColumnInset ? 12 : 16),
                Padding(
                  padding: wide
                      ? const EdgeInsets.only(left: 24, right: 16)
                      : singleColumnInset
                      ? const EdgeInsets.symmetric(horizontal: 1)
                      : EdgeInsets.zero,
                  child: twoColumns
                      ? Column(
                          children: [
                            for (
                              var index = 0;
                              index < cards.length;
                              index += 2
                            ) ...[
                              _EqualHeightOverviewRow(
                                gap: gap,
                                children: [
                                  cards[index].card,
                                  if (index + 1 < cards.length)
                                    cards[index + 1].card,
                                ],
                              ),
                              if (index + 2 < cards.length)
                                SizedBox(height: gap),
                            ],
                          ],
                        )
                      : Column(
                          children: [
                            for (
                              var index = 0;
                              index < cards.length;
                              index++
                            ) ...[
                              SizedBox(
                                width: cardWidth,
                                child: cards[index].card,
                              ),
                              if (index < cards.length - 1)
                                SizedBox(height: cards[index].gapAfter),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EqualHeightOverviewRow extends MultiChildRenderObjectWidget {
  const _EqualHeightOverviewRow({required this.gap, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderEqualHeightOverviewRow(gap: gap);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightOverviewRow renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _EqualHeightOverviewParentData
    extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightOverviewRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualHeightOverviewParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _EqualHeightOverviewParentData
        > {
  _RenderEqualHeightOverviewRow({required double gap}) : _gap = gap;

  double _gap;

  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualHeightOverviewParentData) {
      child.parentData = _EqualHeightOverviewParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childWidth = math.max(0.0, (constraints.maxWidth - _gap) / 2);
    final childConstraints = BoxConstraints.tightFor(
      width: childWidth,
    ).copyWith(minHeight: 0, maxHeight: double.infinity);
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      maxHeight = math.max(
        maxHeight,
        child.getDryLayout(childConstraints).height,
      );
      final parentData = child.parentData! as _EqualHeightOverviewParentData;
      child = parentData.nextSibling;
    }
    return constraints.constrain(Size(constraints.maxWidth, maxHeight));
  }

  @override
  void performLayout() {
    final childWidth = math.max(0.0, (constraints.maxWidth - _gap) / 2);
    final looseChildConstraints = BoxConstraints.tightFor(
      width: childWidth,
    ).copyWith(minHeight: 0, maxHeight: double.infinity);
    var maxHeight = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(looseChildConstraints, parentUsesSize: true);
      maxHeight = math.max(maxHeight, child.size.height);
      final parentData = child.parentData! as _EqualHeightOverviewParentData;
      child = parentData.nextSibling;
    }

    final rowHeight = constraints.constrainHeight(maxHeight);
    final tightChildConstraints = BoxConstraints.tightFor(
      width: childWidth,
      height: rowHeight,
    );
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(tightChildConstraints, parentUsesSize: true);
      final parentData = child.parentData! as _EqualHeightOverviewParentData;
      parentData.offset = Offset(x, 0);
      x += childWidth + _gap;
      child = parentData.nextSibling;
    }
    size = constraints.constrain(Size(constraints.maxWidth, rowHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

class _OverviewCardSpec {
  const _OverviewCardSpec({required this.card, this.gapAfter = 6});

  final Widget card;
  final double gapAfter;
}

class _OverviewProgressCard extends StatelessWidget {
  const _OverviewProgressCard({
    required this.cardKey,
    required this.title,
    required this.percentage,
    required this.completedLabel,
    required this.completedValue,
    required this.missingLabel,
    required this.missingValue,
    required this.color,
    required this.surfaceColor,
    required this.borderColor,
    required this.trackColor,
  });

  final Key cardKey;
  final String title;
  final double? percentage;
  final String completedLabel;
  final String completedValue;
  final String missingLabel;
  final String missingValue;
  final Color color;
  final Color surfaceColor;
  final Color borderColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final value = (percentage ?? 0).clamp(0, 100).toDouble();
    return Material(
      key: cardKey,
      color: surfaceColor,
      borderRadius: AppRadius.allCardFigma,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 15, 24, 12),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor),
          borderRadius: AppRadius.allCardFigma,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.headingS,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mức hoàn thành',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
                Text(
                  _percentLabel(value),
                  style: AppTextStyles.labelS.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _OverviewProgressBar(
              key: Key('${cardKey.toString()}-bar'),
              value: value,
              color: color,
              trackColor: trackColor,
            ),
            const SizedBox(height: 8),
            _OverviewLegendRow(
              label: completedLabel,
              value: '$completedValue (${_percentLabel(value)})',
              color: color,
            ),
            const SizedBox(height: 4),
            _OverviewLegendRow(
              label: missingLabel,
              value: '$missingValue (${_percentLabel(100 - value)})',
              color: AppColors.errorOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewGoalCard extends StatelessWidget {
  const _OverviewGoalCard({
    required this.cardKey,
    required this.title,
    required this.color,
    required this.progress,
    required this.keyPrefix,
    required this.surfaceColor,
    required this.borderColor,
    required this.compactLayout,
    this.assignees = const [],
    this.selectedAssigneeId,
    this.showAssignee = false,
    this.onAssigneeChanged,
    this.missingStoreCodes = const [],
  });

  final Key cardKey;
  final String title;
  final Color color;
  final HomeSalesProgress progress;
  final String keyPrefix;
  final Color surfaceColor;
  final Color borderColor;
  final bool compactLayout;
  final List<HomeSalesProgressAssignee> assignees;
  final String? selectedAssigneeId;
  final bool showAssignee;
  final ValueChanged<String?>? onAssigneeChanged;
  final List<String> missingStoreCodes;

  @override
  Widget build(BuildContext context) {
    final hasSelected = selectedAssigneeId?.trim().isNotEmpty == true;
    final showEmpty = showAssignee && !hasSelected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final firstPeriodLabel = keyPrefix == 'scope' && !compactLayout
            ? 'Khoảng chọn'
            : 'Ngày';
        return Material(
          key: cardKey,
          color: surfaceColor,
          borderRadius: AppRadius.allCardFigma,
          child: Container(
            padding: EdgeInsets.fromLTRB(
              compactLayout ? 20 : 24,
              15,
              compactLayout ? 20 : 24,
              12,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: AppRadius.allCardFigma,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headingS,
                ),
                SizedBox(height: showAssignee ? 17 : 15),
                if (showAssignee)
                  SizedBox(
                    height: 46,
                    child: _SalesProgressAssigneeDropdown(
                      assignees: assignees,
                      selectedAssigneeId: selectedAssigneeId,
                      onChanged: onAssigneeChanged,
                    ),
                  ),
                if (showEmpty)
                  const SizedBox(height: 92, child: _OverviewEmptySelection())
                else ...[
                  if (showAssignee) const SizedBox(height: 8),
                  if (compactLayout && keyPrefix == 'scope')
                    Column(
                      children: [
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-range'),
                          label: firstPeriodLabel,
                          period: progress.day,
                          color: color,
                          dense: true,
                        ),
                        const SizedBox(height: 8),
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-week'),
                          label: 'Tuần',
                          period: progress.week,
                          color: color,
                          dense: true,
                        ),
                        const SizedBox(height: 8),
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-month'),
                          label: 'Tháng',
                          period: progress.month,
                          color: color,
                          dense: true,
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-range'),
                          label: firstPeriodLabel,
                          period: progress.day,
                          color: color,
                        ),
                        const SizedBox(width: 16),
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-week'),
                          label: 'Tuần',
                          period: progress.week,
                          color: color,
                        ),
                        const SizedBox(width: 16),
                        _OverviewPeriod(
                          key: Key('home-analytics-$keyPrefix-month'),
                          label: 'Tháng',
                          period: progress.month,
                          color: color,
                        ),
                      ],
                    ),
                ],
                if (missingStoreCodes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Thiếu chỉ tiêu: ${missingStoreCodes.join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.errorOf(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverviewEmptySelection extends StatelessWidget {
  const _OverviewEmptySelection();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              PhosphorIconsRegular.userCircle,
              size: 24,
              color: AppColors.textMutedOf(context),
            ),
            Positioned(
              right: -7,
              bottom: -5,
              child: Icon(
                PhosphorIconsRegular.magnifyingGlass,
                size: 16,
                color: AppColors.textMutedOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Chọn SA để hiển thị chỉ số',
          maxLines: 1,
          softWrap: false,
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textMutedOf(context),
            height: 18 / 13,
          ),
        ),
      ],
    );
  }
}

class _OverviewProgressBar extends StatelessWidget {
  const _OverviewProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.trackColor,
  });

  final double value;
  final Color color;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Container(
              height: 12,
              decoration: BoxDecoration(
                color: trackColor ?? color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            Container(
              key: const Key('home-overview-progress-bar-value'),
              height: 12,
              width: constraints.maxWidth * (value / 100),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OverviewLegendRow extends StatelessWidget {
  const _OverviewLegendRow({
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
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(color: color),
        ),
      ],
    );
  }
}

class _OverviewPeriod extends StatelessWidget {
  const _OverviewPeriod({
    super.key,
    required this.label,
    required this.period,
    required this.color,
    this.dense = false,
  });

  final String label;
  final HomeSalesProgressPeriod period;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final percentage = (period.percentage ?? 0).clamp(0, 100).toDouble();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelS),
        SizedBox(height: dense ? 0 : 8),
        Text(
          formatCompactVndAmount(period.actual),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        SizedBox(height: dense ? 0 : 8),
        _OverviewProgressBar(value: percentage, color: color),
        SizedBox(height: dense ? 0 : 8),
        Text(
          period.target == null
              ? 'Chỉ tiêu: Chưa thiết lập'
              : 'Mục tiêu ${formatCompactVndAmount(period.target!)}',
          maxLines: dense ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMutedOf(context),
          ),
        ),
      ],
    );
    return dense ? content : Expanded(child: content);
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
                        color: AppColors.errorOf(context),
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
    this.compactTitle,
    required this.subtitle,
    required this.color,
    required this.progress,
    this.assignees = const [],
    this.selectedAssigneeId,
    this.onAssigneeChanged,
  });
  final Key cardKey;
  final String title, subtitle;
  final String? compactTitle;
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
            title: compactTitle ?? title,
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
        border: Border.all(color: AppColors.borderOf(context)),
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
            color: AppColors.errorOf(context),
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
          border: Border.all(color: AppColors.borderOf(context)),
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
                    color: AppColors.primaryOf(context),
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
            color: AppColors.borderOf(context),
            borderRadius: BorderRadius.circular(7),
          ),
        ),
        Container(
          height: 14,
          width: constraints.maxWidth * (value.clamp(0, 100) / 100),
          decoration: BoxDecoration(
            color: AppColors.successOf(context),
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
        border: Border.all(color: AppColors.borderOf(context)),
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
            color: AppColors.primarySurfaceOf(context),
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
          trackColor: AppColors.borderOf(context),
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
      width: double.infinity,
      child: AppCombobox<String>.single(
        label: '',
        value: selectedAssigneeId,
        icon: PhosphorIconsRegular.userCircle,
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
