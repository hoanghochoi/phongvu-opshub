import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/repositories/warranty_repository.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/realtime_ticket_client.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../auth/domain/entities/user.dart';

class WarrantyProvider extends ChangeNotifier {
  final WarrantyRepository _repository;

  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _receipts = [];
  Map<String, dynamic>? _currentDetails;
  StreamSubscription<dynamic>? _realtimeSubscription;
  WebSocketChannel? _realtimeChannel;
  User? _user;
  String? _realtimeKey;

  WarrantyProvider(this._repository);

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get receipts => _receipts;
  Map<String, dynamic>? get currentDetails => _currentDetails;

  void syncAuth(User? user, {required bool isInitialized}) {
    _user = user;
    if (!isInitialized || user == null || !user.canUseFeature('WARRANTY')) {
      _disconnectRealtime('auth_or_feature_unavailable');
      return;
    }
    unawaited(_connectRealtime(user));
  }

  Future<void> _connectRealtime(User user) async {
    final token = ApiClient().authToken;
    if (token == null || token.trim().isEmpty) {
      _disconnectRealtime('missing_token');
      return;
    }
    final nextKey = '${user.email}|${user.storeId ?? ''}|$token';
    if (_realtimeKey == nextKey && _realtimeChannel != null) return;
    _disconnectRealtime('reconnect');

    try {
      final uri = await RealtimeTicketClient.instance.issueConnectionUri(
        storeCode: user.storeId,
      );
      if (_user != user || ApiClient().authToken != token) return;
      final channel = WebSocketChannel.connect(uri);
      _realtimeChannel = channel;
      _realtimeKey = nextKey;
      _realtimeSubscription = channel.stream.listen(
        _handleRealtimeMessage,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'WarrantyRealtime',
              'Warranty realtime error',
              error: error,
              stackTrace: stackTrace,
              context: {'storeId': user.storeId},
            ),
          );
        },
        onDone: () {
          unawaited(
            AppLogger.instance.info(
              'WarrantyRealtime',
              'Warranty realtime disconnected',
              context: {'storeId': user.storeId},
            ),
          );
          _realtimeSubscription = null;
          _realtimeChannel = null;
          _realtimeKey = null;
        },
      );
      unawaited(
        AppLogger.instance.info(
          'WarrantyRealtime',
          'Warranty realtime connected',
          context: {'storeId': user.storeId},
        ),
      );
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'WarrantyRealtime',
          'Warranty realtime connect failed',
          error: error,
          stackTrace: stackTrace,
          context: {'storeId': user.storeId},
        ),
      );
      _disconnectRealtime('connect_failed');
    }
  }

  void _disconnectRealtime(String reason) {
    final hadConnection = _realtimeChannel != null || _realtimeKey != null;
    unawaited(_realtimeSubscription?.cancel());
    _realtimeSubscription = null;
    unawaited(_realtimeChannel?.sink.close());
    _realtimeChannel = null;
    _realtimeKey = null;
    if (hadConnection) {
      unawaited(
        AppLogger.instance.info(
          'WarrantyRealtime',
          'Warranty realtime disconnected',
          context: {'reason': reason},
        ),
      );
    }
  }

  Future<void> _handleRealtimeMessage(dynamic message) async {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['type']?.toString() != 'WARRANTY_EVENT') return;
      final rawPayload = decoded['payload'];
      final payload = rawPayload is String
          ? jsonDecode(rawPayload) as Map<String, dynamic>
          : rawPayload is Map<String, dynamic>
          ? rawPayload
          : null;
      if (payload == null) return;
      final warrantyId = payload['warrantyId']?.toString();
      final newStatus = payload['newStatus']?.toString();
      if (warrantyId == null || warrantyId.isEmpty || newStatus == null) {
        return;
      }
      await AppLogger.instance.info(
        'WarrantyRealtime',
        'Warranty realtime event received',
        context: {'warrantyId': warrantyId, 'status': newStatus},
      );
      final changed = _applyRealtimeStatus(warrantyId, newStatus);
      if (changed) notifyListeners();
      if (_receipts.isNotEmpty && _user != null) {
        unawaited(_refreshListFromRealtime(warrantyId));
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

  Future<void> _refreshListFromRealtime(String warrantyId) async {
    final user = _user;
    if (user == null) return;
    try {
      final receipts = await _repository.showAllWarranty(user.email);
      _receipts = receipts;
      notifyListeners();
      await AppLogger.instance.info(
        'WarrantyRealtime',
        'Warranty realtime list refresh succeeded',
        context: {'warrantyId': warrantyId, 'count': receipts.length},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'WarrantyRealtime',
        'Warranty realtime list refresh failed',
        error: error,
        stackTrace: stackTrace,
        context: {'warrantyId': warrantyId},
      );
    }
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
    await AppLogger.instance.info(
      'Warranty',
      'Warranty list started',
      context: {'userEmail': userEmail},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.showAllWarranty(userEmail);
      await AppLogger.instance.info(
        'Warranty',
        'Warranty list succeeded',
        context: {'userEmail': userEmail, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
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
    await AppLogger.instance.info(
      'Warranty',
      'Warranty search started',
      context: {'userEmail': userEmail, 'receiptNumber': receiptNumber},
    );
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _receipts = await _repository.searchWarranty(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      await AppLogger.instance.info(
        'Warranty',
        'Warranty search succeeded',
        context: {'receiptNumber': receiptNumber, 'count': _receipts.length},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
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
      _currentDetails = await _repository.getWarrantyDetails(
        userEmail: userEmail,
        receiptNumber: receiptNumber,
      );
      await AppLogger.instance.info(
        'Warranty',
        'Warranty detail succeeded',
        context: {'receiptNumber': receiptNumber},
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
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

  @override
  void dispose() {
    _disconnectRealtime('provider_disposed');
    super.dispose();
  }
}
