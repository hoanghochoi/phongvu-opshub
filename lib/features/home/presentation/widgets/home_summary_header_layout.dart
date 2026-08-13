/// Pure geometry contract for the Home summary header controls.
///
/// Keeping the width calculation separate from the widget makes the responsive
/// contract directly testable while preserving the existing header surface.
class HomeSummaryHeaderLayout {
  const HomeSummaryHeaderLayout({
    required this.scopeWidth,
    required this.dateWidth,
    required this.updateWidth,
    required this.hasAction,
  });

  static const gap = 12.0;
  static const actionWidth = 152.0;

  final double scopeWidth;
  final double dateWidth;
  final double updateWidth;
  final bool hasAction;

  static HomeSummaryHeaderLayout desktop({
    required double availableWidth,
    required bool hasAction,
  }) {
    const wideTargetWidths = [324.0, 296.0, 280.0];
    const regularTargetWidths = [220.0, 220.0, 180.0];
    final reservedWidth = hasAction ? actionWidth + gap : 0.0;
    final wideTargetTotal = wideTargetWidths.reduce((a, b) => a + b);
    final canUseWideTargets =
        availableWidth >= wideTargetTotal + gap * 2 + reservedWidth;
    final targetWidths = canUseWideTargets
        ? wideTargetWidths
        : regularTargetWidths;
    final controlsWidth = (availableWidth - reservedWidth - gap * 2)
        .clamp(0.0, double.infinity)
        .toDouble();
    final targetTotal = targetWidths.reduce((a, b) => a + b);
    final scale = (controlsWidth / targetTotal).clamp(0.0, 1.0).toDouble();

    return HomeSummaryHeaderLayout(
      scopeWidth: targetWidths[0] * scale,
      dateWidth: targetWidths[1] * scale,
      updateWidth: targetWidths[2] * scale,
      hasAction: hasAction,
    );
  }
}
