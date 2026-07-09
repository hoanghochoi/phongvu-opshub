import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';
import 'package:phongvu_opshub/core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'web AppTextInput shows Flutter paste toolbar inside SelectionArea',
    (tester) async {
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

      await initializeTextInputContextMenu();

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
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
    },
    skip: !kIsWeb,
  );
}
