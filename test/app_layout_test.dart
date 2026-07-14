import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  testWidgets('AppTwoAxisScrollView exposes draggable desktop scrollbars', (
    tester,
  ) async {
    await _pumpAtSize(
      tester,
      const Size(500, 400),
      Theme(
        data: ThemeData(platform: TargetPlatform.windows),
        child: const Center(
          child: SizedBox(
            width: 240,
            height: 180,
            child: AppTwoAxisScrollView(
              child: SizedBox(width: 800, height: 800),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final horizontal = tester.widget<Scrollbar>(
      find.byKey(const Key('app-two-axis-horizontal-scrollbar')),
    );
    final vertical = tester.widget<Scrollbar>(
      find.byKey(const Key('app-two-axis-vertical-scrollbar')),
    );

    expect(horizontal.controller, isNotNull);
    expect(vertical.controller, isNotNull);
    expect(identical(horizontal.controller, vertical.controller), isFalse);
    expect(horizontal.interactive, isTrue);
    expect(vertical.interactive, isTrue);
    expect(horizontal.thumbVisibility, isTrue);
    expect(vertical.thumbVisibility, isTrue);

    final verticalRect = tester.getRect(
      find.byKey(const Key('app-two-axis-vertical-scrollbar')),
    );
    await tester.dragFrom(
      Offset(verticalRect.right - 3, verticalRect.top + 15),
      const Offset(0, 80),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(vertical.controller!.offset, greaterThan(0));

    final horizontalRect = tester.getRect(
      find.byKey(const Key('app-two-axis-horizontal-scrollbar')),
    );
    await tester.dragFrom(
      Offset(horizontalRect.left + 15, horizontalRect.bottom - 3),
      const Offset(80, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(horizontal.controller!.offset, greaterThan(0));
  });
}

Future<void> _pumpAtSize(WidgetTester tester, Size size, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}
