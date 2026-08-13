part of 'payment_monitor_provider.dart';

typedef PaymentMonitorActionReplaceTransaction =
    void Function(MapPaymentTransaction updated, {String? previousId});

typedef PaymentMonitorActionRefreshCurrentPage =
    Future<void> Function({required String reason});

/// Owns payment-monitor row actions while [PaymentMonitorProvider] remains the
/// stable public facade consumed by the payment monitor, bank statement and
/// VietQR flows.
///
/// The coordinator deliberately receives state mutation callbacks instead of
/// reaching into provider fields. This keeps action orchestration isolated
/// without changing permissions, retry behavior, row messages or repository
/// contracts.
class PaymentMonitorActionRuntime {
  final PaymentMonitorRepository _repository;
  final MapPaymentTransaction? Function(String transactionId)
  _findTransactionById;
  final MapPaymentTransaction? Function(String transactionKey)
  _findTransactionByKey;
  final PaymentMonitorActionReplaceTransaction _replaceTransaction;
  final PaymentMonitorActionRefreshCurrentPage _refreshCurrentPage;
  final void Function(String id, String text, bool success) _showRowMessage;
  final VoidCallback _notifyListeners;
  final Set<String> _updatingOrderIds;
  final Set<String> _updatingOrderTrackingIds;

  PaymentMonitorActionRuntime({
    required PaymentMonitorRepository repository,
    required MapPaymentTransaction? Function(String transactionId)
    findTransactionById,
    required MapPaymentTransaction? Function(String transactionKey)
    findTransactionByKey,
    required PaymentMonitorActionReplaceTransaction replaceTransaction,
    required PaymentMonitorActionRefreshCurrentPage refreshCurrentPage,
    required void Function(String id, String text, bool success) showRowMessage,
    required VoidCallback notifyListeners,
    required Set<String> updatingOrderIds,
    required Set<String> updatingOrderTrackingIds,
  }) : _repository = repository,
       _findTransactionById = findTransactionById,
       _findTransactionByKey = findTransactionByKey,
       _replaceTransaction = replaceTransaction,
       _refreshCurrentPage = refreshCurrentPage,
       _showRowMessage = showRowMessage,
       _notifyListeners = notifyListeners,
       _updatingOrderIds = updatingOrderIds,
       _updatingOrderTrackingIds = updatingOrderTrackingIds;

