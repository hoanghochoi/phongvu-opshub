import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_cards.dart';
import 'package:phongvu_opshub/app/widgets/app_combobox.dart';
import 'package:phongvu_opshub/app/widgets/app_inputs.dart';
import 'package:phongvu_opshub/app/widgets/app_pagination.dart';
import 'package:phongvu_opshub/app/widgets/app_state_widgets.dart';

void main() {
  test('every shared input mode provides a Flutter context menu builder', () {
    expect(appTextInputContextMenuBuilder(), isNotNull);
  });

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

  testWidgets(
    'Android AppTextInput is isolated from ancestor SelectionArea ownership',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
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

        final editableTextContext = tester.element(find.byType(EditableText));
        expect(
          SelectionContainer.maybeOf(editableTextContext),
          isNull,
          reason:
              'The outer SelectionArea must not compete with EditableText long-press selection.',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'iOS AppTextInput exposes a working Paste action under global SelectionArea',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        var clipboardText = 'CP01';
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              switch (call.method) {
                case 'Clipboard.getData':
                  return <String, Object?>{'text': clipboardText};
                case 'Clipboard.hasStrings':
                  return <String, bool>{'value': clipboardText.isNotEmpty};
                case 'Clipboard.setData':
                  clipboardText =
                      (call.arguments as Map<Object?, Object?>?)?['text']
                          as String? ??
                      '';
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: AppTextInput(
                  controller: controller,
                  label: 'Mã đơn hàng',
                ),
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
        await tester.pump();
        expect(editableTextState.showToolbar(), isTrue);
        await tester.pumpAndSettle();

        expect(find.text('Paste'), findsOneWidget);
        await tester.tap(find.text('Paste'));
        await tester.pump();
        expect(controller.text, 'CP01');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('AppCombobox is isolated from ancestor SelectionArea ownership', (
    tester,
  ) async {
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

    final editableTextContext = tester.element(find.byType(EditableText));
    expect(
      SelectionContainer.maybeOf(editableTextContext),
      isNull,
      reason:
          'The global SelectionArea must not compete with the combobox paste menu.',
    );
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

  testWidgets('AppCombobox filters and changes selected value', (tester) async {
    String value = 'ALL';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: Scaffold(
              body: AppCombobox<String>.single(
                label: 'Trạng thái',
                icon: Icons.flag_outlined,
                value: value,
                options: const [
                  AppComboboxOption(value: 'ALL', label: 'Tất cả'),
                  AppComboboxOption(value: 'PENDING', label: 'Chờ xử lý'),
                ],
                allowClear: false,
                onChanged: (next) => setState(() => value = next ?? 'ALL'),
              ),
            ),
          );
        },
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'cho');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chờ xử lý').last);
    await tester.pumpAndSettle();

    expect(value, 'PENDING');
  });

  testWidgets(
    'AppCombobox suffix icon opens and closes the dropdown without racing focus',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCombobox<String>.single(
              label: 'Trạng thái',
              value: null,
              options: const [
                AppComboboxOption(value: 'PENDING', label: 'Chờ xử lý'),
              ],
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Mở danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Chờ xử lý'), findsOneWidget);
      expect(find.byTooltip('Đóng danh sách'), findsOneWidget);

      await tester.tap(find.byTooltip('Đóng danh sách'));
      await tester.pumpAndSettle();

      expect(find.text('Chờ xử lý'), findsNothing);
      expect(find.byTooltip('Mở danh sách'), findsOneWidget);
    },
  );

  testWidgets(
    'AppCombobox keeps the menu open through a desktop mouse click on an option',
    (tester) async {
      String? value;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: AppCombobox<String>.single(
                  label: 'Trạng thái',
                  value: value,
                  options: const [
                    AppComboboxOption(value: 'PENDING', label: 'Chờ xử lý'),
                  ],
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            );
          },
        ),
      );

      await tester.tap(find.byTooltip('Mở danh sách'));
      await tester.pumpAndSettle();

      final option = find.text('Chờ xử lý');
      final mouse = await tester.startGesture(
        tester.getCenter(option),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 180));

      expect(option, findsOneWidget);

      await mouse.up();
      await tester.pumpAndSettle();

      expect(value, 'PENDING');
      expect(find.byTooltip('Xóa lựa chọn'), findsOneWidget);
    },
  );

  testWidgets('AppCombobox closes when desktop mouse clicks outside', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AppCombobox<String>.single(
                label: 'Trạng thái',
                value: null,
                options: const [
                  AppComboboxOption(value: 'PENDING', label: 'Chờ xử lý'),
                ],
                onChanged: (_) {},
              ),
              const SizedBox(height: 40),
              const Text('Bên ngoài dropdown'),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Mở danh sách'));
    await tester.pumpAndSettle();
    expect(find.text('Chờ xử lý'), findsOneWidget);

    await tester.tapAt(const Offset(760, 560), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(find.text('Chờ xử lý'), findsNothing);
    expect(find.byTooltip('Mở danh sách'), findsOneWidget);
  });

  testWidgets(
    'AppCombobox multi-select keeps menu open while checking values',
    (tester) async {
      var values = <String>{};

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: AppCombobox<String>.multi(
                  label: 'Showroom',
                  icon: Icons.store_outlined,
                  values: values,
                  emptyLabel: 'Showroom được gán',
                  options: const [
                    AppComboboxOption(value: 'CP62', label: 'CP62 - Quận 1'),
                    AppComboboxOption(value: 'CP75', label: 'CP75 - Quận 3'),
                  ],
                  onMultiChanged: (next) => setState(() => values = next),
                ),
              ),
            );
          },
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'quan 3');
      await tester.pumpAndSettle();
      expect(find.text('CP62 - Quận 1'), findsNothing);
      final option = find.text('CP75 - Quận 3');
      final mouse = await tester.startGesture(
        tester.getCenter(option),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(option, findsOneWidget);
      await mouse.up();
      await tester.pumpAndSettle();

      expect(values, {'CP75'});
      expect(find.text('Áp dụng'), findsOneWidget);
    },
  );

  testWidgets('AppPaginationControls renders shared page navigation', (
    tester,
  ) async {
    var previousTapped = false;
    var nextTapped = false;
    var refreshTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPaginationControls(
            pageIndex: 1,
            totalItems: 187,
            itemLabel: 'báo cáo',
            onPrevious: () => previousTapped = true,
            onNext: () => nextTapped = true,
            onRefresh: () => refreshTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Trang 2 - 187 báo cáo'), findsOneWidget);

    await tester.tap(find.byTooltip('Trang trước'));
    await tester.tap(find.byTooltip('Trang sau'));
    await tester.tap(find.byTooltip('Làm mới'));

    expect(previousTapped, isTrue);
    expect(nextTapped, isTrue);
    expect(refreshTapped, isTrue);
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
