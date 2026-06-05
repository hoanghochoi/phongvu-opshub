import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../admin/domain/admin_feature_definition.dart';
import '../../../admin/domain/admin_personnel_definition.dart';
import '../../../admin/domain/admin_role_definition.dart';
import '../auth_device_info.dart';
import '../../domain/entities/store_branch.dart';
import '../../domain/entities/user.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final AuthDeviceInfoProvider _deviceInfoProvider;
  final http.Client _publicClient;

  AuthRepository(
    this._apiClient, {
    AuthDeviceInfoProvider? deviceInfoProvider,
    http.Client? publicClient,
  }) : _deviceInfoProvider = deviceInfoProvider ?? AuthDeviceInfoProvider(),
       _publicClient = publicClient ?? http.Client();

  Future<(User, String?)> login({
    required String email,
    required String password,
  }) async {
    try {
      final device = await _deviceInfoProvider.load();
      final response = await _postPublicAuth(
        ApiConstants.loginEndpoint,
        body: {'email': email, 'password': password, ...device.toJson()},
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
      final device = await _deviceInfoProvider.load();
      final response = await _postPublicAuth(
        ApiConstants.registerEndpoint,
        body: {
          'firstName': firstName,
          if (lastName != null && lastName.trim().isNotEmpty)
            'lastName': lastName,
          'email': email,
          'password': password,
          'verificationCode': verificationCode,
          ...device.toJson(),
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

  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _postPublicAuth(
        ApiConstants.forgotPasswordEndpoint,
        body: {'email': email},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Không gửi được email đổi mật khẩu. Vui lòng thử lại.',
      );
    }
  }

  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _postPublicAuth(
        ApiConstants.forgotPasswordVerifyCodeEndpoint,
        body: {'email': email, 'code': code},
      );
      final data = _readResponseMap(response.body);
      final resetToken = data['resetToken']?.toString();
      if (resetToken == null || resetToken.isEmpty) {
        throw ApiException('Mã xác thực chưa hợp lệ. Vui lòng thử lại.');
      }
      return resetToken;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không xác thực được mã. Vui lòng thử lại.');
    }
  }

  Future<void> resetForgottenPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    try {
      await _postPublicAuth(
        ApiConstants.resetPasswordEndpoint,
        body: {'token': resetToken, 'newPassword': newPassword},
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không đổi được mật khẩu. Vui lòng thử lại.');
    }
  }

  Future<(User, String?)> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.changePasswordEndpoint,
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
        timeout: ApiConstants.defaultTimeout,
      );
      return _userAndTokenFromResponse(_readResponseMap(response.body));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không đổi được mật khẩu. Vui lòng thử lại.');
    }
  }

  Future<void> logout() async {
    await _apiClient.post(ApiConstants.logoutEndpoint, body: const {});
  }

  Future<http.Response> _postPublicAuth(
    String endpoint, {
    required Map<String, dynamic> body,
  }) async {
    final response = await _publicClient
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

  Future<Map<String, bool>> getMyFeatureAccess() async {
    final response = await _apiClient.get(ApiConstants.featuresMeEndpoint);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data.map(
      (key, value) => MapEntry(
        key,
        value == true || value.toString().toLowerCase() == 'true',
      ),
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

  Future<void> resetAdminUserPassword(
    String id, {
    required String email,
    required String newPassword,
  }) async {
    await _apiClient.post(
      ApiConstants.adminUserResetPasswordEndpoint(id),
      body: {'newPassword': newPassword},
    );
    await AppLogger.instance.warn(
      'Admin',
      'Admin user password changed',
      context: {'userId': id, 'email': email},
    );
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

  Future<AdminPersonnelDefinition> createAdminDepartment(
    AdminPersonnelDefinition department,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminDepartmentsEndpoint,
      body: department.toJson(),
    );
    return AdminPersonnelDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminPersonnelDefinition> updateAdminDepartment(
    String code,
    AdminPersonnelDefinition department,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminDepartmentsEndpoint}/$code',
      body: department.toJson(),
    );
    return AdminPersonnelDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminDepartment(String code) async {
    await _apiClient.delete('${ApiConstants.adminDepartmentsEndpoint}/$code');
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

  Future<AdminPersonnelDefinition> createAdminJobRole(
    AdminPersonnelDefinition jobRole,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminJobRolesEndpoint,
      body: jobRole.toJson(),
    );
    return AdminPersonnelDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminPersonnelDefinition> updateAdminJobRole(
    String code,
    AdminPersonnelDefinition jobRole,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminJobRolesEndpoint}/$code',
      body: jobRole.toJson(),
    );
    return AdminPersonnelDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminJobRole(String code) async {
    await _apiClient.delete('${ApiConstants.adminJobRolesEndpoint}/$code');
  }

  Future<List<AdminRegionDefinition>> listAdminRegions() async {
    final response = await _apiClient.get(ApiConstants.adminRegionsEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) =>
              AdminRegionDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminRegionDefinition> createAdminRegion(
    AdminRegionDefinition region,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminRegionsEndpoint,
      body: region.toJson(),
    );
    return AdminRegionDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminRegionDefinition> updateAdminRegion(
    String code,
    AdminRegionDefinition region,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminRegionsEndpoint}/$code',
      body: region.toJson(),
    );
    return AdminRegionDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminRegion(String code) async {
    await _apiClient.delete('${ApiConstants.adminRegionsEndpoint}/$code');
  }

  Future<List<AdminAreaDefinition>> listAdminAreas({String? regionCode}) async {
    final response = await _apiClient.get(
      ApiConstants.adminAreasEndpoint,
      queryParameters: regionCode?.trim().isNotEmpty == true
          ? {'regionCode': regionCode!.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) => AdminAreaDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminAreaDefinition> createAdminArea(AdminAreaDefinition area) async {
    final response = await _apiClient.post(
      ApiConstants.adminAreasEndpoint,
      body: area.toJson(),
    );
    return AdminAreaDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminAreaDefinition> updateAdminArea(
    String code,
    AdminAreaDefinition area,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminAreasEndpoint}/$code',
      body: area.toJson(),
    );
    return AdminAreaDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminArea(String code) async {
    await _apiClient.delete('${ApiConstants.adminAreasEndpoint}/$code');
  }

  Future<List<AdminFeatureDefinition>> listAdminFeatures() async {
    final response = await _apiClient.get(ApiConstants.adminFeaturesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    final features = data
        .map(
          (item) =>
              AdminFeatureDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin features loaded',
      context: {'count': features.length},
    );
    return features;
  }

  Future<AdminFeatureDefinition> createAdminFeature(
    AdminFeatureDefinition feature,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminFeaturesEndpoint,
      body: feature.toJson(),
    );
    final created = AdminFeatureDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin feature created',
      context: {'featureCode': created.code},
    );
    return created;
  }

  Future<AdminFeatureDefinition> updateAdminFeature(
    String code,
    AdminFeatureDefinition feature,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminFeaturesEndpoint}/$code',
      body: feature.toJson(),
    );
    final updated = AdminFeatureDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'Admin',
      'Admin feature updated',
      context: {'featureCode': updated.code},
    );
    return updated;
  }

  Future<void> deleteAdminFeature(String code) async {
    await _apiClient.delete('${ApiConstants.adminFeaturesEndpoint}/$code');
    await AppLogger.instance.warn(
      'Admin',
      'Admin feature deleted',
      context: {'featureCode': code},
    );
  }

  Future<List<AdminFeatureRule>> listAdminFeatureRules({
    String? featureCode,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminFeatureRulesEndpoint,
      queryParameters: featureCode?.trim().isNotEmpty == true
          ? {'featureCode': featureCode!.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => AdminFeatureRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminFeatureRule> createAdminFeatureRule(AdminFeatureRule rule) async {
    final response = await _apiClient.post(
      ApiConstants.adminFeatureRulesEndpoint,
      body: rule.toJson(),
    );
    return AdminFeatureRule.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<AdminFeatureRule>> createAdminFeatureRulesBatch(
    AdminFeatureRuleBatchRequest request,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminFeatureRulesBatchEndpoint,
      body: request.toJson(),
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final rules = data
        .map((item) => AdminFeatureRule.fromJson(item as Map<String, dynamic>))
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin feature rules batch created',
      context: {'featureCode': request.featureCode, 'count': rules.length},
    );
    return rules;
  }

  Future<AdminFeatureRule> updateAdminFeatureRule(
    String id,
    AdminFeatureRule rule,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminFeatureRulesEndpoint}/$id',
      body: rule.toJson(),
    );
    return AdminFeatureRule.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminFeatureRule(String id) async {
    await _apiClient.delete('${ApiConstants.adminFeatureRulesEndpoint}/$id');
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
