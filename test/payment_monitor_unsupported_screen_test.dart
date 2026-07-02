import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/screens/payment_monitor_unsupported_screen.dart';

void main() {
  testWidgets('Payment monitor unsupported screen explains web limitation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PaymentMonitorUnsupportedScreen()),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(
      find.byKey(const Key('payment-monitor-unsupported-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('payment-monitor-unsupported-card')),
      findsOneWidget,
    );
    expect(find.text('Theo dõi tiền vào'), findsOneWidget);
    expect(find.text('Chưa hỗ trợ trên web'), findsOneWidget);
    expect(
      find.textContaining('đọc loa thanh toán chỉ chạy trên Windows'),
      findsOneWidget,
    );
    expect(find.text('Về trang chủ'), findsOneWidget);
    expect(find.byIcon(Icons.web_asset_off_outlined), findsOneWidget);
  });
}
