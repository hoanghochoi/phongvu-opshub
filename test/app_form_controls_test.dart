import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_cards.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';
import 'package:phongvu_opshub/app/widgets/app_state_widgets.dart';

void main() {
  testWidgets('AppTextInput renders tokenized label, icon, and input text', (
    tester,
  ) async {
    final controller = TextEditingController(text: '26062512345678');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppTextInput(
            controller: controller,
            label: 'Mã đơn hàng',
            icon: Icons.tag_rounded,
          ),
        ),
      ),
    );

    expect(find.text('Mã đơn hàng'), findsOneWidget);
    expect(find.byIcon(Icons.tag_rounded), findsOneWidget);
    expect(find.text('26062512345678'), findsOneWidget);
  });

  testWidgets('AppFormTextInput keeps form validation on shared input', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AppFormTextInput(
              controller: controller,
              label: 'Số điện thoại',
              icon: Icons.phone_outlined,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Vui lòng nhập SĐT' : null,
            ),
          ),
        ),
      ),
    );

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Vui lòng nhập SĐT'), findsOneWidget);
  });

  testWidgets('AppSelectField changes selected value from shared dropdown', (
    tester,
  ) async {
    String value = 'ALL';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: AppSelectField<String>(
                label: 'Trạng thái',
                icon: Icons.flag_outlined,
                value: value,
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('Tất cả')),
                  DropdownMenuItem(value: 'PENDING', child: Text('Chờ xử lý')),
                ],
                onChanged: (next) => setState(() => value = next ?? 'ALL'),
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.text('Tất cả'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chờ xử lý').last);
    await tester.pumpAndSettle();

    expect(value, 'PENDING');
  });

  testWidgets('AppReadOnlyField shows a disabled tokenized value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppReadOnlyField(
            value: 'Nhân viên',
            label: 'Quyền hệ thống',
            icon: Icons.lock_outline,
          ),
        ),
      ),
    );

    expect(find.text('Quyền hệ thống'), findsOneWidget);
    expect(find.text('Nhân viên'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
  });

  testWidgets('AppSurfaceCard uses one shared tappable card surface', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSurfaceCard(
            onTap: () => tapped = true,
            child: const Text('Nội dung thẻ'),
          ),
        ),
      ),
    );

    expect(find.byType(Card), findsOneWidget);
    await tester.tap(find.text('Nội dung thẻ'));
    expect(tapped, isTrue);
  });

  testWidgets('AppListSkeleton animates shimmer gradient', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppListSkeleton(itemCount: 1, scrollable: false)),
      ),
    );

    final firstGradient = _firstSkeletonGradient(tester);
    await tester.pump(const Duration(milliseconds: 500));
    final nextGradient = _firstSkeletonGradient(tester);

    expect(nextGradient.begin, isNot(firstGradient.begin));
    expect(nextGradient.end, isNot(firstGradient.end));
  });
}

LinearGradient _firstSkeletonGradient(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.gradient is LinearGradient) {
      return decoration.gradient! as LinearGradient;
    }
  }
  throw StateError('Không tìm thấy skeleton gradient');
}
