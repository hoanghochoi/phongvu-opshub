import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/widgets/gradient_header.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_organization_node.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_policy_definition.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/policy_admin_screen.dart';
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

  testWidgets('Policy admin renders content-only workspace and tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakePolicyRepository();

    await tester.pumpWidget(
      MaterialApp(home: PolicyAdminScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('policy-admin-header')), findsOneWidget);
    expect(find.byKey(const Key('policy-admin-tabs')), findsOneWidget);
    expect(find.byKey(const Key('policy-admin-policy-list')), findsOneWidget);
    expect(find.text('Quản lý chính sách'), findsOneWidget);
    expect(find.text('1 chính sách'), findsOneWidget);
    expect(find.text('1 quy tắc'), findsWidgets);
    expect(find.text('1 cấu hình'), findsOneWidget);
    expect(find.text('Quản trị theo phạm vi'), findsOneWidget);
    expect(find.textContaining('ADMIN_USERS'), findsNothing);
    expect(find.byType(GradientHeader), findsNothing);
    expect(find.byType(Scaffold), findsNothing);

    await tester.tap(find.text('Quy tắc'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('policy-admin-rule-list')), findsOneWidget);
    expect(
      find.textContaining('Node tổ chức: Phong Vũ Quận 3'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cấu hình'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('policy-admin-setting-list')), findsOneWidget);
    expect(find.text('Tên miền email được phép'), findsOneWidget);

    await tester.tap(find.byTooltip('Tải lại chính sách'));
    await tester.pumpAndSettle();

    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Policy admin shows retryable error state', (tester) async {
    final repository = _FakePolicyRepository(failCount: 1);

    await tester.pumpWidget(
      MaterialApp(home: PolicyAdminScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa tải được quản lý chính sách.'), findsOneWidget);
    expect(find.text('Thử tải lại'), findsOneWidget);

    await tester.tap(find.text('Thử tải lại'));
    await tester.pumpAndSettle();

    expect(find.text('Chưa tải được quản lý chính sách.'), findsNothing);
    expect(find.text('Quản trị theo phạm vi'), findsOneWidget);
    expect(repository.loadCount, 2);
    expect(tester.takeException(), isNull);
  });
}

class _FakePolicyRepository extends AuthRepository {
  _FakePolicyRepository({this.failCount = 0}) : super(ApiClient());

  final int failCount;
  int loadCount = 0;

  @override
  Future<List<AdminPolicyDefinition>> listAdminPolicies() async {
    loadCount += 1;
    if (loadCount <= failCount) {
      throw Exception('Không tải được dữ liệu kiểm thử');
    }
    return const [_policy];
  }

  @override
  Future<List<AdminPolicyRule>> listAdminPolicyRules({
    String? policyCode,
  }) async {
    return const [_rule];
  }

  @override
  Future<List<AdminSettingDefinition>> listAdminSettings() async {
    return const [_setting];
  }

  @override
  Future<List<AdminOrganizationNode>> listAdminPolicyScopeTree() async {
    return const [_scopeNode];
  }
}

const _policy = AdminPolicyDefinition(
  code: 'ADMIN_USERS',
  title: 'Quản trị theo phạm vi',
  description: 'Điều khiển quyền quản trị theo cây tổ chức.',
  category: 'ADMIN',
  defaultAllowed: false,
  isSystem: false,
  ruleCount: 1,
);

const _rule = AdminPolicyRule(
  id: 'rule-1',
  policyCode: 'ADMIN_USERS',
  allowed: true,
  organizationNodeId: 'store-1',
  organizationNodeName: 'Phong Vũ Quận 3',
  note: 'Kiểm thử',
);

const _setting = AdminSettingDefinition(
  key: 'auth.allowedEmailDomains',
  title: 'Tên miền email được phép',
  description: 'Danh sách miền email nội bộ.',
  value: ['phongvu.vn'],
);

const _scopeNode = AdminOrganizationNode(
  id: 'store-1',
  code: 'CP62',
  title: 'Phong Vũ Quận 3',
  businessCode: 'CP62',
  type: 'LV4_STORE',
  level: 4,
);
