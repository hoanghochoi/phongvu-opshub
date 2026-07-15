import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/data/shared_preferences_query_persistence.dart';
import '../../domain/entities/store_branch.dart';
import '../../domain/entities/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/storage/app_storage_keys.dart';

enum AuthAccessSyncState { idle, syncing, fresh, stale, failed }

class _SavedAuthSnapshot {
  final User user;
  final bool hasUsableAccess;
  final String? bootstrapEtag;
  final DateTime? bootstrapGeneratedAt;
  final DateTime? lastSuccessAt;
  final String? bootstrapVersion;
  final int? bootstrapSchemaVersion;
  final bool conditionalGet;
  final List<String> realtimeV2Topics;

  const _SavedAuthSnapshot({
    required this.user,
    required this.hasUsableAccess,
    this.bootstrapEtag,
    this.bootstrapGeneratedAt,
    this.lastSuccessAt,
    this.bootstrapVersion,
    this.bootstrapSchemaVersion,
    this.conditionalGet = false,
    this.realtimeV2Topics = const [],
  });
}

class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  static const _jwtTokenKey = 'user_jwt_token';
  static const _sessionSnapshotKey = 'auth_session_snapshot_v2';
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
    'user_featureAccess',
    'user_policyAccess',
    'user_personnelCode',
    'user_assignmentPending',
    _sessionSnapshotKey,
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
  AuthAccessSyncState _accessSyncState = AuthAccessSyncState.idle;
  DateTime? _accessLastSyncedAt;
  DateTime? _bootstrapGeneratedAt;
  String? _bootstrapEtag;
  String? _bootstrapVersion;
  int? _bootstrapSchemaVersion;
  bool _bootstrapConditionalGet = false;
  List<String> _realtimeV2Topics = const [];
  Future<bool>? _accessRefreshInFlight;
  int? _accessRefreshEpoch;
  int _sessionEpoch = 0;
  bool _hasUsableAccessSnapshot = false;
  Future<void> _sessionStorageTail = Future<void>.value();

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
  AuthAccessSyncState get accessSyncState => _accessSyncState;
  bool get isAccessSyncing => _accessSyncState == AuthAccessSyncState.syncing;
  DateTime? get accessLastSyncedAt => _accessLastSyncedAt;
  DateTime? get bootstrapGeneratedAt => _bootstrapGeneratedAt;
  String? get bootstrapVersion => _bootstrapVersion;
  bool get hasUsableAccessSnapshot => _user == null || _hasUsableAccessSnapshot;
  String? get accessIdentity {
    final current = _user;
    if (current == null || !_hasUsableAccessSnapshot) return null;
    final version = _bootstrapVersion?.trim();
    if (version != null && version.isNotEmpty) return 'version:$version';
    return 'access:${_accessFingerprint(current)}';
  }

  bool get bootstrapConditionalGet => _bootstrapConditionalGet;
  List<String> get realtimeV2Topics => List.unmodifiable(_realtimeV2Topics);
  String? get accessSyncWarning {
    if (_user == null) return null;
    return switch (_accessSyncState) {
      AuthAccessSyncState.stale =>
        'Đang dùng quyền đã lưu. Chưa đồng bộ được thay đổi mới.',
      AuthAccessSyncState.failed =>
        'Chưa đồng bộ được quyền truy cập. Vui lòng thử lại.',
      _ => null,
    };
  }

  /// Load saved session from SharedPreferences
  Future<void> _loadSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSnapshot = _readSavedAuthSnapshot(prefs);
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

      final fallbackUser = email == null
          ? null
          : User.fromJson({
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
              'featureAccess': _readBoolMapPreference(
                prefs,
                'user_featureAccess',
              ),
              'policyAccess': _readBoolMapPreference(
                prefs,
                'user_policyAccess',
              ),
              'personnelCode': personnelCode,
              'assignmentPending': assignmentPending,
              'mustSelectStore': false,
            }, fallbackEmail: email);
      final savedUser = savedSnapshot?.user ?? fallbackUser;
      if (savedUser == null || token == null) {
        if (savedUser != null || token != null) {
          await AppLogger.instance.warn(
            'Auth',
            'Incomplete saved session discarded',
            context: {
              'hasUserSnapshot': savedUser != null,
              'hasSecureToken': token != null,
              'storageEnvironment': AppStorageKeys.environment,
            },
          );
          await _clearSession();
        }
        return;
      }
      _user = savedUser;
      if (_user != null) _advanceSessionEpoch();
      if (savedSnapshot != null) {
        _hasUsableAccessSnapshot = savedSnapshot.hasUsableAccess;
        _bootstrapEtag = savedSnapshot.bootstrapEtag;
        _bootstrapGeneratedAt = savedSnapshot.bootstrapGeneratedAt;
        _accessLastSyncedAt = savedSnapshot.lastSuccessAt;
        _bootstrapVersion = savedSnapshot.bootstrapVersion;
        _bootstrapSchemaVersion = savedSnapshot.bootstrapSchemaVersion;
        _bootstrapConditionalGet = savedSnapshot.conditionalGet;
        _realtimeV2Topics = savedSnapshot.realtimeV2Topics;
      }

      if (_user != null) {
        ApiClient().setAuthToken(token);
        _accessSyncState = AuthAccessSyncState.syncing;
        _isInitialized = true;
        notifyListeners();
        await AppLogger.instance.info(
          'Auth',
          'Saved session cache loaded',
          context: {
            'email': _user!.email,
            'assignedStoreCount': _user!.assignedStores.length,
            'organizationAssignmentCount':
                _user!.organizationAssignments.length,
            'featureAccessCount': _user!.featureAccess.length,
            'policyAccessCount': _user!.policyAccess.length,
            'hasBootstrapEtag': _bootstrapEtag != null,
            'hasUsableAccessSnapshot': _hasUsableAccessSnapshot,
          },
        );

        // Restore JWT token to ApiClient for authenticated API calls
        await _refreshSavedSessionUser(_user!);
        if (_user != null && ApiClient().authToken != null) {
          _queueDailyActivityLogUpload();
          await AppLogger.instance.info(
            'Auth',
            'Saved session token restored',
            context: {
              'email': _user?.email,
              'storageEnvironment': AppStorageKeys.environment,
              'assignedStoreCount': _user?.assignedStores.length,
            },
          );
          if (kDebugMode) debugPrint('✅ [AuthProvider] Restored JWT token');
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
  Future<void> _serializeSessionStorage(
    Future<void> Function() operation,
  ) async {
    final previous = _sessionStorageTail;
    final release = Completer<void>();
    _sessionStorageTail = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // A failed storage operation must not poison the serialization queue.
      }
      await operation();
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  Future<void> _saveSession(User user, {String? token, int? expectedEpoch}) {
    final sessionEpoch = expectedEpoch ?? _sessionEpoch;
    return _serializeSessionStorage(() async {
      if (sessionEpoch != _sessionEpoch) return;
      await _saveSessionUnlocked(user, token: token);
    });
  }

  Future<void> _saveSessionUnlocked(User user, {String? token}) async {
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
      await _saveBoolMapPreference(
        prefs,
        'user_featureAccess',
        user.featureAccess,
      );
      await _saveBoolMapPreference(
        prefs,
        'user_policyAccess',
        user.policyAccess,
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
      await prefs.setString(
        _sharedKey(_sessionSnapshotKey),
        jsonEncode({
          'schemaVersion': 2,
          'user': _userToJson(user),
          'bootstrap': {
            'accessResolved': _hasUsableAccessSnapshot,
            'etag': _bootstrapEtag,
            'generatedAt': _bootstrapGeneratedAt?.toUtc().toIso8601String(),
            'lastSuccessAt': _accessLastSyncedAt?.toUtc().toIso8601String(),
            'version': _bootstrapVersion,
            'schemaVersion': _bootstrapSchemaVersion,
            'conditionalGet': _bootstrapConditionalGet,
            'realtimeV2Topics': _realtimeV2Topics,
          },
        }),
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
  Future<int?> _clearSession({
    int? expectedEpoch,
    String? expectedAuthToken,
  }) async {
    if ((expectedEpoch != null && expectedEpoch != _sessionEpoch) ||
        (expectedAuthToken != null &&
            expectedAuthToken != ApiClient().authToken)) {
      return null;
    }
    _advanceSessionEpoch();
    final clearEpoch = _sessionEpoch;
    // Revoke in-memory authorization before any storage I/O. A preferences or
    // secure-storage failure must never leave the old token usable in-process.
    ApiClient().setAuthToken(null);
    _hasUsableAccessSnapshot = false;
    _bootstrapEtag = null;
    _bootstrapGeneratedAt = null;
    _accessLastSyncedAt = null;
    _bootstrapVersion = null;
    _bootstrapSchemaVersion = null;
    _bootstrapConditionalGet = false;
    _realtimeV2Topics = const [];
    _accessSyncState = AuthAccessSyncState.idle;
    unawaited(AppLogger.instance.info('Auth', 'Local session clear started'));
    var failedStages = 0;
    await _serializeSessionStorage(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in _sessionPreferenceKeys) {
          await prefs.remove(_sharedKey(key));
          await prefs.remove(key);
        }
        await prefs.remove(_sharedKey(_jwtTokenKey));
        await prefs.remove(_jwtTokenKey);
      } catch (e, stackTrace) {
        failedStages += 1;
        await AppLogger.instance.error(
          'Auth',
          'Shared preferences session clear failed',
          error: e,
          stackTrace: stackTrace,
        );
      }
      for (final key in [_secureKey(_jwtTokenKey), _jwtTokenKey]) {
        try {
          await _secureStorage.delete(key: key);
        } catch (e, stackTrace) {
          failedStages += 1;
          await AppLogger.instance.error(
            'Auth',
            'Secure token clear failed',
            error: e,
            stackTrace: stackTrace,
            context: {'namespaced': key == _secureKey(_jwtTokenKey)},
          );
        }
      }
      try {
        await SharedPreferencesQueryPersistence.clearAll();
      } catch (error, stackTrace) {
        failedStages += 1;
        await AppLogger.instance.warn(
          'Auth',
          'Query cache clear failed during logout',
          context: {
            'errorType': error.runtimeType.toString(),
            'stackAvailable': stackTrace.toString().isNotEmpty,
          },
        );
      }
    });
    await AppLogger.instance.info(
      'Auth',
      'Local session clear completed',
      context: {'failedStages': failedStages},
    );
    return clearEpoch;
  }

  Future<void> _handleRemoteAuthFailure(
    ApiException exception,
    String failedAuthToken,
  ) async {
    final email = _user?.email;
    final rejectedEpoch = _sessionEpoch;
    if (email == null || ApiClient().authToken != failedAuthToken) return;
    await AppLogger.instance.warn(
      'Auth',
      'Remote auth session rejected',
      context: {'email': email, 'message': exception.message},
    );
    final clearEpoch = await _clearSession(
      expectedEpoch: rejectedEpoch,
      expectedAuthToken: failedAuthToken,
    );
    if (clearEpoch == null ||
        clearEpoch != _sessionEpoch ||
        ApiClient().authToken != null) {
      return;
    }
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

  _SavedAuthSnapshot? _readSavedAuthSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_sharedKey(_sessionSnapshotKey));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != 2) return null;
      final userValue = decoded['user'];
      final bootstrapValue = decoded['bootstrap'];
      if (userValue is! Map || bootstrapValue is! Map) return null;
      final userJson = Map<String, dynamic>.from(userValue);
      final user = User.fromJson(userJson);
      if (user.email.trim().isEmpty) return null;
      final topicsValue = bootstrapValue['realtimeV2Topics'];
      final lastSuccessAt = DateTime.tryParse(
        bootstrapValue['lastSuccessAt']?.toString() ?? '',
      );
      final bootstrapEtag = bootstrapValue['etag']?.toString();
      final bootstrapVersion = bootstrapValue['version']?.toString();
      return _SavedAuthSnapshot(
        user: user,
        hasUsableAccess:
            bootstrapValue['accessResolved'] == true ||
            lastSuccessAt != null ||
            (bootstrapEtag?.trim().isNotEmpty ?? false) ||
            (bootstrapVersion?.trim().isNotEmpty ?? false),
        bootstrapEtag: bootstrapEtag,
        bootstrapGeneratedAt: DateTime.tryParse(
          bootstrapValue['generatedAt']?.toString() ?? '',
        ),
        lastSuccessAt: lastSuccessAt,
        bootstrapVersion: bootstrapVersion,
        bootstrapSchemaVersion: int.tryParse(
          bootstrapValue['schemaVersion']?.toString() ?? '',
        ),
        conditionalGet: bootstrapValue['conditionalGet'] == true,
        realtimeV2Topics: topicsValue is List
            ? topicsValue
                  .map((value) => value?.toString().trim() ?? '')
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false)
            : const [],
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [AuthProvider] Invalid saved auth snapshot: $e');
      }
      return null;
    }
  }

  Map<String, bool> _readBoolMapPreference(
    SharedPreferences prefs,
    String key,
  ) {
    final raw = prefs.getString(_sharedKey(key));
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          value == true || value.toString().toLowerCase() == 'true',
        ),
      );
    } catch (_) {
      return const {};
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

  Future<void> _saveBoolMapPreference(
    SharedPreferences prefs,
    String key,
    Map<String, bool> values,
  ) async {
    await prefs.setString(_sharedKey(key), jsonEncode(values));
  }

  Map<String, dynamic> _userToJson(User user) {
    return {
      'id': user.id,
      'email': user.email,
      'emailDomain': user.emailDomain,
      'name': user.name,
      'lastName': user.lastName,
      'avatarUrl': user.avatarUrl,
      'storeId': user.storeId,
      'storeName': user.storeName,
      'role': user.role,
      'status': user.status,
      'departmentCode': user.departmentCode,
      'jobRoleCode': user.jobRoleCode,
      'workScopeType': user.workScopeType,
      'regionCode': user.regionCode,
      'regionName': user.regionName,
      'regionAbbreviation': user.regionAbbreviation,
      'areaCode': user.areaCode,
      'areaName': user.areaName,
      'areaAbbreviation': user.areaAbbreviation,
      'organizationNodeId': user.organizationNodeId,
      'organizationNodeName': user.organizationNodeName,
      'organizationNodeIds': user.organizationNodeIds,
      'organizationAssignments': user.organizationAssignments
          .map(_organizationAssignmentToJson)
          .toList(growable: false),
      'assignedStores': user.assignedStores
          .map(_storeBranchToJson)
          .toList(growable: false),
      'organizationAccessCodes': user.organizationAccessCodes,
      'featureCodes': user.featureCodes,
      'personnelCode': user.personnelCode,
      'featureAccess': user.featureAccess,
      'policyAccess': user.policyAccess,
      'assignmentPending': user.assignmentPending,
      'mustSelectStore': user.mustSelectStore,
    };
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

  Future<void> _refreshSavedSessionUser(User cachedUser) async {
    await _synchronizeSavedSession(cachedUser);
  }

  void _advanceSessionEpoch() {
    _sessionEpoch += 1;
    _accessRefreshInFlight = null;
    _accessRefreshEpoch = null;
  }

  static String _authUserKey(User user) => '${user.id ?? ''}|${user.email}';

  bool _isCurrentAccessRequest(int epoch, String userKey) {
    final current = _user;
    return epoch == _sessionEpoch &&
        current != null &&
        _authUserKey(current) == userKey &&
        ApiClient().authToken != null;
  }

  static String _accessFingerprint(User user) {
    final features = user.featureAccess.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final policies = user.policyAccess.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    final stores = user.assignedStoreIds.toList()..sort();
    return [
      user.role ?? '',
      user.organizationNodeId ?? '',
      ...stores,
      ...features.map((entry) => '${entry.key}:${entry.value}'),
      ...policies.map((entry) => '${entry.key}:${entry.value}'),
    ].join('|');
  }

  Future<bool> retryAccessSync() async {
    final current = _user;
    if (current == null || ApiClient().authToken == null) return false;
    return _synchronizeSavedSession(current);
  }

  Future<bool> _synchronizeSavedSession(User cachedUser) async {
    final epoch = _sessionEpoch;
    final userKey = _authUserKey(cachedUser);
    final running = _accessRefreshInFlight;
    if (running != null && _accessRefreshEpoch == epoch) return running;
    if (!_isCurrentAccessRequest(epoch, userKey)) return false;
    final future = _runSavedSessionSync(cachedUser, epoch, userKey);
    _accessRefreshInFlight = future;
    _accessRefreshEpoch = epoch;
    try {
      return await future;
    } finally {
      if (identical(_accessRefreshInFlight, future)) {
        _accessRefreshInFlight = null;
        _accessRefreshEpoch = null;
      }
    }
  }

  Future<bool> _runSavedSessionSync(
    User cachedUser,
    int epoch,
    String userKey,
  ) async {
    _accessSyncState = AuthAccessSyncState.syncing;
    notifyListeners();
    await AppLogger.instance.info(
      'Auth',
      'Saved session bootstrap refresh started',
      context: {
        'email': cachedUser.email,
        'cachedAssignedStoreCount': cachedUser.assignedStores.length,
        'cachedFeatureAccessCount': cachedUser.featureAccess.length,
        'cachedPolicyAccessCount': cachedUser.policyAccess.length,
        'hasEtag': _bootstrapEtag != null,
      },
    );
    try {
      try {
        final result = await _repository.getBootstrap(
          ifNoneMatch: _bootstrapEtag,
        );
        if (!_isCurrentAccessRequest(epoch, userKey)) return false;
        if (result.isNotModified) {
          _bootstrapEtag = result.etag ?? _bootstrapEtag;
          _accessLastSyncedAt = DateTime.now();
          _accessSyncState = AuthAccessSyncState.fresh;
          _hasUsableAccessSnapshot = true;
          await _saveSession(cachedUser, expectedEpoch: epoch);
          if (!_isCurrentAccessRequest(epoch, userKey)) return false;
          _user = cachedUser;
          await AppLogger.instance.info(
            'Auth',
            'Saved session bootstrap not modified; cache retained',
            context: {
              'email': cachedUser.email,
              'featureAccessCount': cachedUser.featureAccess.length,
              'policyAccessCount': cachedUser.policyAccess.length,
            },
          );
          if (!_isCurrentAccessRequest(epoch, userKey)) return false;
          notifyListeners();
          return true;
        }

        final data = result.data;
        if (data == null) {
          throw ApiException(
            'Dữ liệu đồng bộ tài khoản chưa hợp lệ. Vui lòng thử lại.',
          );
        }
        final resolvedUser = data.user.copyWith(
          featureAccess: data.featureAccess,
          policyAccess: data.policyAccess,
        );
        final resolvedUserKey = _authUserKey(resolvedUser);
        _user = resolvedUser;
        _bootstrapEtag = result.etag ?? data.version;
        _bootstrapGeneratedAt = data.generatedAt;
        _bootstrapVersion = data.version;
        _bootstrapSchemaVersion = data.schemaVersion;
        _bootstrapConditionalGet = data.capabilities.conditionalGet;
        _realtimeV2Topics = data.capabilities.realtimeV2Topics;
        _accessLastSyncedAt = DateTime.now();
        _accessSyncState = AuthAccessSyncState.fresh;
        _hasUsableAccessSnapshot = true;
        await _saveSession(resolvedUser, expectedEpoch: epoch);
        if (!_isCurrentAccessRequest(epoch, resolvedUserKey)) return false;
        await AppLogger.instance.info(
          'Auth',
          'Saved session bootstrap refresh succeeded',
          context: {
            'email': resolvedUser.email,
            'assignedStoreCount': resolvedUser.assignedStores.length,
            'organizationAssignmentCount':
                resolvedUser.organizationAssignments.length,
            'featureAccessCount': resolvedUser.featureAccess.length,
            'policyAccessCount': resolvedUser.policyAccess.length,
            'realtimeTopicCount': _realtimeV2Topics.length,
            'schemaVersion': data.schemaVersion,
          },
        );
        if (!_isCurrentAccessRequest(epoch, resolvedUserKey)) return false;
        notifyListeners();
        return true;
      } on ApiException catch (error) {
        if (error.statusCode != 404 && error.statusCode != 501) rethrow;
        await AppLogger.instance.warn(
          'Auth',
          'Auth bootstrap unavailable; using legacy refresh',
          context: {'email': cachedUser.email, 'statusCode': error.statusCode},
        );
        if (!_isCurrentAccessRequest(epoch, userKey)) return false;
        return await _refreshSavedSessionLegacy(cachedUser, epoch, userKey);
      }
    } on ApiException catch (e) {
      if (!_isCurrentAccessRequest(epoch, userKey)) return false;
      if (e.statusCode == 401) {
        final failedAuthToken = ApiClient().authToken;
        if (failedAuthToken != null) {
          await _handleRemoteAuthFailure(e, failedAuthToken);
        }
        return false;
      }
      _user = cachedUser;
      _accessSyncState = _hasUsableAccessSnapshot
          ? AuthAccessSyncState.stale
          : AuthAccessSyncState.failed;
      await AppLogger.instance.warn(
        'Auth',
        'Saved session bootstrap refresh failed; cache retained',
        context: {
          'email': cachedUser.email,
          'statusCode': e.statusCode,
          'cachedFeatureAccessCount': cachedUser.featureAccess.length,
          'cachedPolicyAccessCount': cachedUser.policyAccess.length,
        },
      );
      if (!_isCurrentAccessRequest(epoch, userKey)) return false;
      notifyListeners();
      return false;
    } catch (e, stackTrace) {
      if (!_isCurrentAccessRequest(epoch, userKey)) return false;
      _user = cachedUser;
      _accessSyncState = _hasUsableAccessSnapshot
          ? AuthAccessSyncState.stale
          : AuthAccessSyncState.failed;
      await AppLogger.instance.warn(
        'Auth',
        'Saved session bootstrap refresh crashed; cache retained',
        context: {
          'email': cachedUser.email,
          'errorType': e.runtimeType.toString(),
          'stackAvailable': stackTrace.toString().isNotEmpty,
          'cachedFeatureAccessCount': cachedUser.featureAccess.length,
          'cachedPolicyAccessCount': cachedUser.policyAccess.length,
        },
      );
      if (!_isCurrentAccessRequest(epoch, userKey)) return false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _refreshSavedSessionLegacy(
    User cachedUser,
    int epoch,
    String userKey,
  ) async {
    final current = await _repository.getUserData(cachedUser.email);
    if (!_isCurrentAccessRequest(epoch, userKey)) return false;
    final featureAccess = await _repository.getMyFeatureAccess();
    if (!_isCurrentAccessRequest(epoch, userKey)) return false;
    final policyAccess = await _repository.getMyPolicyAccess();
    if (!_isCurrentAccessRequest(epoch, userKey)) return false;
    final withAccess = current.copyWith(
      featureAccess: featureAccess,
      policyAccess: policyAccess,
    );
    final withAccessUserKey = _authUserKey(withAccess);
    _user = withAccess;
    _bootstrapEtag = null;
    _bootstrapGeneratedAt = null;
    _bootstrapVersion = null;
    _bootstrapSchemaVersion = null;
    _bootstrapConditionalGet = false;
    _realtimeV2Topics = const [];
    _accessLastSyncedAt = DateTime.now();
    _accessSyncState = AuthAccessSyncState.fresh;
    _hasUsableAccessSnapshot = true;
    await _saveSession(withAccess, expectedEpoch: epoch);
    if (!_isCurrentAccessRequest(epoch, withAccessUserKey)) return false;
    await AppLogger.instance.info(
      'Auth',
      'Legacy saved session refresh succeeded',
      context: {
        'email': withAccess.email,
        'assignedStoreCount': withAccess.assignedStores.length,
        'featureAccessCount': featureAccess.length,
        'policyAccessCount': policyAccess.length,
      },
    );
    if (!_isCurrentAccessRequest(epoch, withAccessUserKey)) return false;
    notifyListeners();
    return true;
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
      Map<String, bool> policyAccess = user.policyAccess.isNotEmpty
          ? user.policyAccess
          : (_user?.policyAccess ?? const {});
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
      _accessLastSyncedAt = DateTime.now();
      _accessSyncState = AuthAccessSyncState.fresh;
      _hasUsableAccessSnapshot = true;
      return user.copyWith(featureAccess: access, policyAccess: policyAccess);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        final failedAuthToken = ApiClient().authToken;
        if (_user != null && failedAuthToken != null) {
          await _handleRemoteAuthFailure(e, failedAuthToken);
        }
        rethrow;
      }
      await AppLogger.instance.warn(
        'Auth',
        'Feature access load failed; using server response access only',
        context: {'email': user.email, 'error': e.toString()},
      );
      if (!allowFallback) rethrow;
      final cachedFeatureAccess = user.featureAccess.isNotEmpty
          ? user.featureAccess
          : (_user?.featureAccess ?? const {});
      final cachedPolicyAccess = user.policyAccess.isNotEmpty
          ? user.policyAccess
          : (_user?.policyAccess ?? const {});
      _accessSyncState =
          cachedFeatureAccess.isNotEmpty ||
              cachedPolicyAccess.isNotEmpty ||
              user.isSuperAdmin
          ? AuthAccessSyncState.stale
          : AuthAccessSyncState.failed;
      return user.copyWith(
        featureAccess: cachedFeatureAccess,
        policyAccess: cachedPolicyAccess,
      );
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
      _advanceSessionEpoch();
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
      _advanceSessionEpoch();
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
      _advanceSessionEpoch();
      _user = await _withFeatureAccess(user);
      await _saveSession(_user!, token: token);
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
    final logoutAuthToken = ApiClient().authToken;
    // Invalidate every in-flight bootstrap immediately, while preserving the
    // token just long enough for the best-effort server-side revoke call.
    _advanceSessionEpoch();
    final logoutEpoch = _sessionEpoch;
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
    if (logoutEpoch != _sessionEpoch ||
        ApiClient().authToken != logoutAuthToken) {
      await AppLogger.instance.info(
        'Auth',
        'Logout completion ignored because session changed',
        context: {'email': email},
      );
      return;
    }
    final clearEpoch = await _clearSession(
      expectedEpoch: logoutEpoch,
      expectedAuthToken: logoutAuthToken,
    );
    if (clearEpoch == null ||
        clearEpoch != _sessionEpoch ||
        ApiClient().authToken != null) {
      return;
    }
    _user = null;
    _errorMessage = null;
    _isLoading = false;
    await AppLogger.instance.info(
      'Auth',
      'Logout completed',
      context: {'email': email},
    );
    if (clearEpoch != _sessionEpoch || ApiClient().authToken != null) return;
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
    await retryAccessSync();
  }
}
