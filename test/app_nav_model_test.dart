import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_nav_model.dart';
import 'package:phongvu_opshub/features/auth/domain/entities/user.dart';

void main() {
  test('admin sales report access shows Báo cáo without Quản trị', () {
    const user = User(
      id: 'lead-1',
      email: 'lead@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-area-hcm',
      featureAccess: {'ADMIN_SALES_REPORTS': true},
    );

    final taskLabels = AppNavModel.visibleTaskDestinations(
      user,
    ).map((destination) => destination.label);
    final sidebarLabels = AppNavModel.visibleSidebarDestinations(
      user,
    ).map((destination) => destination.label);

    expect(taskLabels, contains('Báo cáo'));
    expect(sidebarLabels, contains('Báo cáo'));
    expect(taskLabels, isNot(contains('Quản trị')));
    expect(sidebarLabels, isNot(contains('Quản trị')));

    final salesDestination = AppNavModel.visibleTaskDestinations(
      user,
    ).singleWhere((destination) => destination.id == 'sales');
    expect(salesDestination.route, '/reports');
  });

  test('scoped staff only sees allowed workspaces', () {
    const user = User(
      id: 'staff-1',
      email: 'staff@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store-cp01',
      featureAccess: {'FIFO': true, 'WARRANTY': true, 'FEEDBACK': true},
    );

    final taskLabels = AppNavModel.visibleTaskDestinations(
      user,
    ).map((destination) => destination.label).toList(growable: false);

    expect(taskLabels, containsAll(['FIFO', 'BH / SC', 'Góp ý']));
    expect(taskLabels, isNot(contains('Sắp xếp')));
    expect(taskLabels, isNot(contains('VietQR')));
    expect(taskLabels, isNot(contains('Tiền vào')));
    expect(taskLabels, isNot(contains('Sao kê')));
  });

  test('sort route stays inside the FIFO workspace', () {
    final destination = AppNavModel.destinationForLocation('/sort');

    expect(destination?.id, 'fifo');
    expect(destination?.label, 'FIFO');
  });

  test('admin sales report route stays inside Báo cáo workspace', () {
    final destination = AppNavModel.destinationForLocation(
      '/admin/sales-reports',
    );

    expect(destination?.id, 'sales');
    expect(destination?.label, 'Báo cáo');
  });

  test('generic report route selects Báo cáo workspace', () {
    final destination = AppNavModel.destinationForLocation('/reports');

    expect(destination?.id, 'sales');
    expect(destination?.label, 'Báo cáo');
  });

  test('personnel catalog access makes Admin workspace visible', () {
    const user = User(
      id: 'personnel-admin',
      email: 'personnel-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_PERSONNEL': true},
    );

    final taskLabels = AppNavModel.visibleTaskDestinations(
      user,
    ).map((destination) => destination.label);
    final sidebarLabels = AppNavModel.visibleSidebarDestinations(
      user,
    ).map((destination) => destination.label);

    expect(taskLabels, contains('Quản trị'));
    expect(sidebarLabels, contains('Quản trị'));
  });
}
