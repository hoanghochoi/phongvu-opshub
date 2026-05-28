import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';

void main() {
  test('User parses personnel fields and store scope selection state', () {
    final user = User.fromJson({
      'email': 'sale@phongvu.vn',
      'role': 'STAFF',
      'departmentCode': 'SALES',
      'jobRoleCode': 'SALE',
      'workScopeType': 'STORE',
      'personnelCode': 'SALE_CP62',
      'mustSelectStore': false,
      'storeId': 'CP62',
    });

    expect(user.departmentCode, 'SALES');
    expect(user.jobRoleCode, 'SALE');
    expect(user.workScopeType, 'STORE');
    expect(user.personnelCode, 'SALE_CP62');
    expect(user.needsStoreSelection, isFalse);
    expect(user.belongsToCp62, isTrue);
    expect(user.canUseCp62RestrictedFlows, isTrue);
  });

  test('User does not require store selection for online personnel scope', () {
    final user = User.fromJson({
      'email': 'online@phongvu.vn',
      'role': 'STAFF',
      'jobRoleCode': 'SALE_ONLINE',
      'workScopeType': 'ONLINE',
      'personnelCode': 'SALE_ONLINE',
      'mustSelectStore': false,
    });

    expect(user.needsStoreSelection, isFalse);
    expect(user.belongsToCp62, isFalse);
    expect(user.canUseCp62RestrictedFlows, isFalse);
  });

  test('User treats CP62 store name as CP62 scope', () {
    final user = User.fromJson({
      'email': 'staff@phongvu.vn',
      'role': 'STAFF',
      'storeName': 'Showroom CP62',
    });

    expect(user.belongsToCp62, isTrue);
    expect(user.canUseCp62RestrictedFlows, isTrue);
  });

  test('User allows super admin through CP62 restricted flows', () {
    final user = User.fromJson({
      'email': 'super@phongvu.vn',
      'role': 'SUPER_ADMIN',
      'personnelCode': 'OPS_NATIONAL',
    });

    expect(user.belongsToCp62, isFalse);
    expect(user.canUseCp62RestrictedFlows, isTrue);
  });
}
