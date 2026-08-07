import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/storage/app_storage_keys.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/auth/presentation/screens/profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets(
    'Profile shows tree assignment instead of legacy personnel fields',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        AppStorageKeys.shared('user_email'): 'hoang.nv1@phongvu-mna.vn',
        AppStorageKeys.shared('user_name'): 'Hoàng',
        AppStorageKeys.shared('user_lastName'): 'Nguyễn',
        AppStorageKeys.shared('user_role'): 'USER',
        AppStorageKeys.shared('user_departmentCode'): 'MANAGEMENT',
        AppStorageKeys.shared('user_jobRoleCode'): 'STORE_MANAGER',
        AppStorageKeys.shared('user_workScopeType'): 'STORE',
        AppStorageKeys.shared('user_personnelCode'):
            'STORE_MANAGER_CP62_HCM1_HCM_BD',
        AppStorageKeys.shared('user_organizationNodeId'):
            'org-store-cp62-pos-manager',
        AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
        AppStorageKeys.shared('user_storeId'): 'CP62',
        AppStorageKeys.shared('user_storeName'): 'Phan Đăng Lưu',
        AppStorageKeys.shared('user_assignedStores'): jsonEncode([
          {'id': 'store-62', 'storeId': 'CP62', 'storeName': 'Phan Đăng Lưu'},
          {'id': 'store-75', 'storeId': 'CP75', 'storeName': 'Phan Đăng Lưu 2'},
        ]),
      });
      _seedSecureToken();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(AuthRepository(ApiClient())),
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsNothing);
      expect(findsLegacyGradientHeader(), findsNothing);
      expect(find.byKey(const Key('profile-header')), findsOneWidget);
      expect(find.byKey(const Key('profile-session-card')), findsOneWidget);
      expect(find.byKey(const Key('profile-logout-button')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('profile-session-card')),
          matching: find.byKey(const Key('profile-logout-button')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-edit-card')), findsOneWidget);
      expect(find.byKey(const Key('profile-info-card')), findsOneWidget);
      expect(find.text('Thông tin hiển thị'), findsOneWidget);
      expect(find.text('Thông tin tài khoản'), findsOneWidget);
      expect(find.text('Phiên đăng nhập'), findsOneWidget);
      expect(find.text('Đăng xuất'), findsOneWidget);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Đăng xuất'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Đổi mật khẩu'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(find.text('Quản lý Cửa hàng'), findsWidgets);
      expect(find.text('Cây tổ chức'), findsOneWidget);
      expect(find.textContaining('CP62 - Phan Đăng Lưu'), findsOneWidget);
      expect(find.textContaining('CP75 - Phan Đăng Lưu 2'), findsOneWidget);
      expect(find.text('Showroom được gán'), findsOneWidget);
      expect(find.textContaining('Phòng ban'), findsNothing);
      expect(find.textContaining('Chức danh'), findsNothing);
      expect(find.textContaining('Phạm vi'), findsNothing);
      expect(find.text('STORE_MANAGER_CP62_HCM1_HCM_BD'), findsNothing);
    },
  );

  testWidgets('Profile asks before logging out', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'hoang.nv1@phongvu-mna.vn',
      AppStorageKeys.shared('user_name'): 'Hoàng',
      AppStorageKeys.shared('user_role'): 'USER',
      AppStorageKeys.shared('user_workScopeType'): 'STORE',
      AppStorageKeys.shared('user_organizationNodeId'):
          'org-store-cp62-pos-manager',
      AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
      AppStorageKeys.shared('user_storeId'): 'CP62',
      AppStorageKeys.shared('user_storeName'): 'Phan Đăng Lưu',
    });
    _seedSecureToken();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-logout-button')));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsOneWidget);
    expect(
      find.text(
        'Bạn có chắc chắn muốn đăng xuất khỏi OpsHub? Bạn sẽ cần đăng nhập lại để tiếp tục làm việc trên thiết bị này.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();

    expect(find.text('Xác nhận đăng xuất'), findsNothing);
    expect(find.byKey(const Key('profile-session-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile compact geometry follows the approved Figma nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'staff@example.com',
      AppStorageKeys.shared('user_name'): 'Hoàng',
      AppStorageKeys.shared('user_lastName'): 'Nguyễn',
      AppStorageKeys.shared('user_role'): 'USER',
      AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
    });
    _seedSecureToken();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final contentSize = tester.getSize(
      find.byKey(const Key('profile-content')),
    );
    expect(contentSize.width, 343);
    expect(
      tester.getSize(find.byKey(const Key('profile-header'))),
      const Size(343, 112),
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-session-card'))),
      const Size(343, 92),
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-edit-card'))),
      const Size(343, 292),
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-info-card'))).width,
      343,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact password dialog matches approved REVIEW nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      AppStorageKeys.shared('user_email'): 'staff@example.com',
      AppStorageKeys.shared('user_name'): 'Hoàng',
      AppStorageKeys.shared('user_lastName'): 'Nguyễn',
      AppStorageKeys.shared('user_role'): 'USER',
      AppStorageKeys.shared('user_organizationNodeName'): 'Quản lý Cửa hàng',
    });
    _seedSecureToken();

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(AuthRepository(ApiClient())),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi mật khẩu').first);
    await tester.pumpAndSettle();

    final dialogSurface = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card,
      ),
    );
    expect(dialogSurface, findsOneWidget);
    expect(tester.getSize(dialogSurface).width, 343);
    expect(find.text('Nhập lại mật khẩu'), findsOneWidget);
    expect(find.text('Nhập lại mật khẩu mới'), findsNothing);
    expect(find.byTooltip('Hiện mật khẩu hiện tại'), findsOneWidget);
    expect(find.byTooltip('Hiện mật khẩu mới'), findsOneWidget);
    expect(find.byTooltip('Hiện mật khẩu nhập lại'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.eye), findsNWidgets(3));

    await tester.tap(find.byTooltip('Hiện mật khẩu nhập lại'));
    await tester.pump();
    expect(find.byTooltip('Ẩn mật khẩu nhập lại'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.eyeSlash), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Profile responsive geometry stays aligned across Figma viewport classes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const viewports =
          <
            ({
              Size size,
              double contentWidth,
              double headerHeight,
              double sessionHeight,
              double editHeight,
              double infoWidth,
            })
          >[
            (
              size: Size(768, 1024),
              contentWidth: 720,
              headerHeight: 112,
              sessionHeight: 80,
              editHeight: 292,
              infoWidth: 720,
            ),
            (
              size: Size(1280, 900),
              contentWidth: 1180,
              headerHeight: 114,
              sessionHeight: 80,
              editHeight: 284,
              infoWidth: 430,
            ),
          ];

      for (final viewport in viewports) {
        tester.view.physicalSize = viewport.size;
        SharedPreferences.setMockInitialValues({
          AppStorageKeys.shared('user_email'): 'staff@example.com',
          AppStorageKeys.shared('user_name'): 'Hoàng',
          AppStorageKeys.shared('user_lastName'): 'Nguyễn',
          AppStorageKeys.shared('user_role'): 'USER',
          AppStorageKeys.shared('user_organizationNodeName'):
              'Quản lý Cửa hàng',
        });
        _seedSecureToken();

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(AuthRepository(ApiClient())),
            child: const MaterialApp(home: ProfileScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byKey(const Key('profile-content'))).width,
          viewport.contentWidth,
        );
        expect(
          tester.getSize(find.byKey(const Key('profile-header'))).height,
          viewport.headerHeight,
        );
        expect(
          tester.getSize(find.byKey(const Key('profile-session-card'))).height,
          viewport.sessionHeight,
        );
        expect(
          tester.getSize(find.byKey(const Key('profile-edit-card'))).height,
          viewport.editHeight,
        );
        expect(
          tester.getSize(find.byKey(const Key('profile-info-card'))).width,
          viewport.infoWidth,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}

void _seedSecureToken() {
  FlutterSecureStorage.setMockInitialValues({
    AppStorageKeys.secure('user_jwt_token'): 'widget-test-token',
  });
}
