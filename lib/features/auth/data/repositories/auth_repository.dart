import 'dart:convert';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/constants/api_constants.dart';
import '../../domain/entities/user.dart';

class AuthRepository {
  final ApiClient _apiClient;

  AuthRepository(this._apiClient);

  /// Check email status: returns 'new', 'yes', or 'no'
  Future<String> checkEmail(String email) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.checkEmailEndpoint,
        body: {'user': email},
        timeout: ApiConstants.defaultTimeout,
      );

      print('📥 Check email response: ${response.body}');

      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      final String status = responseData['status']?.toString().trim().toLowerCase() ?? '';
      print('🔍 Email status: "$status" (length: ${status.length})');
      print('🔍 Response data: $responseData');

      if (status.isEmpty || !['new', 'yes', 'no'].contains(status)) {
        print('❌ Invalid status: "$status"');
        throw ApiException('Trạng thái email không hợp lệ');
      }

      print('✅ Returning status: "$status"');
      return status;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không thể kiểm tra email: $e');
    }
  }

  Future<User> login(String email, String password) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.loginEndpoint,
        body: {
          'user': email,
          'password': password,
        },
        timeout: ApiConstants.defaultTimeout,
      );

      print('📥 Login response: ${response.body}');

      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      // Check login field (handle both boolean true and string "true")
      final loginValue = responseData['login'];
      final bool loginSuccess = loginValue == true || loginValue == 'true' || loginValue == 'True';

      print('🔍 Login value: "$loginValue" (type: ${loginValue.runtimeType})');
      print('🔍 Login success: $loginSuccess');

      if (loginSuccess) {
        print('✅ Login success!');
        // Get firstName (or fall back to name or email)
        final firstName = responseData['firstName']?.toString() ??
                         responseData['firstname']?.toString() ??
                         responseData['name']?.toString();
        print('🔍 FirstName: "$firstName"');

        // Get store information and role
        final storeId = responseData['storeId']?.toString() ??
                       responseData['storeid']?.toString();
        final storeName = responseData['storeName']?.toString() ??
                         responseData['storename']?.toString();
        final role = responseData['role']?.toString();

        print('🔍 StoreId: "$storeId"');
        print('🔍 StoreName: "$storeName"');
        print('🔍 Role: "$role"');

        return User(
          email: email,
          name: firstName,
          storeId: storeId,
          storeName: storeName,
          role: role,
        );
      } else {
        throw ApiException('Email hoặc mật khẩu không đúng.');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Đăng nhập thất bại: $e');
    }
  }

  Future<void> register(String email, String password, String name) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.registerEndpoint,
        body: {
          'user': email,
          'password': password,
          // Don't send name to webhook
        },
        timeout: ApiConstants.defaultTimeout,
      );

      print('📥 Register response: ${response.body}');

      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      // Check register field (handle both boolean true and string "true")
      final registerValue = responseData['register'];
      final bool registerSuccess = registerValue == true || registerValue == 'true' || registerValue == 'True';

      print('🔍 Register value: "$registerValue" (type: ${registerValue.runtimeType})');
      print('🔍 Register success: $registerSuccess');

      if (registerSuccess) {
        print('✅ Register success!');
        return;
      } else {
        final message = responseData['message']?.toString() ?? 'Đăng ký thất bại. Vui lòng thử lại.';
        print('❌ Register failed: $message');
        throw ApiException(message);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Đăng ký thất bại: $e');
    }
  }

  Future<User> getUserData(String email) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.getUserEndpoint,
        body: {'user': email},
        timeout: ApiConstants.defaultTimeout,
      );

      print('📥 Get user response: ${response.body}');

      final dynamic jsonResponse = jsonDecode(response.body);

      Map<String, dynamic> responseData;
      if (jsonResponse is List && jsonResponse.isNotEmpty) {
        responseData = jsonResponse[0] as Map<String, dynamic>;
      } else if (jsonResponse is Map<String, dynamic>) {
        responseData = jsonResponse;
      } else {
        throw ApiException('Response format không hợp lệ');
      }

      final name = responseData['name']?.toString();
      final storeId = responseData['storeId']?.toString();
      final storeName = responseData['storeName']?.toString();

      print('🔍 Name: "$name"');
      print('🔍 StoreId: "$storeId"');
      print('🔍 StoreName: "$storeName"');

      return User(
        email: email,
        name: name,
        storeId: storeId,
        storeName: storeName,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không thể lấy thông tin user: $e');
    }
  }
}
