import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';

void main() {
  testWidgets('payment monitor route renders unsupported state on web', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AppRouter.buildPaymentMonitorRoute(isWeb: true)),
    );
    await tester.pump();

    expect(find.text('Chưa hỗ trợ trên web'), findsOneWidget);
    expect(
      find.textContaining('đọc loa thanh toán chỉ chạy trên Windows'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.web_asset_off_outlined), findsOneWidget);
  });
}
