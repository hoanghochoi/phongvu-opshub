import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
  ApiOperatingMode? _pendingOperatingMode;

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
        _pendingOperatingMode = null;
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
              icon: PhosphorIconsRegular.copy,
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
            icon: PhosphorIconsRegular.copy,
            label: 'Sao chép Client ID',
          ),
          AppDialogSecondaryButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: created.clientSecret),
              );
            },
            icon: PhosphorIconsRegular.key,
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

  void _selectOperatingMode(ApiOperatingMode mode) {
    final snapshot = _snapshot;
    if (snapshot == null || _mutating || snapshot.controls.emergencyDisabled) {
      return;
    }
    if (mode != ApiOperatingMode.stopped &&
        !snapshot.controls.canEnableIngestOrLive) {
      return;
    }
    setState(() => _pendingOperatingMode = mode);
    unawaited(
      AppLogger.instance.info(
        'ApiConnectionAdmin',
        'Operating mode selected',
        context: {'mode': mode.wireValue},
      ),
    );
  }

  Future<void> _updateOperatingMode(ApiOperatingMode mode) async {
    final snapshot = _snapshot;
    if (snapshot == null || _mutating || snapshot.controls.emergencyDisabled) {
      return;
    }
    final isLive = mode == ApiOperatingMode.live;
    final pendingCount = snapshot.controls.pendingProjectionCount;
    final confirmation = isLive && pendingCount > 0
        ? 'Có $pendingCount giao dịch chưa tạo Tiền vào. Bật chính thức sẽ xử lý các giao dịch đủ điều kiện này.'
        : switch (mode) {
            ApiOperatingMode.stopped =>
              'BIDV sẽ nhận phản hồi tạm thời. Bạn có thể bật lại khi cần.',
            ApiOperatingMode.uatIngestOnly =>
              'Hệ thống sẽ tiếp nhận và lưu giao dịch, chưa tạo Tiền vào.',
            ApiOperatingMode.live =>
              'Hệ thống sẽ tiếp nhận giao dịch và tạo Tiền vào cho các giao dịch đủ điều kiện.',
          };
    if (!await _confirm(
      title: isLive
          ? 'Xác nhận bật chính thức'
          : 'Xác nhận trạng thái vận hành',
      message: confirmation,
      confirmLabel: mode == ApiOperatingMode.stopped
          ? 'Dừng kết nối'
          : 'Xác nhận',
    )) {
      return;
    }
    await _runMutation('update_operating_mode', () async {
      final updated = await _repository.updateOperatingMode(
        mode: mode,
        expectedVersion: snapshot.controls.version,
      );
      if (mounted) {
        setState(() {
          _snapshot = updated;
          _pendingOperatingMode = null;
        });
      }
    }, successMessage: 'Đã cập nhật trạng thái vận hành.');
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
                backgroundColor: destructive
                    ? AppColors.errorOf(dialogContext)
                    : null,
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
      return const AppResponsiveContent(child: _ApiConnectionLoadingState());
    }
    if (_snapshot == null) {
      return AppResponsiveContent(
        child: _ApiConnectionFailureState(onRetry: _load),
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
              actionIcon: PhosphorIconsRegular.arrowClockwise,
              onAction: _load,
            ),
          ],
          const SizedBox(height: AppLayoutTokens.sectionGap),
          _ControlCard(
            controls: snapshot.controls,
            disabled: _mutating,
            selectedMode: _pendingOperatingMode ?? snapshot.operatingMode,
            onSelect: _selectOperatingMode,
            onSave: _updateOperatingMode,
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
class _ApiConnectionLoadingState extends StatelessWidget {
  const _ApiConnectionLoadingState();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppSurfaceCard(
          key: const Key('api-connection-loading-card'),
          radius: AppRadius.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trạng thái vận hành',
                style: AppTextStyles.pageTitle.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Đang tải trạng thái vận hành…',
                style: AppTextStyles.bodyS.copyWith(
                  height: 18 / 13,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < 3; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                Container(
                  key: ValueKey('api-connection-loading-skeleton-$index'),
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.apiMutedSurfaceOf(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiConnectionFailureState extends StatelessWidget {
  const _ApiConnectionFailureState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppSurfaceCard(
          key: const Key('api-connection-failure-card'),
          radius: AppRadius.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trạng thái vận hành',
                style: AppTextStyles.pageTitle.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.apiEmergencySurfaceOf(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.apiEmergencyTextOf(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chưa tải được cấu hình kết nối. Vui lòng thử lại.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyCompact.copyWith(
                          color: AppColors.apiEmergencyTextOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Dữ liệu hiện tại chưa được thay đổi.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyS.copyWith(
                          height: 18 / 13,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 154,
                      height: 40,
                      child: AppPrimaryButton(
                        onPressed: onRetry,
                        label: 'Thử lại',
                        height: 40,
                        radius: 12,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: AppTextStyles.labelM,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
          icon: PhosphorIconsRegular.devices,
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
    required this.selectedMode,
    required this.onSelect,
    required this.onSave,
  });

  final ApiConnectionControls controls;
  final bool disabled;
  final ApiOperatingMode selectedMode;
  final ValueChanged<ApiOperatingMode> onSelect;
  final Future<void> Function(ApiOperatingMode mode) onSave;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('api-connection-controls-card'),
      radius: AppRadius.lg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint;
          final ready = controls.canEnableIngestOrLive;
          final emergency = controls.emergencyDisabled;
          final canSave =
              !disabled &&
              !emergency &&
              (selectedMode == ApiOperatingMode.stopped || ready);
          final bannerTone = emergency
              ? _ApiConnectionBannerTone.error
              : ready
              ? _ApiConnectionBannerTone.success
              : _ApiConnectionBannerTone.warning;
          final bannerText = emergency
              ? 'Kênh kết nối đang được nền tảng tạm dừng. Liên hệ kỹ thuật.'
              : ready
              ? 'Sẵn sàng để vận hành BIDV.'
              : 'Hoàn tất các bước chuẩn bị trước khi chuyển sang UAT hoặc chính thức.';
          final targetContentHeight =
              constraints.maxWidth < AppLayoutTokens.compactBreakpoint
              ? 672.0
              : constraints.maxWidth < AppLayoutTokens.tabletBreakpoint
              ? 588.0
              : 438.0;
          return ConstrainedBox(
            constraints: BoxConstraints(minHeight: targetContentHeight),
            child: Column(
              key: const Key('api-connection-operating-mode-content'),
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
                const SizedBox(height: 10),
                Text(
                  'Hoàn tất 3 bước chuẩn bị, sau đó chọn trạng thái vận hành phù hợp.',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    height: 18 / 13,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                _ApiConnectionReadinessBanner(
                  tone: bannerTone,
                  text: bannerText,
                  compact: compact,
                  wide: constraints.maxWidth >= 1100,
                ),
                const SizedBox(height: 10),
                _ApiConnectionPreparationChecklist(
                  readiness: controls.readiness,
                  forceIncomplete: emergency,
                ),
                const SizedBox(height: 10),
                _ApiConnectionModeOptions(
                  selectedMode: selectedMode,
                  canEnableIngestOrLive: ready,
                  disabled: disabled || emergency,
                  onSelect: onSelect,
                ),
                if (selectedMode == ApiOperatingMode.live &&
                    controls.pendingProjectionCount > 0) ...[
                  const SizedBox(height: 10),
                  _ApiConnectionLiveConfirmation(
                    pendingProjectionCount: controls.pendingProjectionCount,
                  ),
                ],
                const SizedBox(height: 10),
                _ApiConnectionModeFooter(
                  selectedMode: selectedMode,
                  emergency: emergency,
                  canSave: canSave,
                  compact: compact,
                  onSave: () => onSave(selectedMode),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _ApiConnectionBannerTone { success, warning, error }

class _ApiConnectionReadinessBanner extends StatelessWidget {
  const _ApiConnectionReadinessBanner({
    required this.tone,
    required this.text,
    required this.compact,
    required this.wide,
  });

  final _ApiConnectionBannerTone tone;
  final String text;
  final bool compact;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _ApiConnectionBannerTone.success => AppColors.apiReadyTextOf(context),
      _ApiConnectionBannerTone.warning => AppColors.apiWarningTextOf(context),
      _ApiConnectionBannerTone.error => AppColors.apiEmergencyTextOf(context),
    };
    final background = switch (tone) {
      _ApiConnectionBannerTone.success => AppColors.apiReadySurfaceOf(context),
      _ApiConnectionBannerTone.warning => AppColors.apiWarningSurfaceOf(
        context,
      ),
      _ApiConnectionBannerTone.error => AppColors.apiEmergencySurfaceOf(
        context,
      ),
    };
    return Container(
      key: const Key('api-connection-readiness-banner'),
      height: wide ? 38 : 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyCompact.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiConnectionPreparationChecklist extends StatelessWidget {
  const _ApiConnectionPreparationChecklist({
    required this.readiness,
    required this.forceIncomplete,
  });

  final ApiConnectionReadiness readiness;
  final bool forceIncomplete;

  @override
  Widget build(BuildContext context) {
    final infrastructureReady = readiness.infrastructure && readiness.kek;
    final items = [
      ('1. OAuth client', readiness.client, 'Tạo client trước khi vận hành'),
      ('2. Khóa OpenPGP', readiness.openPgpKey, 'Tạo khóa trước khi vận hành'),
      (
        '3. Hạ tầng kết nối',
        infrastructureReady,
        'Liên hệ kỹ thuật để hoàn tất',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingInset = constraints.maxWidth >= 1100 ? 32.0 : 22.0;
        final rowWidth = constraints.maxWidth > trailingInset
            ? constraints.maxWidth - trailingInset
            : constraints.maxWidth;
        return SizedBox(
          width: rowWidth,
          child: Column(
            key: const Key('api-connection-preparation-checklist'),
            children: [
              for (final item in items)
                _ApiConnectionChecklistRow(
                  label: item.$1,
                  ready: !forceIncomplete && item.$2,
                  notReadyCopy: item.$3,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ApiConnectionChecklistRow extends StatelessWidget {
  const _ApiConnectionChecklistRow({
    required this.label,
    required this.ready,
    required this.notReadyCopy,
  });

  final String label;
  final bool ready;
  final String notReadyCopy;

  @override
  Widget build(BuildContext context) {
    final copy = ready ? 'Đã sẵn sàng' : notReadyCopy;
    final color = ready
        ? AppColors.apiReadyTextOf(context)
        : AppColors.textSecondaryOf(context);
    return SizedBox(
      key: ValueKey('api-connection-checklist-$label'),
      height: 44,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: ready
                  ? AppColors.apiReadyTextOf(context)
                  : AppColors.textMutedOf(context),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  copy,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyCompact.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 82,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ready
                  ? AppColors.apiReadySurfaceOf(context)
                  : AppColors.apiMutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              ready ? 'Sẵn sàng' : 'Cần hoàn tất',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyCompact.copyWith(
                color: ready
                    ? AppColors.apiReadyTextOf(context)
                    : AppColors.textSecondaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiConnectionModeOptions extends StatelessWidget {
  const _ApiConnectionModeOptions({
    required this.selectedMode,
    required this.canEnableIngestOrLive,
    required this.disabled,
    required this.onSelect,
  });

  final ApiOperatingMode selectedMode;
  final bool canEnableIngestOrLive;
  final bool disabled;
  final ValueChanged<ApiOperatingMode> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal =
            constraints.maxWidth >= AppLayoutTokens.tabletBreakpoint;
        final options = [
          ApiOperatingMode.stopped,
          ApiOperatingMode.uatIngestOnly,
          ApiOperatingMode.live,
        ];
        final children = options
            .map((mode) {
              final modeEnabled =
                  !disabled &&
                  (mode == ApiOperatingMode.stopped || canEnableIngestOrLive);
              final option = _ApiConnectionModeOption(
                mode: mode,
                selected: mode == selectedMode,
                enabled: modeEnabled,
                onTap: () => onSelect(mode),
              );
              if (horizontal) return Expanded(child: option);
              return option;
            })
            .toList(growable: false);
        return Flex(
          key: const Key('api-connection-mode-options'),
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: horizontal
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                SizedBox(
                  width: horizontal ? 8 : null,
                  height: horizontal ? 86 : 8,
                ),
              children[index],
            ],
          ],
        );
      },
    );
  }
}

class _ApiConnectionModeOption extends StatelessWidget {
  const _ApiConnectionModeOption({
    required this.mode,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ApiOperatingMode mode;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedVisual = selected && enabled;
    final background = enabled
        ? selectedVisual
              ? AppColors.apiModeSelectedSurfaceOf(context)
              : AppColors.cardOf(context)
        : AppColors.apiMutedSurfaceOf(context);
    final border = selectedVisual
        ? AppColors.primary500
        : AppColors.borderOf(context);
    final textColor = enabled
        ? AppColors.textPrimaryOf(context)
        : AppColors.textSecondaryOf(context);
    return Semantics(
      key: ValueKey('api-connection-mode-${mode.wireValue}'),
      button: true,
      selected: selected,
      enabled: enabled,
      label: mode.label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 86,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _ApiConnectionModeRadio(selected: selected, enabled: enabled),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelM.copyWith(color: textColor),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _modeDescription(mode),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyCompact.copyWith(
                        color: enabled
                            ? AppColors.textSecondaryOf(context)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiConnectionModeRadio extends StatelessWidget {
  const _ApiConnectionModeRadio({
    required this.selected,
    required this.enabled,
  });

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final stroke = selected && enabled
        ? AppColors.primary500
        : AppColors.textMutedOf(context);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: stroke, width: selected ? 2 : 1),
      ),
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: enabled ? AppColors.primary500 : stroke,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

class _ApiConnectionLiveConfirmation extends StatelessWidget {
  const _ApiConnectionLiveConfirmation({required this.pendingProjectionCount});

  final int pendingProjectionCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('api-connection-live-confirmation'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.apiWarningSurfaceOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Có $pendingProjectionCount giao dịch chưa tạo Tiền vào.',
            style: AppTextStyles.labelM.copyWith(
              color: AppColors.apiWarningTextOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Bật chính thức sẽ xử lý các giao dịch đủ điều kiện này.',
            style: AppTextStyles.bodyCompact.copyWith(
              color: AppColors.apiWarningTextOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiConnectionModeFooter extends StatelessWidget {
  const _ApiConnectionModeFooter({
    required this.selectedMode,
    required this.emergency,
    required this.canSave,
    required this.compact,
    required this.onSave,
  });

  final ApiOperatingMode selectedMode;
  final bool emergency;
  final bool canSave;
  final bool compact;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final footerText = emergency
        ? 'Tất cả trạng thái đang tạm dừng.'
        : switch (selectedMode) {
            ApiOperatingMode.stopped =>
              compact
                  ? 'Đang dừng. Có thể giữ Dừng trong khi hoàn tất chuẩn bị.'
                  : 'Đang dừng. BIDV sẽ nhận phản hồi tạm thời.',
            ApiOperatingMode.uatIngestOnly =>
              'Đang UAT: tiếp nhận giao dịch nhưng chưa tạo Tiền vào.',
            ApiOperatingMode.live =>
              'Đang chính thức: tạo Tiền vào cho giao dịch đủ điều kiện.',
          };
    final actionLabel = switch (selectedMode) {
      ApiOperatingMode.stopped => 'Lưu trạng thái',
      ApiOperatingMode.uatIngestOnly => 'Bật UAT',
      ApiOperatingMode.live => 'Bật chính thức',
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final button = SizedBox(
          key: const Key('api-connection-save-mode'),
          width: compact ? 154 : 130,
          height: 40,
          child: AppPrimaryButton(
            onPressed: canSave ? onSave : null,
            label: actionLabel,
            height: 40,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: AppTextStyles.labelM,
          ),
        );
        if (compact) {
          return Column(
            key: const Key('api-connection-mode-footer'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                footerText,
                style: AppTextStyles.bodyCompact.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 8),
              button,
            ],
          );
        }
        final trailingInset = constraints.maxWidth >= 1100 ? 50.0 : 48.0;
        final footerWidth = constraints.maxWidth > trailingInset
            ? constraints.maxWidth - trailingInset
            : constraints.maxWidth;
        return SizedBox(
          key: const Key('api-connection-mode-footer'),
          width: footerWidth,
          height: 42,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  footerText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyCompact.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              button,
            ],
          ),
        );
      },
    );
  }
}

String _modeDescription(ApiOperatingMode mode) => switch (mode) {
  ApiOperatingMode.stopped => 'Không cấp token, không tiếp nhận dữ liệu.',
  ApiOperatingMode.uatIngestOnly => 'Nhận giao dịch, chưa tạo Tiền vào.',
  ApiOperatingMode.live => 'Nhận giao dịch và tạo Tiền vào.',
};

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
