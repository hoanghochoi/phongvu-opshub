import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_layout.dart';

void main() {
  testWidgets('AppResponsiveContent bounds desktop content width', (
    tester,
  ) async {
    BoxConstraints? childConstraints;

    await _pumpAtSize(
      tester,
      const Size(1800, 900),
      AppResponsiveContent(
        child: LayoutBuilder(
          builder: (context, constraints) {
            childConstraints = constraints;
            return const SizedBox(height: 24);
          },
        ),
      ),
    );

    expect(childConstraints?.maxWidth, AppLayoutTokens.contentMaxWidth - 64);
  });

  testWidgets('AppResponsiveScrollView bounds desktop content width', (
    tester,
  ) async {
    BoxConstraints? childConstraints;

    await _pumpAtSize(
      tester,
      const Size(1800, 900),
      AppResponsiveScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            childConstraints = constraints;
            return const SizedBox(width: double.infinity, height: 24);
          },
        ),
      ),
    );

    expect(childConstraints?.maxWidth, AppLayoutTokens.contentMaxWidth);
  });
}

Future<void> _pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}
