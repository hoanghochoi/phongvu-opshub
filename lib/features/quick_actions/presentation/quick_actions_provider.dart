import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/logging/app_logger.dart';
import '../../auth/domain/entities/user.dart';
import '../data/quick_actions_repository.dart';

class QuickActionsProvider extends ChangeNotifier {
  final QuickActionsRepository _repository;
  QuickActionsPayload? _payload;
  bool _loading = false;
  Object? _error;
  String? _userId;

  QuickActionsProvider(this._repository);

  QuickActionsPayload? get payload => _payload;
  bool get isLoading => _loading;
  Object? get error => _error;

  Future<void> syncUser(User? user) async {
    if (_userId == user?.id) return;
    _userId = user?.id;
    _payload = null;
    _error = null;
    if (user?.canUseFeature('QUICK_ACTIONS') != true) {
      notifyListeners();
      return;
    }
    await refresh();
  }

  Future<QuickActionsPayload?> refresh({String? storeCode}) async {
    if (_loading) return _payload;
    final startedAt = DateTime.now();
    _loading = true;
    _error = null;
    notifyListeners();
    await AppLogger.instance.info(
      'QuickActions',
      'Quick actions load started',
      context: {'storeCode': storeCode},
    );
    try {
      _payload = await _repository.load(storeCode: storeCode);
      await AppLogger.instance.info(
        'QuickActions',
        'Quick actions load succeeded',
        context: {
          'storeCode': _payload?.selectedStoreCode,
          'storeCount': _payload?.stores.length ?? 0,
          'availableCount': _payload?.availableActionCodes.length ?? 0,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return _payload;
    } catch (error, stackTrace) {
      _error = error;
      await AppLogger.instance.error(
        'QuickActions',
        'Quick actions load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'storeCode': storeCode,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
