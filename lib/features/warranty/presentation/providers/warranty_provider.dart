import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../data/repositories/warranty_repository.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';

class WarrantyProvider extends ChangeNotifier {
  final WarrantyRepository _repository;
  final RealtimeClient _realtimeClient;
  final Duration _realtimeRefreshDebounce;
  final Duration _realtimeRefreshMaxWait;

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic>? _currentDetails;
  StreamSubscription<RealtimeEnvelope>? _realtimeEventSubscription;
  StreamSubscription<RealtimeSyncReason>? _realtimeSyncSubscription;
  User? _user;
  bool _isInitialized = false;
  bool _isRouteActive = true;
  bool _isForeground = true;
  Timer? _realtimeRefreshTimer;
  DateTime? _realtimeRefreshFirstQueuedAt;
  String? _pendingRealtimeRefreshReason;
  int _pendingRealtimeRefreshEvents = 0;
  bool _realtimeRefreshInFlight = false;
  bool _realtimeRefreshDirty = false;
  String? _authorizationSignature;
  int _authGeneration = 0;
  int _listRequestToken = 0;
  int _detailsRequestToken = 0;

  WarrantyProvider(
    this._repository, {
    RealtimeClient? realtimeClient,
    Duration realtimeRefreshDebounce = const Duration(seconds: 2),
    Duration realtimeRefreshMaxWait = const Duration(seconds: 5),
  }) : _realtimeClient = realtimeClient ?? RealtimeConnectionManager.instance,
       _realtimeRefreshDebounce = realtimeRefreshDebounce,
       _realtimeRefreshMaxWait = realtimeRefreshMaxWait {
    _realtimeEventSubscription = _realtimeClient.events.listen(
      _handleRealtimeEnvelope,
    );
    _realtimeSyncSubscription = _realtimeClient.syncRequests.listen(
      _handleRealtimeSyncRequest,
    );
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get receipts => _receipts;
  Map<String, dynamic>? get currentDetails => _currentDetails;

  void syncRuntime({required bool isRouteActive, required bool isForeground}) {
    _isRouteActive = isRouteActive;
    _isForeground = isForeground;
  }

  void syncAuth(User? user, {required bool isInitialized}) {
    final nextSignature = _authSignature(user, isInitialized);
    final authorizationChanged = _authorizationSignature != nextSignature;
    _user = user;
    _isInitialized = isInitialized;
    _authorizationSignature = nextSignature;
    if (!authorizationChanged) return;

    _authGeneration += 1;
    _listRequestToken += 1;
    _detailsRequestToken += 1;
    _isLoading = false;
    _cancelScheduledRealtimeRefresh();
    _receipts = [];
    _currentDetails = null;
    _errorMessage = null;
    unawaited(
      AppLogger.instance.info(
        'Warranty',
        'Warranty authorization scope changed; local state cleared',
        context: {
          'authenticated': user != null,
          'initialized': isInitialized,
          'warrantyEnabled': user?.canUseFeature('WARRANTY') == true,
        },
      ),
    );
    notifyListeners();
  }

  Future<void> _handleRealtimeEnvelope(RealtimeEnvelope envelope) async {
    if (envelope.kind != 'WARRANTY_EVENT' ||
        envelope.topic != 'warranty' ||
        !_canConsumeRealtime) {
      return;
    }
    try {
      final payload = envelope.data;
      final warrantyId = payload['warrantyId']?.toString();
      final newStatus = payload['newStatus']?.toString();
      if (warrantyId == null || warrantyId.isEmpty || newStatus == null) {
        return;
      }
      await AppLogger.instance.info(
        'WarrantyRealtime',
        'Warranty realtime event received',
        context: {
          'eventId': envelope.id,
          'warrantyId': warrantyId,
          'status': newStatus,
        },
      );
      final changed = _applyRealtimeStatus(warrantyId, newStatus);
      if (changed) notifyListeners();
      if (_receipts.isNotEmpty && _user != null) {
        _scheduleRealtimeRefresh(warrantyId);
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'WarrantyRealtime',
        'Warranty realtime event parse failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool get _canConsumeRealtime =>
      _isInitialized &&
      _isRouteActive &&
      _isForeground &&
      _user?.canUseFeature('WARRANTY') == true;

  void _handleRealtimeSyncRequest(RealtimeSyncReason reason) {
    if (!_canConsumeRealtime || _receipts.isEmpty) return;
    unawaited(
      AppLogger.instance.info(
        'WarrantyRealtime',
        'Warranty realtime sync requested',
        context: {'reason': reason.name},
      ),
    );
    _scheduleRealtimeRefresh('sync_${reason.name}');
  }

  bool _applyRealtimeStatus(String warrantyId, String newStatus) {
    var changed = false;
    _receipts = _receipts
        .map((receipt) {
          if (!_recordMatchesWarrantyId(receipt, warrantyId)) return receipt;
          changed = true;
          return {...receipt, 'status': newStatus};
        })
        .toList(growable: false);
    final details = _currentDetails;
    if (details != null && _recordMatchesWarrantyId(details, warrantyId)) {
      _currentDetails = {...details, 'status': newStatus};
      changed = true;
    }
    return changed;
  }

  bool _recordMatchesWarrantyId(
    Map<String, dynamic> record,
    String warrantyId,
  ) {
    for (final key in const ['id', 'warrantyId', '_id']) {
      if (record[key]?.toString() == warrantyId) return true;
    }
    return false;
  }

  void _scheduleRealtimeRefresh(String reason) {
    if (!_canConsumeRealtime || _receipts.isEmpty || _user == null) return;
    final now = DateTime.now();
    _realtimeRefreshFirstQueuedAt ??= now;
    _pendingRealtimeRefreshReason = reason;
    _pendingRealtimeRefreshEvents += 1;

    final elapsed = now.difference(_realtimeRefreshFirstQueuedAt!);
    final remaining = _realtimeRefreshMaxWait - elapsed;
    if (remaining <= Duration.zero) {
      _realtimeRefreshTimer?.cancel();
      _realtimeRefreshTimer = null;
      unawaited(_flushRealtimeRefresh());
      return;
    }

    _realtimeRefreshTimer?.cancel();
    final delay = remaining < _realtimeRefreshDebounce
        ? remaining
        : _realtimeRefreshDebounce;
    _realtimeRefreshTimer = Timer(delay, () {
      _realtimeRefreshTimer = null;
      unawaited(_flushRealtimeRefresh());
    });
  }

  Future<void> _flushRealtimeRefresh() async {
    if (_realtimeRefreshInFlight) {
      _realtimeRefreshDirty = true;
      return;
    }
    final user = _user;
    final authGeneration = _authGeneration;
    final requestToken = ++_listRequestToken;
    final reason = _pendingRealtimeRefreshReason ?? 'realtime';
    final coalescedEvents = _pendingRealtimeRefreshEvents;
    _realtimeRefreshFirstQueuedAt = null;
    _pendingRealtimeRefreshReason = null;
    _pendingRealtimeRefreshEvents = 0;
    if (user == null || !_canConsumeRealtime || _receipts.isEmpty) return;

    _realtimeRefreshInFlight = true;
    try {
      final receipts = await _repository.showAllWarranty(user.email);
      if (!_isCurrentListRequest(authGeneration, requestToken, user.email)) {
        return;
      }
      _receipts = receipts;
      notifyListeners();
      await AppLogger.instance.info(
        'WarrantyRealtime',
        'Warranty realtime list refresh succeeded',
        context: {
          'reason': reason,
          'count': receipts.length,
          'coalescedEvents': coalescedEvents,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'WarrantyRealtime',
        'Warranty realtime list refresh failed',
        error: error,
        stackTrace: stackTrace,
        context: {'reason': reason, 'coalescedEvents': coalescedEvents},
      );
    } finally {
      _realtimeRefreshInFlight = false;
      if (_realtimeRefreshDirty) {
        _realtimeRefreshDirty = false;
        _scheduleRealtimeRefresh('dirty_after_$reason');
      }
    }
  }

  void _cancelScheduledRealtimeRefresh() {
    _realtimeRefreshTimer?.cancel();
    _realtimeRefreshTimer = null;
    _realtimeRefreshFirstQueuedAt = null;
    _pendingRealtimeRefreshReason = null;
    _pendingRealtimeRefreshEvents = 0;
    _realtimeRefreshDirty = false;
  }

  Future<bool> saveWarranty({
    required String userEmail,
    required String receiptNumber,
    required List<File> images,
  }) async {
    await AppLogger.instance.info(
      'Warranty',
      'Warranty save started',
      context: {
        'userEmail': userEmail,
        'receiptNumber': receiptNumber,
        'imageCount': images.length,
      },
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _repository.saveWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
        images: images,
      );

      final bool success = response['status'] == 'success';
      await AppLogger.instance.info(
        'Warranty',
        'Warranty save completed',
        context: {
          'userEmail': userEmail,
          'receiptNumber': receiptNumber,
          'imageCount': images.length,
          'success': success,
        },
      );
      _isLoading = false;
      notifyListeners();
      return success;
    } on ApiException catch (e) {
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty save failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Chưa lưu được biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> showAllWarranty(String userEmail) async {
    _cancelScheduledRealtimeRefresh();
    final authGeneration = _authGeneration;
    final requestToken = ++_listRequestToken;
    await AppLogger.instance.info(
      'Warranty',
      'Warranty list started',
      context: {'userEmail': userEmail},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final receipts = await _repository.showAllWarranty(userEmail);
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _receipts = receipts;
      await AppLogger.instance.info(
        'Warranty',
        'Warranty list succeeded',
        context: {'userEmail': userEmail, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty list failed',
        context: {'userEmail': userEmail, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _errorMessage = 'Chưa tải được danh sách biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> searchWarranty({
    required String userEmail,
    required String receiptNumber,
  }) async {
    final authGeneration = _authGeneration;
    final requestToken = ++_listRequestToken;
    await AppLogger.instance.info(
      'Warranty',
      'Warranty search started',
      context: {'userEmail': userEmail, 'receiptNumber': receiptNumber},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final receipts = await _repository.searchWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _receipts = receipts;
      await AppLogger.instance.info(
        'Warranty',
        'Warranty search succeeded',
        context: {'receiptNumber': receiptNumber, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty search failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (!_isCurrentListRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _errorMessage = 'Chưa tìm được biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> getWarrantyDetails({
    required String userEmail,
    required String receiptNumber,
  }) async {
    final authGeneration = _authGeneration;
    final requestToken = ++_detailsRequestToken;
    await AppLogger.instance.info(
      'Warranty',
      'Warranty detail started',
      context: {'userEmail': userEmail, 'receiptNumber': receiptNumber},
    );
    _isLoading = true;
    _errorMessage = null;
    _currentDetails = null;
    notifyListeners();

    try {
      final details = await _repository.getWarrantyDetails(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      if (!_isCurrentDetailsRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _currentDetails = details;
      await AppLogger.instance.info(
        'Warranty',
        'Warranty detail succeeded',
        context: {'receiptNumber': receiptNumber},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (!_isCurrentDetailsRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      await AppLogger.instance.warn(
        'Warranty',
        'Warranty detail failed',
        context: {'receiptNumber': receiptNumber, 'message': e.message},
      );
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (!_isCurrentDetailsRequest(authGeneration, requestToken, userEmail)) {
        return false;
      }
      _errorMessage = 'Chưa mở được chi tiết biên nhận. Vui lòng thử lại.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearDetails() {
    _currentDetails = null;
    notifyListeners();
  }

  void clearReceipts() {
    _receipts = [];
    notifyListeners();
  }

  String? _authSignature(User? user, bool isInitialized) {
    if (!isInitialized || user == null) return null;
    return [
      user.id ?? user.email.toLowerCase(),
      user.canUseFeature('WARRANTY') ? '1' : '0',
    ].join('|');
  }

  bool _isCurrentListRequest(
    int authGeneration,
    int requestToken,
    String userEmail,
  ) {
    return authGeneration == _authGeneration &&
        requestToken == _listRequestToken &&
        _user?.email == userEmail &&
        _user?.canUseFeature('WARRANTY') == true;
  }

  bool _isCurrentDetailsRequest(
    int authGeneration,
    int requestToken,
    String userEmail,
  ) {
    return authGeneration == _authGeneration &&
        requestToken == _detailsRequestToken &&
        _user?.email == userEmail &&
        _user?.canUseFeature('WARRANTY') == true;
  }

  @override
  void dispose() {
    _cancelScheduledRealtimeRefresh();
    unawaited(_realtimeEventSubscription?.cancel());
    unawaited(_realtimeSyncSubscription?.cancel());
    super.dispose();
  }
}
