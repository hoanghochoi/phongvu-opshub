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

  final AuthRepository _repository;

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isInitialized = false;

  AuthProvider(this._repository) {
    _loadSavedSession();
  }

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  String? get errorMessage => _errorMessage;
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
      final token = await _readSavedToken(prefs);

      if (email != null) {
        final canSkipStoreSelection = role == 'ADMIN' || role == 'SUPER_ADMIN';
        _user = User(
          email: email,
          name: name,
          lastName: lastName,
          avatarUrl: avatarUrl,
          storeId: storeId,
          storeName: storeName,
          role: role,
          status: status,
          mustSelectStore: !canSkipStoreSelection && storeId == null,
        );

        // Restore JWT token to ApiClient for authenticated API calls
        if (token != null) {
          ApiClient().setAuthToken(token);
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
      await prefs.remove(_jwtTokenKey);
      await _secureStorage.delete(key: _jwtTokenKey);
      ApiClient().setAuthToken(null);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error clearing session: $e');
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
      _user = user;

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
      _errorMessage = 'Đăng nhập thất bại: $e';
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
      _user = user;

      await _saveSession(_user!, token: token);
      await AppLogger.instance.info(
        'Auth',
        'Registration succeeded',
        context: {'email': user.email, 'role': user.role},
      );

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
      _errorMessage = 'Dang ky that bai: $e';
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
      _errorMessage = 'Không gửi được mã xác thực: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final email = _user?.email;
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
      _user = await _repository.selectStore(storeId, _user!.email);
      await _saveSession(_user!);
      await AppLogger.instance.info(
        'Auth',
        'Store selection succeeded',
        context: {'email': _user!.email, 'storeId': _user!.storeId},
      );
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
      _user = await _repository.updateProfile(
        email: _user!.email,
        firstName: firstName,
        lastName: lastName,
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

  Future<bool> uploadAvatar(String path) async {
    if (_user == null) return false;
    await AppLogger.instance.info(
      'Auth',
      'Avatar upload started',
      context: {'email': _user!.email},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _repository.uploadAvatar(email: _user!.email, path: path);
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
    }
  }

  /// Refresh user data
  Future<void> refreshUserData() async {
    if (_user == null) return;

    try {
      final updatedUser = await _repository.getUserData(_user!.email);
      _user = updatedUser;

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
