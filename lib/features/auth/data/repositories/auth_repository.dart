import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../admin/domain/admin_feature_definition.dart';
import '../../../admin/domain/admin_organization_node.dart';
import '../../../admin/domain/admin_personnel_definition.dart';
import '../../../admin/domain/admin_policy_definition.dart';
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

  Future<Map<String, bool>> getMyFeatureAccess() async {
    final response = await _apiClient.get(ApiConstants.featuresMeEndpoint);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _boolMapFromJson(data);
  }

  Future<Map<String, bool>> getMyPolicyAccess() async {
    final response = await _apiClient.get(ApiConstants.policiesMeEndpoint);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _boolMapFromJson(data);
  }

  Map<String, bool> _boolMapFromJson(Map<String, dynamic> data) {
    return data.map(
      (key, value) => MapEntry(
        key,
        value == true || value.toString().toLowerCase() == 'true',
      ),
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
    String? path,
    Uint8List? bytes,
    required String fileName,
  }) async {
    final multipartFile = await _avatarMultipartFile(
      path: path,
      bytes: bytes,
      fileName: fileName,
    );
    final response = await _apiClient.postMultipart(
      ApiConstants.avatarEndpoint,
      fields: const {},
      files: [multipartFile],
      timeout: ApiConstants.uploadTimeout,
    );
    return User.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
      fallbackEmail: email,
    );
  }

  Future<http.MultipartFile> _avatarMultipartFile({
    String? path,
    Uint8List? bytes,
    required String fileName,
  }) async {
    if (path == null && bytes == null) {
      throw ApiException('Chưa đọc được file ảnh. Vui lòng chọn ảnh khác.');
    }

    final mimeType = avatarMimeTypeFor(fileName: fileName, path: path);
    if (mimeType == null) {
      throw ApiException('Chỉ hỗ trợ ảnh JPG, PNG, WebP, HEIC hoặc HEIF.');
    }

    final uploadFileName = _safeUploadFileName(fileName, path, mimeType);
    final mediaType = MediaType.parse(mimeType);
    if (path != null) {
      return http.MultipartFile.fromPath(
        'avatar',
        path,
        filename: uploadFileName,
        contentType: mediaType,
      );
    }

    return http.MultipartFile.fromBytes(
      'avatar',
      bytes!,
      filename: uploadFileName,
      contentType: mediaType,
    );
  }

  static String? avatarMimeTypeFor({required String fileName, String? path}) {
    final extension = _extensionFor(fileName).isNotEmpty
        ? _extensionFor(fileName)
        : _extensionFor(path ?? '');
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
  }

  static String _safeUploadFileName(
    String fileName,
    String? path,
    String mimeType,
  ) {
    final trimmed = fileName.trim();
    if (trimmed.isNotEmpty) return trimmed;

    final pathName = _lastPathSegment(path ?? '').trim();
    if (pathName.isNotEmpty) return pathName;

    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      _ => 'jpg',
    };
    return 'avatar.$extension';
  }

  static String _extensionFor(String value) {
    final name = _lastPathSegment(value).toLowerCase();
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).split('?').first;
  }

  static String _lastPathSegment(String value) {
    final normalized = value.replaceAll('\\', '/');
    final segments = normalized.split('/').where((part) => part.isNotEmpty);
    return segments.isEmpty ? '' : segments.last;
  }

  Future<List<User>> listUsers({
    String? query,
    String? domain,
    String? orgNodeId,
    String? featureCode,
    String? role,
    String? status,
  }) async {
    final queryParameters = <String, String>{
      if (query?.trim().isNotEmpty == true) 'q': query!.trim(),
      if (domain?.trim().isNotEmpty == true) 'domain': domain!.trim(),
      if (orgNodeId?.trim().isNotEmpty == true) 'orgNodeId': orgNodeId!.trim(),
      if (featureCode?.trim().isNotEmpty == true)
        'featureCode': featureCode!.trim(),
      if (role?.trim().isNotEmpty == true) 'role': role!.trim(),
      if (status?.trim().isNotEmpty == true) 'status': status!.trim(),
    };
    final response = await _apiClient.get(
      ApiConstants.adminUsersEndpoint,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final users = data
        .map((item) => User.fromJson(item as Map<String, dynamic>))
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin users loaded',
      context: {
        'query': query,
        'domain': domain,
        'orgNodeId': orgNodeId,
        'featureCode': featureCode,
        'role': role,
        'status': status,
        'count': users.length,
      },
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

  Future<List<AdminOrganizationNode>> listAdminOrganizationTree() async {
    final response = await _apiClient.get(ApiConstants.adminOrgTreeEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    final nodes = data
        .map(
          (item) =>
              AdminOrganizationNode.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'AdminOrganization',
      'Organization tree loaded',
      context: {'count': nodes.length},
    );
    return nodes;
  }

  Future<List<AdminOrganizationNode>> listAdminUserScopeTree() async {
    final response = await _apiClient.get(
      ApiConstants.adminUserScopeTreeEndpoint,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final nodes = data
        .map(
          (item) =>
              AdminOrganizationNode.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'Admin',
      'Admin user scope tree loaded',
      context: {'count': nodes.length},
    );
    return nodes;
  }

  Future<List<AdminOrganizationNode>> listAdminPolicyScopeTree() async {
    final response = await _apiClient.get(
      ApiConstants.adminPolicyScopeTreeEndpoint,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final nodes = data
        .map(
          (item) =>
              AdminOrganizationNode.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'AdminPolicies',
      'Admin policy scope tree loaded',
      context: {'count': nodes.length},
    );
    return nodes;
  }

  Future<AdminOrganizationNode> createAdminOrganizationNode(
    AdminOrganizationNode node,
  ) async {
    return createAdminOrganizationNodeBody(node.toJson());
  }

  Future<AdminOrganizationNode> createAdminOrganizationNodeBody(
    Map<String, dynamic> body,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminOrgTreeNodesEndpoint,
      body: body,
    );
    final created = AdminOrganizationNode.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'AdminOrganization',
      'Organization node created',
      context: {'nodeId': created.id, 'type': created.type},
    );
    return created;
  }

  Future<AdminOrganizationNode> updateAdminOrganizationNode(
    String id,
    AdminOrganizationNode node,
  ) async {
    return updateAdminOrganizationNodeBody(id, node.toJson());
  }

  Future<AdminOrganizationNode> updateAdminOrganizationNodeBody(
    String id,
    Map<String, dynamic> body,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminOrgTreeNodesEndpoint}/$id',
      body: body,
    );
    final updated = AdminOrganizationNode.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'AdminOrganization',
      'Organization node updated',
      context: {'nodeId': updated.id, 'type': updated.type},
    );
    return updated;
  }

  Future<void> deleteAdminOrganizationNode(String id) async {
    await _apiClient.delete('${ApiConstants.adminOrgTreeNodesEndpoint}/$id');
    await AppLogger.instance.warn(
      'AdminOrganization',
      'Organization node delete requested',
      context: {'nodeId': id},
    );
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

  Future<List<AdminFeatureDefinition>> listAdminFeatureTree() async {
    final response = await _apiClient.get(
      ApiConstants.adminFeaturesTreeEndpoint,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) =>
              AdminFeatureDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
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

  Future<List<AdminNodeFeatureAssignment>> listAdminFeatureNodeAssignments({
    String? featureCode,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminFeatureNodeAssignmentsEndpoint,
      queryParameters: featureCode?.trim().isNotEmpty == true
          ? {'featureCode': featureCode!.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final assignments = data
        .map(
          (item) =>
              AdminNodeFeatureAssignment.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'AdminFeatures',
      'Node feature assignments loaded',
      context: {'featureCode': featureCode, 'count': assignments.length},
    );
    return assignments;
  }

  Future<List<AdminNodeFeatureAssignment>> saveAdminFeatureNodeAssignments(
    AdminNodeFeatureAssignmentBatchRequest request,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminFeatureNodeAssignmentsBatchEndpoint,
      body: request.toJson(),
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    final assignments = data
        .map(
          (item) =>
              AdminNodeFeatureAssignment.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    await AppLogger.instance.info(
      'AdminFeatures',
      'Node feature assignments saved',
      context: {
        'nodes': request.organizationNodeIds.length,
        'features': request.featureTreeCodes.length,
        'replaceExisting': request.replaceExisting,
        'resultCount': assignments.length,
      },
    );
    return assignments;
  }

  Future<AdminNodeFeatureAssignment> updateAdminFeatureNodeAssignment(
    String id, {
    required bool enabled,
  }) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminFeatureNodeAssignmentsEndpoint}/$id',
      body: {'enabled': enabled},
    );
    final assignment = AdminNodeFeatureAssignment.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    await AppLogger.instance.info(
      'AdminFeatures',
      'Node feature assignment updated',
      context: {
        'assignmentId': id,
        'featureCode': assignment.featureCode,
        'enabled': assignment.enabled,
      },
    );
    return assignment;
  }

  Future<void> deleteAdminFeatureNodeAssignment(String id) async {
    await _apiClient.delete(
      '${ApiConstants.adminFeatureNodeAssignmentsEndpoint}/$id',
    );
    await AppLogger.instance.warn(
      'AdminFeatures',
      'Node feature assignment deleted',
      context: {'assignmentId': id},
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
      context: {
        'featureCode': request.featureCode,
        'count': rules.length,
        'domainCount': request.emailDomains.length,
      },
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

  Future<List<AdminPolicyDefinition>> listAdminPolicies() async {
    final response = await _apiClient.get(ApiConstants.adminPoliciesEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) =>
              AdminPolicyDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminPolicyDefinition> createAdminPolicy(
    AdminPolicyDefinition policy,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminPoliciesEndpoint,
      body: policy.toJson(),
    );
    return AdminPolicyDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminPolicyDefinition> updateAdminPolicy(
    String code,
    AdminPolicyDefinition policy,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminPoliciesEndpoint}/$code',
      body: policy.toJson(),
    );
    return AdminPolicyDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminPolicy(String code) async {
    await _apiClient.delete('${ApiConstants.adminPoliciesEndpoint}/$code');
  }

  Future<List<AdminPolicyRule>> listAdminPolicyRules({
    String? policyCode,
  }) async {
    final response = await _apiClient.get(
      ApiConstants.adminPolicyRulesEndpoint,
      queryParameters: policyCode?.trim().isNotEmpty == true
          ? {'policyCode': policyCode!.trim()}
          : null,
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => AdminPolicyRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminPolicyRule> createAdminPolicyRule(AdminPolicyRule rule) async {
    final response = await _apiClient.post(
      ApiConstants.adminPolicyRulesEndpoint,
      body: rule.toJson(),
    );
    return AdminPolicyRule.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<List<AdminPolicyRule>> createAdminPolicyRulesBatch(
    AdminPolicyRuleBatchRequest request,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminPolicyRulesBatchEndpoint,
      body: request.toJson(),
    );
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => AdminPolicyRule.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AdminPolicyRule> updateAdminPolicyRule(
    String id,
    AdminPolicyRule rule,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminPolicyRulesEndpoint}/$id',
      body: rule.toJson(),
    );
    return AdminPolicyRule.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> deleteAdminPolicyRule(String id) async {
    await _apiClient.delete('${ApiConstants.adminPolicyRulesEndpoint}/$id');
  }

  Future<List<AdminSettingDefinition>> listAdminSettings() async {
    final response = await _apiClient.get(ApiConstants.adminSettingsEndpoint);
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map(
          (item) =>
              AdminSettingDefinition.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<AdminSettingDefinition> createAdminSetting(
    AdminSettingDefinition setting,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.adminSettingsEndpoint,
      body: setting.toJson(),
    );
    return AdminSettingDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminSettingDefinition> updateAdminSetting(
    String key,
    AdminSettingDefinition setting,
  ) async {
    final response = await _apiClient.patch(
      '${ApiConstants.adminSettingsEndpoint}/$key',
      body: setting.toJson(),
    );
    return AdminSettingDefinition.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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
