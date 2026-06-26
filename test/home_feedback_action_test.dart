import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phongvu_opshub/app/widgets/app_feature_grid.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/store_branch.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/home/presentation/screens/home_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Góp ý is always the last visible Home action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {
          'FIFO': true,
          'WARRANTY': true,
          'VIETQR': true,
          'BANK_STATEMENTS': true,
          'FEEDBACK': true,
        },
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(
      titles,
      containsAll(<String>['FIFO', 'BH / SC', 'VietQR', 'Sao kê']),
    );
    expect(titles.last, 'Góp ý');
    expect(titles.where((title) => title == 'Góp ý'), hasLength(1));
  });

  testWidgets('Home header shows all assigned SR codes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        name: 'Staging',
        role: 'USER',
        organizationNodeId: 'org-store-cp75',
        assignedStores: [
          StoreBranch(id: 'store-75', storeId: 'CP75', storeName: 'CP75'),
          StoreBranch(id: 'store-62', storeId: 'CP62', storeName: 'CP62'),
        ],
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 SR: CP75, CP62'), findsOneWidget);
  });

  testWidgets('Android Home shows Tiền vào but hides speaker quick toggle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'PAYMENT_MONITOR': true, 'PAYMENT_SPEAKER': true},
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<AppFeatureTile>(find.byType(AppFeatureTile))
        .map((tile) => tile.action.title)
        .toList(growable: false);

    expect(titles, contains('Tiền vào'));
    expect(find.text('Đọc loa tiền vào'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Home support icon opens QR and group link dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PhongVu OpsHub',
      packageName: 'com.example.phongvu_opshub',
      version: '1.1.1',
      buildNumber: '2',
      buildSignature: '',
    );
    final authProvider = _FakeAuthProvider(
      const User(
        id: 'user-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hỗ trợ'));
    await tester.pumpAndSettle();

    expect(find.text('Hỗ trợ OpsHub'), findsOneWidget);
    expect(find.textContaining('link.seatalk.io/group/open'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'data/group_invitation.jpg',
      ),
      findsOneWidget,
    );
  });
}

class _FakeAuthProvider extends AuthProvider {
  final User currentUser;

  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  @override
  User? get user => currentUser;
}
