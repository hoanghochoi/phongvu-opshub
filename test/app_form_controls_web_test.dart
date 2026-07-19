import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_combobox.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';
import 'package:phongvu_opshub/core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop web AppTextInput shows only Flutter paste toolbar', (
    tester,
  ) async {
    final contextMenuCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.contextMenu, (call) async {
          contextMenuCalls.add(call.method);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.contextMenu, null);
    });
    addTearDown(BrowserContextMenu.enableContextMenu);

    await initializeTextInputContextMenu(
      targetPlatformOverride: TargetPlatform.windows,
    );

    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: AppTextInput(controller: controller, label: 'Mã đơn hàng'),
          ),
        ),
      ),
    );

    final editableTextState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    editableTextState.renderEditable.selectWordsInRange(
      from: Offset.zero,
      cause: SelectionChangedCause.tap,
    );
    await tester.pump();

    expect(contextMenuCalls, contains('disableContextMenu'));
    expect(editableTextState.showToolbar(), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paste'), findsOneWidget);
  }, skip: !kIsWeb);

  testWidgets(
    'mobile web AppTextInput delegates Paste directly to the browser',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final contextMenuCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.contextMenu, (call) async {
              contextMenuCalls.add(call.method);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.contextMenu, null);
        });

        await initializeTextInputContextMenu(
          targetPlatformOverride: TargetPlatform.iOS,
        );

        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: AppTextInput(controller: controller, label: 'Email'),
              ),
            ),
          ),
        );

        final editableTextState = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        editableTextState.renderEditable.selectWordsInRange(
          from: Offset.zero,
          cause: SelectionChangedCause.longPress,
        );
        final flutterToolbarShown = editableTextState.showToolbar();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(contextMenuCalls, contains('enableContextMenu'));
        expect(contextMenuCalls, isNot(contains('disableContextMenu')));
        expect(BrowserContextMenu.enabled, isTrue);
        expect(flutterToolbarShown, isFalse);
        expect(find.text('Paste'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: !kIsWeb,
  );

  testWidgets(
    'mobile web AppCombobox delegates Paste directly to the browser',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final contextMenuCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.contextMenu, (call) async {
              contextMenuCalls.add(call.method);
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.contextMenu, null);
        });

        await initializeTextInputContextMenu(
          targetPlatformOverride: TargetPlatform.iOS,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: AppCombobox<String>.single(
                  label: 'Showroom',
                  value: null,
                  options: const [
                    AppComboboxOption(value: 'CP01', label: 'Showroom CP01'),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        final editableTextState = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        expect(
          SelectionContainer.maybeOf(tester.element(find.byType(EditableText))),
          isNull,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).contextMenuBuilder,
          isNotNull,
        );

        editableTextState.renderEditable.selectWordsInRange(
          from: Offset.zero,
          cause: SelectionChangedCause.longPress,
        );
        final flutterToolbarShown = editableTextState.showToolbar();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(contextMenuCalls, contains('enableContextMenu'));
        expect(contextMenuCalls, isNot(contains('disableContextMenu')));
        expect(BrowserContextMenu.enabled, isTrue);
        expect(flutterToolbarShown, isFalse);
        expect(find.text('Paste'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    skip: !kIsWeb,
  );
}
