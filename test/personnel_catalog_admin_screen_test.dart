import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_personnel_definition.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/personnel_catalog_admin_screen.dart';
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

  testWidgets(
    'Personnel catalog renders content-only departments and job roles',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakePersonnelRepository();

      await tester.pumpWidget(
        MaterialApp(home: PersonnelCatalogAdminScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('personnel-catalog-header')), findsOneWidget);
      expect(find.byKey(const Key('personnel-catalog-tabs')), findsOneWidget);
      expect(find.text('Danh mục nhân sự'), findsOneWidget);
      expect(find.text('Thêm phòng ban'), findsOneWidget);
      expect(find.text('Thêm chức danh'), findsOneWidget);
      expect(find.text('1 phòng ban • 1 chức danh'), findsOneWidget);
      expect(find.text('Kinh doanh'), findsOneWidget);
      expect(find.textContaining('SALE • 2 người dùng'), findsOneWidget);
      expect(find.byType(GradientHeader), findsNothing);
      expect(find.byType(Scaffold), findsNothing);

      await tester.tap(find.text('Chức danh'));
      await tester.pumpAndSettle();

      expect(find.text('Tư vấn bán hàng'), findsOneWidget);
      expect(find.textContaining('Kinh doanh • 3 người dùng'), findsOneWidget);
      expect(repository.departmentLoadCount, 1);
      expect(repository.jobRoleLoadCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Personnel catalog shows retryable load error state', (
    tester,
  ) async {
    final repository = _FakePersonnelRepository(failDepartmentLoads: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonnelCatalogAdminScreen(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('personnel-catalog-error-state')),
      findsOneWidget,
    );
    expect(find.text('Chưa tải được danh mục nhân sự.'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.ensureVisible(find.text('Thử tải lại'));
    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('personnel-catalog-error-state')),
      findsNothing,
    );
    expect(find.text('Kinh doanh'), findsOneWidget);
    expect(repository.departmentLoadCount, 2);
    expect(tester.takeException(), isNull);
  });
}

class _FakePersonnelRepository extends AuthRepository {
  _FakePersonnelRepository({this.failDepartmentLoads = 0}) : super(ApiClient());

  final int failDepartmentLoads;
  int departmentLoadCount = 0;
  int jobRoleLoadCount = 0;

  @override
  Future<List<AdminPersonnelDefinition>> listAdminDepartments() async {
    departmentLoadCount += 1;
    if (departmentLoadCount <= failDepartmentLoads) {
      throw Exception('Không tải được phòng ban kiểm thử');
    }
    return const [
      AdminPersonnelDefinition(
        code: 'SALE',
        title: 'Kinh doanh',
        description: 'Nhóm bán hàng',
        isSystem: false,
        userCount: 2,
      ),
    ];
  }

  @override
  Future<List<AdminPersonnelDefinition>> listAdminJobRoles() async {
    jobRoleLoadCount += 1;
    return const [
      AdminPersonnelDefinition(
        code: 'SALES_CONSULTANT',
        title: 'Tư vấn bán hàng',
        description: 'Tư vấn tại cửa hàng',
        departmentCode: 'SALE',
        isSystem: false,
        userCount: 3,
      ),
    ];
  }
}
