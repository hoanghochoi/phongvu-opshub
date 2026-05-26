import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../admin/domain/admin_personnel_definition.dart';
import '../../../admin/domain/admin_role_definition.dart';
import '../../domain/entities/store_branch.dart';
import '../../domain/entities/user.dart';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  Future<(User, String?)> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _postPublicAuth(
        ApiConstants.loginEndpoint,
        body: {'email': email, 'password': password},
      );
      return _userAndTokenFromResponse(_readResponseMap(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không đăng nhập được. Vui lòng thử lại sau ít phút.');
    }
  }

  Future<(User, String?)> register({
    required String firstName,
    String? lastName,
    required String email,
    required String password,
    required String verificationCode,
  }) async {
    try {
      final response = await _postPublicAuth(
        ApiConstants.registerEndpoint,
        body: {
          'firstName': firstName,
          if (lastName != null && lastName.trim().isNotEmpty)
            'lastName': lastName,
          'email': email,
          'password': password,
          'verificationCode': verificationCode,
        },
      );
      return _userAndTokenFromResponse(_readResponseMap(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Không tạo được tài khoản. Vui lòng thử lại sau ít phút.',
      );
    }
  }

  Future<void> sendRegistrationVerificationCode({required String email}) async {
    try {
      await _postPublicAuth(
        ApiConstants.verificationCodeEndpoint,
        body: {'email': email},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không gửi được mã xác thực. Vui lòng thử lại.');
    }
  }

  Future<http.Response> _postPublicAuth(
    String endpoint, {
    required Map<String, dynamic> body,
  }) async {
    final response = await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}$endpoint'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(ApiConstants.defaultTimeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }

    throw ApiException(
      _messageFromResponse(response.body) ??
          'Chưa thực hiện được. Vui lòng kiểm tra lại thông tin và thử lại.',
      response.statusCode,
    );
  }

  String? _messageFromResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message;
        }
        if (message is List && message.isNotEmpty) {
          return message.join('\n');
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic> _readResponseMap(String body) {
    final dynamic jsonResponse = jsonDecode(body);

    if (jsonResponse is List && jsonResponse.isNotEmpty) {
      return jsonResponse[0] as Map<String, dynamic>;
    } else if (jsonResponse is Map<String, dynamic>) {
      return jsonResponse;
    }
    throw ApiException('Dữ liệu trả về chưa hợp lệ. Vui lòng thử lại.');
  }

  (User, String?) _userAndTokenFromResponse(Map<String, dynamic> responseData) {
    final loginValue = responseData['login'];
    final bool loginSuccess = loginValue == true || loginValue == 'true';

    if (!loginSuccess) {
      final message =
          responseData['message']?.toString() ?? 'Đăng nhập không thành công';
      throw ApiException(message);
    }

    final accessToken = responseData['access_token']?.toString();
    final firstName =
        responseData['firstName']?.toString() ??
        responseData['name']?.toString();
    final storeId = responseData['storeId']?.toString();
    final storeName = responseData['storeName']?.toString();
    final role = responseData['role']?.toString();

    _apiClient.setAuthToken(accessToken);

    final user = User.fromJson({
      ...responseData,
      'email': responseData['email']?.toString() ?? '',
      'name': firstName,
      'storeId': storeId,
      'storeName': storeName,
      'role': role,
    });

    return (user, accessToken);
  }

  Future<User> getUserData(String email) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.getUserEndpoint,
        body: {'user': email},
        timeout: ApiConstants.defaultTimeout,
      );

      return User.fromJson(
        _readResponseMap(response.body),
        fallbackEmail: email,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Không tải được thông tin tài khoản. Vui lòng thử lại.',
      );
    }
  }

  Future<List<StoreBranch>> getStores({String? query}) async {
    final response = await _apiClient.get(
      ApiConstants.storesEndpoint,
      queryParameters: query != null && query.trim().isNotEmpty
          ? {'q': query.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => StoreBranch.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<StoreBranch>> listAdminStores({String? query}) async {
    final response = await _apiClient.get(
      ApiConstants.adminStoresEndpoint,
      queryParameters: query != null && query.trim().isNotEmpty
          ? {'q': query.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final stores = data
        .map((item) => StoreBranch.fromJson(item as Map<String, dynamic>))
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin stores loaded',
      context: {'query': query, 'count': stores.length},
    );
    return stores;
  }

  Future<StoreBranch> createAdminStore(Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      ApiConstants.adminStoresEndpoint,
      body: body,
    );
    final store = StoreBranch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin store created',
      context: {'storeId': store.storeId},
    );
    return store;
  }

  Future<StoreBranch> updateAdminStore(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminStoresEndpoint}/$storeId',
      body: body,
    );
    final store = StoreBranch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin store updated',
      context: {'storeId': store.storeId},
    );
    return store;
  }

  Future<void> deleteAdminStore(String storeId) async {
    await _apiClient.delete('${ApiConstants.adminStoresEndpoint}/$storeId');
    await AppLogger.instance.warn(
      'Admin',
      'Admin store deleted',
      context: {'storeId': storeId},
    );
  }

  Future<User> selectStore(String storeId, String email) async {
    final response = await _apiClient.post(
      ApiConstants.selectStoreEndpoint,
      body: {'storeId': storeId},
    );
    return User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackEmail: email,
    );
  }

  Future<User> updateProfile({
    required String email,
    required String firstName,
    String? lastName,
  }) async {
    final response = await _apiClient.patch(
      ApiConstants.profileEndpoint,
      body: {'firstName': firstName, 'lastName': lastName},
    );
    return User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackEmail: email,
    );
  }

  Future<User> uploadAvatar({
    required String email,
    required String path,
  }) async {
    final response = await _apiClient.postMultipart(
      ApiConstants.avatarEndpoint,
      fields: const {},
      files: [await http.MultipartFile.fromPath('avatar', path)],
      timeout: ApiConstants.uploadTimeout,
    );
    return User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackEmail: email,
    );
  }

  Future<List<User>> listUsers({String? query}) async {
    final response = await _apiClient.get(
      ApiConstants.adminUsersEndpoint,
      queryParameters: query != null && query.trim().isNotEmpty
          ? {'q': query.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final users = data
        .map((item) => User.fromJson(item as Map<String, dynamic>))
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin users loaded',
      context: {'query': query, 'count': users.length},
    );
    return users;
  }

  Future<User> createAdminUser(Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      ApiConstants.adminUsersEndpoint,
      body: body,
    );
    final user = User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin user created',
      context: {
        'email': user.email,
        'role': user.role,
        'storeId': user.storeId,
        'personnelCode': user.personnelCode,
      },
    );
    return user;
  }

  Future<User> updateAdminUser(String id, Map<String, dynamic> body) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminUsersEndpoint}/$id',
      body: body,
    );
    final user = User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin user updated',
      context: {
        'email': user.email,
        'role': user.role,
        'storeId': user.storeId,
        'personnelCode': user.personnelCode,
      },
    );
    return user;
  }

  Future<List<AdminPersonnelDefinition>> listAdminDepartments() async {
    final response = await _apiClient.get(
      ApiConstants.adminDepartmentsEndpoint,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final departments = data
        .map(
          (item) =>
              AdminPersonnelDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin departments loaded',
      context: {'count': departments.length},
    );
    return departments;
  }

  Future<List<AdminPersonnelDefinition>> listAdminJobRoles() async {
    final response = await _apiClient.get(ApiConstants.adminJobRolesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    final jobRoles = data
        .map(
          (item) =>
              AdminPersonnelDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin job roles loaded',
      context: {'count': jobRoles.length},
    );
    return jobRoles;
  }

  Future<List<AdminRoleDefinition>> listAdminRoles() async {
    final response = await _apiClient.get(ApiConstants.adminRolesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    final roles = data
        .map(
          (item) => AdminRoleDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin roles loaded',
      context: {'count': roles.length},
    );
    return roles;
  }

  Future<AdminRoleDefinition> createAdminRole(AdminRoleDefinition role) async {
    final response = await _apiClient.post(
      ApiConstants.adminRolesEndpoint,
      body: role.toJson(),
    );
    final created = AdminRoleDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin role created',
      context: {'role': created.value},
    );
    return created;
  }

  Future<AdminRoleDefinition> updateAdminRole(
    String code,
    AdminRoleDefinition role,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminRolesEndpoint}/$code',
      body: role.toJson(),
    );
    final updated = AdminRoleDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin role updated',
      context: {'role': updated.value},
    );
    return updated;
  }

  Future<void> deleteAdminRole(String code) async {
    await _apiClient.delete('${ApiConstants.adminRolesEndpoint}/$code');
    await AppLogger.instance.warn(
      'Admin',
      'Admin role deleted',
      context: {'role': code},
    );
  }
}
