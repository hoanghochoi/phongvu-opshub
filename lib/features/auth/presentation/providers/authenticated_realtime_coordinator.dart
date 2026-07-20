import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/realtime_connection_manager.dart';
import '../../../../core/runtime/app_runtime_coordinator.dart';
import '../../domain/realtime_session_identity.dart';
import 'auth_provider.dart';

/// Owns authenticated realtime session changes independently from feature
/// routes. Feature providers only subscribe to typed events and sync requests.
class AuthenticatedRealtimeCoordinator {
  AuthenticatedRealtimeCoordinator({required RealtimeClient realtimeClient})
    : _realtimeClient = realtimeClient;

  final RealtimeClient _realtimeClient;

  String? _requestedSessionKey;
  bool _disposed = false;

  void sync(AuthProvider auth, AppRuntimeCoordinator runtime) {
    if (_disposed) return;
    final user =
        auth.isInitialized &&
            auth.isAuthenticated &&
            auth.hasUsableAccessSnapshot &&
            runtime.hasAuthenticatedRoute
        ? auth.user
        : null;
    final nextSessionKey = user == null
        ? null
        : RealtimeSessionIdentity.forUser(
            user,
            accessIdentity: auth.accessIdentity,
          );
    if (_requestedSessionKey == nextSessionKey) return;
    _requestedSessionKey = nextSessionKey;
    unawaited(_syncSession(nextSessionKey));
  }

  Future<void> _syncSession(String? sessionKey) async {
    final authenticated = sessionKey != null;
    await AppLogger.instance.info(
      'AuthenticatedRealtime',
      'Authenticated realtime session sync started',
      context: {'authenticated': authenticated},
    );
    if (_disposed || _requestedSessionKey != sessionKey) return;
    try {
      await _realtimeClient.syncSession(sessionKey);
      await AppLogger.instance.info(
        'AuthenticatedRealtime',
        'Authenticated realtime session sync succeeded',
        context: {'authenticated': authenticated},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AuthenticatedRealtime',
        'Authenticated realtime session sync failed',
        error: error,
        stackTrace: stackTrace,
        context: {'authenticated': authenticated},
        upload: authenticated,
      );
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestedSessionKey = null;
    unawaited(_realtimeClient.syncSession(null));
  }
}
