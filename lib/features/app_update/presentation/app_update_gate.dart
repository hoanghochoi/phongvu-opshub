import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/app_buttons.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/platform/app_page_reloader.dart';
import '../data/app_update_realtime_connection.dart';
import '../data/app_update_service.dart';
import '../data/app_self_update_service.dart';

typedef AppUpdateChecker = Future<AppUpdateCheckResult?> Function();
typedef AppUpdateInstaller =
    Future<void> Function(
      AppUpdateCheckResult result,
      ValueChanged<AppSelfUpdateProgress> onProgress,
    );
typedef AppUpdatePageReloader = Future<void> Function();

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.checkForUpdate,
    this.installUpdate,
    this.reloadPage,
    this.requiredUpdateOverride,
    this.realtimeConnector,
    this.realtimeEnabled = true,
  });

  final Widget child;
  final AppUpdateChecker? checkForUpdate;
  final AppUpdateInstaller? installUpdate;
  final AppUpdatePageReloader? reloadPage;
  final bool? requiredUpdateOverride;
  final AppUpdateRealtimeConnector? realtimeConnector;
  final bool realtimeEnabled;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  static const _realtimeReadyTimeout = Duration(seconds: 10);
  static const _reconnectDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];
  static const _metadataRetryDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  bool _checked = false;
  bool _runningUpdateAction = false;
  bool _checkingForUpdate = false;
  String? _queuedCheckReason;
  int? _dismissedLatestBuild;
  String? _updateActionError;
  AppSelfUpdateProgress? _selfUpdateProgress;
  AppUpdateCheckResult? _updateResult;
  AppUpdateRealtimeConnection? _realtimeConnection;
  StreamSubscription<dynamic>? _realtimeSubscription;
  Timer? _reconnectTimer;
  Timer? _realtimeReadyTimer;
  Timer? _metadataRetryTimer;
  int _reconnectAttempt = 0;
  int _metadataRetryAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_checkForUpdate(reason: 'startup'));
      _connectRealtime();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      AppLogger.instance.info(
        'AppUpdateRealtime',
        'App resumed; verifying update metadata',
        context: {'realtimeConnected': _realtimeConnection != null},
      ),
    );
    unawaited(_checkForUpdate(reason: 'app_resumed'));
    if (_realtimeConnection == null) _connectRealtime();
  }

  Future<void> _checkForUpdate({required String reason}) async {
    if (_checkingForUpdate) {
      _queuedCheckReason = reason;
      return;
    }
    _checkingForUpdate = true;
    try {
      final checker =
          widget.checkForUpdate ??
          () => AppUpdateService(ApiClient()).checkForUpdate();
      final result = await checker();
      _resetMetadataRetry();
      if (!mounted || result == null) return;
      final required = _isRequired(result);
      final latestBuild = result.updateInfo.latestBuild;
      if (!required &&
          _dismissedLatestBuild != null &&
          latestBuild <= _dismissedLatestBuild!) {
        await AppLogger.instance.info(
          'AppUpdate',
          'Update prompt suppressed after dismissal',
          context: {..._logContext(result), 'reason': reason},
        );
        return;
      }

      final previous = _updateResult;
      final promptChanged =
          previous == null ||
          previous.updateInfo.latestBuild != latestBuild ||
          _isRequired(previous) != required;
      if (!promptChanged) return;
      setState(() {
        _updateResult = result;
        _updateActionError = null;
        _selfUpdateProgress = null;
      });
      await AppLogger.instance.info(
        'AppUpdate',
        'Update prompt shown',
        context: {..._logContext(result), 'reason': reason},
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AppUpdate',
        'Update check failed',
        error: error,
        stackTrace: stackTrace,
        context: {'reason': reason},
      );
      if (kDebugMode) {
        debugPrint('[AppUpdateGate] Update check skipped: $error');
      }
      _scheduleMetadataRetry(reason);
    } finally {
      _checkingForUpdate = false;
      final queuedReason = _queuedCheckReason;
      _queuedCheckReason = null;
      if (mounted && queuedReason != null) {
        unawaited(_checkForUpdate(reason: queuedReason));
      }
    }
  }

  void _connectRealtime() {
    if (!widget.realtimeEnabled || _realtimeConnection != null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final uri = Uri.parse(ApiConstants.appUpdateRealtimeWsUrl);
    try {
      final connector =
          widget.realtimeConnector ??
          WebSocketAppUpdateRealtimeConnection.connect;
      final connection = connector(uri);
      _realtimeConnection = connection;
      _realtimeSubscription = connection.stream.listen(
        _handleRealtimeMessage,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            AppLogger.instance.error(
              'AppUpdateRealtime',
              'App update realtime stream failed',
              error: error,
              stackTrace: stackTrace,
            ),
          );
          _disconnectRealtime(
            'stream_error',
            reconnect: true,
            expectedConnection: connection,
          );
        },
        onDone: () {
          _disconnectRealtime(
            'server_closed',
            reconnect: true,
            expectedConnection: connection,
          );
        },
      );
      unawaited(_awaitRealtimeReady(connection, uri));
    } catch (error, stackTrace) {
      unawaited(
        AppLogger.instance.error(
          'AppUpdateRealtime',
          'App update realtime connect failed',
          error: error,
          stackTrace: stackTrace,
          context: {'urlHost': uri.host, 'path': uri.path},
        ),
      );
      _disconnectRealtime('connect_failed', reconnect: true);
    }
  }

  Future<void> _awaitRealtimeReady(
    AppUpdateRealtimeConnection connection,
    Uri uri,
  ) async {
    final timeoutCompleter = Completer<void>();
    final timeoutTimer = Timer(_realtimeReadyTimeout, () {
      timeoutCompleter.completeError(
        TimeoutException('App update realtime handshake timed out'),
      );
    });
    _realtimeReadyTimer?.cancel();
    _realtimeReadyTimer = timeoutTimer;
    try {
      await Future.any([connection.ready, timeoutCompleter.future]);
      if (!mounted || !identical(connection, _realtimeConnection)) return;
      _reconnectAttempt = 0;
      await AppLogger.instance.info(
        'AppUpdateRealtime',
        'App update realtime connected',
        context: {'urlHost': uri.host, 'path': uri.path},
      );
      await _checkForUpdate(reason: 'realtime_connected');
    } catch (error, stackTrace) {
      if (!identical(connection, _realtimeConnection)) return;
      await AppLogger.instance.error(
        'AppUpdateRealtime',
        'App update realtime handshake failed',
        error: error,
        stackTrace: stackTrace,
        context: {'urlHost': uri.host, 'path': uri.path},
      );
      _disconnectRealtime(
        'handshake_failed',
        reconnect: true,
        expectedConnection: connection,
      );
    } finally {
      timeoutTimer.cancel();
      if (identical(timeoutTimer, _realtimeReadyTimer)) {
        _realtimeReadyTimer = null;
      }
    }
  }

  Future<void> _handleRealtimeMessage(dynamic message) async {
    try {
      final decoded = jsonDecode(message.toString());
      if (decoded is! Map<String, dynamic> || decoded['type'] != 'APP_UPDATE') {
        return;
      }
      final rawPayload = decoded['payload'];
      final payload = rawPayload is Map<String, dynamic>
          ? rawPayload
          : rawPayload is String
          ? jsonDecode(rawPayload) as Map<String, dynamic>
          : const <String, dynamic>{};
      await AppLogger.instance.info(
        'AppUpdateRealtime',
        'App update realtime event received',
        context: {
          'schemaVersion': payload['schemaVersion'],
          'androidBuild': _eventBuild(payload, 'android'),
          'windowsBuild': _eventBuild(payload, 'windows'),
        },
      );
      _metadataRetryTimer?.cancel();
      _metadataRetryTimer = null;
      _metadataRetryAttempt = 0;
      await _checkForUpdate(reason: 'realtime_event');
    } catch (error) {
      await AppLogger.instance.warn(
        'AppUpdateRealtime',
        'App update realtime event ignored',
        context: {'errorType': error.runtimeType.toString()},
      );
    }
  }

  Object? _eventBuild(Map<String, dynamic> payload, String platform) {
    final platforms = payload['platforms'];
    if (platforms is! Map) return null;
    final metadata = platforms[platform];
    return metadata is Map ? metadata['latestBuild'] : null;
  }

  void _disconnectRealtime(
    String reason, {
    required bool reconnect,
    AppUpdateRealtimeConnection? expectedConnection,
  }) {
    if (expectedConnection != null &&
        !identical(expectedConnection, _realtimeConnection)) {
      return;
    }
    final connection = _realtimeConnection;
    final subscription = _realtimeSubscription;
    _realtimeReadyTimer?.cancel();
    _realtimeReadyTimer = null;
    _realtimeConnection = null;
    _realtimeSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (connection != null) unawaited(connection.close());
    if (connection != null || subscription != null) {
      unawaited(
        AppLogger.instance.info(
          'AppUpdateRealtime',
          'App update realtime disconnected',
          context: {'reason': reason, 'willReconnect': reconnect},
        ),
      );
    }
    if (reconnect && mounted) _scheduleRealtimeReconnect();
  }

  void _scheduleRealtimeReconnect() {
    if (!widget.realtimeEnabled || _reconnectTimer?.isActive == true) return;
    final delayIndex = _reconnectAttempt < _reconnectDelays.length
        ? _reconnectAttempt
        : _reconnectDelays.length - 1;
    final delay = _reconnectDelays[delayIndex];
    _reconnectAttempt += 1;
    unawaited(
      AppLogger.instance.info(
        'AppUpdateRealtime',
        'App update realtime reconnect scheduled',
        context: {
          'attempt': _reconnectAttempt,
          'delayMs': delay.inMilliseconds,
        },
      ),
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (mounted) _connectRealtime();
    });
  }

  void _scheduleMetadataRetry(String failedReason) {
    if (!mounted || _metadataRetryTimer?.isActive == true) return;
    if (_metadataRetryAttempt >= _metadataRetryDelays.length) {
      unawaited(
        AppLogger.instance.warn(
          'AppUpdate',
          'Update metadata retry exhausted',
          context: {
            'failedReason': failedReason,
            'attempts': _metadataRetryAttempt,
          },
        ),
      );
      return;
    }
    final delay = _metadataRetryDelays[_metadataRetryAttempt];
    _metadataRetryAttempt += 1;
    unawaited(
      AppLogger.instance.info(
        'AppUpdate',
        'Update metadata retry scheduled',
        context: {
          'failedReason': failedReason,
          'attempt': _metadataRetryAttempt,
          'delayMs': delay.inMilliseconds,
        },
      ),
    );
    _metadataRetryTimer = Timer(delay, () {
      _metadataRetryTimer = null;
      if (mounted) {
        unawaited(_checkForUpdate(reason: 'metadata_retry'));
      }
    });
  }

  void _resetMetadataRetry() {
    _metadataRetryTimer?.cancel();
    _metadataRetryTimer = null;
    _metadataRetryAttempt = 0;
  }

  bool _isRequired(AppUpdateCheckResult result) {
    return widget.requiredUpdateOverride ?? (!kDebugMode && result.isRequired);
  }

  Map<String, Object?> _logContext(AppUpdateCheckResult result) {
    return {
      'platform': result.updateInfo.platform,
      'currentBuild': result.currentBuild,
      'latestBuild': result.updateInfo.latestBuild,
      'required': _isRequired(result),
      'hasUpdateUrl': result.updateInfo.updateUrl.isNotEmpty,
      'hasSelfUpdatePackage': result.updateInfo.hasSelfUpdatePackage,
      'reloadsPage': _shouldReloadForUpdate(result),
    };
  }

  Future<void> _dismissUpdatePrompt() async {
    final result = _updateResult;
    if (result == null || _isRequired(result)) return;
    final latestBuild = result.updateInfo.latestBuild;
    if (_dismissedLatestBuild == null || latestBuild > _dismissedLatestBuild!) {
      _dismissedLatestBuild = latestBuild;
    }
    setState(() {
      _updateResult = null;
      _updateActionError = null;
      _selfUpdateProgress = null;
    });
    await AppLogger.instance.info(
      'AppUpdate',
      'Optional update prompt dismissed',
      context: _logContext(result),
    );
  }

  bool _shouldReloadForUpdate(AppUpdateCheckResult result) {
    return kIsWeb || result.updateInfo.platform == 'web';
  }

  Future<void> _reloadForUpdate(AppUpdateCheckResult result) async {
    setState(() {
      _runningUpdateAction = true;
      _updateActionError = null;
      _selfUpdateProgress = null;
    });
    await AppLogger.instance.info(
      'AppUpdate',
      'Reloading web app for update',
      context: _logContext(result),
    );
    try {
      final reloader = widget.reloadPage ?? reloadCurrentPage;
      await reloader();
    } finally {
      if (mounted) setState(() => _runningUpdateAction = false);
    }
  }

  Future<void> _installUpdate(AppUpdateCheckResult result) async {
    setState(() {
      _runningUpdateAction = true;
      _updateActionError = null;
      _selfUpdateProgress = null;
    });
    await AppLogger.instance.info(
      'AppUpdate',
      'Starting in-app update',
      context: _logContext(result),
    );
    try {
      final installer =
          widget.installUpdate ??
          (updateResult, onProgress) => AppSelfUpdateService()
              .downloadAndInstall(updateResult, onProgress: onProgress);
      await installer(result, (progress) {
        if (!mounted) return;
        setState(() => _selfUpdateProgress = progress);
      });
    } on AppSelfUpdateException catch (error) {
      await AppLogger.instance.warn(
        'AppUpdate',
        'In-app update stopped',
        context: {..._logContext(result), 'reason': error.code ?? 'error'},
      );
      if (mounted) {
        setState(() => _updateActionError = error.message);
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'AppUpdate',
        'In-app update failed',
        error: error,
        stackTrace: stackTrace,
        context: _logContext(result),
      );
      if (mounted) {
        setState(
          () => _updateActionError =
              'Chưa cập nhật được. Vui lòng thử lại sau ít phút.',
        );
      }
    } finally {
      if (mounted) setState(() => _runningUpdateAction = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _realtimeReadyTimer?.cancel();
    _realtimeReadyTimer = null;
    _metadataRetryTimer?.cancel();
    _metadataRetryTimer = null;
    _disconnectRealtime('gate_disposed', reconnect: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _updateResult;
    final isRequired = result != null && _isRequired(result);
    final shouldReload = result != null && _shouldReloadForUpdate(result);
    return PopScope(
      canPop: result == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || result == null || isRequired) return;
        await _dismissUpdatePrompt();
      },
      child: Stack(
        children: [
          widget.child,
          if (result != null)
            _UpdatePromptOverlay(
              result: result,
              isRequired: isRequired,
              runningUpdateAction: _runningUpdateAction,
              shouldReload: shouldReload,
              progress: _selfUpdateProgress,
              errorMessage: _updateActionError,
              onDismiss: _dismissUpdatePrompt,
              onUpdate: shouldReload
                  ? () => _reloadForUpdate(result)
                  : () => _installUpdate(result),
            ),
        ],
      ),
    );
  }
}

