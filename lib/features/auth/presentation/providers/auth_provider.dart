import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';

class AuthProvider extends ChangeNotifier {
  final AuthRepository _repository;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '771288927234-a4t5p35j56nortpngt3fqmr3uhhs3eu6.apps.googleusercontent.com',
  );

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
      final token = prefs.getString('user_jwt_token');

      if (email != null) {
        final isAdmin = role == 'ADMIN' || role == 'SUPER_ADMIN';
        _user = User(
          email: email,
          name: name,
          lastName: lastName,
          avatarUrl: avatarUrl,
          storeId: storeId,
          storeName: storeName,
          role: role,
          status: status,
          mustSelectStore: !isAdmin && storeId == null,
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
        await prefs.setString('user_jwt_token', token);
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
      await prefs.remove('user_jwt_token');
      ApiClient().setAuthToken(null);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error clearing session: $e');
    }
  }

  /// Sign in with Google OAuth
  Future<bool> signInWithGoogle() async {
    if (kDebugMode) debugPrint('🔵 [AuthProvider] Starting Google Sign-In...');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled sign-in
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (kDebugMode) {
        debugPrint('✅ [AuthProvider] Google user: ${googleUser.email}');
      }

      // 2. Get ID Token
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw ApiException('Không lấy được Google token');
      }

      // 3. Send ID Token to backend
      final (user, token) = await _repository.googleLogin(idToken);
      _user = user;

      // 4. Save session (including JWT token)
      if (_user != null) {
        await _saveSession(_user!, token: token);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AuthProvider] Google login failed: ${e.message}');
      }
      _errorMessage = e.message;
      _isLoading = false;
      await _googleSignIn.signOut(); // Clean up Google session on failure
      notifyListeners();
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Google login error: $e');
      _errorMessage = 'Đăng nhập thất bại: $e';
      _isLoading = false;
      await _googleSignIn.signOut();
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearSession();
    await _googleSignIn.signOut();
    _user = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> selectStore(String storeId) async {
    if (_user == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _repository.selectStore(storeId, _user!.email);
      await _saveSession(_user!);
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
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
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadAvatar(String path) async {
    if (_user == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _repository.uploadAvatar(email: _user!.email, path: path);
      await _saveSession(_user!);
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
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
