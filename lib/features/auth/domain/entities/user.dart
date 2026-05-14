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
      mustSelectStore:
          json['mustSelectStore'] == true || json['mustSelectStore'] == 'true',
    );
  }

  bool get isAdmin => role == 'ADMIN' || role == 'SUPER_ADMIN';

  bool get needsStoreSelection =>
      !isAdmin && (mustSelectStore || storeId == null);

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
      mustSelectStore.hashCode;

  @override
  String toString() =>
      'User(email: $email, name: $name, storeId: $storeId, storeName: $storeName, role: $role)';
}
