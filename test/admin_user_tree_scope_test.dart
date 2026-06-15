import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/core/network/api_exception.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_feature_definition.dart';
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
      expect(nodes.single.type, 'LV0_DOMAIN');
    },
  );

  test(
    'AuthRepository manages node feature assignments through admin endpoints',
    () async {
      final calls = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final repository = AuthRepository(
        ApiClient.test(
          MockClient((http.Request request) async {
            calls.add('${request.method} ${request.url.path}');
            if (request.method == 'GET') {
              expect(request.url.queryParameters['featureCode'], 'FIFO');
              return http.Response(
                jsonEncode([
                  {
                    'id': 'assign-1',
                    'scopeRootNodeId': 'org-domain',
                    'scopeRootNodeName': 'phongvu.vn',
                    'nodeType': 'LV5_POSITION',
                    'nodeKey': 'SA',
                    'featureCode': 'FIFO',
                    'featureName': 'FIFO',
                    'enabled': true,
                    'organizationNodeIds': ['org-pos-sa'],
                    'impactedUserCount': 3,
                  },
                ]),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(
              jsonEncode([]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );

      final assignments = await repository.listAdminFeatureNodeAssignments(
        featureCode: 'FIFO',
      );
      await repository.saveAdminFeatureNodeAssignments(
        const AdminNodeFeatureAssignmentBatchRequest(
          organizationNodeIds: ['org-pos-sa'],
          featureTreeCodes: ['FIFO'],
          replaceExisting: true,
        ),
      );

      expect(assignments.single.impactedUserCount, 3);
      expect(calls, [
        'GET /api/admin/features/node-assignments',
        'POST /api/admin/features/node-assignments/batch',
      ]);
      expect(bodies.single['organizationNodeIds'], ['org-pos-sa']);
      expect(bodies.single['featureTreeCodes'], ['FIFO']);
      expect(bodies.single['replaceExisting'], true);
    },
  );

  test('Admin user import result parses summary and per-row results', () {
    final result = AdminUserImportResult.fromJson({
      'totalRows': 2,
      'createdRows': 1,
      'updatedRows': 1,
      'skippedRows': 0,
      'results': [
        {
          'rowNumber': 2,
          'email': 'new@phongvu.vn',
          'action': 'created',
          'role': 'USER',
          'organizationNodeId': 'org-pos-sa',
          'organizationNodeName': 'Nhân viên Bán hàng',
          'personnelCode': 'SA_CP62_HCM_MN',
        },
      ],
    });

    expect(result.totalRows, 2);
    expect(result.createdRows, 1);
    expect(result.updatedRows, 1);
    expect(result.results.single.email, 'new@phongvu.vn');
    expect(result.results.single.personnelCode, 'SA_CP62_HCM_MN');
  });

  test('Admin user editor payload sends tree-only scope input', () {
    final body = AdminUserEditorPayload.build(
      email: ' staff@phongvu.vn ',
      firstName: ' An ',
      lastName: ' Nguyen ',
      status: 'yes',
      role: 'USER',
      organizationNodeId: 'org-store-cp62',
      canEditRole: true,
    );

    expect(body['email'], 'staff@phongvu.vn');
    expect(body['firstName'], 'An');
    expect(body['lastName'], 'Nguyen');
    expect(body['organizationNodeId'], 'org-store-cp62');
    expect(body, isNot(contains('featureTreeCodes')));
    expect(body, isNot(contains('featureCodes')));
    expect(body, isNot(contains('departmentCode')));
    expect(body, isNot(contains('jobRoleCode')));
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
        type: 'LV2_REGION',
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
        type: 'LV4_STORE',
        parentId: 'org-area-hcm',
        storeId: 'CP62',
        storeName: 'CP62',
      );
      expect(showroom.toJson(), containsPair('storeId', 'CP62'));
      expect(showroom.toJson(), containsPair('storeName', 'CP62'));
    },
  );

  test('AdminOrganizationNodeTypes exposes the full Lv0-Lv5 tree', () {
    final types = AdminOrganizationNodeTypes.definitions
        .map((definition) => definition.$1)
        .toList();

    expect(
      types,
      containsAllInOrder([
        'LV0_DOMAIN',
        'LV1_BLOCK',
        'LV2_DEPARTMENT',
        'LV2_REGION',
        'LV3_AREA',
        'LV3_UNIT',
        'LV4_STORE',
        'LV5_POSITION',
      ]),
    );
    expect(AdminOrganizationNodeTypes.titleOf('BLOCK'), 'Lv1 Khối');
    expect(AdminOrganizationNodeTypes.titleOf('REGION'), 'Lv2 Miền');
    expect(AdminOrganizationNodeTypes.titleOf('AREA'), 'Lv3 Vùng');
  });

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
