class AdminOrganizationNode {
  final String id;
  final String code;
  final String title;
  final String? businessCode;
  final String? abbreviation;
  final String? description;
  final String type;
  final int level;
  final String? parentId;
  final String? emailDomain;
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
  final String? storeId;
  final String? storeName;
  final String? transferAccountNumber;
  final String? transferAccountName;
  final String? transferBankName;
  final String? transferBankBin;
  final String? mapVietinUsername;
  final bool hasMapVietinPassword;

  const AdminOrganizationNode({
    required this.id,
    required this.code,
    required this.title,
    this.businessCode,
    this.abbreviation,
    this.description,
    required this.type,
    this.level = 0,
    this.parentId,
    this.emailDomain,
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
    this.storeId,
    this.storeName,
    this.transferAccountNumber,
    this.transferAccountName,
    this.transferBankName,
    this.transferBankBin,
    this.mapVietinUsername,
    this.hasMapVietinPassword = false,
  });

  factory AdminOrganizationNode.fromJson(Map<String, dynamic> json) {
    final counts = json['_count'] is Map<String, dynamic>
        ? json['_count'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AdminOrganizationNode(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      title: json['displayName']?.toString() ?? json['code']?.toString() ?? '',
      businessCode: json['businessCode']?.toString(),
      abbreviation: json['abbreviation']?.toString(),
      description: json['description']?.toString(),
      type: canonicalType(json['type']?.toString() ?? 'LV1_BLOCK'),
      level:
          int.tryParse(json['level']?.toString() ?? '') ??
          levelOf(json['type']?.toString() ?? 'LV1_BLOCK'),
      parentId: json['parentId']?.toString(),
      emailDomain: json['emailDomain']?.toString(),
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
      storeId: json['storeId']?.toString(),
      storeName: json['storeName']?.toString(),
      transferAccountNumber: json['transferAccountNumber']?.toString(),
      transferAccountName: json['transferAccountName']?.toString(),
      transferBankName: json['transferBankName']?.toString(),
      transferBankBin: json['transferBankBin']?.toString(),
      mapVietinUsername: json['mapVietinUsername']?.toString(),
      hasMapVietinPassword: json['hasMapVietinPassword'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    final isDomain = type == 'LV0_DOMAIN';
    final isShowroom = type == 'LV4_STORE';
    return {
      'code': code,
      'displayName': title,
      'businessCode': businessCode,
      'abbreviation': abbreviation,
      'description': description,
      'type': type,
      'parentId': parentId,
      'isActive': isActive,
      'sortOrder': sortOrder,
      if (isDomain) 'emailDomain': emailDomain,
      if (isShowroom) 'storeId': storeId,
      if (isShowroom) 'storeName': storeName,
      if (isShowroom) 'transferAccountNumber': transferAccountNumber,
      if (isShowroom) 'transferAccountName': transferAccountName,
      if (isShowroom) 'transferBankName': transferBankName,
      if (isShowroom) 'transferBankBin': transferBankBin,
      if (isShowroom) 'mapVietinUsername': mapVietinUsername,
    };
  }

  int get referenceCount =>
      userCount +
      storeCount +
      departmentCount +
      jobRoleCount +
      regionCount +
      areaCount;

  bool get isStoreNode => type == 'LV4_STORE';

  bool get isDomainNode => type == 'LV0_DOMAIN';

  static String canonicalType(String value) {
    return switch (value.toUpperCase()) {
      'ROOT_DOMAIN' => 'LV0_DOMAIN',
      'BLOCK' => 'LV1_BLOCK',
      'DEPARTMENT' => 'LV2_DEPARTMENT',
      'REGION' => 'LV2_REGION',
      'AREA' => 'LV3_AREA',
      'VIRTUAL_SCOPE' => 'LV3_UNIT',
      'SHOWROOM' => 'LV4_STORE',
      'JOB_ROLE' => 'LV5_POSITION',
      _ => value.toUpperCase(),
    };
  }

  static int levelOf(String value) {
    return switch (canonicalType(value)) {
      'LV0_DOMAIN' => 0,
      'LV1_BLOCK' => 1,
      'LV2_DEPARTMENT' || 'LV2_REGION' => 2,
      'LV3_AREA' || 'LV3_UNIT' => 3,
      'LV4_STORE' => 4,
      'LV5_POSITION' => 5,
      _ => 0,
    };
  }
}

List<AdminOrganizationNode> filterAdminOrganizationNodesForSearch(
  List<AdminOrganizationNode> nodes,
  String query,
) {
  final normalizedQuery = normalizeAdminOrganizationSearchText(query);
  if (normalizedQuery.isEmpty) return List<AdminOrganizationNode>.of(nodes);

  final byId = {for (final node in nodes) node.id: node};
  final includedIds = <String>{};

  void includeWithAncestors(AdminOrganizationNode node) {
    if (!includedIds.add(node.id)) return;
    final parentId = node.parentId;
    if (parentId == null) return;
    final parent = byId[parentId];
    if (parent != null) includeWithAncestors(parent);
  }

  for (final node in nodes) {
    if (adminOrganizationNodeMatchesSearch(node, normalizedQuery)) {
      includeWithAncestors(node);
    }
  }

  return [
    for (final node in nodes)
      if (includedIds.contains(node.id)) node,
  ];
}

bool adminOrganizationNodeMatchesSearch(
  AdminOrganizationNode node,
  String query,
) {
  final normalizedQuery = normalizeAdminOrganizationSearchText(query);
  if (normalizedQuery.isEmpty) return true;

  final fields = [
    node.businessCode,
    node.abbreviation,
    node.title,
    node.code,
    node.storeId,
    node.storeName,
  ];

  return fields
      .where((value) => value?.trim().isNotEmpty == true)
      .any(
        (value) => normalizeAdminOrganizationSearchText(
          value!,
        ).contains(normalizedQuery),
      );
}

String normalizeAdminOrganizationSearchText(String value) {
  var normalized = value.trim().toLowerCase();
  const replacements = {
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'e': 'èéẹẻẽêềếệểễ',
    'i': 'ìíịỉĩ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'u': 'ùúụủũưừứựửữ',
    'y': 'ỳýỵỷỹ',
    'd': 'đ',
  };
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  return normalized;
}

class AdminOrganizationNodeTypes {
  AdminOrganizationNodeTypes._();

  static const definitions = [
    ('LV0_DOMAIN', 'Lv0 Domain'),
    ('LV1_BLOCK', 'Lv1 Khối'),
    ('LV2_DEPARTMENT', 'Lv2 Phòng/Bộ phận'),
    ('LV2_REGION', 'Lv2 Miền'),
    ('LV3_AREA', 'Lv3 Vùng'),
    ('LV3_UNIT', 'Lv3 Bộ phận'),
    ('LV4_STORE', 'Lv4 Cửa hàng'),
    ('LV5_POSITION', 'Lv5 Vị trí'),
  ];

  static String titleOf(String type) {
    final canonical = AdminOrganizationNode.canonicalType(type);
    for (final definition in definitions) {
      if (definition.$1 == canonical) return definition.$2;
    }
    return canonical;
  }
}
