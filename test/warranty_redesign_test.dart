import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/warranty/data/repositories/warranty_repository.dart';
import 'package:phongvu_opshub/features/warranty/presentation/providers/warranty_provider.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/warranty_main_screen.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/warranty_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Warranty hub renders content-only task cards', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: WarrantyMainScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warranty-main-header')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.text('Bảo hành / Sửa chữa'), findsOneWidget);
    expect(find.text('Tác vụ BH / SC'), findsOneWidget);
    expect(find.text('Lưu hình ảnh'), findsOneWidget);
    expect(find.text('Xem lại hình ảnh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Warranty upload form renders compactly on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildWarrantyUploadApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warranty-upload-header')), findsOneWidget);
    expect(find.byKey(const Key('warranty-upload-form-card')), findsOneWidget);
    expect(find.byKey(const Key('warranty-image-count-chip')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.text('Lưu hình ảnh BH / SC'), findsOneWidget);
    expect(find.text('Số biên nhận / mã sửa chữa'), findsOneWidget);
    expect(find.text('Thêm hình ảnh'), findsOneWidget);
    expect(find.text('Lưu'), findsOneWidget);

    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập số biên nhận'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _buildWarrantyUploadApp() {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_warrantyUser),
      ),
      ChangeNotifierProvider<WarrantyProvider>(
        create: (_) => WarrantyProvider(WarrantyRepository(ApiClient())),
      ),
    ],
    child: const MaterialApp(home: WarrantyScreen()),
  );
}

const _warrantyUser = User(
  id: 'warranty-user-1',
  email: 'warranty@example.com',
  role: 'USER',
  storeId: 'CP01',
  storeName: 'Showroom 1',
  featureAccess: {'WARRANTY': true},
);

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}
