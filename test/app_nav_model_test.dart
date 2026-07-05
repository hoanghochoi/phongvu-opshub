import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/navigation/app_nav_model.dart';
import 'package:phongvu_opshub/core/platform/app_platform_capabilities.dart';
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

    final workspaceLabels = AppNavModel.visibleWorkspaceDestinations(
      user,
    ).map((destination) => destination.label);
    final sidebarLabels = AppNavModel.visibleSidebarDestinations(
      user,
    ).map((destination) => destination.label);

    expect(workspaceLabels, contains('Báo cáo'));
    expect(sidebarLabels, contains('Báo cáo'));
    expect(workspaceLabels, isNot(contains('Quản trị')));
    expect(sidebarLabels, isNot(contains('Quản trị')));

    final salesDestination = AppNavModel.visibleWorkspaceDestinations(
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

    final workspaceLabels = AppNavModel.visibleWorkspaceDestinations(
      user,
    ).map((destination) => destination.label).toList(growable: false);
    final sidebarLabels = AppNavModel.visibleSidebarDestinations(
      user,
    ).map((destination) => destination.label).toList(growable: false);

    expect(
      workspaceLabels,
      containsAll(['Kiểm tra FIFO', 'Sắp xếp FIFO', 'Bảo hành']),
    );
    expect(workspaceLabels, isNot(contains('Góp ý')));
    expect(workspaceLabels, isNot(contains('Sắp xếp')));
    expect(workspaceLabels, isNot(contains('VietQR')));
    expect(workspaceLabels, isNot(contains('Tiền vào')));
    expect(workspaceLabels, isNot(contains('Sao kê')));
    expect(
      sidebarLabels,
      containsAll(['Vận hành', 'Quản trị', 'Cài đặt', 'Góp ý', 'Hướng dẫn']),
    );
  });

  test(
    'mobile navigation shows Home, Operations, notifications and account',
    () {
      const user = User(
        id: 'staff-1',
        email: 'staff@phongvu.vn',
        role: 'USER',
        organizationNodeId: 'org-store-cp01',
        featureAccess: {'FIFO': true, 'WARRANTY': true, 'FEEDBACK': true},
      );

      final mobileLabels = AppNavModel.visibleMobileDestinations(
        user,
      ).map((destination) => destination.label).toList(growable: false);
      final sidebarLabels = AppNavModel.visibleSidebarDestinations(
        user,
      ).map((destination) => destination.label).toList(growable: false);

      expect(mobileLabels, ['Trang chủ', 'Vận hành', 'Thông báo', 'Tài khoản']);
      expect(sidebarLabels, contains('Vận hành'));
      expect(sidebarLabels, contains('Hướng dẫn'));
      expect(mobileLabels, isNot(contains('Tác vụ')));
    },
  );

  test('operations route selects Vận hành destination', () {
    final destination = AppNavModel.destinationForLocation('/operations');

    expect(destination?.id, 'operations');
    expect(destination?.label, 'Vận hành');
  });

  test('sort route selects the warehouse sorting destination', () {
    final destination = AppNavModel.destinationForLocation('/sort');

    expect(destination?.id, 'fifoSort');
    expect(destination?.label, 'Sắp xếp FIFO');
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

  test('warranty detail route stays inside BH SC workspace', () {
    final destination = AppNavModel.destinationForLocation(
      '/check-warranty/details/CP01-J12345678',
    );

    expect(destination?.id, 'warranty');
    expect(destination?.label, 'Bảo hành');
  });

  test('personnel catalog access makes Admin workspace visible', () {
    const user = User(
      id: 'personnel-admin',
      email: 'personnel-admin@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-admin',
      featureAccess: {'ADMIN_PERSONNEL': true},
    );

    final workspaceLabels = AppNavModel.visibleWorkspaceDestinations(
      user,
    ).map((destination) => destination.label);
    final sidebarLabels = AppNavModel.visibleSidebarDestinations(
      user,
    ).map((destination) => destination.label);

    expect(workspaceLabels, isNot(contains('Quản trị')));
    expect(sidebarLabels, contains('Quản trị'));
  });

  test('workspace taxonomy keeps the requested section order', () {
    const user = User(
      id: 'all-tools',
      email: 'all.tools@phongvu.vn',
      role: 'USER',
      organizationNodeId: 'org-store-cp01',
      featureAccess: {
        'VIETQR': true,
        'SALES_REPORT': true,
        'PAYMENT_MONITOR': true,
        'FIFO': true,
        'BANK_STATEMENTS': true,
        'OFFSET_ADJUSTMENTS': true,
        'WARRANTY': true,
      },
    );

    final sections = AppNavModel.visibleWorkspaceSections(user);

    expect(sections.map((section) => section.label), [
      'Bán hàng',
      'Kho',
      'Tài chính',
      'Kỹ thuật',
    ]);
    expect(sections[0].destinations.map((item) => item.label), [
      'VietQR',
      'Báo cáo',
      if (AppPlatformCapabilities.isPaymentMonitorSupported()) 'Tiền vào',
    ]);
    expect(sections[1].destinations.map((item) => item.label), [
      'Kiểm tra FIFO',
      'Sắp xếp FIFO',
    ]);
    expect(sections[2].destinations.map((item) => item.label), [
      'Sao kê',
      'Cấn trừ',
    ]);
    expect(sections[3].destinations.map((item) => item.label), ['Bảo hành']);
  });
}
