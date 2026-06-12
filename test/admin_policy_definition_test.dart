import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_policy_definition.dart';

void main() {
  test('AdminPolicyRule parses and writes detailed selectors', () {
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
      'storeCode': 'CP62',
      'userId': 'user-1',
      'scopeContains': 'CP',
      'note': 'temporary block',
    });

    expect(rule.policyCode, 'FIFO');
    expect(rule.allowed, isFalse);
    expect(rule.scopeContains, 'CP');
    expect(rule.toJson(), containsPair('emailDomain', 'acare.vn'));
    expect(rule.toJson(), containsPair('scopeContains', 'CP'));
  });

  test('AdminPolicyRuleBatchRequest writes multi-select selectors', () {
    final request = AdminPolicyRuleBatchRequest(
      policyCode: 'FIFO',
      allowed: false,
      emailDomains: const ['acare.vn'],
      systemRoles: const ['STAFF'],
      departmentCodes: const ['SALES', 'TECHNICAL'],
      regionCodes: const ['MIEN_NAM'],
      areaCodes: const ['HCM'],
      storeCodes: const ['CP62'],
      userIds: const ['user-1', 'user-2'],
      scopeContainsValues: const ['CP'],
      note: 'temporary block',
    );

    final json = request.toJson();
    expect(json['departmentCodes'], ['SALES', 'TECHNICAL']);
    expect(json['userIds'], ['user-1', 'user-2']);
    expect(json['scopeContainsValues'], ['CP']);
  });

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