import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_role_definition.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/role_admin_screen.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Role admin renders content-only workspace and reload action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeRoleAdminRepository(
      roles: const [
        AdminRoleDefinition(
          value: 'SUPER_ADMIN',
          title: 'Quản trị toàn hệ thống',
          description: 'Toàn quyền hệ thống',
          icon: Icons.verified_user_outlined,
          color: Colors.deepPurple,
          isSystem: true,
        ),
        AdminRoleDefinition(
          value: 'ADMIN',
          title: 'Quản trị viên',
          description: 'Quản trị theo phạm vi cây tổ chức',
          icon: Icons.admin_panel_settings_outlined,
          color: Colors.blue,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: RoleAdminScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('role-admin-header')), findsOneWidget);
    expect(find.byKey(const Key('role-admin-list')), findsOneWidget);
    expect(find.text('Quản lý vai trò'), findsOneWidget);
    expect(find.text('2 vai trò'), findsOneWidget);
    expect(find.text('Chỉ đọc'), findsOneWidget);
    expect(find.text('Quản trị toàn hệ thống'), findsOneWidget);
    expect(find.text('Quản trị theo phạm vi cây tổ chức'), findsOneWidget);
    expect(find.text('SUPER_ADMIN'), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byType(Scaffold), findsNothing);

    await tester.tap(find.byTooltip('Tải lại danh sách vai trò'));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Role admin shows retryable error state', (tester) async {
    final repository = _FakeRoleAdminRepository(
      roles: AdminRoles.definitions,
      failCount: 1,
    );

    await tester.pumpWidget(
      MaterialApp(home: RoleAdminScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Không tải được danh sách vai trò'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(find.text('Không tải được danh sách vai trò'), findsNothing);
    expect(find.text('Quản trị toàn hệ thống'), findsOneWidget);
    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });
}

class _FakeRoleAdminRepository extends AuthRepository {
  _FakeRoleAdminRepository({required this.roles, this.failCount = 0})
    : super(ApiClient());

  final List<AdminRoleDefinition> roles;
  final int failCount;
  int loadCount = 0;

  @override
  Future<List<AdminRoleDefinition>> listAdminRoles() async {
    loadCount += 1;
    if (loadCount <= failCount) {
      throw Exception('Không tải được dữ liệu kiểm thử');
    }
    return roles;
  }
}
