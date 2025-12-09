class AuthRequest {
  final String type; // 'login', 'register', 'check_email'
  final String email;
  final String password;
  final String? name; // Họ tên cho register

  const AuthRequest({
    required this.type,
    required this.email,
    required this.password,
    this.name,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'type': type,
      'email': email,
      'password': password,
    };

    // Chỉ thêm name khi đăng ký
    if (name != null && name!.isNotEmpty) {
      json['name'] = name!;
    }

    return json;
  }
}
