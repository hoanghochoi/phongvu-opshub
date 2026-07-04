import 'package:flutter/material.dart';

import '../../core/platform/app_platform_capabilities.dart';
import '../../features/auth/domain/entities/user.dart';
import '../theme/app_colors.dart';

enum AppNavGroup { root, workspace, account }

class AppNavDestination {
  final String id;
  final String label;
  final String description;
  final String route;
  final IconData icon;
  final Color color;
  final AppNavGroup group;
  final bool showInSidebar;
  final bool showInMobileNav;

  const AppNavDestination({
    required this.id,
    required this.label,
    required this.description,
    required this.route,
    required this.icon,
    required this.color,
    required this.group,
    this.showInSidebar = true,
    this.showInMobileNav = false,
  });
}

class AppNavModel {
  AppNavModel._();

  static const List<AppNavDestination> destinations = [
    AppNavDestination(
      id: 'home',
      label: 'Trang chủ',
      description: 'Tổng quan vận hành',
      route: '/home',
      icon: Icons.dashboard_outlined,
      color: AppColors.primary,
      group: AppNavGroup.root,
      showInMobileNav: true,
    ),
    AppNavDestination(
      id: 'operations',
      label: 'Vận hành',
      description: 'Công cụ nghiệp vụ theo quyền',
      route: '/operations',
      icon: Icons.apps_outlined,
      color: AppColors.success,
      group: AppNavGroup.root,
      showInMobileNav: true,
    ),
    AppNavDestination(
      id: 'notifications',
      label: 'Thông báo',
      description: 'Hộp thư thông báo',
      route: '/notifications',
      icon: Icons.notifications_none_rounded,
      color: AppColors.warning,
      group: AppNavGroup.root,
      showInSidebar: false,
      showInMobileNav: true,
    ),
    AppNavDestination(
      id: 'admin',
      label: 'Quản trị',
      description: 'Tài khoản, vai trò và cấu hình',
      route: '/admin',
      icon: Icons.admin_panel_settings_outlined,
      color: AppColors.neutral600,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'fifo',
      label: 'FIFO',
      description: 'Kiểm tra và sắp xếp tồn kho',
      route: '/fifo-menu',
      icon: Icons.qr_code_scanner_rounded,
      color: AppColors.info,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'warranty',
      label: 'Bảo hành',
      description: 'Tiếp nhận và tra cứu bảo hành/sửa chữa',
      route: '/warranty-main',
      icon: Icons.camera_alt_rounded,
      color: AppColors.success,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'vietqr',
      label: 'VietQR',
      description: 'Tạo mã chuyển khoản',
      route: '/vietqr',
      icon: Icons.qr_code_2_rounded,
      color: AppColors.teal600,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'payment',
      label: 'Tiền vào',
      description: 'Theo dõi giao dịch thanh toán',
      route: '/payment-monitor',
      icon: Icons.payments_outlined,
      color: AppColors.violet600,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'statement',
      label: 'Sao kê',
      description: 'Rà soát giao dịch theo mã đơn',
      route: '/bank-statement',
      icon: Icons.fact_check_outlined,
      color: AppColors.info,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'offset',
      label: 'Cấn trừ',
      description: 'Gửi yêu cầu xác nhận cấn trừ',
      route: '/offset-adjustments',
      icon: Icons.swap_horiz_rounded,
      color: AppColors.teal600,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'sales',
      label: 'Báo cáo',
      description: 'Theo dõi và gửi báo cáo sale',
      route: '/reports',
      icon: Icons.assignment_outlined,
      color: AppColors.info,
      group: AppNavGroup.workspace,
    ),
    AppNavDestination(
      id: 'settings',
      label: 'Cài đặt',
      description: 'Tùy chỉnh ứng dụng',
      route: '/settings',
      icon: Icons.settings_outlined,
      color: AppColors.neutral600,
      group: AppNavGroup.account,
    ),
    AppNavDestination(
      id: 'feedback',
      label: 'Góp ý',
      description: 'Gửi đề xuất và báo lỗi',
      route: '/feedback',
      icon: Icons.lightbulb_outline_rounded,
      color: AppColors.amber500,
      group: AppNavGroup.account,
    ),
    AppNavDestination(
      id: 'help',
      label: 'Hướng dẫn',
      description: 'Tài liệu thao tác và hỗ trợ',
      route: '/help',
      icon: Icons.menu_book_outlined,
      color: AppColors.info,
      group: AppNavGroup.account,
    ),
    AppNavDestination(
      id: 'profile',
      label: 'Tài khoản',
      description: 'Thông tin cá nhân',
      route: '/profile',
      icon: Icons.person_outline,
      color: AppColors.primary,
      group: AppNavGroup.account,
      showInSidebar: false,
      showInMobileNav: true,
    ),
  ];

