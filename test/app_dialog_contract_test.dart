import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_dialogs.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';
import 'package:phongvu_opshub/app/widgets/app_layout.dart';

void main() {
  testWidgets('global selection scope owns text on every surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppGlobalSelectionScope(
          child: Scaffold(body: Text('Nội dung có thể sao chép')),
        ),
      ),
    );

    final context = tester.element(find.text('Nội dung có thể sao chép'));
    expect(SelectionContainer.maybeOf(context), isNotNull);
  });

  testWidgets('dirty dialog confirms before outside dismissal', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AppDirtyFormGuard(
                  source: 'DialogContractTest',
                  child: AlertDialog(
                    title: const Text('Biểu mẫu'),
                    content: AppTextInput(controller: controller, label: 'Tên'),
                  ),
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Đang sửa');
    await tester.pump();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Hủy các thay đổi?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục chỉnh sửa'));
    await tester.pumpAndSettle();
    expect(find.text('Biểu mẫu'), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thoát và hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Biểu mẫu'), findsNothing);
  });

  testWidgets('clean dialog closes immediately when clicking outside', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AppDirtyFormGuard(
                  source: 'DialogContractTest',
                  child: AlertDialog(title: Text('Thông tin')),
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('Thông tin'), findsNothing);
  });

  testWidgets('successful save closes a dirty dialog without discard prompt', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => AppDirtyFormGuard(
                  source: 'DialogContractTest',
                  child: AlertDialog(
                    title: const Text('Biểu mẫu lưu'),
                    content: AppTextInput(
                      controller: controller,
                      label: 'Tên',
                    ),
                    actions: [
                      Builder(
                        builder: (dialogContext) => FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Lưu'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Đã sửa');
    await tester.pump();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Biểu mẫu lưu'), findsNothing);
    expect(find.text('Hủy các thay đổi?'), findsNothing);
  });
}
