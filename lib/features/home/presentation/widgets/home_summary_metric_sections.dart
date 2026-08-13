part of 'home_summary_page.dart';

class SummaryCardGrid extends StatelessWidget {
  const SummaryCardGrid({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      SummaryCard(
        metricKey: 'revenue',
        icon: PhosphorIconsRegular.currencyCircleDollar,
        title: 'Giá trị bán (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.totalRevenue),
        trend: const SummaryTrend.neutral('Theo đơn hàng ERP'),
        helperText: 'Theo đơn cache',
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'totalOrders',
        icon: PhosphorIconsRegular.receipt,
        title: 'Đơn bán',
        value: _integerLabel(summary.totalOrders),
        trend: const SummaryTrend.neutral('Theo phạm vi'),
        helperText: 'Tổng đơn trong ngày',
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'averageOrderValue',
        icon: PhosphorIconsRegular.arrowsLeftRight,
        title: 'Trung bình đơn hàng (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.averageOrderValue),
        trend: const SummaryTrend.neutral('Giá trị/đơn'),
        helperText: 'Giá trị trung bình/đơn',
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'completedRevenue',
        icon: PhosphorIconsRegular.checkCircle,
        title: 'Hoàn thành (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.completedRevenue),
        trend: const SummaryTrend.success('Đã hoàn tất'),
        helperText: 'Doanh thu đã hoàn thành',
        color: AppColors.secondaryOf(context),
      ),
      SummaryCard(
        metricKey: 'pendingRevenue',
        icon: PhosphorIconsRegular.clockCounterClockwise,
        title: 'Chờ hoàn thành (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.pendingRevenue),
        trend: summary.pendingRevenue > 0
            ? const SummaryTrend.warning('chưa hoàn thành')
            : const SummaryTrend.success('đã đủ'),
        helperText: 'Doanh thu cần xử lý',
        color: AppColors.warningOf(context),
      ),
      SummaryCard(
        metricKey: 'conversionRate',
        icon: PhosphorIconsRegular.sortAscending,
        title: 'Tỉ lệ chuyển đổi',
        value: _percentLabel(summary.conversionRate),
        trend: SummaryTrend.conversion(summary.conversionRate),
        helperText: 'Từ nhu cầu sang đơn',
        color: AppColors.secondaryOf(context),
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-summary-grid'),
      cards: cards,
      wideColumns: 6,
      rowHeights: const [182],
      expandedRowHeights: const [146],
      mediumRowHeights: const [136],
      compactRowHeights: const [184],
      showComparisons: true,
      useRootViewportBreakpoints: true,
      comparisons: summary.comparisons,
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
        icon: PhosphorIconsRegular.buildings,
        title: 'Khách doanh nghiệp (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.businessCustomerRevenue),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'personalCustomerRevenue',
        icon: PhosphorIconsRegular.userCircle,
        title: 'Khách cá nhân (đã bao gồm VAT)',
        value: formatCompactVndAmount(summary.personalCustomerRevenue),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'examScorePromotionCount',
        icon: PhosphorIconsRegular.gift,
        title: 'CTKM đổi điểm thi',
        value: _integerLabel(summary.examScorePromotionCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.secondaryOf(context),
      ),
      SummaryCard(
        metricKey: 'studentPromotionCount',
        icon: PhosphorIconsRegular.graduationCap,
        title: 'CTKM HSSV',
        value: _integerLabel(summary.studentPromotionCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'installmentNeedCount',
        icon: PhosphorIconsRegular.handCoins,
        title: 'Nhu cầu trả góp',
        value: _integerLabel(summary.installmentNeedCount),
        trend: const SummaryTrend.neutral('Theo báo cáo'),
        color: AppColors.warningOf(context),
        textTapTooltip: 'Xem chi tiết nhu cầu trả góp',
        onTextTap: () => _openInstallmentNeedDetailsDialog(context, provider),
      ),
      SummaryCard(
        metricKey: 'successfulInstallmentCount',
        icon: PhosphorIconsRegular.checkCircle,
        title: 'Trả góp thành công',
        value: _integerLabel(summary.successfulInstallmentCount),
        trend: const SummaryTrend.success('Có đơn trả góp'),
        color: AppColors.successOf(context),
      ),
    ];
    final secondRow = [
      SummaryCard(
        metricKey: 'extendedInsuranceQuantity',
        icon: PhosphorIconsRegular.shieldCheck,
        title: 'Bảo hiểm mở rộng',
        value: _integerLabel(summary.extendedInsuranceQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.secondaryOf(context),
      ),
      SummaryCard(
        metricKey: 'laptopQuantity',
        icon: PhosphorIconsRegular.laptop,
        title: 'Laptop',
        value: _integerLabel(summary.laptopQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'pcQuantity',
        icon: PhosphorIconsRegular.desktopTower,
        title: 'PC bộ',
        value: _integerLabel(summary.pcQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.infoOf(context),
      ),
      SummaryCard(
        metricKey: 'assembledPcQuantity',
        icon: PhosphorIconsRegular.cpu,
        title: 'PC ráp',
        value: _integerLabel(summary.assembledPcQuantity),
        trend: const SummaryTrend.neutral('Theo bộ ráp'),
        color: AppColors.warningOf(context),
      ),
      SummaryCard(
        metricKey: 'appleQuantity',
        icon: PhosphorIconsRegular.appleLogo,
        title: 'Apple',
        value: _integerLabel(summary.appleQuantity),
        trend: const SummaryTrend.neutral('iPhone/MacBook/iPad'),
        color: AppColors.successOf(context),
      ),
      SummaryCard(
        metricKey: 'monitorQuantity',
        icon: PhosphorIconsRegular.monitor,
        title: 'Màn hình',
        value: _integerLabel(summary.monitorQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.primaryOf(context),
      ),
      SummaryCard(
        metricKey: 'printerQuantity',
        icon: PhosphorIconsRegular.printer,
        title: 'Máy in',
        value: _integerLabel(summary.printerQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.secondaryOf(context),
      ),
      SummaryCard(
        metricKey: 'accessoriesQuantity',
        icon: PhosphorIconsRegular.package,
        title: 'Phụ kiện',
        value: _integerLabel(summary.accessoriesQuantity),
        trend: const SummaryTrend.neutral('Theo lượng'),
        color: AppColors.infoOf(context),
      ),
    ];

    return _SummaryMetricGrid(
      gridKey: const Key('home-main-kpi-summary-grid'),
      cards: [...firstRow, ...secondRow],
      wideColumns: 5,
      rowHeights: const [164, 136, 136],
      expandedRowHeights: const [146],
      mediumRowHeights: const [136],
      compactRowHeights: const [184],
      showComparisons: true,
      useRootViewportBreakpoints: true,
      comparisons: summary.comparisons,
    );
  }
}
