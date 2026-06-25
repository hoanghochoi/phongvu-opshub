import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/admin/domain/admin_personnel_definition.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';

void main() {
  test('User parses personnel fields and backend feature access', () {
    final user = User.fromJson({
      'email': 'sale@phongvu.vn',
      'role': 'STAFF',
      'departmentCode': 'SALES',
      'jobRoleCode': 'SALE',
      'workScopeType': 'STORE',
      'personnelCode': 'SALE_CP62_HCM_MN',
      'mustSelectStore': false,
      'storeId': 'CP62',
      'areaCode': 'HCM',
      'regionCode': 'MIEN_NAM',
      'resolvedFeatureAccess': {'FIFO': true},
    });

    expect(user.departmentCode, 'SALES');
    expect(user.jobRoleCode, 'SALE');
    expect(user.workScopeType, 'STORE');
    expect(user.personnelCode, 'SALE_CP62_HCM_MN');
    expect(user.areaCode, 'HCM');
    expect(user.regionCode, 'MIEN_NAM');
    expect(user.needsStoreSelection, isFalse);
    expect(user.belongsToCp62, isTrue);
    expect(user.canUseCp62RestrictedFlows, isTrue);
  });

  test('User does not require store selection for Chatsale region scope', () {
    final user = User.fromJson({
      'email': 'online@phongvu.vn',
      'role': 'STAFF',
      'jobRoleCode': 'CHATSALE',
      'workScopeType': 'REGION',
      'regionCode': 'CHATSALE',
      'regionAbbreviation': 'CHATSALE',
      'personnelCode': 'CHATSALE_CHATSALE_CHATSALE_CHATSALE',
      'mustSelectStore': false,
    });

    expect(user.needsStoreSelection, isFalse);
    expect(user.belongsToCp62, isFalse);
    expect(user.canUseCp62RestrictedFlows, isFalse);
  });

  test('User treats ADMIN_ACARE as admin scoped role with resolved access', () {
    final user = User.fromJson({
      'email': 'admin@acare.vn',
      'role': 'ADMIN_ACARE',
      'resolvedFeatureAccess': {
        'ADMIN': true,
        'ADMIN_USERS': true,
        'ADMIN_ORG_TREE': true,
        'FIFO_IMPORT': true,
        'ADMIN_FEATURES': false,
      },
      'resolvedAdminPolicies': {'ADMIN': true, 'ADMIN_POLICIES': false},
    });

    expect(user.isAdmin, isTrue);
    expect(user.needsStoreSelection, isFalse);
    expect(user.needsOrganizationAssignment, isFalse);
    expect(user.hasNationalWorkScope, isTrue);
    expect(user.canUseFeature('ADMIN_USERS'), isTrue);
    expect(user.canUseFeature('ADMIN_ORG_TREE'), isTrue);
    expect(user.canUseFeature('FIFO_IMPORT'), isTrue);
    expect(user.canUseFeature('ADMIN_FEATURES'), isFalse);
    expect(user.canUsePolicy('ADMIN'), isTrue);
    expect(user.canUsePolicy('ADMIN_POLICIES'), isFalse);
  });

  test('User exposes pending organization assignment from auth response', () {
    final pendingUser = User.fromJson({
      'email': 'new@phongvu.vn',
      'role': 'USER',
      'assignmentPending': true,
      'mustSelectStore': false,
    });
    final assignedUser = User.fromJson({
      'email': 'assigned@phongvu.vn',
      'role': 'USER',
      'organizationNodeId': 'org-store-cp62',
      'assignmentPending': false,
      'mustSelectStore': false,
    });

    expect(pendingUser.needsStoreSelection, isFalse);
    expect(pendingUser.needsOrganizationAssignment, isTrue);
    expect(assignedUser.needsOrganizationAssignment, isFalse);
  });

  test('Scope definitions do not expose legacy ONLINE or MULTI_STORE', () {
    final values = AdminWorkScopes.definitions.map((scope) => scope.value);

    expect(values, containsAll(['NATIONAL', 'REGION', 'AREA', 'STORE']));
    expect(values, isNot(contains('ONLINE')));
    expect(values, isNot(contains('MULTI_STORE')));
  });

  test(
    'User does not infer FIFO access from CP62 scope without backend map',
    () {
      final user = User.fromJson({
        'email': 'staff@phongvu.vn',
        'role': 'STAFF',
        'storeName': 'Showroom CP62',
      });

      expect(user.belongsToCp62, isTrue);
      expect(user.canUseCp62RestrictedFlows, isFalse);
    },
  );

  test('User allows super admin through CP62 restricted flows', () {
    final user = User.fromJson({
      'email': 'super@phongvu.vn',
      'role': 'SUPER_ADMIN',
      'personnelCode': 'OPS_NATIONAL',
      'resolvedFeatureAccess': {'FIFO': false, 'ADMIN': false},
      'resolvedAdminPolicies': {'ADMIN_POLICIES': false},
    });

    expect(user.belongsToCp62, isFalse);
    expect(user.isAdmin, isTrue);
    expect(user.isSuperAdmin, isTrue);
    expect(user.canUseCp62RestrictedFlows, isTrue);
    expect(user.canUsePolicy('ADMIN_POLICIES'), isTrue);
  });

  test('User treats bank statement all-scope policy as statement access', () {
    final user = User.fromJson({
      'email': 'finance@phongvu.vn',
      'role': 'USER',
      'workScopeType': 'STORE',
      'organizationNodeId': 'org-finance-accounting',
      'resolvedFeatureAccess': {'BANK_STATEMENTS': false},
      'resolvedAdminPolicies': {'BANK_STATEMENT_ALL_SCOPE': true},
    });

    expect(user.hasNationalWorkScope, isFalse);
    expect(user.canUseFeature('BANK_STATEMENTS'), isFalse);
    expect(user.canUseBankStatements, isTrue);
    expect(user.canUseAllBankStatementStores, isTrue);
  });

  test('User does not infer all-showroom statement scope from admin role', () {
    final user = User.fromJson({
      'email': 'manager@phongvu.vn',
      'role': 'MANAGER',
      'storeId': 'CP01',
      'workScopeType': 'STORE',
      'resolvedFeatureAccess': {'BANK_STATEMENTS': true},
      'resolvedAdminPolicies': {'BANK_STATEMENT_ALL_SCOPE': false},
    });

    expect(user.hasNationalWorkScope, isTrue);
    expect(user.canUseBankStatements, isTrue);
    expect(user.canUseAllBankStatementStores, isFalse);
  });
}
