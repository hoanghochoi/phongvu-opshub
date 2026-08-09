import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/app_colors.dart';
import 'package:phongvu_opshub/app/theme/app_theme.dart';
import 'package:phongvu_opshub/app/widgets/app_buttons.dart';
import 'package:phongvu_opshub/app/widgets/app_command_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  testWidgets(
    'AppCommandBar exposes its label and routes scan, search, Enter, and clear',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var scanCount = 0;
      var primaryCount = 0;
      var submittedValue = '';
      var clearCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppCommandBar(
              controller: controller,
              label: 'SKU hoặc serial',
              hintText: 'SKU-12345',
              onSubmitted: (value) => submittedValue = value,
              onScan: () => scanCount++,
              onPrimaryAction: () => primaryCount++,
              scanTooltip: 'Quét mã',
              primaryActionTooltip: 'Tìm FIFO',
              scanKey: const Key('command-scan'),
              primaryActionKey: const Key('command-primary'),
              suffixIcon: IconButton(
                key: const Key('command-clear'),
                onPressed: () {
                  clearCount++;
                  controller.clear();
                },
                tooltip: 'Xóa nội dung',
                icon: const Icon(PhosphorIconsRegular.x),
              ),
            ),
          ),
        ),
      );

      final editableSemantics = tester.getSemantics(find.byType(EditableText));
      expect(editableSemantics.label, startsWith('SKU hoặc serial'));
      expect(editableSemantics.flagsCollection.isTextField, isTrue);

      await tester.enterText(find.byType(TextField), 'SN001');
      await tester.tap(find.byKey(const Key('command-scan')));
      await tester.tap(find.byKey(const Key('command-primary')));
      await tester.tap(find.byType(TextField));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(scanCount, 1);
      expect(primaryCount, 1);
      expect(submittedValue, 'SN001');

      await tester.tap(find.byKey(const Key('command-clear')));
      await tester.pump();

      expect(clearCount, 1);
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('AppCommandBar distinguishes disabled and loading states', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'SN001');
    addTearDown(controller.dispose);
    var actionCount = 0;

    Future<void> pumpState({required bool enabled, required bool isLoading}) {
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppCommandBar(
              controller: controller,
              label: 'Biên nhận',
              hintText: 'Biên nhận',
              enabled: enabled,
              isLoading: isLoading,
              onSubmitted: (_) => actionCount++,
              onScan: () => actionCount++,
              onPrimaryAction: () => actionCount++,
              scanTooltip: 'Quét mã',
              primaryActionTooltip: 'Tìm',
              scanKey: const Key('state-command-scan'),
              primaryActionKey: const Key('state-command-primary'),
            ),
          ),
        ),
      );
    }

    await pumpState(enabled: false, isLoading: false);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.byIcon(PhosphorIconsRegular.magnifyingGlass), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.spinnerGap), findsNothing);
    expect(
      tester
          .widget<AppIconAction>(find.byKey(const Key('state-command-primary')))
          .onPressed,
      isNull,
    );

    await pumpState(enabled: true, isLoading: true);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.byIcon(PhosphorIconsRegular.magnifyingGlass), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.spinnerGap), findsOneWidget);
    expect(find.byTooltip('Đang tìm kiếm'), findsOneWidget);
    expect(
      tester
          .widget<AppIconAction>(find.byKey(const Key('state-command-scan')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AppIconAction>(find.byKey(const Key('state-command-primary')))
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const Key('state-command-scan')),
      warnIfMissed: false,
    );
    await tester.tap(
      find.byKey(const Key('state-command-primary')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(actionCount, 0);
    expect(controller.text, 'SN001');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppCommandBar uses exact command colors in production themes', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(
            body: AppCommandBar(
              controller: controller,
              label: 'SKU hoặc serial',
              hintText: 'SKU-12345',
              onScan: () {},
              onPrimaryAction: () {},
              scanTooltip: 'Quét mã',
              primaryActionTooltip: 'Tìm FIFO',
              scanKey: const Key('color-command-scan'),
              primaryActionKey: const Key('color-command-primary'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dark = themeMode == ThemeMode.dark;
      final card = tester.widget<Card>(
        find.descendant(
          of: find.byType(AppCommandBar),
          matching: find.byType(Card),
        ),
      );
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.side.color, dark ? AppColors.darkBorder : AppColors.divider);

      final input = tester.widget<TextField>(find.byType(TextField));
      final enabledBorder =
          input.decoration!.enabledBorder! as OutlineInputBorder;
      final disabledBorder =
          input.decoration!.disabledBorder! as OutlineInputBorder;
      final expectedInputBorder = dark
          ? AppColors.darkCommandInputBorder
          : AppColors.commandInputBorder;
      expect(enabledBorder.borderSide.color, expectedInputBorder);
      expect(disabledBorder.borderSide.color, expectedInputBorder);

      final qr = tester.widget<AppIconAction>(
        find.byKey(const Key('color-command-scan')),
      );
      expect(
        qr.backgroundColor,
        dark ? AppColors.darkCommandQrSurface : AppColors.commandQrSurface,
      );
      expect(
        qr.foregroundColor,
        dark
            ? AppColors.darkCommandQrForeground
            : AppColors.commandQrForeground,
      );

      final searchButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('color-command-primary')),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        searchButton.style!.backgroundColor!.resolve(<WidgetState>{}),
        dark ? AppColors.darkPrimary : AppColors.primary,
      );
      expect(
        searchButton.style!.foregroundColor!.resolve(<WidgetState>{}),
        dark ? AppColors.primary900 : AppColors.surface,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(
            body: AppCommandBar(
              controller: controller,
              label: 'SKU hoặc serial',
              hintText: 'SKU-12345',
              isLoading: true,
              onScan: () {},
              onPrimaryAction: () {},
              scanTooltip: 'Quét mã',
              primaryActionTooltip: 'Tìm FIFO',
              primaryActionKey: const Key('loading-color-command-primary'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final loadingSearchButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const Key('loading-color-command-primary')),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        loadingSearchButton.style!.backgroundColor!.resolve({
          WidgetState.disabled,
        }),
        dark ? AppColors.darkPrimary : AppColors.primary,
      );
      expect(
        loadingSearchButton.style!.foregroundColor!.resolve({
          WidgetState.disabled,
        }),
        dark ? AppColors.primary900 : AppColors.surface,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('AppCommandBar supports keyboard focus and tab traversal', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(
            body: AppCommandBar(
              controller: controller,
              focusNode: focusNode,
              label: 'SKU hoặc serial',
              hintText: 'SKU-12345',
              onScan: () {},
              onPrimaryAction: () {},
              scanTooltip: 'Quét mã',
              primaryActionTooltip: 'Tìm FIFO',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      final focusedBorder =
          Theme.of(
                tester.element(find.byType(TextField)),
              ).inputDecorationTheme.focusedBorder!
              as OutlineInputBorder;
      expect(
        focusedBorder.borderSide.color,
        themeMode == ThemeMode.dark ? AppColors.darkPrimary : AppColors.focus,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('AppCommandBar keeps geometry and avoids scaled-text overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in const [343.0, 720.0, 872.0, 1126.0]) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 108,
                  child: AppCommandBar(
                    controller: controller,
                    label: 'SKU hoặc serial cần kiểm tra',
                    hintText: 'SKU-12345',
                    onScan: () {},
                    onPrimaryAction: () {},
                    scanTooltip: 'Quét mã',
                    primaryActionTooltip: 'Tìm FIFO',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.getSize(find.byType(AppCommandBar)), Size(width, 108));
        expect(tester.getSize(find.byType(TextField)).height, 48);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