  Future<bool> updateOrders(String transactionId, String rawInput) async {
    final existing = _findTransactionById(transactionId);
    final transactionKey = existing?.transactionKey.trim() ?? '';
    if (!_updatingOrderIds.add(transactionId)) return false;
    _notifyListeners();
    try {
      final orders = parseStatementOrderInput(rawInput);
      if (orders.isEmpty && existing?.orders.isEmpty != false) {
        throw const FormatException('Missing order codes');
      }
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save started',
        context: {
          'transactionId': transactionId,
          'hasTransactionKey': transactionKey.isNotEmpty,
          'orderCount': orders.length,
        },
      );
      final updated = await _repository.updateOrders(
        transactionId,
        orders,
        transactionKey: transactionKey,
        allowRateLimitCooldownBypass: true,
      );
      _replaceTransaction(updated, previousId: transactionId);
      _showRowMessage(updated.id, 'Đã cập nhật mã đơn hàng.', true);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save succeeded',
        context: {
          'transactionId': transactionId,
          'resolvedTransactionId': updated.id,
          'hasTransactionKey': transactionKey.isNotEmpty,
          'orderCount': orders.length,
        },
      );
      return true;
    } catch (error) {
      final orders = _tryParseStatementOrderInput(rawInput);
      if (orders != null &&
          transactionKey.isNotEmpty &&
          _isInvalidTransactionError(error) &&
          await _retryOrderSaveAfterStatementRefresh(
            originalTransactionId: transactionId,
            transactionKey: transactionKey,
            orders: orders,
          )) {
        return true;
      }
      _showRowMessage(
        transactionId,
        _orderInputErrorMessage(error, fallback: 'Chưa lưu được mã đơn.'),
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor inline order save failed',
        error: error,
        context: {
          'transactionId': transactionId,
          'hasTransactionKey': transactionKey.isNotEmpty,
        },
      );
      return false;
    } finally {
      _updatingOrderIds.remove(transactionId);
      _notifyListeners();
    }
  }

  Future<bool> updateOrderTracking(String transactionId, String status) async {
    final existing = _findTransactionById(transactionId);
    final nextStatus = status.trim().toUpperCase();
    if (existing == null ||
        !existing.canManageOrderTracking ||
        (nextStatus != 'FOLLOWING' && nextStatus != 'UNFOLLOWED')) {
      _showRowMessage(
        transactionId,
        existing?.orderTrackingActionBlockedReason ??
            'Không thể thay đổi trạng thái theo dõi giao dịch.',
        false,
      );
      return false;
    }
    if (existing.orderTrackingStatus == nextStatus) return true;
    if (!_updatingOrderTrackingIds.add(transactionId)) return false;
    _notifyListeners();
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor tracking update started',
        context: {'transactionId': transactionId, 'nextStatus': nextStatus},
      );
      final updated = await _repository.updateOrderTracking(
        transactionId,
        nextStatus,
        allowRateLimitCooldownBypass: true,
      );
      _replaceTransaction(updated, previousId: transactionId);
      _showRowMessage(
        updated.id,
        updated.isFollowing
            ? 'Đã theo dõi lại giao dịch.'
            : 'Đã bỏ theo dõi giao dịch.',
        true,
      );
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor tracking update succeeded',
        context: {
          'transactionId': updated.id,
          'nextStatus': updated.orderTrackingStatus,
        },
      );
      return true;
    } catch (error) {
      _showRowMessage(
        transactionId,
        _orderInputErrorMessage(
          error,
          fallback: 'Chưa thay đổi được trạng thái theo dõi.',
        ),
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor tracking update failed',
        error: error,
        context: {'transactionId': transactionId, 'nextStatus': nextStatus},
      );
      return false;
    } finally {
      _updatingOrderTrackingIds.remove(transactionId);
      _notifyListeners();
    }
  }

  Future<bool> requestOrderTransfer(
    String transactionId,
    String rawInput,
  ) async {
    final existing = _findTransactionById(transactionId);
    final transactionKey = existing?.transactionKey.trim() ?? '';
    try {
      final orders = parseStatementOrderInput(rawInput);
      if (orders.isEmpty) {
        _showRowMessage(transactionId, 'Vui lòng nhập mã đơn hàng mới.', false);
        return false;
      }
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor compatibility order update started',
        context: {
          'transactionId': transactionId,
          'hasTransactionKey': transactionKey.isNotEmpty,
          'orderCount': orders.length,
        },
      );
      await _repository.createOrderTransferRequest(
        transactionId,
        orders,
        transactionKey: transactionKey,
        allowRateLimitCooldownBypass: true,
      );
      await _refreshCurrentPage(reason: 'compatibility_order_update');
      _showRowMessage(transactionId, 'Đã cập nhật mã đơn hàng.', true);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor compatibility order update succeeded',
        context: {
          'transactionId': transactionId,
          'hasTransactionKey': transactionKey.isNotEmpty,
          'orderCount': orders.length,
        },
      );
      return true;
    } catch (error) {
      _showRowMessage(
        transactionId,
        _orderInputErrorMessage(error, fallback: 'Chưa cập nhật được mã đơn.'),
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor compatibility order update failed',
        error: error,
        upload: true,
        context: {
          'transactionId': transactionId,
          'hasTransactionKey': transactionKey.isNotEmpty,
        },
      );
      return false;
    }
  }

  Future<List<BankStatementOrderHistoryEntry>> fetchOrderHistory(
    String transactionId,
  ) async {
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order history load started',
        context: {'transactionId': transactionId},
      );
      final rows = await _repository.fetchOrderHistory(
        transactionId,
        allowRateLimitCooldownBypass: true,
      );
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor order history load succeeded',
        context: {'transactionId': transactionId, 'count': rows.length},
      );
      return rows;
    } catch (error) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor order history load failed',
        error: error,
        context: {'transactionId': transactionId},
      );
      rethrow;
    }
  }

  Future<void> reviewOrderTransferRequest(
    String transactionId,
    String requestId, {
    required bool approved,
    String? note,
  }) async {
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval started'
            : 'Payment monitor order transfer rejection started',
        context: {
          'transactionId': transactionId,
          'requestId': requestId,
          'hasNote': note?.trim().isNotEmpty == true,
        },
      );
      final updated = approved
          ? await _repository.approveOrderTransferRequest(
              requestId,
              allowRateLimitCooldownBypass: true,
            )
          : await _repository.rejectOrderTransferRequest(
              requestId,
              note: note,
              allowRateLimitCooldownBypass: true,
            );
      if (updated != null) {
        _replaceTransaction(updated);
      } else {
        await _refreshCurrentPage(
          reason: approved
              ? 'order_transfer_approved'
              : 'order_transfer_rejected',
        );
      }
      _showRowMessage(
        transactionId,
        approved ? 'Đã cập nhật mã đơn hàng.' : 'Đã từ chối yêu cầu.',
        true,
      );
      await AppLogger.instance.info(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval succeeded'
            : 'Payment monitor order transfer rejection succeeded',
        context: {'transactionId': transactionId, 'requestId': requestId},
      );
    } catch (error) {
      _showRowMessage(
        transactionId,
        approved ? 'Chưa duyệt được yêu cầu.' : 'Chưa từ chối được yêu cầu.',
        false,
      );
      await AppLogger.instance.error(
        'PaymentMonitor',
        approved
            ? 'Payment monitor order transfer approval failed'
            : 'Payment monitor order transfer rejection failed',
        error: error,
        context: {'transactionId': transactionId, 'requestId': requestId},
      );
    }
  }

  Future<bool> _retryOrderSaveAfterStatementRefresh({
    required String originalTransactionId,
    required String transactionKey,
    required List<String> orders,
  }) async {
    try {
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save retry started',
        context: {
          'transactionId': originalTransactionId,
          'hasTransactionKey': transactionKey.trim().isNotEmpty,
        },
      );
      await _refreshCurrentPage(reason: 'order_save_stale_transaction');
      final refreshed = _findTransactionByKey(transactionKey);
      if (refreshed == null || refreshed.id == originalTransactionId) {
        await AppLogger.instance.warn(
          'PaymentMonitor',
          'Payment monitor inline order save retry skipped',
          context: {
            'transactionId': originalTransactionId,
            'hasRefreshedTransaction': refreshed != null,
          },
        );
        return false;
      }
      final updated = await _repository.updateOrders(
        refreshed.id,
        orders,
        transactionKey: refreshed.transactionKey,
        allowRateLimitCooldownBypass: true,
      );
      _replaceTransaction(updated, previousId: originalTransactionId);
      _showRowMessage(updated.id, 'Đã cập nhật mã đơn hàng.', true);
      await AppLogger.instance.info(
        'PaymentMonitor',
        'Payment monitor inline order save retry succeeded',
        context: {
          'transactionId': originalTransactionId,
          'resolvedTransactionId': updated.id,
        },
      );
      return true;
    } catch (retryError, retryStackTrace) {
      await AppLogger.instance.error(
        'PaymentMonitor',
        'Payment monitor inline order save retry failed',
        error: retryError,
        stackTrace: retryStackTrace,
        context: {'transactionId': originalTransactionId},
      );
      return false;
    }
  }

  String _orderInputErrorMessage(Object error, {required String fallback}) {
    if (error is api.ApiException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    if (error is FormatException) {
      return 'Mã đơn hàng phải gồm 14 chữ số, ngăn cách bằng dòng hoặc dấu phẩy.';
    }
    return fallback;
  }

  bool _isInvalidTransactionError(Object error) {
    return error is api.ApiException &&
        error.message.contains('Giao dịch không hợp lệ');
  }

  List<String>? _tryParseStatementOrderInput(String rawInput) {
    try {
      return parseStatementOrderInput(rawInput);
    } catch (_) {
      return null;
    }
  }
}
