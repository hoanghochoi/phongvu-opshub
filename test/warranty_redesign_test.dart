import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/navigation/app_shell.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/warranty/data/repositories/warranty_repository.dart';
import 'package:phongvu_opshub/features/warranty/presentation/providers/warranty_provider.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/check_warranty_screen.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/warranty_details_screen.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/warranty_main_screen.dart';
import 'package:phongvu_opshub/features/warranty/presentation/screens/warranty_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '2026.07.03.86',
      buildNumber: '200086',
      buildSignature: '',
    );
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

    expect(find.byKey(const Key('warranty-main-header')), findsNothing);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Bảo hành / Sửa chữa'), findsNothing);
    expect(find.text('Tác vụ BH / SC'), findsOneWidget);
    expect(find.text('Lưu hình ảnh'), findsOneWidget);
    expect(find.text('Xem lại hình ảnh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Warranty hub renders actions directly inside AppShell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1919, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_warrantyUser),
        child: MaterialApp(
          home: AppShell(
            location: '/warranty-main',
            child: const SelectionArea(child: WarrantyMainScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warranty-main-header')), findsNothing);
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
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Lưu hình ảnh BH / SC'), findsOneWidget);
    expect(find.text('Số biên nhận / mã sửa chữa'), findsOneWidget);
    expect(find.text('Thêm hình ảnh'), findsOneWidget);
    expect(find.text('Lưu'), findsOneWidget);

    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập số biên nhận'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Warranty lookup renders content-only search and receipts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final warrantyProvider = _FakeWarrantyProvider(receipts: _warrantyReceipts);

    await tester.pumpWidget(_buildWarrantyLookupApp(warrantyProvider));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warranty-lookup-header')), findsOneWidget);
    expect(
      find.byKey(const Key('warranty-lookup-search-card')),
      findsOneWidget,
    );
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Xem lại biên nhận'), findsOneWidget);
    expect(find.text('CP01-J12345678'), findsOneWidget);
    expect(find.text('1 kết quả'), findsOneWidget);
    expect(warrantyProvider.listCallCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Warranty detail renders content header and image viewer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final warrantyProvider = _FakeWarrantyProvider(details: _warrantyDetails);

    await tester.pumpWidget(_buildWarrantyDetailApp(warrantyProvider));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('warranty-detail-header')), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('Chi tiết biên nhận'), findsOneWidget);
    expect(find.text('Thông tin biên nhận'), findsOneWidget);
    expect(find.text('Hình ảnh (2)'), findsOneWidget);
    expect(find.byKey(const Key('warranty-image-card-0')), findsOneWidget);
    expect(warrantyProvider.detailCallCount, 1);

    await tester.tap(find.byKey(const Key('warranty-image-card-0')));
    await tester.pumpAndSettle();

    expect(find.text('CP01-J12345678 - Ảnh 1'), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
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

Widget _buildWarrantyLookupApp(_FakeWarrantyProvider warrantyProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_warrantyUser),
      ),
      ChangeNotifierProvider<WarrantyProvider>.value(value: warrantyProvider),
    ],
    child: const MaterialApp(home: CheckWarrantyScreen()),
  );
}

Widget _buildWarrantyDetailApp(_FakeWarrantyProvider warrantyProvider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_warrantyUser),
      ),
      ChangeNotifierProvider<WarrantyProvider>.value(value: warrantyProvider),
    ],
    child: const MaterialApp(
      home: WarrantyDetailsScreen(receiptNumber: 'CP01-J12345678'),
    ),
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

class _FakeWarrantyProvider extends WarrantyProvider {
  List<Map<String, dynamic>> fakeReceipts;
  Map<String, dynamic>? fakeDetails;
  int listCallCount = 0;
  int searchCallCount = 0;
  int detailCallCount = 0;

  _FakeWarrantyProvider({
    List<Map<String, dynamic>> receipts = const [],
    Map<String, dynamic>? details,
  }) : fakeReceipts = List<Map<String, dynamic>>.from(receipts),
       fakeDetails = details,
       super(WarrantyRepository(ApiClient()));

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  List<Map<String, dynamic>> get receipts => fakeReceipts;

  @override
  Map<String, dynamic>? get currentDetails => fakeDetails;

  @override
  Future<bool> showAllWarranty(String userEmail) async {
    listCallCount++;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    searchCallCount++;
    fakeReceipts = fakeReceipts
        .where((receipt) => receipt['receipt']?.toString() == receiptNumber)
        .toList(growable: false);
    notifyListeners();
    return true;
  }

  @override
  Future<bool> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    detailCallCount++;
    notifyListeners();
    return true;
  }
}

const _warrantyReceipts = [
  {
    'receipt': 'CP01-J12345678',
    'user': 'warranty@example.com',
    'date': '2026-07-02T09:00:00.000Z',
  },
];

const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lctDZwAAAABJRU5ErkJggg==';

const _warrantyDetails = {
  'receipt': 'CP01-J12345678',
  'user': 'warranty@example.com',
  'date': '2026-07-02T09:00:00.000Z',
  'images': [_onePixelPngBase64, _onePixelPngBase64],
};
