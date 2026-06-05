import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/screens/payment_monitor_unsupported_screen.dart';

void main() {
  testWidgets(
    'Payment monitor unsupported screen explains Windows-only support',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PaymentMonitorUnsupportedScreen()),
      );
      await tester.pump();

      expect(find.text('Chỉ hỗ trợ Windows'), findsOneWidget);
      expect(find.text('Về trang chủ'), findsOneWidget);
      expect(find.byIcon(Icons.desktop_windows_outlined), findsOneWidget);
    },
  );
}
