import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';

void main() {
  testWidgets(
    'GradientHeader applies readable tab colors on gradient app bar',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: GradientHeader(
                title: 'Feature admin',
                bottom: TabBar(
                  tabs: [
                    Tab(text: 'Features'),
                    Tab(text: 'Rules'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [SizedBox.shrink(), SizedBox.shrink()],
              ),
            ),
          ),
        ),
      );

      final context = tester.element(find.byType(TabBar));
      final tabTheme = Theme.of(context).tabBarTheme;

      expect(tabTheme.labelColor, AppColors.surface);
      expect(tabTheme.unselectedLabelColor, AppColors.neutral100);
      expect(tabTheme.indicatorColor, AppColors.surface);
      expect(tabTheme.dividerColor, Colors.transparent);
    },
  );
}
