import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('payment monitor route renders list screen on web', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(AuthRepository(ApiClient())),
          ),
          ChangeNotifierProvider(
            create: (_) => PaymentMonitorProvider(
              PaymentMonitorRepository(ApiClient()),
              PaymentSpeaker(),
            ),
          ),
        ],
        child: MaterialApp(
          home: AppRouter.buildPaymentMonitorRoute(isWeb: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PaymentMonitorScreen), findsOneWidget);
    expect(find.text('Theo dõi tiền vào'), findsOneWidget);
    expect(find.text('Giao dịch tiền vào'), findsOneWidget);
    expect(find.text('Chưa hỗ trợ trên web'), findsNothing);
  });
}
