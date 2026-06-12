import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_feature_definition.dart';

void main() {
  test('AdminFeatureRule parses and writes email domain', () {
    final rule = AdminFeatureRule.fromJson({
      'id': 'rule-1',
      'featureCode': 'ADMIN_FEATURES',
      'enabled': true,
      'emailDomain': 'acare.vn',
    });

    expect(rule.emailDomain, 'acare.vn');
    expect(rule.toJson()['emailDomain'], 'acare.vn');
  });

  test('AdminFeatureRuleBatchRequest writes email domains', () {
    final request = AdminFeatureRuleBatchRequest(
      featureCode: 'ADMIN_FEATURES',
      enabled: false,
      emailDomains: const ['acare.vn', 'phongvu.vn'],
    );

    expect(request.toJson()['emailDomains'], ['acare.vn', 'phongvu.vn']);
  });
}
