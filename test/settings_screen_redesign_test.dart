import 'dart:async';

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
    expect(find.byKey(const Key('settings-header')), findsNothing);
    expect(find.byKey(const Key('settings-status-row')), findsOneWidget);
    expect(find.byKey(const Key('settings-theme-card')), findsOneWidget);
    expect(find.byKey(const Key('settings-startup-card')), findsOneWidget);
    expect(find.text('Tùy chọn thiết bị'), findsNothing);
    expect(find.text('Giao diện'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Giao diện: Hệ thống'), findsOneWidget);
    expect(find.text('Windows: Không hỗ trợ'), findsNothing);
    expect(find.text('Windows: Chỉ hỗ trợ trên Windows'), findsNothing);
    expect(find.text('Chỉ hỗ trợ trên Windows'), findsOneWidget);
    expect(find.text('Tùy chọn này chỉ hỗ trợ trên Windows.'), findsNothing);
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

  testWidgets(
    'Settings follows the approved desktop and tablet card geometry',
    (tester) async {
      final desktopRuntime = _FakeSettingsRuntime(
        const StartupSettingsSnapshot(isSupported: true, isEnabled: true),
      );
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_wrapSettings(desktopRuntime));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('settings-theme-card'))),
        const Size(555, 230),
      );
      expect(
        tester.getSize(find.byKey(const Key('settings-startup-card'))),
        const Size(555, 230),
      );

      final tabletRuntime = _FakeSettingsRuntime(
        const StartupSettingsSnapshot(isSupported: false, isEnabled: false),
      );
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpWidget(_wrapSettings(tabletRuntime));
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('settings-theme-card'))),
        const Size(343, 188),
      );
      expect(
        tester.getSize(find.byKey(const Key('settings-startup-card'))),
        const Size(343, 188),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings uses the approved startup loading, saving and error states',
    (tester) async {
      final load = Completer<StartupSettingsSnapshot>();
      final save = Completer<StartupSettingsSnapshot>();
      final themeProvider = ThemeProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider,
          child: MaterialApp(
            home: SettingsScreen(
              loadStartupSetting: () => load.future,
              setStartupEnabled: (_) => save.future,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Đang tải tùy chọn khởi động...'), findsOneWidget);

      load.complete(
        const StartupSettingsSnapshot(isSupported: true, isEnabled: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-startup-toggle')));
      await tester.pump();
      expect(find.text('Đang lưu thay đổi...'), findsOneWidget);

      save.complete(
        const StartupSettingsSnapshot(isSupported: true, isEnabled: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đang bật'), findsOneWidget);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: ThemeProvider(),
          child: MaterialApp(
            home: SettingsScreen(
              key: UniqueKey(),
              loadStartupSetting: () async =>
                  throw StateError('startup unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Không thể tải tùy chọn. Thử lại.'), findsOneWidget);
      expect(find.byKey(const Key('settings-startup-toggle')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
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
