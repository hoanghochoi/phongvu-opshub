part of 'home_summary_page.dart';

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
