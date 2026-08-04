import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/widgets/app_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppLogo keeps the approved size lanes and inside stroke', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            AppLogo(key: Key('logo-small'), size: 32),
            AppLogo(key: Key('logo-medium'), size: 44),
            AppLogo(key: Key('logo-large'), size: 56),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('logo-small'))),
      const Size(32, 32),
    );
    expect(
      tester.getSize(find.byKey(const Key('logo-medium'))),
      const Size(44, 44),
    );
    expect(
      tester.getSize(find.byKey(const Key('logo-large'))),
      const Size(56, 56),
    );
  });

  testWidgets('AppLogo accepts the navigation surface stroke explicitly', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLogo(size: 56, strokeColor: AppColors.sidebarText),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.color, AppColors.sidebarText);
    expect(border.top.width, 1);
    expect(border.top.style, BorderStyle.solid);
    expect(border.left.color, AppColors.sidebarText);
  });
}
