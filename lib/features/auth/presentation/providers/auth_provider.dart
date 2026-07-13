import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/store_branch.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/app_storage_keys.dart';

class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  static const _jwtTokenKey = 'user_jwt_token';
  static const _sessionExpiredMessage =
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
  static const _sessionPreferenceKeys = <String>[
    'user_email',
    'user_name',
    'user_lastName',
    'user_avatarUrl',
    'user_storeId',
    'user_storeName',
    'user_role',
    'user_status',
    'user_departmentCode',
    'user_jobRoleCode',
    'user_workScopeType',
    'user_regionCode',
    'user_regionName',
    'user_regionAbbreviation',
    'user_areaCode',
    'user_areaName',
    'user_areaAbbreviation',
    'user_organizationNodeId',
    'user_organizationNodeName',
    'user_organizationNodeIds',
    'user_organizationAssignments',
    'user_assignedStores',
    'user_organizationAccessCodes',
    'user_featureCodes',
    'user_personnelCode',
    'user_assignmentPending',
  ];

  static String _sharedKey(String key) => AppStorageKeys.shared(key);
  static String _secureKey(String key) => AppStorageKeys.secure(key);

  final AuthRepository _repository;

  User? _user;
  bool _isLoading = false;
  String? _errorMessage;
  bool _passwordResetAccountMissing = false;
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
  bool get passwordResetAccountMissing => _passwordResetAccountMissing;
  String? get sessionExpiredDialogMessage => _sessionExpiredDialogMessage;
  bool get isInitialized => _isInitialized;

  /// Load saved session from SharedPreferences
  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_sharedKey('user_email'));
      final name = prefs.getString(_sharedKey('user_name'));
      final lastName = prefs.getString(_sharedKey('user_lastName'));
      final avatarUrl = prefs.getString(_sharedKey('user_avatarUrl'));
      final storeId = prefs.getString(_sharedKey('user_storeId'));
      final storeName = prefs.getString(_sharedKey('user_storeName'));
      final role = prefs.getString(_sharedKey('user_role'));
      final status = prefs.getString(_sharedKey('user_status'));
      final departmentCode = prefs.getString(_sharedKey('user_departmentCode'));
      final jobRoleCode = prefs.getString(_sharedKey('user_jobRoleCode'));
      final workScopeType = prefs.getString(_sharedKey('user_workScopeType'));
      final regionCode = prefs.getString(_sharedKey('user_regionCode'));
      final regionName = prefs.getString(_sharedKey('user_regionName'));
      final regionAbbreviation = prefs.getString(
        _sharedKey('user_regionAbbreviation'),
      );
      final areaCode = prefs.getString(_sharedKey('user_areaCode'));
      final areaName = prefs.getString(_sharedKey('user_areaName'));
      final areaAbbreviation = prefs.getString(
        _sharedKey('user_areaAbbreviation'),
      );
      final organizationNodeId = prefs.getString(
        _sharedKey('user_organizationNodeId'),
      );
      final organizationNodeName = prefs.getString(
        _sharedKey('user_organizationNodeName'),
      );
      final organizationNodeIds = _readStringListPreference(
        prefs,
        'user_organizationNodeIds',
      );
      final organizationAssignments = _readJsonMapListPreference(
        prefs,
        'user_organizationAssignments',
      );
      final assignedStores = _readJsonMapListPreference(
        prefs,
        'user_assignedStores',
      );
      final organizationAccessCodes = _readStringListPreference(
        prefs,
        'user_organizationAccessCodes',
      );
      final featureCodes = _readStringListPreference(
        prefs,
        'user_featureCodes',
      );
      final personnelCode = prefs.getString(_sharedKey('user_personnelCode'));
      final assignmentPending =
          prefs.getBool(_sharedKey('user_assignmentPending')) ??
          (!User.isAdminRole(role) && organizationNodeId == null);
      final token = await _readSavedToken(prefs);

      if (email != null) {
        _user = User.fromJson({
          'email': email,
          'name': name,
          'lastName': lastName,
          'avatarUrl': avatarUrl,
          'storeId': storeId,
          'storeName': storeName,
          'role': role,
          'status': status,
          'departmentCode': departmentCode,
          'jobRoleCode': jobRoleCode,
          'workScopeType': workScopeType,
          'regionCode': regionCode,
          'regionName': regionName,
          'regionAbbreviation': regionAbbreviation,
          'areaCode': areaCode,
          'areaName': areaName,
          'areaAbbreviation': areaAbbreviation,
          'organizationNodeId': organizationNodeId,
          'organizationNodeName': organizationNodeName,
          'organizationNodeIds': organizationNodeIds,
          'organizationAssignments': organizationAssignments,
          'assignedStores': assignedStores,
          'organizationAccessCodes': organizationAccessCodes,
          'featureCodes': featureCodes,
          'personnelCode': personnelCode,
          'assignmentPending': assignmentPending,
          'mustSelectStore': false,
        }, fallbackEmail: email);
        await AppLogger.instance.info(
          'Auth',
          'Saved session cache loaded',
          context: {
            'email': email,
            'assignedStoreCount': _user!.assignedStores.length,
            'organizationAssignmentCount':
                _user!.organizationAssignments.length,
          },
        );

        // Restore JWT token to ApiClient for authenticated API calls
        if (token != null) {
          ApiClient().setAuthToken(token);
          _user = await _refreshSavedSessionUser(_user!);
          _queueDailyActivityLogUpload();
          await AppLogger.instance.info(
            'Auth',
            'Saved session token restored',
            context: {
              'email': email,
              'storageEnvironment': AppStorageKeys.environment,
              'assignedStoreCount': _user?.assignedStores.length,
            },
          );
          if (kDebugMode) debugPrint('✅ [AuthProvider] Restored JWT token');
        } else {
          await AppLogger.instance.warn(
            'Auth',
            'Saved session found without namespaced token',
            context: {
              'email': email,
              'storageEnvironment': AppStorageKeys.environment,
            },
          );
        }

        if (kDebugMode) debugPrint('✅ [AuthProvider] Loaded cached session');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error loading session: $e');
      await AppLogger.instance.error(
        'Auth',
        'Saved session load failed',
        error: e,
        stackTrace: stackTrace,
        context: {'storageEnvironment': AppStorageKeys.environment},
      );
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Save session to SharedPreferences (including JWT token)
  Future<void> _saveSession(User user, {String? token}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sharedKey('user_email'), user.email);
      if (user.name != null) {
        await prefs.setString(_sharedKey('user_name'), user.name!);
      }
      if (user.lastName != null) {
        await prefs.setString(_sharedKey('user_lastName'), user.lastName!);
      } else {
        await prefs.remove(_sharedKey('user_lastName'));
      }
      if (user.avatarUrl != null) {
        await prefs.setString(_sharedKey('user_avatarUrl'), user.avatarUrl!);
      } else {
        await prefs.remove(_sharedKey('user_avatarUrl'));
      }
      if (user.storeId != null) {
        await prefs.setString(_sharedKey('user_storeId'), user.storeId!);
      } else {
        await prefs.remove(_sharedKey('user_storeId'));
      }
      if (user.storeName != null) {
        await prefs.setString(_sharedKey('user_storeName'), user.storeName!);
      } else {
        await prefs.remove(_sharedKey('user_storeName'));
      }
      if (user.role != null) {
        await prefs.setString(_sharedKey('user_role'), user.role!);
      }
      if (user.status != null) {
        await prefs.setString(_sharedKey('user_status'), user.status!);
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
        'user_organizationNodeId',
        user.organizationNodeId,
      );
      await _saveOptionalString(
        prefs,
        'user_organizationNodeName',
        user.organizationNodeName,
      );
      await _saveStringListPreference(
        prefs,
        'user_organizationNodeIds',
        user.organizationNodeIds,
      );
      await _saveJsonListPreference(
        prefs,
        'user_organizationAssignments',
        user.organizationAssignments
            .map(_organizationAssignmentToJson)
            .toList(growable: false),
      );
      await _saveJsonListPreference(
        prefs,
        'user_assignedStores',
        user.assignedStores.map(_storeBranchToJson).toList(growable: false),
      );
      await _saveStringListPreference(
        prefs,
        'user_organizationAccessCodes',
        user.organizationAccessCodes,
      );
      await _saveStringListPreference(
        prefs,
        'user_featureCodes',
        user.featureCodes,
      );
      await _saveOptionalString(
        prefs,
        'user_personnelCode',
        user.personnelCode,
      );
      await prefs.setBool(
        _sharedKey('user_assignmentPending'),
        user.needsOrganizationAssignment,
      );
      if (token != null) {
        await _secureStorage.write(key: _secureKey(_jwtTokenKey), value: token);
        await prefs.remove(_sharedKey(_jwtTokenKey));
        await prefs.remove(_jwtTokenKey);
        await _secureStorage.delete(key: _jwtTokenKey);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ [AuthProvider] Error saving session: $e');
    }
  }

  /// Clear session from SharedPreferences
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _sessionPreferenceKeys) {
        await prefs.remove(_sharedKey(key));
        await prefs.remove(key);
      }
      await prefs.remove(_sharedKey(_jwtTokenKey));
      await prefs.remove(_jwtTokenKey);
      await _secureStorage.delete(key: _secureKey(_jwtTokenKey));
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

  @visibleForTesting
  void setSessionExpiredDialogMessageForTesting(String? message) {
    _sessionExpiredDialogMessage = message;
    notifyListeners();
  }

  Future<void> _saveOptionalString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value != null && value.trim().isNotEmpty) {
      await prefs.setString(_sharedKey(key), value);
    } else {
      await prefs.remove(_sharedKey(key));
    }
  }

  List<String> _readStringListPreference(SharedPreferences prefs, String key) {
    final raw = prefs.getString(_sharedKey(key));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [AuthProvider] Invalid saved string list $key: $e');
      }
      return const [];
    }
  }

  List<Map<String, dynamic>> _readJsonMapListPreference(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(_sharedKey(key));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [AuthProvider] Invalid saved JSON list $key: $e');
      }
      return const [];
    }
  }

  Future<void> _saveStringListPreference(
    SharedPreferences prefs,
    String key,
    List<String> values,
  ) async {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      await prefs.remove(_sharedKey(key));
      return;
    }
    await prefs.setString(_sharedKey(key), jsonEncode(normalized));
  }

  Future<void> _saveJsonListPreference(
    SharedPreferences prefs,
    String key,
    List<Map<String, dynamic>> values,
  ) async {
    if (values.isEmpty) {
      await prefs.remove(_sharedKey(key));
      return;
    }
    await prefs.setString(_sharedKey(key), jsonEncode(values));
  }

  Map<String, dynamic> _organizationAssignmentToJson(
    UserOrganizationAssignment assignment,
  ) {
    return {
      'id': assignment.id,
      'organizationNodeId': assignment.organizationNodeId,
      'organizationNodeName': assignment.organizationNodeName,
      'organizationNodeType': assignment.organizationNodeType,
      'storeId': assignment.storeId,
      'storeName': assignment.storeName,
      'isPrimary': assignment.isPrimary,
    };
  }

  Map<String, dynamic> _storeBranchToJson(StoreBranch store) {
    return {
      'id': store.id,
      'storeId': store.storeId,
      'storeName': store.storeName,
      'areaCode': store.areaCode,
      'areaName': store.areaName,
      'areaAbbreviation': store.areaAbbreviation,
      'regionCode': store.regionCode,
      'regionName': store.regionName,
      'regionAbbreviation': store.regionAbbreviation,
    };
  }

  Future<String?> _readSavedToken(SharedPreferences prefs) async {
    final secureToken = await _secureStorage.read(
      key: _secureKey(_jwtTokenKey),
    );
    if (secureToken != null) return secureToken;

    final sharedToken = prefs.getString(_sharedKey(_jwtTokenKey));
    if (sharedToken != null) {
      await _secureStorage.write(
        key: _secureKey(_jwtTokenKey),
        value: sharedToken,
      );
      await prefs.remove(_sharedKey(_jwtTokenKey));
    }
    return sharedToken;
  }

  Future<User> _refreshSavedSessionUser(User cachedUser) async {
    var current = cachedUser;
    await AppLogger.instance.info(
      'Auth',
      'Saved session profile refresh started',
      context: {
        'email': cachedUser.email,
        'cachedAssignedStoreCount': cachedUser.assignedStores.length,
      },
    );
    try {
      current = await _repository.getUserData(cachedUser.email);
      await AppLogger.instance.info(
        'Auth',
        'Saved session profile refresh succeeded',
        context: {
          'email': current.email,
          'assignedStoreCount': current.assignedStores.length,
          'organizationAssignmentCount': current.organizationAssignments.length,
        },
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _handleRemoteAuthFailure(e);
        rethrow;
      }
      await AppLogger.instance.warn(
        'Auth',
        'Saved session profile refresh failed; using cached scope',
        context: {'email': cachedUser.email, 'message': e.message},
      );
    } catch (e) {
      await AppLogger.instance.warn(
        'Auth',
        'Saved session profile refresh crashed; using cached scope',
        context: {'email': cachedUser.email, 'error': e.toString()},
      );
    }
    final withAccess = await _withFeatureAccess(current, allowFallback: false);
    await _saveSession(withAccess);
    return withAccess;
  }

  void _queueDailyActivityLogUpload() {
    final currentUser = _user;
    if (currentUser == null || currentUser.needsOrganizationAssignment) return;
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
          'assignedStoreCount': user.assignedStores.length,
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
    _passwordResetAccountMissing = false;
    notifyListeners();

    try {
      await _repository.requestPasswordReset(email: email);
      await AppLogger.instance.info(
        'Auth',
        'Password reset request succeeded',
        context: {'email': email},
      );
      _passwordResetAccountMissing = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      final accountMissing = e.statusCode == 404;
      await AppLogger.instance.warn(
        'Auth',
        'Password reset request failed',
        context: {
          'email': email,
          'message': e.message,
          'statusCode': e.statusCode,
          'accountMissing': accountMissing,
        },
      );
      _passwordResetAccountMissing = accountMissing;
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
      _passwordResetAccountMissing = false;
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
    _passwordResetAccountMissing = false;
    notifyListeners();
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
