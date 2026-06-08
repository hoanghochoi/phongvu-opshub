import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';

class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  static const _jwtTokenKey = 'user_jwt_token';
  static const _sessionExpiredMessage =
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';

  final AuthRepository _repository;

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  String? _sessionExpiredDialogMessage;
  bool _isInitialized = false;

  AuthProvider(this._repository) {
    ApiClient().setAuthFailureHandler(_handleRemoteAuthFailure);
    _loadSavedSession();
  }

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get errorMessage => _errorMessage;
  String? get sessionExpiredDialogMessage => _sessionExpiredDialogMessage;
  bool get isInitialized => _isInitialized;

  /// Load saved session from SharedPreferences
  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      final name = prefs.getString('user_name');
      final lastName = prefs.getString('user_lastName');
      final avatarUrl = prefs.getString('user_avatarUrl');
      final storeId = prefs.getString('user_storeId');
      final storeName = prefs.getString('user_storeName');
      final role = prefs.getString('user_role');
      final status = prefs.getString('user_status');
      final departmentCode = prefs.getString('user_departmentCode');
      final jobRoleCode = prefs.getString('user_jobRoleCode');
      final workScopeType = prefs.getString('user_workScopeType');
      final regionCode = prefs.getString('user_regionCode');
      final regionName = prefs.getString('user_regionName');
      final regionAbbreviation = prefs.getString('user_regionAbbreviation');
      final areaCode = prefs.getString('user_areaCode');
      final areaName = prefs.getString('user_areaName');
      final areaAbbreviation = prefs.getString('user_areaAbbreviation');
      final personnelCode = prefs.getString('user_personnelCode');
      final token = await _readSavedToken(prefs);

      if (email != null) {
        _user = User(
          email: email,
          name: name,
          lastName: lastName,
          avatarUrl: avatarUrl,
          storeId: storeId,
          storeName: storeName,
          role: role,
          status: status,
          departmentCode: departmentCode,
          jobRoleCode: jobRoleCode,
          workScopeType: workScopeType,
          regionCode: regionCode,
          regionName: regionName,
          regionAbbreviation: regionAbbreviation,
          areaCode: areaCode,
          areaName: areaName,
          areaAbbreviation: areaAbbreviation,
          personnelCode: personnelCode,
          mustSelectStore:
              (workScopeType ??
                      (User.isAdminRole(role) ? 'NATIONAL' : 'STORE')) ==
                  'STORE' &&
              storeId == null,
        );

        // Restore JWT token to ApiClient for authenticated API calls
        if (token != null) {
          ApiClient().setAuthToken(token);
          _user = await _withFeatureAccess(_user!, allowFallback: false);
          _queueDailyActivityLogUpload();
          if (kDebugMode) debugPrint('✅ [AuthProvider] Restored JWT token');
        }

        if (kDebugMode) debugPrint('✅ [AuthProvider] Loaded session: $email');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error loading session: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Save session to SharedPreferences (including JWT token)
  Future<void> _saveSession(User user, {String? token}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', user.email);
      if (user.name != null) {
        await prefs.setString('user_name', user.name!);
      }
      if (user.lastName != null) {
        await prefs.setString('user_lastName', user.lastName!);
      } else {
        await prefs.remove('user_lastName');
      }
      if (user.avatarUrl != null) {
        await prefs.setString('user_avatarUrl', user.avatarUrl!);
      } else {
        await prefs.remove('user_avatarUrl');
      }
      if (user.storeId != null) {
        await prefs.setString('user_storeId', user.storeId!);
      } else {
        await prefs.remove('user_storeId');
      }
      if (user.storeName != null) {
        await prefs.setString('user_storeName', user.storeName!);
      } else {
        await prefs.remove('user_storeName');
      }
      if (user.role != null) {
        await prefs.setString('user_role', user.role!);
      }
      if (user.status != null) {
        await prefs.setString('user_status', user.status!);
      }
      await _saveOptionalString(
        prefs,
        'user_departmentCode',
        user.departmentCode,
      );
      await _saveOptionalString(prefs, 'user_jobRoleCode', user.jobRoleCode);
      await _saveOptionalString(
        prefs,
        'user_workScopeType',
        user.workScopeType,
      );
      await _saveOptionalString(prefs, 'user_regionCode', user.regionCode);
      await _saveOptionalString(prefs, 'user_regionName', user.regionName);
      await _saveOptionalString(
        prefs,
        'user_regionAbbreviation',
        user.regionAbbreviation,
      );
      await _saveOptionalString(prefs, 'user_areaCode', user.areaCode);
      await _saveOptionalString(prefs, 'user_areaName', user.areaName);
      await _saveOptionalString(
        prefs,
        'user_areaAbbreviation',
        user.areaAbbreviation,
      );
      await _saveOptionalString(
        prefs,
        'user_personnelCode',
        user.personnelCode,
      );
      if (token != null) {
        await _secureStorage.write(key: _jwtTokenKey, value: token);
        await prefs.remove(_jwtTokenKey);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error saving session: $e');
    }
  }

  /// Clear session from SharedPreferences
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      await prefs.remove('user_lastName');
      await prefs.remove('user_avatarUrl');
      await prefs.remove('user_storeId');
      await prefs.remove('user_storeName');
      await prefs.remove('user_role');
      await prefs.remove('user_status');
      await prefs.remove('user_departmentCode');
      await prefs.remove('user_jobRoleCode');
      await prefs.remove('user_workScopeType');
      await prefs.remove('user_regionCode');
      await prefs.remove('user_regionName');
      await prefs.remove('user_regionAbbreviation');
      await prefs.remove('user_areaCode');
      await prefs.remove('user_areaName');
      await prefs.remove('user_areaAbbreviation');
      await prefs.remove('user_personnelCode');
      await prefs.remove(_jwtTokenKey);
      await _secureStorage.delete(key: _jwtTokenKey);
      ApiClient().setAuthToken(null);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error clearing session: $e');
    }
  }

  Future<void> _handleRemoteAuthFailure(ApiException exception) async {
    final email = _user?.email;
    if (email == null) return;
    await AppLogger.instance.warn(
      'Auth',
      'Remote auth session rejected',
      context: {'email': email, 'message': exception.message},
    );
    await _clearSession();
    _user = null;
    _errorMessage = _friendlyAuthFailureMessage(exception.message);
    _sessionExpiredDialogMessage = _errorMessage;
    _isLoading = false;
    notifyListeners();
  }

  String _friendlyAuthFailureMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('thiet bi khac') ||
        lower.contains('thiết bị khác') ||
        lower.contains('session')) {
      return 'Tài khoản đã đăng nhập trên thiết bị khác cùng nền tảng. Vui lòng đăng nhập lại.';
    }
    if (lower.contains('unauthorized') ||
        lower.contains('jwt expired') ||
        lower.contains('invalid token') ||
        lower.contains('phiên làm việc') ||
        lower.contains('phiên đăng nhập')) {
      return _sessionExpiredMessage;
    }
    return message.trim().isEmpty ? _sessionExpiredMessage : message;
  }

  void clearSessionExpiredDialogMessage() {
    if (_sessionExpiredDialogMessage == null) return;
    _sessionExpiredDialogMessage = null;
    notifyListeners();
  }

  Future<void> _saveOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value != null && value.trim().isNotEmpty) {
      await prefs.setString(key, value);
    } else {
      await prefs.remove(key);
    }
  }

  Future<String?> _readSavedToken(SharedPreferences prefs) async {
    final secureToken = await _secureStorage.read(key: _jwtTokenKey);
    if (secureToken != null) return secureToken;

    final legacyToken = prefs.getString(_jwtTokenKey);
    if (legacyToken != null) {
      await _secureStorage.write(key: _jwtTokenKey, value: legacyToken);
      await prefs.remove(_jwtTokenKey);
    }
    return legacyToken;
  }

  void _queueDailyActivityLogUpload() {
    final currentUser = _user;
    if (currentUser == null || currentUser.needsStoreSelection) return;
    unawaited(
      AppLogger.instance.uploadDailyActivityLogIfDue(
        storeCode: currentUser.storeId,
      ),
    );
  }

  Future<User> _withFeatureAccess(
    User user, {
    bool allowFallback = true,
  }) async {
    try {
      final access = await _repository.getMyFeatureAccess();
      Map<String, bool> policyAccess = const {};
      try {
        policyAccess = await _repository.getMyPolicyAccess();
        await AppLogger.instance.info(
          'Auth',
          'Policy access loaded',
          context: {'email': user.email, 'count': policyAccess.length},
        );
      } catch (e) {
        await AppLogger.instance.warn(
          'Auth',
          'Policy access load failed; using server response access only',
          context: {'email': user.email, 'error': e.toString()},
        );
      }
      await AppLogger.instance.info(
        'Auth',
        'Feature access loaded',
        context: {
          'email': user.email,
          'count': access.length,
          'policyCount': policyAccess.length,
        },
      );
      return user.copyWith(featureAccess: access, policyAccess: policyAccess);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        if (_user != null) await _handleRemoteAuthFailure(e);
        rethrow;
      }
      await AppLogger.instance.warn(
        'Auth',
        'Feature access load failed; using server response access only',
        context: {'email': user.email, 'error': e.toString()},
      );
      if (!allowFallback) rethrow;
      return user;
    }
  }

  Future<bool> login({required String email, required String password}) async {
    if (kDebugMode) debugPrint('[AuthProvider] Starting password login...');
    await AppLogger.instance.info(
      'Auth',
      'Login started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final (user, token) = await _repository.login(
        email: email,
        password: password,
      );
      _user = await _withFeatureAccess(user);

      if (_user != null) {
        await _saveSession(_user!, token: token);
      }

      await AppLogger.instance.info(
        'Auth',
        'Login succeeded',
        context: {
          'email': user.email,
          'role': user.role,
          'storeId': user.storeId,
        },
      );
      _queueDailyActivityLogUpload();

      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthProvider] Login failed: ${e.message}');
      }
      await AppLogger.instance.warn(
        'Auth',
        'Login failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] Login error: $e');
      await AppLogger.instance.error(
        'Auth',
        'Login crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Không đăng nhập được. Vui lòng thử lại sau ít phút.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String firstName,
    String? lastName,
    required String email,
    required String password,
    required String verificationCode,
  }) async {
    if (kDebugMode) debugPrint('[AuthProvider] Starting registration...');
    await AppLogger.instance.info(
      'Auth',
      'Registration started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final (user, token) = await _repository.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
        verificationCode: verificationCode,
      );
      _user = await _withFeatureAccess(user);

      await _saveSession(_user!, token: token);
      await AppLogger.instance.info(
        'Auth',
        'Registration succeeded',
        context: {'email': user.email, 'role': user.role},
      );
      _queueDailyActivityLogUpload();

      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[AuthProvider] Registration failed: ${e.message}');
      }
      await AppLogger.instance.warn(
        'Auth',
        'Registration failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[AuthProvider] Registration error: $e');
      await AppLogger.instance.error(
        'Auth',
        'Registration crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Chưa đăng ký được tài khoản. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendRegistrationVerificationCode({required String email}) async {
    await AppLogger.instance.info(
      'Auth',
      'Verification code request started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.sendRegistrationVerificationCode(email: email);
      await AppLogger.instance.info(
        'Auth',
        'Verification code request succeeded',
        context: {'email': email},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Verification code request failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      await AppLogger.instance.error(
        'Auth',
        'Verification code request crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Chưa gửi được mã xác thực. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestPasswordReset({required String email}) async {
    await AppLogger.instance.info(
      'Auth',
      'Password reset request started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.requestPasswordReset(email: email);
      await AppLogger.instance.info(
        'Auth',
        'Password reset request succeeded',
        context: {'email': email},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Password reset request failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      await AppLogger.instance.error(
        'Auth',
        'Password reset request crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Không gửi được email đổi mật khẩu. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    await AppLogger.instance.info(
      'Auth',
      'Password reset code verification started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final resetToken = await _repository.verifyPasswordResetCode(
        email: email,
        code: code,
      );
      await AppLogger.instance.info(
        'Auth',
        'Password reset code verification succeeded',
        context: {'email': email},
      );
      _isLoading = false;
      notifyListeners();
      return resetToken;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Password reset code verification failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      await AppLogger.instance.error(
        'Auth',
        'Password reset code verification crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Không xác thực được mã. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> resetForgottenPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await AppLogger.instance.info(
      'Auth',
      'Forgotten password reset started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.resetForgottenPassword(
        resetToken: resetToken,
        newPassword: newPassword,
      );
      await AppLogger.instance.info(
        'Auth',
        'Forgotten password reset succeeded',
        context: {'email': email},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Forgotten password reset failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      await AppLogger.instance.error(
        'Auth',
        'Forgotten password reset crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Không đổi được mật khẩu. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = _user?.email;
    if (_user == null) return false;
    await AppLogger.instance.info(
      'Auth',
      'Password change started',
      context: {'email': email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final (user, token) = await _repository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      _user = await _withFeatureAccess(user);
      await _saveSession(user, token: token);
      await AppLogger.instance.info(
        'Auth',
        'Password change succeeded',
        context: {'email': user.email, 'role': user.role},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Password change failed',
        context: {'email': email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      await AppLogger.instance.error(
        'Auth',
        'Password change crashed',
        error: e,
        upload: true,
        context: {'email': email},
      );
      _errorMessage = 'Không đổi được mật khẩu. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final email = _user?.email;
    if (_user != null) {
      await AppLogger.instance.info(
        'Auth',
        'Logout started',
        context: {'email': email},
      );
      try {
        await _repository.logout();
        await AppLogger.instance.info(
          'Auth',
          'Logout server session revoked',
          context: {'email': email},
        );
      } catch (e) {
        await AppLogger.instance.warn(
          'Auth',
          'Logout server revoke failed; clearing local session',
          context: {'email': email, 'error': e.toString()},
        );
      }
    }
    await _clearSession();
    _user = null;
    _errorMessage = null;
    _isLoading = false;
    await AppLogger.instance.info(
      'Auth',
      'Logout completed',
      context: {'email': email},
    );
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> selectStore(String storeId) async {
    if (_user == null) return false;
    await AppLogger.instance.info(
      'Auth',
      'Store selection started',
      context: {'email': _user!.email, 'storeId': storeId},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _withFeatureAccess(
        await _repository.selectStore(storeId, _user!.email),
      );
      await _saveSession(_user!);
      await AppLogger.instance.info(
        'Auth',
        'Store selection succeeded',
        context: {'email': _user!.email, 'storeId': _user!.storeId},
      );
      _queueDailyActivityLogUpload();
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Store selection failed',
        context: {'storeId': storeId, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfile({
    required String firstName,
    String? lastName,
  }) async {
    if (_user == null) return false;
    await AppLogger.instance.info(
      'Auth',
      'Profile update started',
      context: {'email': _user!.email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _withFeatureAccess(
        await _repository.updateProfile(
          email: _user!.email,
          firstName: firstName,
          lastName: lastName,
        ),
      );
      await _saveSession(_user!);
      await AppLogger.instance.info(
        'Auth',
        'Profile update succeeded',
        context: {'email': _user!.email},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Profile update failed',
        context: {'email': _user?.email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadAvatar({
    String? path,
    Uint8List? bytes,
    required String fileName,
  }) async {
    if (_user == null) return false;
    if (path == null && bytes == null) {
      _errorMessage = 'Chưa đọc được file ảnh. Vui lòng chọn ảnh khác.';
      return false;
    }

    await AppLogger.instance.info(
      'Auth',
      'Avatar upload started',
      context: {
        'email': _user!.email,
        'fileName': fileName,
        'hasPath': path != null,
        'byteLength': bytes?.length,
      },
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _withFeatureAccess(
        await _repository.uploadAvatar(
          email: _user!.email,
          path: path,
          bytes: bytes,
          fileName: fileName,
        ),
      );
      await _saveSession(_user!);
      await AppLogger.instance.info(
        'Auth',
        'Avatar upload succeeded',
        context: {'email': _user!.email},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Avatar upload failed',
        context: {'email': _user?.email, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e, stackTrace) {
      await AppLogger.instance.error(
        'Auth',
        'Avatar upload crashed',
        error: e,
        stackTrace: stackTrace,
        upload: true,
        context: {'email': _user?.email, 'fileName': fileName},
      );
      _errorMessage = 'Không cập nhật được avatar. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Refresh user data
  Future<void> refreshUserData() async {
    if (_user == null) return;

    try {
      final updatedUser = await _repository.getUserData(_user!.email);
      _user = await _withFeatureAccess(updatedUser);

      await _saveSession(_user!);
      notifyListeners();
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AuthProvider] Refresh failed: ${e.message}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Refresh error: $e');
    }
  }
}
