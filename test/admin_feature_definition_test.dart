import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_feature_definition.dart';

void main() {
  test('AdminFeatureRule parses and writes email domain', () {
    final rule = AdminFeatureRule.fromJson({
      'id': 'rule-1',
      'featureCode': 'ADMIN_FEATURES',
      'enabled': true,
      'emailDomain': 'acaretek.vn',
    });

    expect(rule.emailDomain, 'acaretek.vn');
    expect(rule.toJson()['emailDomain'], 'acaretek.vn');
  });

  test('AdminFeatureRuleBatchRequest writes email domains', () {
    final request = AdminFeatureRuleBatchRequest(
      featureCode: 'ADMIN_FEATURES',
      enabled: false,
      emailDomains: const ['acaretek.vn', 'phongvu.vn'],
    );

    expect(request.toJson()['emailDomains'], ['acaretek.vn', 'phongvu.vn']);
  });
}
