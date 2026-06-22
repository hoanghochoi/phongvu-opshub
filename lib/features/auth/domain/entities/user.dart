class User {
  final String? id;
  final String email;
  final String? emailDomain;
  final String? name;
  final String? lastName;
  final String? avatarUrl;
  final String? storeId;
  final String? storeName;
  final String? role;
  final String? status;
  final String? departmentCode;
  final String? jobRoleCode;
  final String? workScopeType;
  final String? regionCode;
  final String? regionName;
  final String? regionAbbreviation;
  final String? areaCode;
  final String? areaName;
  final String? areaAbbreviation;
  final String? organizationNodeId;
  final String? organizationNodeName;
  final List<String> featureCodes;
  final String? personnelCode;
  final Map<String, bool> featureAccess;
  final Map<String, bool> policyAccess;
  final bool assignmentPending;
  final bool mustSelectStore;

  const User({
    this.id,
    required this.email,
    this.emailDomain,
    this.name,
    this.lastName,
    this.avatarUrl,
    this.storeId,
    this.storeName,
    this.role,
    this.status,
    this.departmentCode,
    this.jobRoleCode,
    this.workScopeType,
    this.regionCode,
    this.regionName,
    this.regionAbbreviation,
    this.areaCode,
    this.areaName,
    this.areaAbbreviation,
    this.organizationNodeId,
    this.organizationNodeName,
    this.featureCodes = const [],
    this.personnelCode,
    this.featureAccess = const {},
    this.policyAccess = const {},
    this.assignmentPending = false,
    this.mustSelectStore = false,
  });

  static String normalizeRole(String? role) {
    return switch ((role ?? '').trim().toUpperCase()) {
      'SUPER_ADMIN' => 'SUPER_ADMIN',
      'ADMIN' || 'ADMIN_PHONGVU' || 'ADMIN_ACARE' || 'MANAGER' => 'ADMIN',
      'USER' || 'STAFF' => 'USER',
      _ => 'USER',
    };
  }

  static bool isAdminRole(String? role) {
    final normalized = normalizeRole(role);
    return normalized == 'SUPER_ADMIN' || normalized == 'ADMIN';
  }

  static bool isAdminMenuRole(String? role) => isAdminRole(role);

  bool get isSuperAdmin => role == 'SUPER_ADMIN';

  factory User.fromJson(Map<String, dynamic> json, {String? fallbackEmail}) {
    return User(
      id: json['id']?.toString(),
      email: json['email']?.toString() ?? fallbackEmail ?? '',
      emailDomain: json['emailDomain']?.toString(),
      name: json['name']?.toString() ?? json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      storeId: json['storeId']?.toString(),
      storeName: json['storeName']?.toString(),
      role: normalizeRole(json['role']?.toString()),
      status: json['status']?.toString(),
      departmentCode: json['departmentCode']?.toString(),
      jobRoleCode: json['jobRoleCode']?.toString(),
      workScopeType: json['workScopeType']?.toString(),
      regionCode: json['regionCode']?.toString(),
      regionName: json['regionName']?.toString(),
      regionAbbreviation: json['regionAbbreviation']?.toString(),
      areaCode: json['areaCode']?.toString(),
      areaName: json['areaName']?.toString(),
      areaAbbreviation: json['areaAbbreviation']?.toString(),
      organizationNodeId: json['organizationNodeId']?.toString(),
      organizationNodeName: json['organizationNodeName']?.toString(),
      featureCodes: _stringListFromJson(json['featureCodes']),
      personnelCode: json['personnelCode']?.toString(),
      featureAccess: _featureAccessFromJson(
        json['resolvedFeatureAccess'] ?? json['featureAccess'],
      ),
      policyAccess: _featureAccessFromJson(
        json['resolvedAdminPolicies'] ??
            json['resolvedPolicyAccess'] ??
            json['policyAccess'],
      ),
      assignmentPending:
          json['assignmentPending'] == true ||
          json['assignmentPending'] == 'true',
      mustSelectStore:
          json['mustSelectStore'] == true || json['mustSelectStore'] == 'true',
    );
  }

  bool get isAdmin {
    if (isSuperAdmin) return true;
    final resolved = featureAccess['ADMIN'];
    if (resolved != null) return resolved;
    return isAdminMenuRole(role);
  }

  bool get needsStoreSelection => false;

  bool get needsOrganizationAssignment =>
      assignmentPending || (!isAdminRole(role) && organizationNodeId == null);

  bool get belongsToCp62 {
    final values = [
      storeId,
      storeName,
      personnelCode,
      workScopeType,
      regionCode,
      areaCode,
    ];
    return values.any((value) => value?.toUpperCase().contains('CP62') == true);
  }

  bool get canUseCp62RestrictedFlows => canUseFeature('FIFO');

  bool get hasNationalWorkScope =>
      isAdminRole(role) || workScopeType?.toUpperCase() == 'NATIONAL';

  bool get canUseBankStatements =>
      canUseFeature('BANK_STATEMENTS') ||
      canUsePolicy('BANK_STATEMENT_ALL_SCOPE');

  bool get canUseAllBankStatementStores =>
      hasNationalWorkScope || canUsePolicy('BANK_STATEMENT_ALL_SCOPE');

  bool canUseFeature(String featureCode) {
    if (isSuperAdmin) return true;
    final resolved = featureAccess[featureCode];
    if (resolved != null) return resolved;
    return false;
  }

  bool canUsePolicy(String policyCode) {
    if (isSuperAdmin) return true;
    final resolved = policyAccess[policyCode];
    if (resolved != null) return resolved;
    return false;
  }

  User copyWith({
    Map<String, bool>? featureAccess,
    Map<String, bool>? policyAccess,
  }) {
    return User(
      id: id,
      email: email,
      emailDomain: emailDomain,
      name: name,
      lastName: lastName,
      avatarUrl: avatarUrl,
      storeId: storeId,
      storeName: storeName,
      role: role,
      status: status,
      departmentCode: departmentCode,
      jobRoleCode: jobRoleCode,
      workScopeType: workScopeType,
      regionCode: regionCode,
      regionName: regionName,
      regionAbbreviation: regionAbbreviation,
      areaCode: areaCode,
      areaName: areaName,
      areaAbbreviation: areaAbbreviation,
      organizationNodeId: organizationNodeId,
      organizationNodeName: organizationNodeName,
      featureCodes: featureCodes,
      personnelCode: personnelCode,
      featureAccess: featureAccess ?? this.featureAccess,
      policyAccess: policyAccess ?? this.policyAccess,
      assignmentPending: assignmentPending,
      mustSelectStore: mustSelectStore,
    );
  }

  static Map<String, bool> _featureAccessFromJson(Object? value) {
    if (value is! Map) return const {};
    return value.map(
      (key, access) => MapEntry(
        key.toString(),
        access == true || access.toString().toLowerCase() == 'true',
      ),
    );
  }

  String get storeInfo {
    if (storeId != null && storeName != null) {
      return '$storeId - $storeName';
    } else if (storeId != null) {
      return storeId!;
    } else if (storeName != null) {
      return storeName!;
    }
    return 'Chưa gán chi nhánh';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
        other.email == email &&
        other.emailDomain == emailDomain &&
        other.name == name &&
        other.lastName == lastName &&
        other.avatarUrl == avatarUrl &&
        other.storeId == storeId &&
        other.storeName == storeName &&
        other.role == role &&
        other.status == status &&
        other.departmentCode == departmentCode &&
        other.jobRoleCode == jobRoleCode &&
        other.workScopeType == workScopeType &&
        other.regionCode == regionCode &&
        other.regionName == regionName &&
        other.regionAbbreviation == regionAbbreviation &&
        other.areaCode == areaCode &&
        other.areaName == areaName &&
        other.areaAbbreviation == areaAbbreviation &&
        other.organizationNodeId == organizationNodeId &&
        other.organizationNodeName == organizationNodeName &&
        _listEquals(other.featureCodes, featureCodes) &&
        other.personnelCode == personnelCode &&
        _mapEquals(other.featureAccess, featureAccess) &&
        _mapEquals(other.policyAccess, policyAccess) &&
        other.assignmentPending == assignmentPending &&
        other.mustSelectStore == mustSelectStore;
  }

  static bool _mapEquals(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      email.hashCode ^
      emailDomain.hashCode ^
      name.hashCode ^
      lastName.hashCode ^
      avatarUrl.hashCode ^
      storeId.hashCode ^
      storeName.hashCode ^
      role.hashCode ^
      status.hashCode ^
      departmentCode.hashCode ^
      jobRoleCode.hashCode ^
      workScopeType.hashCode ^
      regionCode.hashCode ^
      regionName.hashCode ^
      regionAbbreviation.hashCode ^
      areaCode.hashCode ^
      areaName.hashCode ^
      areaAbbreviation.hashCode ^
      organizationNodeId.hashCode ^
      organizationNodeName.hashCode ^
      Object.hashAll(featureCodes) ^
      personnelCode.hashCode ^
      featureAccess.hashCode ^
      policyAccess.hashCode ^
      assignmentPending.hashCode ^
      mustSelectStore.hashCode;

  @override
  String toString() =>
      'User(email: $email, name: $name, storeId: $storeId, storeName: $storeName, role: $role, personnelCode: $personnelCode)';
}

List<String> _stringListFromJson(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