class _UpdatePromptOverlay extends StatelessWidget {
  const _UpdatePromptOverlay({
    required this.result,
    required this.isRequired,
    required this.runningUpdateAction,
    required this.shouldReload,
    required this.progress,
    required this.errorMessage,
    required this.onDismiss,
    required this.onUpdate,
  });

  final AppUpdateCheckResult result;
  final bool isRequired;
  final bool runningUpdateAction;
  final bool shouldReload;
  final AppSelfUpdateProgress? progress;
  final String? errorMessage;
  final Future<void> Function() onDismiss;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final updateInfo = result.updateInfo;
    return Positioned.fill(
      child: Material(
        color: AppColors.shadow.withValues(alpha: 0.54),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AlertDialog(
                title: Text(
                  shouldReload
                      ? isRequired
                            ? 'Cần tải lại ứng dụng'
                            : 'Có bản web mới'
                      : isRequired
                      ? 'Cần cập nhật ứng dụng'
                      : 'Có bản cập nhật mới',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Phiên bản hiện tại: ${result.currentVersion}+${result.currentBuild}',
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Phiên bản mới: ${updateInfo.latestVersion}+${updateInfo.latestBuild}',
                      ),
                      if (!shouldReload) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Sau khi cập nhật xong, hãy mở lại ứng dụng để dùng phiên bản mới.',
                        ),
                      ],
                      if (updateInfo.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(updateInfo.releaseNotes),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 14),
                        LinearProgressIndicator(value: progress!.fraction),
                        const SizedBox(height: 8),
                        Text(progress!.displayMessage),
                      ],
                      if (errorMessage != null &&
                          errorMessage!.trim().isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          errorMessage!,
                          style: AppTextStyles.labelM.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  if (!isRequired)
                    AppDialogCancelButton(
                      onPressed: runningUpdateAction ? null : onDismiss,
                      label: 'Để sau',
                    ),
                  AppDialogConfirmButton(
                    onPressed: runningUpdateAction ? null : onUpdate,
                    icon: shouldReload
                        ? Icons.refresh_rounded
                        : Icons.system_update_alt_rounded,
                    label: shouldReload ? 'Tải lại' : 'Cập nhật',
                    isLoading: runningUpdateAction,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
