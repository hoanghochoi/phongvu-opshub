import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses one context-menu owner for each platform', () {
    expect(
      resolveTextInputContextMenuMode(
        isWeb: true,
        targetPlatform: TargetPlatform.iOS,
      ),
      TextInputContextMenuMode.flutter,
    );
    expect(
      resolveTextInputContextMenuMode(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      ),
      TextInputContextMenuMode.flutter,
    );
    expect(
      resolveTextInputContextMenuMode(
        isWeb: true,
        targetPlatform: TargetPlatform.windows,
      ),
      TextInputContextMenuMode.flutter,
    );
    expect(
      resolveTextInputContextMenuMode(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      ),
      TextInputContextMenuMode.platformNative,
    );
  });

  test('disables browser context menu for desktop web', () async {
    var disabledCalls = 0;

    await initializeTextInputContextMenu(
      isWebOverride: true,
      targetPlatformOverride: TargetPlatform.windows,
      disableBrowserContextMenu: () async {
        disabledCalls += 1;
      },
    );

    expect(disabledCalls, 1);
  });

  test(
    'disables browser menu so mobile web uses Flutter paste toolbar',
    () async {
      var disabledCalls = 0;

      await initializeTextInputContextMenu(
        isWebOverride: true,
        targetPlatformOverride: TargetPlatform.iOS,
        disableBrowserContextMenu: () async {
          disabledCalls += 1;
        },
      );

      expect(disabledCalls, 1);
    },
  );

  test('skips browser context menu changes outside web', () async {
    var calls = 0;

    await initializeTextInputContextMenu(
      isWebOverride: false,
      targetPlatformOverride: TargetPlatform.android,
      disableBrowserContextMenu: () async {
        calls += 1;
      },
    );

    expect(calls, 0);
  });

  test(
    'keeps startup non-blocking when web context menu setup fails',
    () async {
      await initializeTextInputContextMenu(
        isWebOverride: true,
        targetPlatformOverride: TargetPlatform.windows,
        disableBrowserContextMenu: () async {
          throw StateError('context menu unavailable');
        },
      );
    },
  );
}
