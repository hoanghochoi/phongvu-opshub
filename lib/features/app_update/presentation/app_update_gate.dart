import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../data/app_update_service.dart';

typedef AppUpdateChecker = Future<AppUpdateCheckResult?> Function();
typedef AppUpdateUrlOpener = Future<void> Function(String updateUrl);

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.checkForUpdate,
    this.openUpdateUrl,
    this.requiredUpdateOverride,
  });

  final Widget child;
  final AppUpdateChecker? checkForUpdate;
  final AppUpdateUrlOpener? openUpdateUrl;
  final bool? requiredUpdateOverride;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _checked = false;
  bool _openingUpdateUrl = false;
  AppUpdateCheckResult? _updateResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final checker =
          widget.checkForUpdate ??
          () => AppUpdateService(ApiClient()).checkForUpdate();
      final result = await checker();
      if (!mounted || result == null) return;
      setState(() => _updateResult = result);
      await AppLogger.instance.info(
        'AppUpdate',
        'Update prompt shown',
        context: _logContext(result),
      );
    } catch (error) {
      await AppLogger.instance.error(
        'AppUpdate',
        'Update check failed',
        error: error,
      );
      if (kDebugMode) {
        debugPrint('[AppUpdateGate] Update check skipped: $error');
      }
    }
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
    };
  }

  Future<void> _dismissUpdatePrompt() async {
    final result = _updateResult;
    if (result == null || _isRequired(result)) return;
    setState(() => _updateResult = null);
    await AppLogger.instance.info(
      'AppUpdate',
      'Optional update prompt dismissed',
      context: _logContext(result),
    );
  }

  Future<void> _openUpdateUrl(String updateUrl) async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return;
    setState(() => _openingUpdateUrl = true);
    await AppLogger.instance.info(
      'AppUpdate',
      'Opening update URL',
      context: {'urlHost': uri.host, 'path': uri.path},
    );
    try {
      final opener = widget.openUpdateUrl;
      if (opener != null) {
        await opener(updateUrl);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } finally {
      if (mounted) setState(() => _openingUpdateUrl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _updateResult;
    final isRequired = result != null && _isRequired(result);
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
              openingUpdateUrl: _openingUpdateUrl,
              onDismiss: _dismissUpdatePrompt,
              onUpdate: result.updateInfo.updateUrl.isEmpty
                  ? null
                  : () => _openUpdateUrl(result.updateInfo.updateUrl),
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
    required this.openingUpdateUrl,
    required this.onDismiss,
    required this.onUpdate,
  });

  final AppUpdateCheckResult result;
  final bool isRequired;
  final bool openingUpdateUrl;
  final Future<void> Function() onDismiss;
  final VoidCallback? onUpdate;

  @override
  Widget build(BuildContext context) {
    final updateInfo = result.updateInfo;
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AlertDialog(
                title: Text(
                  isRequired ? 'Cần cập nhật ứng dụng' : 'Có bản cập nhật mới',
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
                      if (updateInfo.releaseNotes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(updateInfo.releaseNotes),
                      ],
                    ],
                  ),
                ),
                actions: [
                  if (!isRequired)
                    TextButton(
                      onPressed: openingUpdateUrl ? null : onDismiss,
                      child: const Text('Để sau'),
                    ),
                  FilledButton.icon(
                    onPressed: openingUpdateUrl ? null : onUpdate,
                    icon: openingUpdateUrl
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: const Text('Cập nhật'),
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
