import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_organization_node.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_user_editor_payload.dart';
import 'package:phongvu_opshub/features/admin/presentation/screens/user_admin_screen.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';

void main() {
  test(
    'AuthRepository loads user scope tree from ADMIN_USERS endpoint',
    () async {
      final paths = <String>[];
      final repository = AuthRepository(
        ApiClient.test(
          MockClient((http.Request request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode([
                {
                  'id': 'org-domain-phongvu-vn',
                  'code': 'DOMAIN_PHONGVU_VN',
                  'displayName': 'phongvu.vn',
                  'type': 'ROOT_DOMAIN',
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final nodes = await repository.listAdminUserScopeTree();

      expect(paths.single, endsWith('/admin/users/scope-tree'));
      expect(nodes.single.id, 'org-domain-phongvu-vn');
      expect(nodes.single.type, 'ROOT_DOMAIN');
    },
  );

  test('Admin user editor payload sends tree-only scope input', () {
    final body = AdminUserEditorPayload.build(
      email: ' staff@phongvu.vn ',
      firstName: ' An ',
      lastName: ' Nguyen ',
      status: 'yes',
      role: 'STAFF',
      departmentCode: 'SALES',
      jobRoleCode: 'SALE',
      workScopeType: 'STORE',
      organizationNodeId: 'org-store-cp62',
      canEditRole: true,
      canEditFeatures: true,
      featureTreeCodes: const ['FIFO', 'ADMIN_USERS'],
    );

    expect(body['email'], 'staff@phongvu.vn');
    expect(body['firstName'], 'An');
    expect(body['lastName'], 'Nguyen');
    expect(body['workScopeType'], 'STORE');
    expect(body['organizationNodeId'], 'org-store-cp62');
    expect(body['featureTreeCodes'], ['FIFO', 'ADMIN_USERS']);
    expect(body, isNot(contains('featureCodes')));
    expect(body, isNot(contains('storeId')));
    expect(body, isNot(contains('regionCode')));
    expect(body, isNot(contains('areaCode')));
  });

  test(
    'AdminOrganizationNode payload only sends showroom fields for showroom nodes',
    () {
      const region = AdminOrganizationNode(
        id: '',
        code: 'HCM-BD',
        title: 'Ho Chi Minh - Binh Duong',
        businessCode: 'HCM-BD',
        type: 'REGION',
        parentId: 'org-block-sales',
        storeId: 'HCM-BD',
        storeName: 'Ho Chi Minh - Binh Duong',
      );
      final regionJson = region.toJson();

      expect(regionJson['businessCode'], 'HCM-BD');
      expect(regionJson['parentId'], 'org-block-sales');
      expect(regionJson, isNot(contains('storeId')));
      expect(regionJson, isNot(contains('storeName')));

      const showroom = AdminOrganizationNode(
        id: '',
        code: 'STORE_CP62',
        title: 'CP62',
        businessCode: 'CP62',
        type: 'SHOWROOM',
        parentId: 'org-area-hcm',
        storeId: 'CP62',
        storeName: 'CP62',
      );
      expect(showroom.toJson(), containsPair('storeId', 'CP62'));
      expect(showroom.toJson(), containsPair('storeName', 'CP62'));
    },
  );

  test(
    'Admin user editor snackbar message keeps backend ApiException text',
    () {
      expect(
        adminUserSaveErrorMessage(ApiException('Vui lòng chọn showroom')),
        'Vui lòng chọn showroom',
      );
      expect(
        adminUserSaveErrorMessage(StateError('boom')),
        'Không lưu được người dùng',
      );
    },
  );
}
