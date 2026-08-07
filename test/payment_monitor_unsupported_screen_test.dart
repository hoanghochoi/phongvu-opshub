import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'helpers/legacy_widget_finders.dart';
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
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(
      find.byKey(const Key('payment-monitor-unsupported-header')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('payment-monitor-unsupported-card')),
      findsOneWidget,
    );
    expect(find.text('Chưa hỗ trợ trên web'), findsOneWidget);
    expect(
      find.textContaining('app Android, iOS, iPadOS hoặc Windows'),
      findsOneWidget,
    );
    expect(find.text('Về trang chủ'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.browser), findsOneWidget);
  });
}
