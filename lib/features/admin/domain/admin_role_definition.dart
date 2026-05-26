import 'package:flutter/material.dart';

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
    final code = json['code']?.toString() ?? 'STAFF';
    return AdminRoleDefinition(
      id: json['id']?.toString(),
      value: code,
      title: json['displayName']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
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
      'MANAGER' => Icons.manage_accounts_outlined,
      'STAFF' => Icons.badge_outlined,
      _ => Icons.security_outlined,
    };
  }

  static Color _colorFor(String code) {
    return switch (code) {
      'SUPER_ADMIN' => const Color(0xFF7C3AED),
      'ADMIN' => const Color(0xFF2563EB),
      'MANAGER' => const Color(0xFF0F766E),
      'STAFF' => const Color(0xFF4B5563),
      _ => const Color(0xFF9333EA),
    };
  }
}

class AdminRoles {
  AdminRoles._();

  static const definitions = [
    AdminRoleDefinition(
      value: 'SUPER_ADMIN',
      title: 'Super Admin',
      description: 'Toàn quyền hệ thống',
      icon: Icons.verified_user_outlined,
      color: Color(0xFF7C3AED),
    ),
    AdminRoleDefinition(
      value: 'ADMIN',
      title: 'Admin',
      description: 'Quản lý người dùng theo phạm vi',
      icon: Icons.admin_panel_settings_outlined,
      color: Color(0xFF2563EB),
    ),
    AdminRoleDefinition(
      value: 'MANAGER',
      title: 'Manager',
      description: 'Nhóm quyền quản lý vận hành',
      icon: Icons.manage_accounts_outlined,
      color: Color(0xFF0F766E),
    ),
    AdminRoleDefinition(
      value: 'STAFF',
      title: 'Staff',
      description: 'Quyền thao tác hằng ngày',
      icon: Icons.badge_outlined,
      color: Color(0xFF4B5563),
    ),
  ];

  static List<String> get values =>
      definitions.map((definition) => definition.value).toList();
}
