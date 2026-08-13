import 'package:flutter_test/flutter_test.dart';

import 'package:phongvu_opshub/features/home/presentation/widgets/home_summary_header_layout.dart';

void main() {
  group('HomeSummaryHeaderLayout', () {
    test('preserves the wide desktop geometry contract without an action', () {
      final layout = HomeSummaryHeaderLayout.desktop(
        availableWidth: 936,
        hasAction: false,
      );

      expect(layout.scopeWidth, 324);
      expect(layout.dateWidth, 296);
      expect(layout.updateWidth, 280);
      expect(layout.hasAction, isFalse);
    });

    test('preserves regular desktop geometry and action reservation', () {
      final layout = HomeSummaryHeaderLayout.desktop(
        availableWidth: 700,
        hasAction: true,
      );

      expect(layout.scopeWidth, closeTo(181.68, 0.01));
      expect(layout.dateWidth, closeTo(181.68, 0.01));
      expect(layout.updateWidth, closeTo(148.65, 0.01));
      expect(layout.hasAction, isTrue);
    });

    test('scales controls without producing negative widths', () {
      final layout = HomeSummaryHeaderLayout.desktop(
        availableWidth: 40,
        hasAction: true,
      );

      expect(layout.scopeWidth, 0);
      expect(layout.dateWidth, 0);
      expect(layout.updateWidth, 0);
    });

    test('wide threshold accounts for the optional action control', () {
      final withoutAction = HomeSummaryHeaderLayout.desktop(
        availableWidth: 936,
        hasAction: false,
      );
      final withAction = HomeSummaryHeaderLayout.desktop(
        availableWidth: 1100,
        hasAction: true,
      );

      expect(withoutAction.scopeWidth, 324);
      expect(withAction.scopeWidth, 324);
      expect(withAction.dateWidth, 296);
      expect(withAction.updateWidth, 280);
    });
  });
}
