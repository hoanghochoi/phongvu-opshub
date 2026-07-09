import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phongvu_opshub/features/app_update/data/app_update_realtime_connection.dart';
import 'package:phongvu_opshub/features/app_update/data/app_update_service.dart';
import 'package:phongvu_opshub/features/app_update/data/app_self_update_service.dart';
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

  testWidgets('required update blocks later action and starts in-app update', (
    tester,
  ) async {
    AppUpdateCheckResult? installedResult;
    final progressEvents = <AppSelfUpdateProgress>[];

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => _requiredUpdateResult,
          requiredUpdateOverride: true,
          installUpdate: (result, onProgress) async {
            installedResult = result;
            final progress = const AppSelfUpdateProgress(
              stage: AppSelfUpdateStage.installing,
              message: 'Đang mở trình cài đặt...',
            );
            progressEvents.add(progress);
            onProgress(progress);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
    expect(find.text('Để sau'), findsNothing);
    expect(
      find.text(
        'Sau khi cài xong, OpsHub sẽ tự mở lại. Nếu Windows yêu cầu khởi động lại, hãy mở OpsHub sau khi máy sẵn sàng.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cập nhật'));
    await tester.pump();

    expect(installedResult, _requiredUpdateResult);
    expect(progressEvents, hasLength(1));
    expect(find.text('Đang mở trình cài đặt...'), findsOneWidget);
    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
  });

  testWidgets('web update reloads page instead of opening download URL', (
    tester,
  ) async {
    var reloadCount = 0;
    AppUpdateCheckResult? installedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => _webUpdateResult,
          installUpdate: (result, _) async => installedResult = result,
          reloadPage: () async => reloadCount += 1,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Có bản web mới'), findsOneWidget);
    expect(find.text('Tải lại'), findsOneWidget);
    expect(
      find.text(
        'Sau khi cập nhật xong, hãy mở lại ứng dụng để dùng phiên bản mới.',
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tap(find.text('Tải lại'));
    await tester.pump();

    expect(reloadCount, 1);
    expect(installedResult, isNull);
  });

  testWidgets('shows in-app update error without opening browser', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => _requiredUpdateResult,
          requiredUpdateOverride: true,
          installUpdate: (_, _) async {
            throw const AppSelfUpdateException('Không tải được gói cập nhật.');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Cập nhật'));
    await tester.pump();

    expect(find.text('Không tải được gói cập nhật.'), findsOneWidget);
    expect(find.text('Cần cập nhật ứng dụng'), findsOneWidget);
  });

  testWidgets('shows update prompt when realtime event arrives', (
    tester,
  ) async {
    final realtime = _FakeAppUpdateRealtimeConnection();
    var updateAvailable = false;
    Uri? connectedUri;

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async =>
              updateAvailable ? _optionalUpdateResult : null,
          realtimeEnabled: true,
          realtimeConnector: (uri) {
            connectedUri = uri;
            return realtime;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Có bản cập nhật mới'), findsNothing);
    expect(connectedUri?.path, '/ws/app-updates');
    expect(connectedUri?.query, isEmpty);

    updateAvailable = true;
    realtime.add(_appUpdateEvent(200001));
    await tester.pump();
    await tester.pump();

    expect(find.text('Có bản cập nhật mới'), findsOneWidget);
  });

  testWidgets(
    'realtime connection verifies metadata without waiting for event',
    (tester) async {
      final realtime = _FakeAppUpdateRealtimeConnection();
      var checks = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: _UpdateGateHarness(
            checkForUpdate: () async {
              checks += 1;
              return checks >= 2 ? _optionalUpdateResult : null;
            },
            realtimeEnabled: true,
            realtimeConnector: (_) => realtime,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(checks, greaterThanOrEqualTo(2));
      expect(find.text('Có bản cập nhật mới'), findsOneWidget);
    },
  );

  testWidgets('app resume verifies update metadata as missed-event fallback', (
    tester,
  ) async {
    var checks = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async {
            checks += 1;
            return null;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(checks, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(checks, 2);
  });

  testWidgets('dismissed build stays hidden until a newer build arrives', (
    tester,
  ) async {
    final realtime = _FakeAppUpdateRealtimeConnection();
    var result = _optionalUpdateResult;

    await tester.pumpWidget(
      MaterialApp(
        home: _UpdateGateHarness(
          checkForUpdate: () async => result,
          realtimeEnabled: true,
          realtimeConnector: (_) => realtime,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Để sau'));
    await tester.pump();

    realtime.add(_appUpdateEvent(200001));
    await tester.pump();
    await tester.pump();
    expect(find.text('Có bản cập nhật mới'), findsNothing);

    result = _optionalUpdateResultForBuild(200002);
    realtime.add(_appUpdateEvent(200002));
    await tester.pump();
    await tester.pump();

    expect(find.text('Có bản cập nhật mới'), findsOneWidget);
    expect(find.textContaining('+200002'), findsOneWidget);
  });
}

String _appUpdateEvent(int latestBuild) {
  return '{"type":"APP_UPDATE","payload":{"schemaVersion":1,'
      '"platforms":{"windows":{"latestBuild":$latestBuild}}}}';
}

AppUpdateCheckResult _optionalUpdateResultForBuild(int latestBuild) {
  return AppUpdateCheckResult(
    currentVersion: '2026.06.01.1',
    currentBuild: 199999,
    updateInfo: AppUpdateInfo(
      platform: 'windows',
      latestVersion: '2026.06.05.2',
      latestBuild: latestBuild,
      minSupportedBuild: 100000,
      updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.exe',
      packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.exe',
      packageSha256:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      packageSizeBytes: 20,
      packageType: 'windowsInstaller',
      installerArgs: ['/VERYSILENT', '/OPSHUBRELAUNCH=1'],
      releaseNotes: 'Bản cập nhật realtime',
      forceUpdate: false,
    ),
  );
}

const _optionalUpdateInfo = AppUpdateInfo(
  platform: 'android',
  latestVersion: '2026.06.05.1',
  latestBuild: 200001,
  minSupportedBuild: 100000,
  updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
  packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.apk',
  packageSha256:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  packageSizeBytes: 20,
  packageType: 'apk',
  installerArgs: [],
  releaseNotes: 'Bản cập nhật kiểm thử',
  forceUpdate: false,
);

const _requiredUpdateInfo = AppUpdateInfo(
  platform: 'windows',
  latestVersion: '2026.06.05.1',
  latestBuild: 200001,
  minSupportedBuild: 200000,
  updateUrl: 'https://opshub.hoanghochoi.com/downloads/app.exe',
  packageUrl: 'https://opshub.hoanghochoi.com/downloads/app.exe',
  packageSha256:
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  packageSizeBytes: 20,
  packageType: 'windowsInstaller',
  installerArgs: ['/VERYSILENT', '/OPSHUBRELAUNCH=1'],
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

const _webUpdateResult = AppUpdateCheckResult(
  currentVersion: '2026.06.01.1',
  currentBuild: 199999,
  updateInfo: AppUpdateInfo(
    platform: 'web',
    latestVersion: '2026.06.05.1',
    latestBuild: 200001,
    minSupportedBuild: 100000,
    updateUrl: '',
    packageUrl: '',
    packageSha256: '',
    packageSizeBytes: 0,
    packageType: 'web',
    installerArgs: [],
    releaseNotes: 'Bản web mới',
    forceUpdate: false,
  ),
);

class _UpdateGateHarness extends StatefulWidget {
  const _UpdateGateHarness({
    super.key,
    required this.checkForUpdate,
    this.installUpdate,
    this.reloadPage,
    this.requiredUpdateOverride,
    this.realtimeConnector,
    this.realtimeEnabled = false,
  });

  final AppUpdateChecker checkForUpdate;
  final AppUpdateInstaller? installUpdate;
  final AppUpdatePageReloader? reloadPage;
  final bool? requiredUpdateOverride;
  final AppUpdateRealtimeConnector? realtimeConnector;
  final bool realtimeEnabled;

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
      installUpdate: widget.installUpdate,
      reloadPage: widget.reloadPage,
      requiredUpdateOverride: widget.requiredUpdateOverride,
      realtimeConnector: widget.realtimeConnector,
      realtimeEnabled: widget.realtimeEnabled,
      child: Scaffold(body: Center(child: Text(_routeLabel))),
    );
  }
}

class _FakeAppUpdateRealtimeConnection implements AppUpdateRealtimeConnection {
  final StreamController<dynamic> _controller = StreamController<dynamic>();

  void add(dynamic event) => _controller.add(event);

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}
