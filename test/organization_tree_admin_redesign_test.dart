import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_organization_node.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/organization_tree_admin_screen.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:provider/provider.dart';
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

  testWidgets('Organization tree renders content-only workspace and detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeOrganizationRepository(nodes: [_storeNode]);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_superAdmin),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: OrganizationTreeAdminScreen(repository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('organization-tree-header')), findsOneWidget);
    expect(
      find.byKey(const Key('organization-tree-list-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('organization-tree-detail-panel')),
      findsOneWidget,
    );
    expect(find.text('Cơ cấu tổ chức'), findsOneWidget);
    expect(
      find.text('Quản lý cây tổ chức và quyền theo node.'),
      findsOneWidget,
    );
    expect(find.textContaining('Lv0-Lv5'), findsNothing);
    expect(find.text('Phong Vũ Quận 3'), findsWidgets);
    expect(find.text('Mã cửa hàng'), findsOneWidget);
    expect(find.byTooltip('Thêm node'), findsOneWidget);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);

    await tester.tap(find.byTooltip('Tải lại'));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Organization tree shows retryable error state', (tester) async {
    final repository = _FakeOrganizationRepository(
      nodes: [_storeNode],
      failCount: 1,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _FakeAuthProvider(_scopedAdmin),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: OrganizationTreeAdminScreen(repository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa tải được cơ cấu tổ chức.'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(find.text('Chưa tải được cơ cấu tổ chức.'), findsNothing);
    expect(find.text('Phong Vũ Quận 3'), findsWidgets);
    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Organization tree searches by business code abbreviation title',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeOrganizationRepository(
        nodes: [_domainNode, _q3Node, _goVapNode],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: _FakeAuthProvider(_superAdmin),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox.expand(
                child: OrganizationTreeAdminScreen(repository: repository),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final search = find.byKey(const Key('organization-tree-search-field'));
      expect(search, findsOneWidget);

      await tester.enterText(search, 'CP62');
      await tester.pumpAndSettle();

      expect(find.text('Đang hiển thị 2/3 node'), findsOneWidget);
      expect(find.text('Phong Vũ Quận 3'), findsWidgets);
      expect(find.text('Phong Vũ Gò Vấp'), findsNothing);
      expect(find.text('Mã cửa hàng'), findsOneWidget);

      await tester.enterText(search, 'PVQ3');
      await tester.pumpAndSettle();

      expect(find.text('Đang hiển thị 2/3 node'), findsOneWidget);
      expect(find.text('Phong Vũ Quận 3'), findsWidgets);

      await tester.enterText(search, 'quan 3');
      await tester.pumpAndSettle();

      expect(find.text('Đang hiển thị 2/3 node'), findsOneWidget);
      expect(find.text('Phong Vũ Quận 3'), findsWidgets);

      await tester.enterText(search, 'khong-co-node');
      await tester.pumpAndSettle();

      expect(find.text('Không tìm thấy node'), findsOneWidget);
      expect(
        find.byKey(const Key('organization-tree-detail-empty-state')),
        findsOneWidget,
      );
      expect(find.text('Chưa chọn node'), findsOneWidget);
      expect(find.text('Chọn node để xem chi tiết.'), findsOneWidget);
      expect(
        find.text('Thử mã nghiệp vụ, viết tắt hoặc tên node khác.'),
        findsNothing,
      );
      expect(find.text('Phong Vũ Quận 3'), findsNothing);

      await tester.tap(find.byTooltip('Xóa tìm kiếm'));
      await tester.pumpAndSettle();

      expect(find.text('Không tìm thấy node'), findsNothing);
      expect(
        find.byKey(const Key('organization-tree-detail-empty-state')),
        findsNothing,
      );
      expect(find.text('Phong Vũ'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}

const _superAdmin = User(
  id: 'super-1',
  email: 'super@phongvu.vn',
  name: 'Super Admin',
  role: 'SUPER_ADMIN',
  status: 'yes',
);

const _scopedAdmin = User(
  id: 'admin-1',
  email: 'admin@phongvu.vn',
  name: 'Admin cây tổ chức',
  role: 'ADMIN',
  status: 'yes',
  featureAccess: {'ADMIN_ORG_TREE': true},
);

const _storeNode = AdminOrganizationNode(
  id: 'store-1',
  code: 'CP62',
  title: 'Phong Vũ Quận 3',
  businessCode: 'CP62',
  type: 'LV4_STORE',
  level: 4,
  storeId: 'CP62',
  storeName: 'Phong Vũ Quận 3',
  userCount: 8,
  storeCount: 1,
  hasMapVietinPassword: true,
);

const _domainNode = AdminOrganizationNode(
  id: 'domain-1',
  code: 'PV',
  title: 'Phong Vũ',
  businessCode: 'PV',
  abbreviation: 'PV',
  type: 'LV0_DOMAIN',
  level: 0,
  childCount: 2,
  storeCount: 2,
);

const _q3Node = AdminOrganizationNode(
  id: 'store-q3',
  code: 'CP62',
  title: 'Phong Vũ Quận 3',
  businessCode: 'CP62',
  abbreviation: 'PVQ3',
  type: 'LV4_STORE',
  level: 4,
  parentId: 'domain-1',
  storeId: 'CP62',
  storeName: 'Phong Vũ Quận 3',
  userCount: 8,
  storeCount: 1,
  hasMapVietinPassword: true,
);

const _goVapNode = AdminOrganizationNode(
  id: 'store-gv',
  code: 'CP01',
  title: 'Phong Vũ Gò Vấp',
  businessCode: 'CP01',
  abbreviation: 'PVGV',
  type: 'LV4_STORE',
  level: 4,
  parentId: 'domain-1',
  storeId: 'CP01',
  storeName: 'Phong Vũ Gò Vấp',
  userCount: 5,
  storeCount: 1,
);

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

class _FakeOrganizationRepository extends AuthRepository {
  _FakeOrganizationRepository({required this.nodes, this.failCount = 0})
    : super(ApiClient());

  final List<AdminOrganizationNode> nodes;
  final int failCount;
  int loadCount = 0;

  @override
  Future<List<AdminOrganizationNode>> listAdminOrganizationTree() async {
    loadCount += 1;
    if (loadCount <= failCount) {
      throw Exception('Không tải được dữ liệu kiểm thử');
    }
    return nodes;
  }
}
