class AdminPersonnelDefinition {
  final String? id;
  final String code;
  final String title;
  final String description;
  final String? departmentCode;
  final bool isSystem;

  const AdminPersonnelDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.description,
    this.departmentCode,
    this.isSystem = true,
  });

  factory AdminPersonnelDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    return AdminPersonnelDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      departmentCode: json['departmentCode']?.toString(),
      isSystem: json['isSystem'] == true,
    );
  }
}

class AdminWorkScopeDefinition {
  final String value;
  final String title;

  const AdminWorkScopeDefinition({required this.value, required this.title});
}

class AdminWorkScopes {
  AdminWorkScopes._();

  static const definitions = [
    AdminWorkScopeDefinition(value: 'STORE', title: 'Theo SR'),
    AdminWorkScopeDefinition(value: 'MULTI_STORE', title: 'Nhiều SR'),
    AdminWorkScopeDefinition(value: 'REGION', title: 'Vùng/Miền'),
    AdminWorkScopeDefinition(value: 'NATIONAL', title: 'Toàn quốc'),
    AdminWorkScopeDefinition(value: 'ONLINE', title: 'Online'),
  ];

  static String titleOf(String? value) {
    for (final scope in definitions) {
      if (scope.value == value) return scope.title;
    }
    return value?.isNotEmpty == true ? value! : 'Chưa gán';
  }
}
