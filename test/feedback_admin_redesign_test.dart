import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/feedback_admin_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Feedback admin renders content-only runtime list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var loadCount = 0;
    Future<List<Map<String, dynamic>>> loader() async {
      loadCount += 1;
      return _feedbackItems([
        {
          'id': 'feedback-1',
          'content': 'Chức năng: FIFO\nMô tả: Lỗi quét serial',
          'rating': 4,
          'createdAt': '2026-07-02T02:30:00.000Z',
          'user': {'email': 'minh.anh@phongvu.vn', 'firstName': 'Minh Anh'},
        },
        {
          'id': 'feedback-2',
          'content': 'Mô tả: Thiếu trạng thái lưu',
          'rating': 5,
          'createdAt': '2026-07-02T03:45:00.000Z',
          'user': {'email': 'ops@phongvu.vn'},
        },
      ]);
    }

    await tester.pumpWidget(
      MaterialApp(home: FeedbackAdminScreen(loader: loader)),
    );
    await tester.pumpAndSettle();

    expect(loadCount, 1);
    expect(find.byKey(const Key('feedback-admin-header')), findsOneWidget);
    expect(find.byKey(const Key('feedback-admin-list')), findsOneWidget);
    expect(find.text('Danh sách góp ý'), findsOneWidget);
    expect(find.text('2 góp ý'), findsOneWidget);
    expect(find.text('0 có ảnh'), findsOneWidget);
    expect(find.text('Minh Anh'), findsOneWidget);
    expect(find.text('FIFO'), findsOneWidget);
    expect(find.text('4/5 điểm'), findsOneWidget);
    expect(find.text('minh.anh@phongvu.vn'), findsOneWidget);
    expect(find.byTooltip('Tải lại danh sách góp ý'), findsOneWidget);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Feedback admin shows retryable error state', (tester) async {
    var calls = 0;
    Future<List<Map<String, dynamic>>> loader() async {
      calls += 1;
      if (calls == 1) {
        throw Exception('server busy');
      }
      return _feedbackItems([
        {
          'id': 'feedback-1',
          'content': 'Chức năng: VietQR\nMô tả: Cần hiện rõ kết quả',
          'rating': 5,
          'createdAt': '2026-07-02T02:30:00.000Z',
          'user': {'email': 'super@phongvu.vn'},
        },
      ]);
    }

    await tester.pumpWidget(
      MaterialApp(home: FeedbackAdminScreen(loader: loader)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Không tải được danh sách góp ý'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(find.text('Không tải được danh sách góp ý'), findsNothing);
    expect(find.text('VietQR'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}

List<Map<String, dynamic>> _feedbackItems(List<Map<String, dynamic>> values) {
  return jsonDecode(
    jsonEncode(values),
  ).whereType<Map<String, dynamic>>().toList(growable: false);
}
