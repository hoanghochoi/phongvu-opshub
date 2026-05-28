class User {
  final String? id;
  final String email;
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
  final String? personnelCode;
  final bool mustSelectStore;

  const User({
    this.id,
    required this.email,
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
    this.personnelCode,
    this.mustSelectStore = false,
  });

  factory User.fromJson(Map<String, dynamic> json, {String? fallbackEmail}) {
    return User(
      id: json['id']?.toString(),
      email: json['email']?.toString() ?? fallbackEmail ?? '',
      name: json['name']?.toString() ?? json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      storeId: json['storeId']?.toString(),
      storeName: json['storeName']?.toString(),
      role: json['role']?.toString(),
      status: json['status']?.toString(),
      departmentCode: json['departmentCode']?.toString(),
      jobRoleCode: json['jobRoleCode']?.toString(),
      workScopeType: json['workScopeType']?.toString(),
      personnelCode: json['personnelCode']?.toString(),
      mustSelectStore:
          json['mustSelectStore'] == true || json['mustSelectStore'] == 'true',
    );
  }

  bool get isAdmin =>
      role == 'ADMIN' || role == 'SUPER_ADMIN' || role == 'MANAGER';

  bool get needsStoreSelection =>
      (workScopeType ??
              (role == 'SUPER_ADMIN' || role == 'ADMIN'
                  ? 'NATIONAL'
                  : 'STORE')) ==
          'STORE' &&
      (mustSelectStore || storeId == null);

  bool get belongsToCp62 {
    final values = [storeId, storeName, personnelCode, workScopeType];
    return values.any((value) => value?.toUpperCase().contains('CP62') == true);
  }

  bool get canUseCp62RestrictedFlows => role == 'SUPER_ADMIN' || belongsToCp62;

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
        other.personnelCode == personnelCode &&
        other.mustSelectStore == mustSelectStore;
  }

  @override
  int get hashCode =>
      email.hashCode ^
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
      personnelCode.hashCode ^
      mustSelectStore.hashCode;

  @override
  String toString() =>
      'User(email: $email, name: $name, storeId: $storeId, storeName: $storeName, role: $role, personnelCode: $personnelCode)';
}
