class AdminFeatureDefinition {
  final String? id;
  final String code;
  final String title;
  final String description;
  final bool isSystem;
  final bool isActive;
  final int ruleCount;

  const AdminFeatureDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.description,
    this.isSystem = true,
    this.isActive = true,
    this.ruleCount = 0,
  });

  factory AdminFeatureDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final counts = json['_count'] is Map<String, dynamic>
        ? json['_count'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminFeatureDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      ruleCount: int.tryParse(counts['rules']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'description': description,
    'isActive': isActive,
  };
}

class AdminFeatureRule {
  final String? id;
  final String featureCode;
  final bool enabled;
  final String? systemRole;
  final String? departmentCode;
  final String? jobRoleCode;
  final String? workScopeType;
  final String? regionCode;
  final String? areaCode;
  final String? storeCode;
  final String? userId;
  final String? userEmail;
  final String? note;

  const AdminFeatureRule({
    this.id,
    required this.featureCode,
    required this.enabled,
    this.systemRole,
    this.departmentCode,
    this.jobRoleCode,
    this.workScopeType,
    this.regionCode,
    this.areaCode,
    this.storeCode,
    this.userId,
    this.userEmail,
    this.note,
  });

  factory AdminFeatureRule.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminFeatureRule(
      id: json['id']?.toString(),
      featureCode: json['featureCode']?.toString() ?? '',
      enabled: json['enabled'] == true,
      systemRole: json['systemRole']?.toString(),
      departmentCode: json['departmentCode']?.toString(),
      jobRoleCode: json['jobRoleCode']?.toString(),
      workScopeType: json['workScopeType']?.toString(),
      regionCode: json['regionCode']?.toString(),
      areaCode: json['areaCode']?.toString(),
      storeCode: json['storeCode']?.toString(),
      userId: json['userId']?.toString(),
      userEmail: user['email']?.toString(),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'featureCode': featureCode,
    'enabled': enabled,
    'systemRole': systemRole,
    'departmentCode': departmentCode,
    'jobRoleCode': jobRoleCode,
    'workScopeType': workScopeType,
    'regionCode': regionCode,
    'areaCode': areaCode,
    'storeCode': storeCode,
    'userId': userId,
    'note': note,
  };
}

class AdminFeatureRuleBatchRequest {
  final String featureCode;
  final bool enabled;
  final List<String> systemRoles;
  final List<String> departmentCodes;
  final List<String> jobRoleCodes;
  final List<String> workScopeTypes;
  final List<String> regionCodes;
  final List<String> areaCodes;
  final List<String> storeCodes;
  final List<String> userIds;
  final String? note;

  const AdminFeatureRuleBatchRequest({
    required this.featureCode,
    required this.enabled,
    this.systemRoles = const [],
    this.departmentCodes = const [],
    this.jobRoleCodes = const [],
    this.workScopeTypes = const [],
    this.regionCodes = const [],
    this.areaCodes = const [],
    this.storeCodes = const [],
    this.userIds = const [],
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'featureCode': featureCode,
    'enabled': enabled,
    'systemRoles': systemRoles,
    'departmentCodes': departmentCodes,
    'jobRoleCodes': jobRoleCodes,
    'workScopeTypes': workScopeTypes,
    'regionCodes': regionCodes,
    'areaCodes': areaCodes,
    'storeCodes': storeCodes,
    'userIds': userIds,
    'note': note,
  };
}
