class AdminOrganizationNode {
  final String id;
  final String code;
  final String title;
  final String type;
  final String? parentId;
  final String? emailDomain;
  final bool loginAllowed;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;
  final int childCount;
  final int userCount;
  final int storeCount;
  final int departmentCount;
  final int jobRoleCount;
  final int regionCount;
  final int areaCount;

  const AdminOrganizationNode({
    required this.id,
    required this.code,
    required this.title,
    required this.type,
    this.parentId,
    this.emailDomain,
    this.loginAllowed = false,
    this.isSystem = false,
    this.isActive = true,
    this.sortOrder = 0,
    this.childCount = 0,
    this.userCount = 0,
    this.storeCount = 0,
    this.departmentCount = 0,
    this.jobRoleCount = 0,
    this.regionCount = 0,
    this.areaCount = 0,
  });

  factory AdminOrganizationNode.fromJson(Map<String, dynamic> json) {
    final counts = json['_count'] is Map<String, dynamic>
        ? json['_count'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminOrganizationNode(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      title: json['displayName']?.toString() ?? json['code']?.toString() ?? '',
      type: json['type']?.toString() ?? 'BLOCK',
      parentId: json['parentId']?.toString(),
      emailDomain: json['emailDomain']?.toString(),
      loginAllowed: json['loginAllowed'] == true,
      isSystem: json['isSystem'] == true,
      isActive: json['isActive'] != false,
      sortOrder: int.tryParse(json['sortOrder']?.toString() ?? '') ?? 0,
      childCount: int.tryParse(counts['children']?.toString() ?? '') ?? 0,
      userCount: int.tryParse(counts['users']?.toString() ?? '') ?? 0,
      storeCount: int.tryParse(counts['stores']?.toString() ?? '') ?? 0,
      departmentCount:
          int.tryParse(counts['departments']?.toString() ?? '') ?? 0,
      jobRoleCount: int.tryParse(counts['jobRoles']?.toString() ?? '') ?? 0,
      regionCount: int.tryParse(counts['regions']?.toString() ?? '') ?? 0,
      areaCount: int.tryParse(counts['areas']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'displayName': title,
    'type': type,
    'parentId': parentId,
    'emailDomain': emailDomain,
    'loginAllowed': loginAllowed,
    'isActive': isActive,
    'sortOrder': sortOrder,
  };

  int get referenceCount =>
      userCount +
      storeCount +
      departmentCount +
      jobRoleCount +
      regionCount +
      areaCount;
}

class AdminOrganizationNodeTypes {
  AdminOrganizationNodeTypes._();

  static const definitions = [
    ('ROOT_DOMAIN', 'Domain gốc'),
    ('SUBDOMAIN', 'Sub domain'),
    ('BLOCK', 'Khối'),
    ('DEPARTMENT', 'Phòng ban'),
    ('AREA', 'Vùng'),
    ('SHOWROOM', 'Showroom'),
    ('JOB_ROLE', 'Chức danh'),
    ('VIRTUAL_SCOPE', 'Scope ảo'),
  ];

  static String titleOf(String type) {
    for (final definition in definitions) {
      if (definition.$1 == type) return definition.$2;
    }
    return type;
  }
}
