import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/vietqr/presentation/screens/vietqr_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'VietQR lets super-admin choose any showroom from the full list',
    (tester) async {
      final authRepository = _FakeAuthRepository([
        const StoreBranch(
          id: 'store-62',
          storeId: 'CP62',
          storeName: 'SR CP62',
        ),
        const StoreBranch(
          id: 'store-75',
          storeId: 'CP75',
          storeName: 'SR CP75',
        ),
      ]);
      final authProvider = _FakeAuthProvider(
        const User(
          id: 'super-1',
          email: 'admin@phongvu.vn',
          role: 'SUPER_ADMIN',
          assignedStores: [],
        ),
        repository: authRepository,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: MaterialApp(
            home: VietQrScreen(authRepository: authRepository),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vietqr-workspace-header')), findsNothing);
      expect(find.byType(Scaffold), findsNothing);
      expect(findsLegacyGradientHeader(), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('CP62 - SR CP62'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('CP75 - SR CP75'), findsOneWidget);

      await tester.tap(find.text('CP75 - SR CP75').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), 'DH-001');
      await tester.pumpAndSettle();

      expect(find.text('DH-001 CP75 BOT'), findsOneWidget);
    },
  );

  testWidgets('VietQR desktop shows history and reopens a still-valid QR', (
    tester,
  ) async {
    final createdAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 5),
    );
    final historyKey = AppStorageKeys.shared('vietqr_history.user-1');
    SharedPreferences.setMockInitialValues({
      historyKey: jsonEncode([
        {
          'storeCode': 'CP62',
          'transfer': {
            'id': 'payment-1',
            'bankBin': '970436',
            'bankName': 'Vietcombank',
            'accountNumber': '123456789',
            'accountName': 'PHONG VU',
            'amount': 150000,
            'transferContent': 'DH-001 CP62 BOT',
            'qrPayload': 'payload',
            'status': 'PENDING',
            'createdAt': createdAt.toIso8601String(),
            'qrBrand': {
              'key': 'phongvu',
              'title': 'Phong Vũ',
              'logoKey': 'phongvu',
              'logoAsset': 'assets/icon/source/app_icon_master.png',
            },
          },
        },
      ]),
    });
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        assignedStores: [
          StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'SR CP62'),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: VietQrScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lịch sử tạo QR'), findsOneWidget);
    expect(find.text('Thông tin chuyển khoản'), findsOneWidget);

    final formTopLeft = tester.getTopLeft(find.text('Thông tin chuyển khoản'));
    final historyTopLeft = tester.getTopLeft(find.text('Lịch sử tạo QR'));
    expect(historyTopLeft.dy, lessThan(formTopLeft.dy + 120));
    expect(historyTopLeft.dx, greaterThanOrEqualTo(formTopLeft.dx));

    expect(find.text('Còn hạn'), findsOneWidget);

    await tester.tap(find.text('Showroom CP62').last);
    await tester.pumpAndSettle();

    expect(find.text('Kiểm tra ngay'), findsOneWidget);
    expect(find.text('Tải ảnh QR'), findsOneWidget);
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser, {AuthRepository? repository})
    : super(repository ?? _FakeAuthRepository(const []));

  @override
  User? get user => currentUser;
}

class _FakeAuthRepository extends AuthRepository {
  final List<StoreBranch> stores;

  _FakeAuthRepository(this.stores) : super(ApiClient());

  @override
  Future<List<StoreBranch>> getStores({String? query}) async {
    return stores;
  }
}
