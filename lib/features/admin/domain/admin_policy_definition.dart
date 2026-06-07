class AdminPolicyDefinition {
  final String? id;
  final String code;
  final String title;
  final String description;
  final String category;
  final bool defaultAllowed;
  final bool isSystem;
  final bool isActive;
  final int ruleCount;

  const AdminPolicyDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.description,
    this.category = 'GENERAL',
    this.defaultAllowed = false,
    this.isSystem = true,
    this.isActive = true,
    this.ruleCount = 0,
  });

  factory AdminPolicyDefinition.fromJson(Map<String, dynamic> json) {
    final code = json['code']?.toString() ?? '';
    final counts = json['_count'] is Map<String, dynamic>
        ? json['_count'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminPolicyDefinition(
      id: json['id']?.toString(),
      code: code,
      title: json['displayName']?.toString() ?? code,
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? 'GENERAL',
      defaultAllowed: json['defaultAllowed'] == true,
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      ruleCount: int.tryParse(counts['rules']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'description': description,
    'category': category,
    'defaultAllowed': defaultAllowed,
    'isActive': isActive,
  };
}

class AdminPolicyRule {
  final String? id;
  final String policyCode;
  final bool allowed;
  final String? emailDomain;
  final String? systemRole;
  final String? departmentCode;
  final String? jobRoleCode;
  final String? workScopeType;
  final String? regionCode;
  final String? areaCode;
  final String? storeCode;
  final String? userId;
  final String? scopeContains;
  final String? note;

  const AdminPolicyRule({
    this.id,
    required this.policyCode,
    required this.allowed,
    this.emailDomain,
    this.systemRole,
    this.departmentCode,
    this.jobRoleCode,
    this.workScopeType,
    this.regionCode,
    this.areaCode,
    this.storeCode,
    this.userId,
    this.scopeContains,
    this.note,
  });

  factory AdminPolicyRule.fromJson(Map<String, dynamic> json) {
    return AdminPolicyRule(
      id: json['id']?.toString(),
      policyCode: json['policyCode']?.toString() ?? '',
      allowed: json['allowed'] == true,
      emailDomain: json['emailDomain']?.toString(),
      systemRole: json['systemRole']?.toString(),
      departmentCode: json['departmentCode']?.toString(),
      jobRoleCode: json['jobRoleCode']?.toString(),
      workScopeType: json['workScopeType']?.toString(),
      regionCode: json['regionCode']?.toString(),
      areaCode: json['areaCode']?.toString(),
      storeCode: json['storeCode']?.toString(),
      userId: json['userId']?.toString(),
      scopeContains: json['scopeContains']?.toString(),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'policyCode': policyCode,
    'allowed': allowed,
    'emailDomain': emailDomain,
    'systemRole': systemRole,
    'departmentCode': departmentCode,
    'jobRoleCode': jobRoleCode,
    'workScopeType': workScopeType,
    'regionCode': regionCode,
    'areaCode': areaCode,
    'storeCode': storeCode,
    'userId': userId,
    'scopeContains': scopeContains,
    'note': note,
  };
}

class AdminPolicyRuleBatchRequest {
  final String policyCode;
  final bool allowed;
  final List<String> emailDomains;
  final List<String> systemRoles;
  final List<String> departmentCodes;
  final List<String> jobRoleCodes;
  final List<String> workScopeTypes;
  final List<String> regionCodes;
  final List<String> areaCodes;
  final List<String> storeCodes;
  final List<String> userIds;
  final List<String> scopeContainsValues;
  final String? note;

  const AdminPolicyRuleBatchRequest({
    required this.policyCode,
    required this.allowed,
    this.emailDomains = const [],
    this.systemRoles = const [],
    this.departmentCodes = const [],
    this.jobRoleCodes = const [],
    this.workScopeTypes = const [],
    this.regionCodes = const [],
    this.areaCodes = const [],
    this.storeCodes = const [],
    this.userIds = const [],
    this.scopeContainsValues = const [],
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'policyCode': policyCode,
    'allowed': allowed,
    'emailDomains': emailDomains,
    'systemRoles': systemRoles,
    'departmentCodes': departmentCodes,
    'jobRoleCodes': jobRoleCodes,
    'workScopeTypes': workScopeTypes,
    'regionCodes': regionCodes,
    'areaCodes': areaCodes,
    'storeCodes': storeCodes,
    'userIds': userIds,
    'scopeContainsValues': scopeContainsValues,
    'note': note,
  };
}

class AdminSettingDefinition {
  final String key;
  final String title;
  final String description;
  final String category;
  final dynamic value;
  final bool isSystem;
  final bool isSensitive;

  const AdminSettingDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.value,
    this.category = 'GENERAL',
    this.isSystem = true,
    this.isSensitive = false,
  });

  factory AdminSettingDefinition.fromJson(Map<String, dynamic> json) {
    final key = json['key']?.toString() ?? '';
    return AdminSettingDefinition(
      key: key,
      title: json['displayName']?.toString() ?? key,
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? 'GENERAL',
      value: json['value'],
      isSystem: json['isSystem'] == true,
      isSensitive: json['isSensitive'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'displayName': title,
    'description': description,
    'category': category,
    'value': value,
  };
}
