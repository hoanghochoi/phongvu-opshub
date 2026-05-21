import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../auth/domain/entities/user.dart';
import '../../data/payment_speaker.dart';
import '../../data/repositories/payment_monitor_repository.dart';
import '../../domain/map_payment_transaction.dart';

class PaymentMonitorProvider extends ChangeNotifier {
  static const _pollInterval = Duration(seconds: 5);

  final PaymentMonitorRepository _repository;
  final PaymentSpeaker _speaker;
  final Set<String> _seenTransactionIds = {};
  final List<MapPaymentTransaction> _latestTransactions = [];

  Timer? _timer;
  User? _user;
  String? _storeOverride;
  bool _isActive = false;
  bool _isLoading = false;
  bool _hasSeeded = false;
  String? _errorMessage;
  DateTime? _lastCheckedAt;

  PaymentMonitorProvider(this._repository, this._speaker);

  bool get isActive => _isActive;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  String? get storeOverride => _storeOverride;
  List<MapPaymentTransaction> get latestTransactions =>
      List.unmodifiable(_latestTransactions);

  void syncAuth(User? user, {required bool isInitialized}) {
    _user = user;
    if (!isInitialized || user == null || !_canMonitorOnThisDevice) {
      _stop();
      return;
    }
    _reconcile();
  }

  void setStoreOverride(String value) {
    final normalized = value.trim().toUpperCase();
    if (_storeOverride == normalized) return;
    _storeOverride = normalized.isEmpty ? null : normalized;
    _restart();
  }

  bool get _canMonitorOnThisDevice =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get _hasMonitorScope {
    final user = _user;
    if (user == null) return false;
    if (user.role == 'SUPER_ADMIN') return _storeOverride?.isNotEmpty == true;
    return user.storeId?.isNotEmpty == true;
  }

  String? get _requestStoreId {
    final user = _user;
    if (user?.role == 'SUPER_ADMIN') return _storeOverride;
    return null;
  }

  void _reconcile() {
    if (!_hasMonitorScope) {
      _stop();
      return;
    }
    if (_isActive) return;
    _isActive = true;
    _hasSeeded = false;
    _seenTransactionIds.clear();
    _latestTransactions.clear();
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    notifyListeners();
  }

  void _restart() {
    _stop();
    _reconcile();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (!_isActive &&
        !_isLoading &&
        _latestTransactions.isEmpty &&
        _errorMessage == null) {
      return;
    }
    _isActive = false;
    _isLoading = false;
    _hasSeeded = false;
    _seenTransactionIds.clear();
    _latestTransactions.clear();
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (_isLoading || !_hasMonitorScope) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final transactions = await _repository.fetchStoredTransactions(
        storeId: _requestStoreId,
        limit: 50,
      );
      final sorted = [...transactions]
        ..sort((a, b) {
          final aTime =
              a.firstSeenAt ??
              a.paidAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime =
              b.firstSeenAt ??
              b.paidAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return aTime.compareTo(bTime);
        });

      final newTransactions = <MapPaymentTransaction>[];
      for (final transaction in sorted) {
        if (_seenTransactionIds.add(transaction.id) && _hasSeeded) {
          newTransactions.add(transaction);
        }
      }
      _hasSeeded = true;

      for (final transaction in newTransactions) {
        await _speaker.speakAmount(transaction.amount);
      }

      _lastCheckedAt = DateTime.now();
      _latestTransactions
        ..clear()
        ..addAll(transactions.take(10));
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
