import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/app_toast.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/platform/app_platform_capabilities.dart';
import '../../data/api_connection_repository.dart';
import '../../domain/api_connection.dart';

class ApiConnectionAdminScreen extends StatefulWidget {
  const ApiConnectionAdminScreen({
    super.key,
    this.repository,
    this.platformSupported,
  });

  final ApiConnectionRepository? repository;
  final bool? platformSupported;

  @override
  State<ApiConnectionAdminScreen> createState() =>
      _ApiConnectionAdminScreenState();
}

class _ApiConnectionAdminScreenState extends State<ApiConnectionAdminScreen> {
  late final ApiConnectionRepository _repository =
      widget.repository ?? ApiConnectionRepository(ApiClient());
  ApiConnectionSnapshot? _snapshot;
  String? _error;
  bool _loading = true;
  bool _mutating = false;

  bool get _supported =>
      widget.platformSupported ??
      AppPlatformCapabilities.isApiConnectionAdminSupported();

  @override
  void initState() {
    super.initState();
    if (_supported) {
      unawaited(_load());
    } else {
      _loading = false;
      unawaited(
        AppLogger.instance.warn(
          'ApiConnectionAdmin',
          'API connection administration platform unsupported',
        ),
      );
    }
  }

  Future<void> _load() async {
    final startedAt = DateTime.now();
    setState(() {
      _loading = _snapshot == null;
      _error = null;
    });
    await AppLogger.instance.info(
      'ApiConnectionAdmin',
      'API connection snapshot load started',
    );
    try {
      final snapshot = await _repository.fetchSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
      await AppLogger.instance.info(
        'ApiConnectionAdmin',
        'API connection snapshot load succeeded',
        context: {
          'clientCount': snapshot.clients.length,
          'keyCount': snapshot.keys.length,
          'ingressEffective': snapshot.controls.ingressEffective,
          'projectionEffective': snapshot.controls.projectionEffective,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
      await AppLogger.instance.warn(
        'ApiConnectionAdmin',
        'API connection snapshot load failed',
        context: {
          'statusCode': error.statusCode,
          'hasCachedSnapshot': _snapshot != null,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Chưa tải được cấu hình kết nối. Vui lòng thử lại.';
      });
      await AppLogger.instance.error(
        'ApiConnectionAdmin',
        'API connection snapshot load failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {
          'hasCachedSnapshot': _snapshot != null,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
        upload: true,
      );
    }
  }

  Future<void> _runMutation(
    String action,
    Future<void> Function() mutation, {
    String? successMessage,
  }) async {
    if (_mutating) return;
    final startedAt = DateTime.now();
    setState(() => _mutating = true);
    await AppLogger.instance.info(
      'ApiConnectionAdmin',
      'API connection action started',
      context: {'action': action},
    );
    try {
      await mutation();
      if (!mounted) return;
      if (successMessage != null) {
        AppToast.show(context, SnackBar(content: Text(successMessage)));
      }
      await AppLogger.instance.info(
        'ApiConnectionAdmin',
        'API connection action succeeded',
        context: {
          'action': action,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      AppToast.show(context, SnackBar(content: Text(error.message)));
      await AppLogger.instance.warn(
        'ApiConnectionAdmin',
        'API connection action failed',
        context: {
          'action': action,
          'statusCode': error.statusCode,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      AppToast.show(
        context,
        const SnackBar(content: Text('Chưa thực hiện được. Vui lòng thử lại.')),
      );
      await AppLogger.instance.error(
        'ApiConnectionAdmin',
        'API connection action failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
        context: {
          'action': action,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
        upload: true,
      );
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _createClient() async {
    final name = await _askName(
      title: 'Tạo client BIDV',
      hint: 'Ví dụ: BIDV UAT tháng 07/2026',
    );
    if (name == null || !mounted) return;
    await _runMutation('create_client', () async {
      final created = await _repository.createClient(name);
      if (!mounted) return;
      await _showSecret(created);
      await _load();
    });
  }

  Future<void> _rotateClient(ApiClientCredential client) async {
    if (!await _confirm(
      title: 'Xoay vòng client?',
      message:
          'Client cũ tiếp tục hoạt động trong thời gian chuyển đổi. Secret mới chỉ hiện một lần.',
      confirmLabel: 'Tạo client mới',
    )) {
      return;
    }
    await _runMutation('rotate_client', () async {
      final created = await _repository.rotateClient(client.id);
      if (!mounted) return;
      await _showSecret(created);
      await _load();
    });
  }

  Future<void> _revokeClient(ApiClientCredential client) async {
    if (!await _confirm(
      title: 'Thu hồi client?',
      message:
          'Token đã cấp cho client này sẽ mất hiệu lực ngay. Hãy chắc chắn BIDV đã chuyển sang client mới.',
      confirmLabel: 'Thu hồi',
      destructive: true,
    )) {
      return;
    }
    await _runMutation('revoke_client', () async {
      await _repository.revokeClient(client.id);
      await _load();
    }, successMessage: 'Đã thu hồi client.');
  }

  Future<void> _generateKey() async {
    final name = await _askName(
      title: 'Tạo khóa OpenPGP',
      hint: 'Ví dụ: BIDV UAT 2026',
    );
    if (name == null) return;
    await _runMutation(
      'generate_pgp_key',
      () async {
        await _repository.generateKey(name);
        await _load();
      },
      successMessage: 'Đã tạo khóa. Hãy xuất khóa công khai để gửi BIDV.',
    );
  }

  Future<void> _rotateKey(ApiPgpKey key) async {
    if (!await _confirm(
      title: 'Xoay vòng khóa OpenPGP?',
      message:
          'Khóa cũ được giữ trong thời gian chuyển đổi. BIDV cần xác nhận fingerprint khóa mới trước khi sử dụng.',
      confirmLabel: 'Tạo khóa mới',
    )) {
      return;
    }
    await _runMutation('rotate_pgp_key', () async {
      await _repository.rotateKey(key.id);
      await _load();
    }, successMessage: 'Đã tạo khóa thay thế.');
  }

  Future<void> _revokeKey(ApiPgpKey key) async {
    if (!await _confirm(
      title: 'Thu hồi khóa OpenPGP?',
      message:
          'Dữ liệu BIDV mã hóa bằng khóa này sẽ không còn được tiếp nhận. Hãy xác nhận BIDV đã dùng khóa mới.',
      confirmLabel: 'Thu hồi',
      destructive: true,
    )) {
      return;
    }
    await _runMutation('revoke_pgp_key', () async {
      await _repository.revokeKey(key.id);
      await _load();
    }, successMessage: 'Đã thu hồi khóa.');
  }

  Future<void> _exportKey(ApiPgpKey key) async {
    await _runMutation('export_public_key', () async {
      final exported = await _repository.exportPublicKey(key.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Khóa công khai BIDV'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tên file đề xuất: ${exported.fileName}'),
                const SizedBox(height: 8),
                SelectableText('Fingerprint: ${exported.fingerprint}'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: SingleChildScrollView(
                    child: SelectableText(exported.publicKeyArmor),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              label: 'Đóng',
            ),
            AppDialogConfirmButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: exported.publicKeyArmor),
                );
                if (!dialogContext.mounted) return;
                AppToast.show(
                  dialogContext,
                  const SnackBar(content: Text('Đã sao chép khóa công khai.')),
                );
              },
              icon: Icons.copy_rounded,
              label: 'Sao chép khóa',
            ),
          ],
        ),
      );
    });
  }

  Future<void> _showSecret(CreatedApiClientCredential created) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lưu thông tin kết nối ngay'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Client secret chỉ hiển thị lần này. Nếu đóng mà chưa lưu, hãy xoay vòng client để tạo secret mới.',
              ),
              const SizedBox(height: 16),
              const Text('Client ID'),
              SelectableText(created.client.clientId),
              const SizedBox(height: 12),
              const Text('Client secret'),
              SelectableText(created.clientSecret),
            ],
          ),
        ),
        actions: [
          AppDialogSecondaryButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: created.client.clientId),
              );
            },
            icon: Icons.copy_rounded,
            label: 'Sao chép Client ID',
          ),
          AppDialogSecondaryButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: created.clientSecret),
              );
            },
            icon: Icons.key_rounded,
            label: 'Sao chép secret',
          ),
          AppDialogConfirmButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            label: 'Tôi đã lưu an toàn',
          ),
        ],
      ),
    );
  }

  Future<void> _updateControls({
    required bool ingressEnabled,
    required bool projectionEnabled,
  }) async {
    final enabling = ingressEnabled || projectionEnabled;
    if (!await _confirm(
      title: enabling ? 'Xác nhận thay đổi kết nối' : 'Tạm dừng kết nối?',
      message: projectionEnabled
          ? 'Đối soát tự động có thể tạo giao dịch Tiền vào và thông báo loa. Chỉ bật sau khi đã đối soát UAT.'
          : ingressEnabled
          ? 'Hệ thống chỉ tiếp nhận và lưu dữ liệu; chưa tạo giao dịch Tiền vào.'
          : 'BIDV sẽ nhận phản hồi lỗi và thực hiện retry theo hợp đồng.',
      confirmLabel: 'Xác nhận',
      destructive: !ingressEnabled,
    )) {
      return;
    }
    await _runMutation('update_controls', () async {
      final snapshot = await _repository.updateControls(
        ingressEnabled: ingressEnabled,
        projectionEnabled: projectionEnabled,
      );
      if (mounted) setState(() => _snapshot = snapshot);
    }, successMessage: 'Đã cập nhật trạng thái kết nối.');
  }

  Future<String?> _askName({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: AppTextInput(
          controller: controller,
          label: 'Tên gợi nhớ',
          hintText: hint,
          autofocus: true,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          onSubmitted: (value) {
            if (value.trim().length >= 3) {
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          AppDialogCancelButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppDialogConfirmButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 3) Navigator.of(dialogContext).pop(value);
            },
            label: 'Tạo',
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              AppDialogCancelButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              AppDialogConfirmButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                label: confirmLabel,
                backgroundColor: destructive ? AppColors.error : null,
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return const AppResponsiveContent(
        child: _ApiConnectionUnsupportedState(),
      );
    }
    if (_loading && _snapshot == null) {
      return const AppResponsiveContent(
        child: AppStatePanel.loading(
          title: 'Đang tải kết nối API',
          message: 'Hệ thống đang đọc trạng thái client và khóa BIDV.',
        ),
      );
    }
    if (_snapshot == null) {
      return AppResponsiveContent(
        child: AppStatePanel.error(
          title: 'Chưa tải được kết nối API',
          message: _error ?? 'Vui lòng thử lại.',
          actionLabel: 'Thử lại',
          actionIcon: Icons.refresh_rounded,
          onAction: _load,
        ),
      );
    }
    final snapshot = _snapshot!;
    return AppResponsiveScrollView(
      padding: _apiConnectionPagePadding(context),
      onRefresh: _load,
      refreshLogSource: 'ApiConnectionAdmin',
      child: Column(
        key: const Key('api-connection-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snapshot.clients.isEmpty)
            _HeaderCard(
              snapshot: snapshot,
              disabled: _mutating,
              onCreateClient: _mutating ? null : _createClient,
            )
          else
            ...snapshot.clients.map(
              (client) => Padding(
                padding: const EdgeInsets.only(bottom: AppLayoutTokens.cardGap),
                child: _ClientCard(
                  client: client,
                  disabled: _mutating,
                  onCreate: _mutating ? null : _createClient,
                  onRotate: () => _rotateClient(client),
                  onRevoke: () => _revokeClient(client),
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppLayoutTokens.cardGap),
            AppStatePanel.error(
              title: 'Dữ liệu đang hiển thị có thể chưa mới nhất',
              message: _error!,
              actionLabel: 'Tải lại',
              actionIcon: Icons.refresh_rounded,
              onAction: _load,
            ),
          ],
          const SizedBox(height: AppLayoutTokens.sectionGap),
          _ControlCard(
            controls: snapshot.controls,
            disabled: _mutating,
            onChange: _updateControls,
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          if (snapshot.keys.isEmpty)
            _KeyManagementCard(
              disabled: _mutating,
              onExport: null,
              onCreate: _mutating ? null : _generateKey,
            )
          else
            ...snapshot.keys.map(
              (key) => Padding(
                padding: const EdgeInsets.only(bottom: AppLayoutTokens.cardGap),
                child: _KeyCard(
                  keyRecord: key,
                  disabled: _mutating,
                  onCreate: _mutating ? null : _generateKey,
                  onExport: () => _exportKey(key),
                  onRotate: () => _rotateKey(key),
                  onRevoke: () => _revokeKey(key),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

EdgeInsets _apiConnectionPagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  // The approved API Connections nodes use 24 px inside the wide desktop
  // shell and 16 px inside compact/tablet route viewports. Keep this local
  // geometry explicit until the medium supported-web state receives its own
  // approved Figma node.
  final horizontal = width >= AppLayoutTokens.desktopBreakpoint ? 24.0 : 16.0;
  final vertical = width >= AppLayoutTokens.compactBreakpoint ? 24.0 : 16.0;
  return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
}

/// Figma authority: Android Mobile `1729:121826` and Android Tablet
/// `1729:134628`. The platform guard is business behavior; this widget only
/// supplies the approved unsupported visual path and never invents a
/// supported mobile/tablet API-connection state.
class _ApiConnectionUnsupportedState extends StatelessWidget {
  const _ApiConnectionUnsupportedState();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('api-connection-unsupported-card'),
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 236,
        child: const AppStatePanel(
          icon: Icons.devices_other_rounded,
          title: 'Thiết bị chưa hỗ trợ quản lý kết nối',
          message: 'Vui lòng dùng OpsHub trên Windows hoặc Web để tiếp tục.',
          compact: true,
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.snapshot,
    required this.disabled,
    required this.onCreateClient,
  });

  final ApiConnectionSnapshot snapshot;
  final bool disabled;
  final VoidCallback? onCreateClient;

  @override
  Widget build(BuildContext context) {
    final environment = snapshot.environment.toLowerCase() == 'production'
        ? 'Sản xuất'
        : snapshot.environment;
    final compact =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    return AppSurfaceCard(
      key: const Key('api-connection-header-card'),
      radius: AppRadius.lg,
      child: SizedBox(
        height: compact ? 152 : 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ApiConnectionHeader(
              identity: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kết nối ${snapshot.bankCode}',
                    style: AppTextStyles.pageTitle.copyWith(
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Môi trường: $environment${snapshot.publicBaseUrl == null ? '' : ' · Endpoint đã cấu hình'}',
                    style: AppTextStyles.bodyS.copyWith(
                      height: 18 / 13,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
              actions: [
                _ApiActionButton.primary(
                  width: 112,
                  label: 'Tạo client',
                  onPressed: onCreateClient,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ApiConnectionStatusPanel(
              text: snapshot.controls.ingressEffective
                  ? 'BIDV sẵn sàng tiếp nhận dữ liệu'
                  : 'BIDV sẵn sàng tiếp nhận dữ liệu',
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({
    required this.controls,
    required this.disabled,
    required this.onChange,
  });

  final ApiConnectionControls controls;
  final bool disabled;
  final Future<void> Function({
    required bool ingressEnabled,
    required bool projectionEnabled,
  })
  onChange;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('api-connection-controls-card'),
      radius: AppRadius.lg,
      child: SizedBox(
        height: 178,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trạng thái vận hành',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.pageTitle.copyWith(
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Đối soát chỉ hoạt động sau khi tiếp nhận dữ liệu BIDV được bật.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyS.copyWith(
                height: 18 / 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 12),
            _ApiConnectionControlRow(
              label: 'Tiếp nhận dữ liệu BIDV',
              support: 'Nhận giao dịch BIDV mới vào OpsHub',
              value: controls.ingressRequested,
              enabled: !disabled,
              onChanged: (value) => onChange(
                ingressEnabled: value,
                projectionEnabled: value ? controls.projectionRequested : false,
              ),
            ),
            const SizedBox(height: 12),
            _ApiConnectionControlRow(
              label: 'Đối soát sang Tiền vào',
              support: 'Đưa giao dịch hợp lệ vào khu vực Tiền vào',
              value: controls.projectionRequested,
              enabled: !disabled && controls.ingressRequested,
              onChanged: (value) =>
                  onChange(ingressEnabled: true, projectionEnabled: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.disabled,
    required this.onCreate,
    required this.onRotate,
    required this.onRevoke,
  });

  final ApiClientCredential client;
  final bool disabled;
  final VoidCallback? onCreate;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: ValueKey('api-connection-client-card-${client.id}'),
      radius: AppRadius.lg,
      child: _LifecycleCardBody(
        minContentHeight: 228,
        compactContentHeight: 244,
        identity: _LifecycleIdentity(
          title: client.status == 'ACTIVE'
              ? 'OAuth client hoạt động'
              : 'OAuth client ${_statusLabel(client.status).toLowerCase()}',
          subtitle: '${client.displayName} · Client ID đã cấp',
        ),
        actions: [
          _ApiActionButton.primary(
            width: 112,
            label: 'Tạo client',
            onPressed: onCreate,
          ),
          _ApiActionButton.secondary(
            width: 108,
            label: 'Xoay vòng',
            onPressed: disabled || !client.canRotate ? null : onRotate,
          ),
          _ApiActionButton.secondary(
            width: 96,
            label: 'Thu hồi',
            onPressed: disabled || !client.canRevoke ? null : onRevoke,
          ),
        ],
        details: _ApiDetailPanel(
          title: '${client.displayName} · Client ID đã cấp',
          values: 'Client ID: ${client.clientId} · Scope: ${client.scope}',
          helper: client.overlapExpiresAt == null
              ? null
              : 'Hết thời gian chuyển đổi: ${_dateTime(client.overlapExpiresAt)}',
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.keyRecord,
    required this.disabled,
    required this.onCreate,
    required this.onExport,
    required this.onRotate,
    required this.onRevoke,
  });

  final ApiPgpKey keyRecord;
  final bool disabled;
  final VoidCallback? onCreate;
  final VoidCallback onExport;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: ValueKey('api-connection-key-card-${keyRecord.id}'),
      radius: AppRadius.lg,
      child: _LifecycleCardBody(
        minContentHeight: 260,
        compactContentHeight: 288,
        identity: _LifecycleIdentity(
          title: keyRecord.status == 'ACTIVE'
              ? 'Khóa OpenPGP hoạt động'
              : 'Khóa OpenPGP ${_statusLabel(keyRecord.status).toLowerCase()}',
          subtitle: '${keyRecord.displayName} · fingerprint đã cấp',
        ),
        actions: [
          _ApiActionButton.secondary(
            width: 164,
            label: 'Xuất khóa công khai',
            onPressed: disabled ? null : onExport,
          ),
          _ApiActionButton.secondary(
            width: 108,
            label: 'Xoay vòng',
            onPressed: disabled || !keyRecord.canRotate ? null : onRotate,
          ),
          _ApiActionButton.secondary(
            width: 96,
            label: 'Thu hồi',
            onPressed: disabled || !keyRecord.canRevoke ? null : onRevoke,
          ),
          _ApiActionButton.primary(
            width: 104,
            label: 'Tạo khóa',
            onPressed: disabled ? null : onCreate,
          ),
        ],
        details: _ApiDetailPanel(
          title: '${keyRecord.displayName} · fingerprint đã cấp',
          values:
              'Fingerprint: ${keyRecord.fingerprint} · Thuật toán: ${keyRecord.algorithm}',
          helper: keyRecord.overlapExpiresAt == null
              ? 'Chỉ xuất khóa công khai; khóa riêng không bao giờ hiển thị.'
              : 'Hết thời gian chuyển đổi: ${_dateTime(keyRecord.overlapExpiresAt)}',
        ),
      ),
    );
  }
}

class _KeyManagementCard extends StatelessWidget {
  const _KeyManagementCard({
    required this.disabled,
    required this.onExport,
    required this.onCreate,
  });

  final bool disabled;
  final VoidCallback? onExport;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppLayoutTokens.compactBreakpoint;
    return AppSurfaceCard(
      key: const Key('api-connection-key-management-card'),
      radius: AppRadius.lg,
      child: SizedBox(
        height: compact ? 208 : 188,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApiConnectionHeader(
              identity: _LifecycleIdentity(
                title: 'Khóa OpenPGP',
                subtitle: 'Bảo vệ nội dung trao đổi với BIDV',
              ),
              actions: [
                _ApiActionButton.secondary(
                  width: 164,
                  label: 'Xuất khóa công khai',
                  onPressed: disabled ? null : onExport,
                ),
                _ApiActionButton.primary(
                  width: 104,
                  label: 'Tạo khóa',
                  onPressed: onCreate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Expanded(
              child: _ApiDetailPanel(
                title: 'Chưa có khóa hoạt động',
                values:
                    'Sau khi tạo khóa, có thể xuất khóa công khai, xoay vòng hoặc thu hồi khóa cũ.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiConnectionHeader extends StatelessWidget {
  const _ApiConnectionHeader({required this.identity, required this.actions});

  final Widget identity;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionRow = Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: actions,
        );
        if (constraints.maxWidth < AppLayoutTokens.compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 48, child: identity),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: actionRow),
            ],
          );
        }
        return SizedBox(
          height: 48,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              actionRow,
            ],
          ),
        );
      },
    );
  }
}

class _LifecycleCardBody extends StatelessWidget {
  const _LifecycleCardBody({
    required this.minContentHeight,
    required this.compactContentHeight,
    required this.identity,
    required this.actions,
    required this.details,
  });

  final double minContentHeight;
  final double compactContentHeight;
  final _LifecycleIdentity identity;
  final List<Widget> actions;
  final Widget details;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
        return ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: compact ? compactContentHeight : minContentHeight,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ApiConnectionHeader(identity: identity, actions: actions),
              const SizedBox(height: 12),
              details,
            ],
          ),
        );
      },
    );
  }
}

class _LifecycleIdentity extends StatelessWidget {
  const _LifecycleIdentity({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.pageTitle.copyWith(
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyS.copyWith(
            height: 18 / 13,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }
}

class _ApiDetailPanel extends StatelessWidget {
  const _ApiDetailPanel({
    required this.title,
    required this.values,
    this.helper,
  });

  final String title;
  final String values;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySurfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelM.copyWith(
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            values,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyS.copyWith(
              height: 18 / 13,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 8),
            Text(
              helper!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyS.copyWith(
                height: 18 / 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApiConnectionStatusPanel extends StatelessWidget {
  const _ApiConnectionStatusPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.successSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        text,
        style: AppTextStyles.labelSmallSubtle.copyWith(
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}

class _ApiConnectionControlRow extends StatelessWidget {
  const _ApiConnectionControlRow({
    required this.label,
    required this.support,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String support;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelM.copyWith(
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                Text(
                  support,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyCompact.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ),
          _ApiConnectionSwitch(
            value: value,
            enabled: enabled,
            onChanged: onChanged,
            label: label,
          ),
        ],
      ),
    );
  }
}

class _ApiConnectionSwitch extends StatelessWidget {
  const _ApiConnectionSwitch({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final trackColor = value
        ? AppColors.primaryOf(context)
        : AppColors.neutral300;
    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: AppRadius.allPill,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 48,
              height: 24,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: enabled ? trackColor : AppColors.neutral200,
                borderRadius: AppRadius.allPill,
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiActionButton extends StatelessWidget {
  const _ApiActionButton._({
    required this.width,
    required this.label,
    required this.onPressed,
    required this.primary,
  });

  factory _ApiActionButton.primary({
    required double width,
    required String label,
    required VoidCallback? onPressed,
  }) => _ApiActionButton._(
    width: width,
    label: label,
    onPressed: onPressed,
    primary: true,
  );

  factory _ApiActionButton.secondary({
    required double width,
    required String label,
    required VoidCallback? onPressed,
  }) => _ApiActionButton._(
    width: width,
    label: label,
    onPressed: onPressed,
    primary: false,
  );

  final double width;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return SizedBox(
        width: width,
        child: AppPrimaryButton(
          onPressed: onPressed,
          label: label,
          size: AppButtonSize.small,
          height: 40,
          radius: AppRadius.md,
          textStyle: AppTextStyles.labelSmallSubtle,
        ),
      );
    }
    return SizedBox(
      width: width,
      child: AppSecondaryButton(
        onPressed: onPressed,
        label: label,
        expand: false,
        size: AppButtonSize.small,
        height: 40,
        radius: AppRadius.md,
        foregroundColor: AppColors.primaryOf(context),
        borderColor: AppColors.borderOf(context),
        textStyle: AppTextStyles.labelSmallSubtle,
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'ACTIVE' => 'Đang dùng',
  'OVERLAP' => 'Đang chuyển đổi',
  'EXPIRED' => 'Đã hết hạn',
  'REVOKED' => 'Đã thu hồi',
  _ => 'Chưa xác định',
};

String _dateTime(DateTime? value) => value == null
    ? 'Chưa xác định'
    : DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
