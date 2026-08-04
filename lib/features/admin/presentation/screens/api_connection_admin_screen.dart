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
          _HeaderCard(
            snapshot: snapshot,
            disabled: _mutating,
            onCreateClient: _mutating ? null : _createClient,
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
          _SectionHeader(
            title: 'OAuth client',
            description:
                'Secret chỉ hiện một lần; hệ thống chỉ lưu bộ kiểm tra một chiều.',
            actionLabel: 'Tạo client',
            actionIcon: Icons.add_rounded,
            onAction: _mutating ? null : _createClient,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          if (snapshot.clients.isEmpty)
            const AppStatePanel.empty(
              title: 'Chưa có client',
              message: 'Tạo client đầu tiên để chuẩn bị kết nối BIDV.',
            )
          else
            ...snapshot.clients.map(
              (client) => Padding(
                padding: const EdgeInsets.only(bottom: AppLayoutTokens.cardGap),
                child: _ClientCard(
                  client: client,
                  disabled: _mutating,
                  onRotate: () => _rotateClient(client),
                  onRevoke: () => _revokeClient(client),
                ),
              ),
            ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          _SectionHeader(
            title: 'Khóa OpenPGP',
            description:
                'Chỉ khóa công khai và fingerprint được phép xuất khỏi OpsHub.',
            actionLabel: 'Tạo khóa',
            actionIcon: Icons.key_rounded,
            onAction: _mutating ? null : _generateKey,
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          if (snapshot.keys.isEmpty)
            const AppStatePanel.empty(
              title: 'Chưa có khóa OpenPGP',
              message: 'Tạo khóa để BIDV mã hóa dữ liệu trước khi gửi.',
            )
          else
            ...snapshot.keys.map(
              (key) => Padding(
                padding: const EdgeInsets.only(bottom: AppLayoutTokens.cardGap),
                child: _KeyCard(
                  keyRecord: key,
                  disabled: _mutating,
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
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kết nối ${snapshot.bankCode}',
                      style: AppTextStyles.headingS,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Môi trường: $environment${snapshot.publicBaseUrl == null ? '' : ' · Endpoint đã cấu hình'}',
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 128,
                child: AppPrimaryButton(
                  onPressed: onCreateClient,
                  label: 'Tạo client',
                  size: AppButtonSize.small,
                  height: 40,
                  isLoading: disabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                snapshot.controls.ingressEffective
                    ? 'BIDV đang sẵn sàng tiếp nhận dữ liệu'
                    : 'BIDV sẵn sàng tiếp nhận dữ liệu',
                style: AppTextStyles.labelM.copyWith(color: AppColors.success),
              ),
            ),
          ),
        ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Trạng thái vận hành', style: AppTextStyles.headingS),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tiếp nhận dữ liệu BIDV'),
            subtitle: Text(
              controls.ingressMasterEnabled
                  ? 'Công tắc hạ tầng đã cho phép.'
                  : 'Hạ tầng đang khóa; thay đổi tại UI chưa làm kênh hoạt động.',
            ),
            value: controls.ingressRequested,
            onChanged: disabled
                ? null
                : (value) => onChange(
                    ingressEnabled: value,
                    projectionEnabled: value
                        ? controls.projectionRequested
                        : false,
                  ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Đối soát sang Tiền vào'),
            subtitle: Text(
              controls.projectionMasterEnabled
                  ? 'Chỉ bật sau khi hoàn tất UAT và đối soát.'
                  : 'Hạ tầng đang khóa đối soát tự động.',
            ),
            value: controls.projectionRequested,
            onChanged: disabled || !controls.ingressRequested
                ? null
                : (value) =>
                      onChange(ingressEnabled: true, projectionEnabled: value),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  final String title;
  final String description;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.headingS),
            const SizedBox(height: 4),
            Text(
              description,
              style: AppTextStyles.bodyS.copyWith(
                color: AppColors.textMutedOf(context),
              ),
            ),
          ],
        );
        final button = AppSecondaryButton(
          onPressed: onAction,
          icon: actionIcon,
          label: actionLabel,
          expand: false,
        );
        if (constraints.maxWidth < AppLayoutTokens.compactBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [text, const SizedBox(height: 12), button],
          );
        }
        return Row(
          children: [
            Expanded(child: text),
            const SizedBox(width: 16),
            button,
          ],
        );
      },
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.client,
    required this.disabled,
    required this.onRotate,
    required this.onRevoke,
  });

  final ApiClientCredential client;
  final bool disabled;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecordTitle(
            title: client.displayName,
            status: client.status,
            version: client.version,
          ),
          const SizedBox(height: 10),
          const Text('Client ID'),
          SelectableText(client.clientId),
          const SizedBox(height: 6),
          Text('Scope: ${client.scope}'),
          if (client.overlapExpiresAt != null)
            Text(
              'Hết thời gian chuyển đổi: ${_dateTime(client.overlapExpiresAt)}',
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppLinkButton(
                onPressed: disabled || !client.canRotate ? null : onRotate,
                icon: Icons.autorenew_rounded,
                label: 'Xoay vòng',
              ),
              AppLinkButton(
                onPressed: disabled || !client.canRevoke ? null : onRevoke,
                icon: Icons.block_rounded,
                label: 'Thu hồi',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.keyRecord,
    required this.disabled,
    required this.onExport,
    required this.onRotate,
    required this.onRevoke,
  });

  final ApiPgpKey keyRecord;
  final bool disabled;
  final VoidCallback onExport;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecordTitle(
            title: keyRecord.displayName,
            status: keyRecord.status,
            version: keyRecord.version,
          ),
          const SizedBox(height: 10),
          Text('Thuật toán: ${keyRecord.algorithm}'),
          const SizedBox(height: 6),
          const Text('Fingerprint'),
          SelectableText(keyRecord.fingerprint),
          if (keyRecord.overlapExpiresAt != null)
            Text(
              'Hết thời gian chuyển đổi: ${_dateTime(keyRecord.overlapExpiresAt)}',
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppLinkButton(
                onPressed: disabled ? null : onExport,
                icon: Icons.ios_share_rounded,
                label: 'Xuất khóa công khai',
              ),
              AppLinkButton(
                onPressed: disabled || !keyRecord.canRotate ? null : onRotate,
                icon: Icons.autorenew_rounded,
                label: 'Xoay vòng',
              ),
              AppLinkButton(
                onPressed: disabled || !keyRecord.canRevoke ? null : onRevoke,
                icon: Icons.block_rounded,
                label: 'Thu hồi',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTitle extends StatelessWidget {
  const _RecordTitle({
    required this.title,
    required this.status,
    required this.version,
  });

  final String title;
  final String status;
  final int version;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('$title • v$version', style: AppTextStyles.headingS),
        ),
        Chip(label: Text(_statusLabel(status))),
      ],
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
