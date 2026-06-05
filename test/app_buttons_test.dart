import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';

void main() {
  testWidgets('AppActionRow caps paired action width on desktop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: AppActionRow(
              children: [
                SizedBox(key: Key('secondary'), height: 52),
                SizedBox(key: Key('primary'), height: 52),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('secondary'))).width, 220);
    expect(tester.getSize(find.byKey(const Key('primary'))).width, 220);
    expect(tester.getSize(find.byKey(const Key('secondary'))).height, 52);
    expect(tester.getSize(find.byKey(const Key('primary'))).height, 52);
  });

  testWidgets('AppActionRow stacks full-width actions on compact screens', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AppActionRow(
              children: [
                SizedBox(key: Key('secondary'), height: 52),
                SizedBox(key: Key('primary'), height: 52),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('secondary'))).width, 360);
    expect(tester.getSize(find.byKey(const Key('primary'))).width, 360);
    expect(tester.getSize(find.byKey(const Key('secondary'))).height, 52);
    expect(tester.getSize(find.byKey(const Key('primary'))).height, 52);
  });
}
