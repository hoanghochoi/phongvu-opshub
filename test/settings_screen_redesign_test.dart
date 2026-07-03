import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/app/theme/theme_provider.dart';
import 'helpers/legacy_widget_finders.dart';
import 'package:phongvu_opshub/core/logging/app_logger.dart';
import 'package:phongvu_opshub/features/settings/data/startup_settings_service.dart';
import 'package:phongvu_opshub/features/settings/presentation/screens/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLogger.instance.setUploadsEnabledForTesting(false);
  });

  tearDown(() {
    AppLogger.instance.setUploadsEnabledForTesting(true);
  });

  testWidgets('Settings renders content-only runtime controls', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settingsRuntime = _FakeSettingsRuntime(
      const StartupSettingsSnapshot(
        isSupported: false,
        isEnabled: false,
        message: 'Tùy chọn này chỉ hỗ trợ trên Windows.',
      ),
    );

    await tester.pumpWidget(_wrapSettings(settingsRuntime));
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsNothing);
    expect(findsLegacyGradientHeader(), findsNothing);
    expect(find.byKey(const Key('settings-header')), findsOneWidget);
    expect(find.byKey(const Key('settings-theme-card')), findsOneWidget);
    expect(find.byKey(const Key('settings-startup-card')), findsOneWidget);
    expect(find.text('Cài đặt'), findsOneWidget);
    expect(find.text('Giao diện'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Giao diện: Hệ thống'), findsOneWidget);
    expect(find.text('Windows: Không hỗ trợ'), findsOneWidget);
    expect(find.text('Tùy chọn này chỉ hỗ trợ trên Windows.'), findsOneWidget);
    expect(settingsRuntime.loadCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings theme segmented control updates selected mode', (
    tester,
  ) async {
    final settingsRuntime = _FakeSettingsRuntime(
      const StartupSettingsSnapshot(isSupported: true, isEnabled: false),
    );

    await tester.pumpWidget(_wrapSettings(settingsRuntime));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(find.text('Giao diện: Tối'), findsOneWidget);
    expect(find.text('Windows: Đang tắt'), findsOneWidget);
    expect(settingsRuntime.loadCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _wrapSettings(_FakeSettingsRuntime settingsRuntime) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      home: SettingsScreen(
        loadStartupSetting: settingsRuntime.load,
        setStartupEnabled: settingsRuntime.setEnabled,
      ),
    ),
  );
}

class _FakeSettingsRuntime {
  _FakeSettingsRuntime(this.snapshot);

  StartupSettingsSnapshot snapshot;
  int loadCount = 0;
  int setCount = 0;

  Future<StartupSettingsSnapshot> load() async {
    loadCount += 1;
    return snapshot;
  }

  Future<StartupSettingsSnapshot> setEnabled(bool enabled) async {
    setCount += 1;
    snapshot = StartupSettingsSnapshot(
      isSupported: snapshot.isSupported,
      isEnabled: enabled,
      hasStaleEntry: false,
      message: snapshot.message,
    );
    return snapshot;
  }
}
