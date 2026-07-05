import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

void main() {
  test('mọi thông báo tạm thời đều đi qua AppToast', () {
    final violations = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('.showSnackBar('))
        .map((file) => file.path)
        .toList();

    expect(violations, isEmpty);
  });

  testWidgets('toast floats at the top right with a bounded width', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AppToast.show(
                context,
                const SnackBar(
                  content: Text('Đã cập nhật dữ liệu.'),
                  duration: Duration(seconds: 10),
                ),
              ),
              child: const Text('Hiện thông báo'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Hiện thông báo'));
    await tester.pump(const Duration(milliseconds: 250));

    final rect = tester.getRect(find.byKey(const Key('app-toast-position')));
    expect(find.text('Đã cập nhật dữ liệu.'), findsOneWidget);
    expect(rect.top, lessThan(80));
    expect(rect.right, closeTo(784, 0.1));
    expect(rect.width, lessThanOrEqualTo(360));
    expect(rect.width, lessThan(800));
  });
}
