import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_router.dart';
import 'package:phongvu_opshub/core/network/api_client.dart';
import 'package:phongvu_opshub/features/auth/data/repositories/auth_repository.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';
import 'package:phongvu_opshub/features/auth/presentation/providers/auth_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/payment_speaker.dart';
import 'package:phongvu_opshub/features/payment_monitor/data/repositories/payment_monitor_repository.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/providers/payment_monitor_provider.dart';
import 'package:phongvu_opshub/features/payment_monitor/presentation/screens/payment_monitor_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('admin feature management route requires matching feature access', () {
    const featureAdmin = User(
      email: 'feature-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_FEATURES': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(AppRouter.canUseRouteForTesting(featureAdmin, '/admin'), isTrue);
    expect(
      AppRouter.canUseRouteForTesting(featureAdmin, '/admin/features'),
      isTrue,
    );

    expect(AppRouter.canUseRouteForTesting(staff, '/admin'), isFalse);
    expect(AppRouter.canUseRouteForTesting(staff, '/admin/features'), isFalse);
  });

  test('personnel catalog route requires ADMIN_PERSONNEL access', () {
    const personnelAdmin = User(
      email: 'personnel-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_PERSONNEL': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(AppRouter.canUseRouteForTesting(personnelAdmin, '/admin'), isTrue);
    expect(
      AppRouter.canUseRouteForTesting(personnelAdmin, '/admin/personnel'),
      isTrue,
    );
    expect(AppRouter.canUseRouteForTesting(staff, '/admin/personnel'), isFalse);
  });

  test('sales target route requires ADMIN_SALES_TARGETS access', () {
    const targetAdmin = User(
      email: 'target-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-area',
      featureAccess: {'ADMIN_SALES_TARGETS': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(AppRouter.canUseRouteForTesting(targetAdmin, '/admin'), isTrue);
    expect(
      AppRouter.canUseRouteForTesting(targetAdmin, '/admin/sales-targets'),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(staff, '/admin/sales-targets'),
      isFalse,
    );
  });

  test('quick action code route requires both manager title and feature', () {
    const manager = User(
      email: 'manager@phongvu.vn',
      role: 'USER',
      jobRoleCode: 'STORE_MANAGER',
      organizationNodeId: 'org-store',
      featureAccess: {'ADMIN_QUICK_ACTION_CODES': true},
    );
    const regularStaff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      jobRoleCode: 'SALES_STAFF',
      organizationNodeId: 'org-store',
      featureAccess: {'ADMIN_QUICK_ACTION_CODES': true},
    );

    expect(
      AppRouter.canUseRouteForTesting(manager, '/admin/quick-action-links'),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(
        regularStaff,
        '/admin/quick-action-links',
      ),
      isFalse,
    );
  });

  test('sales report routes separate staff and admin permissions', () {
    const salesUser = User(
      email: 'sales@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'SALES_REPORT': true},
    );
    const salesAdmin = User(
      email: 'sales-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_SALES_REPORTS': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(AppRouter.canUseRouteForTesting(salesUser, '/reports'), isTrue);
    expect(
      AppRouter.canUseRouteForTesting(salesUser, '/sales-reports'),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(
        salesUser,
        '/sales-reports/follow-up-cases',
      ),
      isTrue,
    );
    expect(AppRouter.canUseRouteForTesting(salesAdmin, '/reports'), isFalse);
    expect(AppRouter.canUseRouteForTesting(salesAdmin, '/admin'), isTrue);
    expect(
      AppRouter.canUseRouteForTesting(salesAdmin, '/admin/sales-reports'),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(
        salesAdmin,
        '/sales-reports/follow-up-cases',
      ),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(staff, '/sales-reports/follow-up-cases'),
      isFalse,
    );
    expect(AppRouter.canUseRouteForTesting(staff, '/reports'), isFalse);
  });

  test('bank statement query route still requires statement access', () {
    const statementUser = User(
      email: 'statement@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'BANK_STATEMENTS': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(
      AppRouter.canUseRouteForTesting(
        statementUser,
        '/bank-statement?orderStatus=MISSING_ORDER&autoSearch=true',
      ),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(
        staff,
        '/bank-statement?orderStatus=MISSING_ORDER&autoSearch=true',
      ),
      isFalse,
    );
  });

  test('warranty detail route requires WARRANTY access', () {
    const warrantyUser = User(
      email: 'warranty@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'WARRANTY': true},
    );
    const staff = User(
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store',
      featureAccess: {'FIFO': true},
    );

    expect(
      AppRouter.canUseRouteForTesting(
        warrantyUser,
        '/check-warranty/details/CP01-J12345678',
      ),
      isTrue,
    );
    expect(
      AppRouter.canUseRouteForTesting(
        staff,
        '/check-warranty/details/CP01-J12345678',
      ),
      isFalse,
    );
  });

  testWidgets('payment monitor route renders list screen on web', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(AuthRepository(ApiClient())),
          ),
          ChangeNotifierProvider(
            create: (_) => PaymentMonitorProvider(
              PaymentMonitorRepository(ApiClient()),
              PaymentSpeaker(),
            ),
          ),
        ],
        child: MaterialApp(
          home: AppRouter.buildPaymentMonitorRoute(isWeb: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(PaymentMonitorScreen), findsOneWidget);
    expect(find.text('Giao dịch tiền vào'), findsOneWidget);
    expect(find.text('Chưa hỗ trợ trên web'), findsNothing);
  });
}
