import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
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
          selectedDate: provider.selectedDate,
          isRefreshing: provider.isRefreshing || provider.isInitialLoading,
          onPickDate: () => _pickDate(context),
          onRefresh: provider.canRefresh
              ? () => unawaited(provider.refreshNow())
              : null,
        ),
        const SizedBox(height: AppLayoutTokens.cardGap),
        if (provider.errorMessage != null && summary != null) ...[
          AppStatusBanner(
            icon: Icons.sync_problem_rounded,
            title: 'Đang hiển thị dữ liệu gần nhất',
            message: provider.errorMessage!,
            tone: AppStateTone.warning,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
        ],
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

    return AppSurfaceCard(
      key: const Key('home-summary-header'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final leading = DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(
                Icons.space_dashboard_outlined,
                color: AppColors.primary,
              ),
            ),
          );
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dashboard theo phạm vi', style: AppTextStyles.headingM),
              const SizedBox(height: 6),
              Text(
                summary?.resolvedScopeDetail ??
                    'Theo dõi doanh số, đơn hàng và tiến độ báo cáo trong ngày theo đúng quyền hiện tại.',
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusChip(label: scopeLabel, color: scopeColor),
                  AppInfoChip(
                    Icons.calendar_today_outlined,
                    _dateLabel(selectedDate),
                    color: AppColors.neutral700,
                  ),
                  AppInfoChip(
                    Icons.analytics_outlined,
                    summary?.resolvedCoverageLabel ?? 'Tỷ lệ phủ báo cáo',
                    color: AppColors.neutral700,
                  ),
                  if (summary?.refreshedAt != null)
                    AppInfoChip(
                      Icons.schedule_outlined,
                      'Cập nhật ${_timeLabel(summary!.refreshedAt!)}',
                      color: AppColors.neutral700,
                    ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [leading, const SizedBox(height: 12), content],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(child: content),
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
    required this.selectedDate,
    required this.isRefreshing,
    required this.onPickDate,
    required this.onRefresh,
  });

  final DateTime selectedDate;
  final bool isRefreshing;
  final VoidCallback onPickDate;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('home-summary-toolbar'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final buttons = [
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
              Text(
                'Công cụ dữ liệu',
                style: AppTextStyles.labelL.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chọn ngày để đổi phạm vi xem, hoặc làm mới khi cần đối soát số liệu mới nhất.',
                style: AppTextStyles.bodyS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              compact
                  ? AppActionRow(
                      desktopAlignment: MainAxisAlignment.start,
                      children: buttons,
                    )
                  : Wrap(spacing: 12, runSpacing: 12, children: buttons),
            ],
          );
        },
      ),
    );
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
    final label = compact
        ? _dateLabel(selectedDate)
        : 'Ngày ${_dateLabel(selectedDate)}';

    return AppSecondaryButton(
      key: const Key('home-summary-date-picker'),
      onPressed: onPressed,
      icon: Icons.calendar_month_rounded,
      label: label,
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
        hint: 'Tổng doanh số của các đơn đã có báo cáo hợp lệ.',
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'totalOrders',
        icon: Icons.shopping_bag_outlined,
        title: 'Tổng số đơn hợp lệ',
        value: _integerLabel(summary.totalOrders),
        hint: 'Tổng số đơn đang nằm trong phạm vi theo dõi hôm nay.',
        color: AppColors.primary,
      ),
      SummaryCard(
        metricKey: 'conversionRate',
        icon: Icons.percent_rounded,
        title: summary.resolvedCoverageLabel,
        value: _percentLabel(summary.coverageRate),
        hint: 'Tỷ lệ đơn đã có báo cáo hợp lệ trên tổng số đơn.',
        color: AppColors.info,
      ),
      SummaryCard(
        metricKey: 'totalReports',
        icon: Icons.description_outlined,
        title: 'Tổng số báo cáo hợp lệ',
        value: _integerLabel(summary.totalReports),
        hint: 'Số báo cáo hợp lệ đang đóng góp vào dashboard hiện tại.',
        color: AppColors.secondary,
      ),
      SummaryCard(
        metricKey: 'reportedOrders',
        icon: Icons.task_alt_rounded,
        title: 'Số đơn đã báo cáo',
        value: _integerLabel(summary.reportedOrders),
        hint: 'Đơn đã được ghi nhận báo cáo hợp lệ trong ngày đang xem.',
        color: AppColors.success,
      ),
      SummaryCard(
        metricKey: 'unreportedOrders',
        icon: Icons.assignment_late_outlined,
        title: 'Số đơn chưa báo cáo',
        value: _integerLabel(summary.unreportedOrders),
        hint: 'Đơn còn thiếu báo cáo để đội xử lý tiếp trong tab Vận hành.',
        color: AppColors.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1024
            ? 3
            : width >= 680
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
    required this.hint,
    required this.color,
  });

  final String metricKey;
  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: Key('home-summary-card-$metricKey'),
      borderColor: color.withValues(alpha: 0.20),
      backgroundColor: color.withValues(alpha: 0.04),
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
                  padding: const EdgeInsets.all(10),
                  child: Icon(icon, color: color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
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
          Text(
            hint,
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportProgressPanel extends StatelessWidget {
  const ReportProgressPanel({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final ratio = summary.totalOrders <= 0
        ? 0.0
        : summary.reportedOrders / summary.totalOrders;
    final progressValue = ratio.clamp(0.0, 1.0);
    final remainingText = summary.unreportedOrders > 0
        ? 'Còn ${_integerLabel(summary.unreportedOrders)} đơn cần bổ sung báo cáo.'
        : 'Toàn bộ đơn trong phạm vi hôm nay đã có báo cáo hợp lệ.';

    return AppSurfaceCard(
      key: const Key('home-summary-progress-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tiến độ báo cáo', style: AppTextStyles.headingS),
          const SizedBox(height: 6),
          Text(
            'Theo dõi mức phủ báo cáo trong ngày để đội vận hành biết còn bao nhiêu đơn cần xử lý tiếp.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${_integerLabel(summary.reportedOrders)}/${_integerLabel(summary.totalOrders)} đơn',
                  style: AppTextStyles.headingM.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppStatusChip(
                label: _percentLabel(summary.coverageRate),
                color: AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 12,
              backgroundColor: AppColors.neutral100,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.info),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppStatusChip(
                label: '${_integerLabel(summary.reportedOrders)} đã báo cáo',
                color: AppColors.success,
              ),
              AppStatusChip(
                label:
                    '${_integerLabel(summary.unreportedOrders)} chưa báo cáo',
                color: AppColors.warning,
              ),
              AppStatusChip(
                label: '${_integerLabel(summary.totalReports)} báo cáo hợp lệ',
                color: AppColors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            remainingText,
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeOperationsShortcutCard extends StatelessWidget {
  const HomeOperationsShortcutCard({super.key, required this.onOpenOperations});

  final VoidCallback onOpenOperations;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('home-operations-shortcut'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cần thao tác tiếp?', style: AppTextStyles.headingS),
          const SizedBox(height: 6),
          Text(
            'Mở tab Vận hành để xử lý các nghiệp vụ theo quyền mà không rời khỏi dashboard tổng quan.',
            style: AppTextStyles.bodyM.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 220,
            child: AppSecondaryButton(
              onPressed: onOpenOperations,
              icon: Icons.apps_rounded,
              label: 'Mở Vận hành',
            ),
          ),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

String _timeLabel(DateTime value) =>
    DateFormat('HH:mm dd/MM').format(value.toLocal());

String _integerLabel(int value) => vietnameseMoneyNumberFormat.format(value);

String _percentLabel(double value) {
  final rounded = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
  return '$rounded%';
}
