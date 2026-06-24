import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';

class AdminRoleDefinition {
  final String? id;
  final String value;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isSystem;

  const AdminRoleDefinition({
    this.id,
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.isSystem = false,
  });

  factory AdminRoleDefinition.fromJson(Map<String, dynamic> json) {
    final code = AdminRoles.normalize(json['code']?.toString());
    return AdminRoleDefinition(
      id: json['id']?.toString(),
      value: code,
      title: AdminRoles.displayTitle(code, json['displayName']?.toString()),
      description: AdminRoles.displayDescription(
        code,
        json['description']?.toString(),
      ),
      icon: _iconFor(code),
      color: _colorFor(code),
      isSystem: json['isSystem'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': value,
    'displayName': title,
    'description': description,
  };

  static IconData _iconFor(String code) {
    return switch (code) {
      'SUPER_ADMIN' => Icons.verified_user_outlined,
      'ADMIN' => Icons.admin_panel_settings_outlined,
      'USER' => Icons.badge_outlined,
      _ => Icons.security_outlined,
    };
  }

  static Color _colorFor(String code) {
    return switch (code) {
      'SUPER_ADMIN' => AppColors.violet600,
      'ADMIN' => AppColors.info,
      'USER' => AppColors.neutral600,
      _ => AppColors.purple600,
    };
  }
}

class AdminRoles {
  AdminRoles._();

  static const definitions = [
    AdminRoleDefinition(
      value: 'SUPER_ADMIN',
      title: 'Quản trị toàn hệ thống',
      description: 'Toàn quyền hệ thống',
      icon: Icons.verified_user_outlined,
      color: AppColors.violet600,
    ),
    AdminRoleDefinition(
      value: 'ADMIN',
      title: 'Quản trị viên',
      description: 'Quản trị theo phạm vi cây tổ chức',
      icon: Icons.admin_panel_settings_outlined,
      color: AppColors.info,
    ),
    AdminRoleDefinition(
      value: 'USER',
      title: 'Nhân viên',
      description: 'Quyền thao tác hằng ngày',
      icon: Icons.badge_outlined,
      color: AppColors.neutral600,
    ),
  ];

  static List<String> get values =>
      definitions.map((definition) => definition.value).toList();

  static String normalize(String? value) {
    return switch ((value ?? '').trim().toUpperCase()) {
      'SUPER_ADMIN' => 'SUPER_ADMIN',
      'ADMIN' || 'ADMIN_PHONGVU' || 'ADMIN_ACARE' || 'MANAGER' => 'ADMIN',
      'USER' || 'STAFF' => 'USER',
      _ => 'USER',
    };
  }

  static String displayTitle(String? role, [String? rawTitle]) {
    final title = rawTitle?.trim();
    final code = normalize(role);
    final technicalTitle =
        title == null ||
        title.isEmpty ||
        title == code ||
        title == 'Super Admin' ||
        title == 'Admin' ||
        title == 'User';
    if (!technicalTitle) return title;
    return switch (code) {
      'SUPER_ADMIN' => 'Quản trị toàn hệ thống',
      'ADMIN' => 'Quản trị viên',
      'USER' => 'Nhân viên',
      _ => 'Nhân viên',
    };
  }

  static String displayDescription(String? role, [String? rawDescription]) {
    final description = rawDescription?.trim();
    if (description != null && description.isNotEmpty) return description;
    return switch (normalize(role)) {
      'SUPER_ADMIN' => 'Toàn quyền hệ thống',
      'ADMIN' => 'Quản trị theo phạm vi cây tổ chức',
      'USER' => 'Quyền thao tác hằng ngày',
      _ => 'Quyền thao tác hằng ngày',
    };
  }
}
