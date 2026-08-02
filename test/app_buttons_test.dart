import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';

void main() {
  testWidgets('shared buttons expose the Figma foundation size lanes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppPrimaryButton(
                key: const Key('small'),
                onPressed: () {},
                label: 'Nhỏ',
                size: AppButtonSize.small,
              ),
              AppPrimaryButton(
                key: const Key('medium'),
                onPressed: () {},
                label: 'Vừa',
                size: AppButtonSize.medium,
              ),
              AppPrimaryButton(
                key: const Key('large'),
                onPressed: () {},
                label: 'Lớn',
                size: AppButtonSize.large,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('small'))).height, 40);
    expect(tester.getSize(find.byKey(const Key('medium'))).height, 48);
    expect(tester.getSize(find.byKey(const Key('large'))).height, 52);

    final smallButton = tester.widget<FilledButton>(
      find.byType(FilledButton).first,
    );
    expect(
      smallButton.style?.side?.resolve(<WidgetState>{WidgetState.focused}),
      const BorderSide(color: AppColors.focus, width: 2),
    );
  });

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
