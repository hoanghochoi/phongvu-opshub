import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/store_branch.dart';
import '../../domain/entities/user.dart';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  /// Login with Google ID Token — returns (User, JWT token)
  Future<(User, String?)> googleLogin(String idToken) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.googleLoginEndpoint,
        body: {'idToken': idToken},
        timeout: ApiConstants.defaultTimeout,
      );

      if (kDebugMode) debugPrint('📥 Google login response: ${response.body}');
      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      final loginValue = responseData['login'];
      final bool loginSuccess = loginValue == true || loginValue == 'true';

      if (loginSuccess) {
        final accessToken = responseData['access_token']?.toString();
        final firstName =
            responseData['firstName']?.toString() ??
            responseData['name']?.toString();
        final storeId = responseData['storeId']?.toString();
        final storeName = responseData['storeName']?.toString();
        final role = responseData['role']?.toString();

        if (kDebugMode) {
          final tokenPreview = accessToken != null && accessToken.length >= 10
              ? '${accessToken.substring(0, 10)}...'
              : accessToken;
          debugPrint('✅ Google login success! token: $tokenPreview');
        }

        // Save token to ApiClient for future authorized requests
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
      } else {
        final message =
            responseData['message']?.toString() ?? 'Đăng nhập thất bại';
        throw ApiException(message);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Đăng nhập Google thất bại: $e');
    }
  }

  Future<User> getUserData(String email) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.getUserEndpoint,
        body: {'user': email},
        timeout: ApiConstants.defaultTimeout,
      );

      if (kDebugMode) debugPrint('📥 Get user response: ${response.body}');
      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      return User.fromJson(responseData, fallbackEmail: email);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không thể lấy thông tin user: $e');
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
}
