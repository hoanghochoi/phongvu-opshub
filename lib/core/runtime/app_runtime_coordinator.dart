import 'dart:async';

import 'package:flutter/widgets.dart';

import '../logging/app_logger.dart';

/// Shared source of truth for foreground and active-route request eligibility.
///
/// Providers may keep cached data while inactive, but they must not start
/// feature reads, polling or retry loops until their route/surface is active.
class AppRuntimeCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  AppRuntimeCoordinator()
    : _lifecycleState =
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed {
    WidgetsBinding.instance.addObserver(this);
  }

  String? _activeRoute;
  AppLifecycleState _lifecycleState;
  bool _disposed = false;

  String? get activeRoute => _activeRoute;
  AppLifecycleState get lifecycleState => _lifecycleState;
  bool get isForeground => _lifecycleState == AppLifecycleState.resumed;
  bool get hasAuthenticatedRoute {
    final route = _activeRoute;
    if (route == null || !route.startsWith('/')) return false;
    return !const {
      '/loading',
      '/login',
      '/register',
      '/forgot-password',
      '/help',
    }.contains(route);
  }

  bool routeIs(String route) => _activeRoute == route;

  bool routeStartsWith(String prefix) =>
      _activeRoute?.startsWith(prefix) == true;

  void setActiveRoute(String? route) {
    if (_disposed) return;
    final normalized = route?.trim();
    final next = normalized?.isNotEmpty == true ? normalized : null;
    if (_activeRoute == next) return;
    final previous = _activeRoute;
    _activeRoute = next;
    notifyListeners();
    unawaited(
      AppLogger.instance.info(
        'AppRuntime',
        'Active route changed',
        context: {'from': previous, 'to': next, 'foreground': isForeground},
      ),
    );
  }

  void clearActiveRoute(String route) {
    if (_activeRoute != route) return;
    setActiveRoute(null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycleState == state) return;
    final previous = _lifecycleState;
    _lifecycleState = state;
    notifyListeners();
    unawaited(
      AppLogger.instance.info(
        'AppRuntime',
        'App lifecycle changed',
        context: {
          'from': previous.name,
          'to': state.name,
          'route': _activeRoute,
        },
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
