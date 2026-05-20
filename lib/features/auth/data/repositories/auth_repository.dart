import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
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
      throw ApiException('Dang nhap that bai: $e');
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
      throw ApiException('Dang ky that bai: $e');
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
      throw ApiException('Không gửi được mã xác thực: $e');
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
          'Request thất bại: ${response.statusCode}',
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
    throw ApiException('Response format khong hop le');
  }

  (User, String?) _userAndTokenFromResponse(Map<String, dynamic> responseData) {
    final loginValue = responseData['login'];
    final bool loginSuccess = loginValue == true || loginValue == 'true';

    if (!loginSuccess) {
      final message =
          responseData['message']?.toString() ?? 'Dang nhap that bai';
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
      throw ApiException('Khong the lay thong tin user: $e');
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
    return data
        .map((item) => StoreBranch.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<StoreBranch> createAdminStore(Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      ApiConstants.adminStoresEndpoint,
      body: body,
    );
    return StoreBranch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<StoreBranch> updateAdminStore(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminStoresEndpoint}/$storeId',
      body: body,
    );
    return StoreBranch.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminStore(String storeId) async {
    await _apiClient.delete('${ApiConstants.adminStoresEndpoint}/$storeId');
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
    return data
        .map((item) => User.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<User> createAdminUser(Map<String, dynamic> body) async {
    final response = await _apiClient.post(
      ApiConstants.adminUsersEndpoint,
      body: body,
    );
    return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<User> updateAdminUser(String id, Map<String, dynamic> body) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminUsersEndpoint}/$id',
      body: body,
    );
    return User.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<AdminRoleDefinition>> listAdminRoles() async {
    final response = await _apiClient.get(ApiConstants.adminRolesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) => AdminRoleDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminRoleDefinition> createAdminRole(AdminRoleDefinition role) async {
    final response = await _apiClient.post(
      ApiConstants.adminRolesEndpoint,
      body: role.toJson(),
    );
    return AdminRoleDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminRoleDefinition> updateAdminRole(
    String code,
    AdminRoleDefinition role,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminRolesEndpoint}/$code',
      body: role.toJson(),
    );
    return AdminRoleDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminRole(String code) async {
    await _apiClient.delete('${ApiConstants.adminRolesEndpoint}/$code');
  }
}
