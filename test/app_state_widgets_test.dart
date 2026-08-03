import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/widgets/app_state_widgets.dart';

void main() {
  testWidgets('loading state follows the shared Figma geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppStatePanel.loading(
            title: 'Đang tải dữ liệu',
            message: 'Vui lòng chờ trong giây lát.',
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('app-state-panel'))).width, 480);
    expect(
      tester.getSize(find.byKey(const Key('app-state-loading-spinner'))),
      const Size(36, 36),
    );
    expect(find.byIcon(PhosphorIconsRegular.spinnerGap), findsOneWidget);

    final title = tester.widget<Text>(find.text('Đang tải dữ liệu'));
    expect(title.style?.fontSize, 16);
    expect(title.style?.height, 24 / 16);
    final message = tester.widget<Text>(
      find.text('Vui lòng chờ trong giây lát.'),
    );
    expect(message.style?.fontSize, 14);
    expect(message.style?.height, 20 / 14);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtered-empty state keeps its 220x44 action', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppStatePanel.empty(
            title: 'Không tìm thấy kết quả',
            message: 'Hãy đổi bộ lọc hoặc từ khóa để xem dữ liệu khác.',
            actionLabel: 'Xóa bộ lọc',
            onAction: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('app-state-icon-tile'))),
      const Size(56, 56),
    );
    expect(
      tester.getSize(find.byKey(const Key('app-state-action'))),
      const Size(220, 44),
    );
    final action = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(
      action.style?.shape?.resolve(<WidgetState>{}),
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    expect(find.text('Xóa bộ lọc'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long state copy shrinks the action to avoid compact overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AppStatePanel.error(
                title:
                    'Chưa tải được dữ liệu với nội dung dài để kiểm tra xuống dòng',
                message:
                    'Kiểm tra kết nối rồi thử tải lại danh sách với hướng dẫn dài.',
                actionLabel: 'Thử tải lại',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('app-state-action'))).width,
      200,
    );
    expect(tester.takeException(), isNull);
  });
}
