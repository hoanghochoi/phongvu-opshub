import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/admin_menu_screen.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Admin menu shows feature management action by feature access', (
    tester,
  ) async {
    const user = User(
      email: 'admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_FEATURES': true},
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(user),
        child: const MaterialApp(home: AdminMenuScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byKey(const Key('admin-menu-header')), findsOneWidget);
    expect(find.text('Công cụ theo quyền'), findsOneWidget);
    expect(find.text('1 chức năng khả dụng'), findsOneWidget);
    expect(find.text('Chức năng quản trị'), findsOneWidget);
    expect(find.text('Quản lý tính năng'), findsOneWidget);
    expect(find.text('Tính năng và quyền truy cập'), findsOneWidget);
    expect(find.text('Quản lý người dùng'), findsNothing);
  });

  testWidgets('Admin menu keeps empty state content-only without permissions', (
    tester,
  ) async {
    const user = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-staff',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(user),
        child: const MaterialApp(home: AdminMenuScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byKey(const Key('admin-menu-header')), findsOneWidget);
    expect(find.text('Chưa có chức năng khả dụng'), findsOneWidget);
    expect(find.text('Chưa có tính năng quản trị'), findsOneWidget);
    expect(
      find.text('Liên hệ quản trị viên để được cấp quyền phù hợp.'),
      findsOneWidget,
    );
  });

  testWidgets('Admin menu shows personnel catalog by feature access', (
    tester,
  ) async {
    const user = User(
      email: 'personnel-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_PERSONNEL': true},
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(user),
        child: const MaterialApp(home: AdminMenuScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.text('1 chức năng khả dụng'), findsOneWidget);
    expect(find.text('Danh mục nhân sự'), findsOneWidget);
    expect(find.text('Phòng ban và chức danh'), findsOneWidget);
    expect(find.text('Quản lý tính năng'), findsNothing);
  });

  testWidgets('Admin menu shows help management for super admin only', (
    tester,
  ) async {
    const user = User(
      email: 'super-admin@phongvu.vn',
      role: 'SUPER_ADMIN',
      organizationNodeId: 'org-super-admin',
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(user),
        child: const MaterialApp(home: AdminMenuScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Quản lý hướng dẫn'), findsOneWidget);
    expect(find.text('Nội dung runtime công khai'), findsOneWidget);
    expect(find.text('Danh sách góp ý'), findsOneWidget);
  });
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this.currentUser) : super(AuthRepository(ApiClient()));

  final User currentUser;

  @override
  User? get user => currentUser;

  @override
  bool get isInitialized => true;

  @override
  bool get isAuthenticated => true;
}
