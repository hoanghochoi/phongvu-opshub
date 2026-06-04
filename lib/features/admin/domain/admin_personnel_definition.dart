class AdminPersonnelDefinition {
  final String? id;
  final String code;
  final String title;
  final String description;
  final String? departmentCode;
  final bool isSystem;
  final bool isActive;
  final int userCount;

  const AdminPersonnelDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.description,
    this.departmentCode,
    this.isSystem = true,
    this.isActive = true,
    this.userCount = 0,
  });

  factory AdminPersonnelDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final counts = _counts(json);
    return AdminPersonnelDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      departmentCode: json['departmentCode']?.toString(),
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      userCount: int.tryParse(counts['users']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'description': description,
    if (departmentCode != null) 'departmentCode': departmentCode,
    'isActive': isActive,
  };
}

class AdminRegionDefinition {
  final String? id;
  final String code;
  final String title;
  final String abbreviation;
  final String description;
  final bool isSystem;
  final bool isActive;
  final int areaCount;
  final int storeCount;
  final int userCount;

  const AdminRegionDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.abbreviation,
    required this.description,
    this.isSystem = false,
    this.isActive = true,
    this.areaCount = 0,
    this.storeCount = 0,
    this.userCount = 0,
  });

  factory AdminRegionDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final counts = _counts(json);
    return AdminRegionDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      abbreviation: json['abbreviation']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      areaCount: int.tryParse(counts['areas']?.toString() ?? '') ?? 0,
      storeCount: int.tryParse(counts['stores']?.toString() ?? '') ?? 0,
      userCount: int.tryParse(counts['users']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'abbreviation': abbreviation,
    'description': description,
    'isActive': isActive,
  };
}

class AdminAreaDefinition extends AdminRegionDefinition {
  final String regionCode;
  final String? regionTitle;

  const AdminAreaDefinition({
    super.id,
    required super.code,
    required super.title,
    required super.abbreviation,
    required super.description,
    required this.regionCode,
    this.regionTitle,
    super.isSystem,
    super.isActive,
    super.storeCount,
    super.userCount,
  });

  factory AdminAreaDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final region = json['region'] is Map<String, dynamic>
        ? json['region'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final counts = _counts(json);
    return AdminAreaDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      abbreviation: json['abbreviation']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      regionCode: json['regionCode']?.toString() ?? '',
      regionTitle: region['displayName']?.toString(),
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      storeCount: int.tryParse(counts['stores']?.toString() ?? '') ?? 0,
      userCount: int.tryParse(counts['users']?.toString() ?? '') ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'regionCode': regionCode,
  };
}

class AdminWorkScopeDefinition {
  final String value;
  final String title;

  const AdminWorkScopeDefinition({required this.value, required this.title});
}

class AdminWorkScopes {
  AdminWorkScopes._();

  static const definitions = [
    AdminWorkScopeDefinition(value: 'NATIONAL', title: 'Toan quoc'),
    AdminWorkScopeDefinition(value: 'REGION', title: 'Theo Mien'),
    AdminWorkScopeDefinition(value: 'AREA', title: 'Theo Vung'),
    AdminWorkScopeDefinition(value: 'STORE', title: 'Theo SR'),
  ];

  static String titleOf(String? value) {
    for (final scope in definitions) {
      if (scope.value == value) return scope.title;
    }
    return value?.isNotEmpty == true ? value! : 'Chua gan';
  }
}

Map<String, dynamic> _counts(Map<String, dynamic> json) {
  return json['_count'] is Map<String, dynamic>
      ? json['_count'] as Map<String, dynamic>
      : const <String, dynamic>{};
}
