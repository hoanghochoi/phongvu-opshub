class AdminFeatureDefinition {
  final String? id;
  final String code;
  final String title;
  final String description;
  final String? parentCode;
  final int sortOrder;
  final bool visibleInUserPicker;
  final bool isSystem;
  final bool isActive;
  final int ruleCount;
  final int userAssignmentCount;

  const AdminFeatureDefinition({
    this.id,
    required this.code,
    required this.title,
    required this.description,
    this.parentCode,
    this.sortOrder = 0,
    this.visibleInUserPicker = true,
    this.isSystem = true,
    this.isActive = true,
    this.ruleCount = 0,
    this.userAssignmentCount = 0,
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
      parentCode: json['parentCode']?.toString(),
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
      visibleInUserPicker: json['visibleInUserPicker'] != false,
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      ruleCount: int.tryParse(counts['rules']?.toString() ?? '') ?? 0,
      userAssignmentCount:
          int.tryParse(counts['userAssignments']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'description': description,
    'parentCode': parentCode,
    'sortOrder': sortOrder,
    'visibleInUserPicker': visibleInUserPicker,
    'isActive': isActive,
  };
}

class AdminFeatureRule {
  final String? id;
  final String featureCode;
  final bool enabled;
  final String? emailDomain;
  final String? systemRole;
  final String? departmentCode;
  final String? jobRoleCode;
  final String? workScopeType;
  final String? regionCode;
  final String? areaCode;
  final String? organizationNodeId;
  final String? organizationNodeName;
  final String? storeCode;
  final String? userId;
  final String? userEmail;
  final String? note;

  const AdminFeatureRule({
    this.id,
    required this.featureCode,
    required this.enabled,
    this.emailDomain,
    this.systemRole,
    this.departmentCode,
    this.jobRoleCode,
    this.workScopeType,
    this.regionCode,
    this.areaCode,
    this.organizationNodeId,
    this.organizationNodeName,
    this.storeCode,
    this.userId,
    this.userEmail,
    this.note,
  });

  factory AdminFeatureRule.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final organizationNode = json['organizationNode'] is Map<String, dynamic>
        ? json['organizationNode'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminFeatureRule(
      id: json['id']?.toString(),
      featureCode: json['featureCode']?.toString() ?? '',
      enabled: json['enabled'] == true,
      emailDomain: json['emailDomain']?.toString(),
      systemRole: json['systemRole']?.toString(),
      departmentCode: json['departmentCode']?.toString(),
      jobRoleCode: json['jobRoleCode']?.toString(),
      workScopeType: json['workScopeType']?.toString(),
      regionCode: json['regionCode']?.toString(),
      areaCode: json['areaCode']?.toString(),
      organizationNodeId: json['organizationNodeId']?.toString(),
      organizationNodeName: organizationNode['displayName']?.toString(),
      storeCode: json['storeCode']?.toString(),
      userId: json['userId']?.toString(),
      userEmail: user['email']?.toString(),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'featureCode': featureCode,
    'enabled': enabled,
    'emailDomain': emailDomain,
    'systemRole': systemRole,
    'departmentCode': departmentCode,
    'jobRoleCode': jobRoleCode,
    'workScopeType': workScopeType,
    'regionCode': regionCode,
    'areaCode': areaCode,
    'organizationNodeId': organizationNodeId,
    'storeCode': storeCode,
    'userId': userId,
    'note': note,
  };
}

class AdminFeatureRuleBatchRequest {
  final String featureCode;
  final bool enabled;
  final List<String> emailDomains;
  final List<String> systemRoles;
  final List<String> departmentCodes;
  final List<String> jobRoleCodes;
  final List<String> workScopeTypes;
  final List<String> regionCodes;
  final List<String> areaCodes;
  final List<String> organizationNodeIds;
  final List<String> storeCodes;
  final List<String> userIds;
  final String? note;

  const AdminFeatureRuleBatchRequest({
    required this.featureCode,
    required this.enabled,
    this.emailDomains = const [],
    this.systemRoles = const [],
    this.departmentCodes = const [],
    this.jobRoleCodes = const [],
    this.workScopeTypes = const [],
    this.regionCodes = const [],
    this.areaCodes = const [],
    this.organizationNodeIds = const [],
    this.storeCodes = const [],
    this.userIds = const [],
    this.note,
  });

  Map<String, dynamic> toJson() => {
    'featureCode': featureCode,
    'enabled': enabled,
    'emailDomains': emailDomains,
    'systemRoles': systemRoles,
    'departmentCodes': departmentCodes,
    'jobRoleCodes': jobRoleCodes,
    'workScopeTypes': workScopeTypes,
    'organizationNodeIds': organizationNodeIds,
    'userIds': userIds,
    'note': note,
    if (regionCodes.isNotEmpty) 'regionCodes': regionCodes,
    if (areaCodes.isNotEmpty) 'areaCodes': areaCodes,
    if (storeCodes.isNotEmpty) 'storeCodes': storeCodes,
  };
}