  static List<AppNavDestination> visibleSidebarDestinations(User? user) {
    return destinations
        .where((destination) => destination.showInSidebar)
        .where((destination) => canUseDestination(user, destination))
        .toList(growable: false);
  }

  static List<AppNavDestination> visibleWorkspaceDestinations(User? user) {
    return destinations
        .where((destination) => destination.group == AppNavGroup.workspace)
        .where((destination) => canUseDestination(user, destination))
        .toList(growable: false);
  }

  static int hiddenWorkspaceCount(User? user) {
    return destinations
        .where((destination) => destination.group == AppNavGroup.workspace)
        .where((destination) => !canUseDestination(user, destination))
        .length;
  }

  static List<AppNavDestination> visibleMobileDestinations(User? user) {
    return destinations
        .where((destination) => destination.showInMobileNav)
        .where((destination) => canUseDestination(user, destination))
        .toList(growable: false);
  }

  static int hiddenSidebarCount(User? user) {
    return destinations
        .where((destination) => destination.showInSidebar)
        .where((destination) => !canUseDestination(user, destination))
        .length;
  }

  static AppNavDestination? destinationForLocation(String location) {
    for (final destination in destinations) {
      if (isSelected(destination, location)) return destination;
    }
    return null;
  }

  static bool isSelected(AppNavDestination destination, String location) {
    if (location == destination.route) return true;
    return switch (destination.id) {
      'admin' =>
        location.startsWith('/admin') && location != '/admin/sales-reports',
      'fifo' =>
        location == '/fifo-check' ||
            location == '/fifo-history' ||
            location == '/fifo/inventory-import' ||
            location == '/sort',
      'warranty' =>
        location == '/warranty' || location.startsWith('/check-warranty'),
      'sales' =>
        location == '/reports' ||
            location.startsWith('/sales-reports') ||
            location == '/admin/sales-reports',
      _ => false,
    };
  }

  static bool canUseDestination(User? user, AppNavDestination destination) {
    return switch (destination.id) {
      'home' ||
      'notifications' ||
      'operations' ||
      'help' ||
      'profile' ||
      'settings' => true,
      'admin' => _canUseAdmin(user),
      'fifo' =>
        user?.canUseFeature('FIFO') == true ||
            user?.canUseFeature('FIFO_IMPORT') == true,
      'warranty' => user?.canUseFeature('WARRANTY') == true,
      'vietqr' => user?.canUseFeature('VIETQR') == true,
      'payment' =>
        user?.canUseFeature('PAYMENT_MONITOR') == true &&
            AppPlatformCapabilities.isPaymentMonitorSupported(),
      'statement' => user?.canUseBankStatements == true,
      'offset' => user?.canUseOffsetAdjustments == true,
      'sales' =>
        user?.canUseFeature('SALES_REPORT') == true ||
            user?.canUseFeature('ADMIN_SALES_REPORTS') == true,
      'feedback' => user?.canUseFeature('FEEDBACK') == true,
      _ => false,
    };
  }

  static bool _canUseAdmin(User? user) {
    return user?.isAdmin == true ||
        user?.canUseFeature('ADMIN') == true ||
        user?.canUseFeature('ADMIN_USERS') == true ||
        user?.canUseFeature('ADMIN_ROLES') == true ||
        user?.canUseFeature('ADMIN_ORG_TREE') == true ||
        user?.canUseFeature('ADMIN_POLICIES') == true ||
        user?.canUseFeature('ADMIN_FEATURES') == true ||
        user?.canUseFeature('ADMIN_PERSONNEL') == true ||
        user?.canUseFeature('ADMIN_FEEDBACK') == true;
  }
}
