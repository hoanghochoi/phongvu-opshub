import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/app_update/data/app_update_service.dart';
import 'package:phongvu_opshub/features/app_update/domain/app_update_info.dart';
import 'package:phongvu_opshub/features/app_update/presentation/app_update_gate.dart';

void main() {
  testWidgets('keeps update prompt visible when app child changes', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_UpdateGateHarnessState>();

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          key: harnessKey,
          checkForUpdate: () async => _optionalUpdateResult,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Có bản cập nhật mới'), findsOneWidget);
    expect(find.text('Loading route'), findsOneWidget);

    harnessKey.currentState!.showHomeRoute();
    await tester.pump();

    expect(find.text('Home route'), findsOneWidget);
    expect(find.text('Có bản cập nhật mới'), findsOneWidget);
  });

  testWidgets('dismisses optional update only when user chooses later', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => _optionalUpdateResult,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Để sau'));
    await tester.pump();

    expect(find.text('Có bản cập nhật mới'), findsNothing);
    expect(find.text('Loading route'), findsOneWidget);
  });

  testWidgets('required update blocks later action and opens update URL', (
    tester,
  ) async {
    String? openedUrl;

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => _requiredUpdateResult,
          requiredUpdateOverride: true,
          openUpdateUrl: (url) async => openedUrl = url,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
    expect(find.text('Để sau'), findsNothing);

    await tester.tap(find.text('Cập nhật'));
    await tester.pump();

    expect(openedUrl, _requiredUpdateResult.updateInfo.updateUrl);
    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
  });
}

const _optionalUpdateInfo = AppUpdateInfo(
  platform: 'android',
  latestVersion: '2026.06.05.1',
  latestBuild: 200001,
  minSupportedBuild: 100000,
  updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
  releaseNotes: 'Bản cập nhật kiểm thử',
  forceUpdate: false,
);

const _requiredUpdateInfo = AppUpdateInfo(
  platform: 'windows',
  latestVersion: '2026.06.05.1',
  latestBuild: 200001,
  minSupportedBuild: 200000,
  updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.exe',
  releaseNotes: 'Bản cập nhật bắt buộc',
  forceUpdate: true,
);

const _optionalUpdateResult = AppUpdateCheckResult(
  currentVersion: '2026.06.01.1',
  currentBuild: 199999,
  updateInfo: _optionalUpdateInfo,
);

const _requiredUpdateResult = AppUpdateCheckResult(
  currentVersion: '2026.06.01.1',
  currentBuild: 199999,
  updateInfo: _requiredUpdateInfo,
);

class _UpdateGateHarness extends StatefulWidget {
  const _UpdateGateHarness({
    super.key,
    required this.checkForUpdate,
    this.openUpdateUrl,
    this.requiredUpdateOverride,
  });

  final AppUpdateChecker checkForUpdate;
  final AppUpdateUrlOpener? openUpdateUrl;
  final bool? requiredUpdateOverride;

  @override
  State<_UpdateGateHarness> createState() => _UpdateGateHarnessState();
}

class _UpdateGateHarnessState extends State<_UpdateGateHarness> {
  String _routeLabel = 'Loading route';

  void showHomeRoute() {
    setState(() => _routeLabel = 'Home route');
  }

  @override
  Widget build(BuildContext context) {
    return AppUpdateGate(
      checkForUpdate: widget.checkForUpdate,
      openUpdateUrl: widget.openUpdateUrl,
      requiredUpdateOverride: widget.requiredUpdateOverride,
      child: Scaffold(body: Center(child: Text(_routeLabel))),
    );
  }
}
