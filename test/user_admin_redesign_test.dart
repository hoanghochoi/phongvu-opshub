import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/app_filter_dropdowns.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_feature_definition.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_organization_node.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_role_definition.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/user_admin_screen.dart';
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

  testWidgets('User admin renders content-only workspace and runtime actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const currentUser = User(
      id: 'admin-1',
      email: 'admin@phongvu.vn',
      name: 'Quản trị viên',
      role: 'SUPER_ADMIN',
      status: 'yes',
    );
    final repository = _FakeUserAdminRepository(
      users: const [
        User(
          id: 'user-1',
          email: 'minh.anh@phongvu.vn',
          name: 'Nguyễn Minh Anh',
          role: 'USER',
          status: 'yes',
          storeId: '7001',
          storeName: 'Phong Vũ Quận 3',
        ),
        User(
          id: 'user-2',
          email: 'hoang.nam@phongvu.vn',
          name: 'Trần Hoàng Nam',
          role: 'ADMIN',
          status: 'no',
          organizationNodeName: 'Miền Nam',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(currentUser),
        child: MaterialApp(home: UserAdminScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('user-admin-header')), findsOneWidget);
    expect(find.byKey(const Key('user-admin-filters')), findsOneWidget);
    expect(find.text('Nhập danh sách'), findsOneWidget);
    expect(find.text('Thêm người dùng'), findsOneWidget);
    expect(find.text('minh.anh@phongvu.vn'), findsOneWidget);
    expect(find.text('hoang.nam@phongvu.vn'), findsOneWidget);
    expect(find.text('Đã khóa'), findsOneWidget);
    expect(find.byType(AppFilterDropdown<String>), findsNWidgets(3));
    expect(find.byType(AppSearchableFilterDropdown<String>), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('User admin remains usable on compact viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const currentUser = User(
      id: 'staff-admin',
      email: 'staff.admin@phongvu.vn',
      name: 'Admin cửa hàng',
      role: 'ADMIN',
      status: 'yes',
      featureAccess: {'ADMIN_USERS': true},
    );
    final repository = _FakeUserAdminRepository(
      users: const [
        User(
          id: 'user-mobile',
          email: 'mobile.user@phongvu.vn',
          name: 'Người dùng Mobile',
          role: 'USER',
          status: 'yes',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(currentUser),
        child: MaterialApp(home: UserAdminScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhập danh sách'), findsNothing);
    expect(find.text('Thêm người dùng'), findsNothing);
    expect(find.text('mobile.user@phongvu.vn'), findsOneWidget);
    expect(find.text('Hoạt động'), findsOneWidget);
    expect(find.byTooltip('Đặt lại mật khẩu'), findsOneWidget);
    expect(find.byTooltip('Sửa người dùng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('User admin sends text search to the server', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const currentUser = User(
      id: 'admin-1',
      email: 'admin@phongvu.vn',
      name: 'Quản trị viên',
      role: 'SUPER_ADMIN',
      status: 'yes',
    );
    final repository = _FakeUserAdminRepository(users: const []);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(currentUser),
        child: MaterialApp(home: UserAdminScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'vu.nt1@phongvu-mna.vn',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repository.requestedQueries.last, 'vu.nt1@phongvu-mna.vn');
    expect(find.text('vu.nt1@phongvu-mna.vn'), findsAtLeastNWidgets(2));
    expect(tester.takeException(), isNull);
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

class _FakeUserAdminRepository extends AuthRepository {
  _FakeUserAdminRepository({required this.users}) : super(ApiClient());

  final List<User> users;
  final List<String?> requestedQueries = [];

  @override
  Future<List<User>> listUsers({
    String? query,
    String? domain,
    String? orgNodeId,
    String? featureCode,
    String? role,
    String? status,
  }) async {
    requestedQueries.add(query);
    if (query?.trim() == 'vu.nt1@phongvu-mna.vn') {
      return const [
        User(
          id: 'user-db-search',
          email: 'vu.nt1@phongvu-mna.vn',
          name: 'Vũ Nhật',
          role: 'USER',
          status: 'yes',
        ),
      ];
    }
    return users;
  }

  @override
  Future<List<AdminRoleDefinition>> listAdminRoles() async =>
      AdminRoles.definitions;

  @override
  Future<List<AdminFeatureDefinition>> listAdminFeatureTree() async => const [];

  @override
  Future<List<AdminOrganizationNode>> listAdminUserScopeTree() async =>
      const [];
}
