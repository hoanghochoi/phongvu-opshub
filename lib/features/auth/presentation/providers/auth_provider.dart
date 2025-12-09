import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../../core/network/api_exception.dart';

class AuthProvider extends ChangeNotifier {
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
      final storeId = prefs.getString('user_storeId');
      final storeName = prefs.getString('user_storeName');
      final role = prefs.getString('user_role');

      if (email != null) {
        _user = User(
          email: email,
          name: name,
          storeId: storeId,
          storeName: storeName,
          role: role,
        );
        print('✅ [AuthProvider] Loaded saved session: $email');
      }
    } catch (e) {
      print('❌ [AuthProvider] Error loading session: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Save session to SharedPreferences
  Future<void> _saveSession(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', user.email);
      if (user.name != null) {
        await prefs.setString('user_name', user.name!);
      }
      if (user.storeId != null) {
        await prefs.setString('user_storeId', user.storeId!);
      }
      if (user.storeName != null) {
        await prefs.setString('user_storeName', user.storeName!);
      }
      if (user.role != null) {
        await prefs.setString('user_role', user.role!);
      }
      print('✅ [AuthProvider] Session saved');
    } catch (e) {
      print('❌ [AuthProvider] Error saving session: $e');
    }
  }

  /// Clear session from SharedPreferences
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      print('✅ [AuthProvider] Session cleared');
    } catch (e) {
      print('❌ [AuthProvider] Error clearing session: $e');
    }
  }

  Future<bool> login(String email, String password) async {
    print('🔵 [AuthProvider] Starting login...');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _repository.login(email, password);
      print('✅ [AuthProvider] Login success! User: ${_user?.email}, Name: ${_user?.name}');
      print('✅ [AuthProvider] isAuthenticated: $isAuthenticated');

      // Save session
      if (_user != null) {
        await _saveSession(_user!);
      }

      _isLoading = false;
      notifyListeners();
      print('✅ [AuthProvider] notifyListeners() called');
      return true;
    } on ApiException catch (e) {
      print('❌ [AuthProvider] Login failed: ${e.message}');
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      print('❌ [AuthProvider] Login error: $e');
      _errorMessage = 'Lỗi không xác định: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearSession();
    _user = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Check email status: returns 'new', 'yes', or 'no'
  Future<String?> checkEmail(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final status = await _repository.checkEmail(email);
      _isLoading = false;
      notifyListeners();
      return status;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      print('🔴 AuthProvider checkEmail error: $_errorMessage');
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
      print('🔴 AuthProvider checkEmail error: $_errorMessage');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.register(email, password, name);
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      print('🔴 AuthProvider set errorMessage: $_errorMessage');
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Lỗi không xác định: $e';
      print('🔴 AuthProvider set errorMessage: $_errorMessage');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Refresh user data from webhook
  Future<void> refreshUserData() async {
    if (_user == null) return;

    print('🔵 [AuthProvider] Refreshing user data...');

    try {
      final updatedUser = await _repository.getUserData(_user!.email);
      _user = updatedUser;
      print('✅ [AuthProvider] User data refreshed: ${_user?.name}, Store: ${_user?.storeName}');

      // Save updated session
      await _saveSession(_user!);

      notifyListeners();
    } on ApiException catch (e) {
      print('❌ [AuthProvider] Refresh failed: ${e.message}');
      // Don't set error message for silent refresh
    } catch (e) {
      print('❌ [AuthProvider] Refresh error: $e');
    }
  }
}
