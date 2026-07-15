import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/core/runtime/app_runtime_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  test('tracks the active route and foreground request eligibility', () {
    final coordinator = AppRuntimeCoordinator();
    addTearDown(coordinator.dispose);

    expect(coordinator.isForeground, isTrue);
    expect(coordinator.hasAuthenticatedRoute, isFalse);

    coordinator.setActiveRoute('/home');
    expect(coordinator.activeRoute, '/home');
    expect(coordinator.routeIs('/home'), isTrue);
    expect(coordinator.routeStartsWith('/home'), isTrue);
    expect(coordinator.hasAuthenticatedRoute, isTrue);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(coordinator.isForeground, isFalse);

    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(coordinator.isForeground, isTrue);
  });

  test('ignores duplicate route and lifecycle updates', () {
    final coordinator = AppRuntimeCoordinator();
    addTearDown(coordinator.dispose);
    var notifications = 0;
    coordinator.addListener(() => notifications += 1);

    coordinator.setActiveRoute('/payment-monitor');
    coordinator.setActiveRoute('/payment-monitor');
    coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(notifications, 1);
  });
}
