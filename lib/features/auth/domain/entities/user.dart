class User {
  final String email;
  final String? name;
  final String? storeId;
  final String? storeName;
  final String? role;

  const User({
    required this.email,
    this.name,
    this.storeId,
    this.storeName,
    this.role,
  });

  String get storeInfo {
    if (storeId != null && storeName != null) {
      return '$storeId: $storeName';
    } else if (storeId != null) {
      return '$storeId: #N/A';
    } else if (storeName != null) {
      return '#N/A: $storeName';
    }
    return '#N/A';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
        other.email == email &&
        other.name == name &&
        other.storeId == storeId &&
        other.storeName == storeName &&
        other.role == role;
  }

  @override
  int get hashCode =>
      email.hashCode ^
      name.hashCode ^
      storeId.hashCode ^
      storeName.hashCode ^
      role.hashCode;

  @override
  String toString() =>
      'User(email: $email, name: $name, storeId: $storeId, storeName: $storeName, role: $role)';
}
