import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../data/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await AppUpdateService(ApiClient()).checkForUpdate();
      if (!mounted || result == null) return;
      await _showUpdateDialog(result);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[AppUpdateGate] Update check skipped: $error');
      }
    }
  }

  Future<void> _showUpdateDialog(AppUpdateCheckResult result) async {
    final updateInfo = result.updateInfo;
    final isRequired = result.isRequired;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isRequired,
      builder: (dialogContext) {
        return PopScope(
          canPop: !isRequired,
          child: AlertDialog(
            title: Text(
              isRequired ? 'Cần cập nhật ứng dụng' : 'Có bản cập nhật mới',
            ),
            content: Column(
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
            actions: [
              if (!isRequired)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Để sau'),
                ),
              FilledButton(
                onPressed: updateInfo.updateUrl.isEmpty
                    ? null
                    : () => _openUpdateUrl(updateInfo.updateUrl),
                child: const Text('Cập nhật'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUpdateUrl(String updateUrl) async {
    final uri = Uri.tryParse(updateUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
