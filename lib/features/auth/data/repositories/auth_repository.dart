import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
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

        final user = User(
          email: responseData['email']?.toString() ?? '',
          name: firstName,
          storeId: storeId,
          storeName: storeName,
          role: role,
        );

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

      return User(
        email: email,
        name:
            responseData['name']?.toString() ??
            responseData['firstName']?.toString(),
        storeId: responseData['storeId']?.toString(),
        storeName: responseData['storeName']?.toString(),
        role: responseData['role']?.toString(),
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không thể lấy thông tin user: $e');
    }
  }
}
