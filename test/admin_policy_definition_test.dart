import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_policy_definition.dart';

void main() {
  test(
    'AdminPolicyRule parses legacy selectors but writes node-only payload',
    () {
      final rule = AdminPolicyRule.fromJson({
        'id': 'rule-1',
        'policyCode': 'FIFO',
        'allowed': false,
        'emailDomain': 'acare.vn',
        'systemRole': 'STAFF',
        'departmentCode': 'SALES',
        'jobRoleCode': 'SALE',
        'workScopeType': 'STORE',
        'regionCode': 'MIEN_NAM',
        'areaCode': 'HCM',
        'organizationNodeId': 'org-store-cp62',
        'storeCode': 'CP62',
        'userId': 'user-1',
        'scopeContains': 'CP',
        'note': 'temporary block',
      });

      expect(rule.policyCode, 'FIFO');
      expect(rule.allowed, isFalse);
      expect(rule.scopeContains, 'CP');
      final json = rule.toJson();
      expect(json, containsPair('emailDomain', 'acare.vn'));
      expect(json, containsPair('organizationNodeId', 'org-store-cp62'));
      expect(json, isNot(contains('departmentCode')));
      expect(json, isNot(contains('jobRoleCode')));
      expect(json, isNot(contains('workScopeType')));
      expect(json, isNot(contains('regionCode')));
      expect(json, isNot(contains('areaCode')));
      expect(json, isNot(contains('storeCode')));
      expect(json, isNot(contains('userId')));
      expect(json, isNot(contains('scopeContains')));
    },
  );

  test(
    'AdminPolicyRuleBatchRequest writes tree-only organization selectors',
    () {
      final request = AdminPolicyRuleBatchRequest(
        policyCode: 'FIFO',
        allowed: false,
        emailDomains: const ['acare.vn'],
        systemRoles: const ['STAFF'],
        organizationNodeIds: const ['org-store-cp62'],
        note: 'temporary block',
      );

      final json = request.toJson();
      expect(json['organizationNodeIds'], ['org-store-cp62']);
      expect(json, isNot(contains('departmentCodes')));
      expect(json, isNot(contains('jobRoleCodes')));
      expect(json, isNot(contains('workScopeTypes')));
      expect(json, isNot(contains('regionCodes')));
      expect(json, isNot(contains('areaCodes')));
      expect(json, isNot(contains('storeCodes')));
      expect(json, isNot(contains('userIds')));
      expect(json, isNot(contains('scopeContainsValues')));
    },
  );

  test('AdminSettingDefinition parses and writes configurable values', () {
    final setting = AdminSettingDefinition.fromJson({
      'key': 'AUTH_ALLOWED_EMAIL_DOMAINS',
      'displayName': 'Domain dang nhap',
      'description': 'Allowed domains',
      'category': 'AUTH',
      'value': ['phongvu.vn', 'acare.vn'],
      'isSystem': true,
    });

    expect(setting.key, 'AUTH_ALLOWED_EMAIL_DOMAINS');
    expect(setting.value, ['phongvu.vn', 'acare.vn']);
    expect(setting.toJson()['value'], ['phongvu.vn', 'acare.vn']);
  });
}
