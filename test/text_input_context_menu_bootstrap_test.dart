import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/core/platform/text_input_context_menu_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses Flutter text input context menu only on web', () {
    expect(shouldUseFlutterTextInputContextMenu(isWeb: true), isTrue);
    expect(shouldUseFlutterTextInputContextMenu(isWeb: false), isFalse);
  });

  test('disables browser context menu for web builds', () async {
    var calls = 0;

    await initializeTextInputContextMenu(
      isWebOverride: true,
      disableBrowserContextMenu: () async {
        calls += 1;
      },
    );

    expect(calls, 1);
  });

  test('skips browser context menu changes outside web', () async {
    var calls = 0;

    await initializeTextInputContextMenu(
      isWebOverride: false,
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
        disableBrowserContextMenu: () async {
          throw StateError('context menu unavailable');
        },
      );
    },
  );
}
