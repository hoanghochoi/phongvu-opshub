import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/widgets/app_buttons.dart';
import '../../../app/widgets/app_combobox.dart';
import '../../../app/widgets/app_inputs.dart';
import '../../../app/widgets/app_layout.dart';
import '../../../app/widgets/app_state_widgets.dart';
import '../../../app/widgets/app_toast.dart';
import '../../../core/logging/app_logger.dart';
import '../../fifo_check/presentation/widgets/barcode_scanner_screen.dart';
import '../data/quick_actions_repository.dart';
import 'quick_actions_provider.dart';

const _adminActionFields = <String, String>{
  'APP_DOWNLOAD': 'Tải app',
  'CHECK_IN': 'Check-in',
  'ZALO_OA': 'Zalo OA',
  'GOOGLE_MAP': 'GG Map',
};

typedef QuickActionLinkScanner =
    Future<String?> Function(BuildContext context, String code, String label);

class QuickActionLinksAdminScreen extends StatefulWidget {
  final QuickActionsRepository repository;
  final QuickActionLinkScanner? scanner;
  final bool? cameraScannerSupported;

  const QuickActionLinksAdminScreen({
    super.key,
    required this.repository,
    this.scanner,
    this.cameraScannerSupported,
  });

  @override
  State<QuickActionLinksAdminScreen> createState() =>
      _QuickActionLinksAdminScreenState();
}

class _QuickActionLinksAdminScreenState
    extends State<QuickActionLinksAdminScreen> {
  final Map<String, TextEditingController> _controllers = {
    for (final code in _adminActionFields.keys) code: TextEditingController(),
  };
  final Map<String, FocusNode> _focusNodes = {
    for (final code in _adminActionFields.keys)
      code: FocusNode(debugLabel: 'quick-action-$code'),
  };
  List<QuickActionStore> _stores = const [];
  String? _storeCode;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStores());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStores() async {
    final startedAt = DateTime.now();
    try {
      final stores = await widget.repository.loadManagedStores();
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _storeCode = stores.isEmpty ? null : stores.first.storeCode;
        _loading = false;
      });
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Managed stores loaded',
        context: {
          'storeCount': stores.length,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (_storeCode != null) await _loadLinks(_storeCode!);
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'QuickActionAdmin',
        'Managed stores load failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Chưa tải được danh sách showroom. Vui lòng thử lại.';
        });
      }
    }
  }

  Future<void> _loadLinks(String storeCode) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await widget.repository.loadAdminLinks(storeCode);
      for (final code in _adminActionFields.keys) {
        _controllers[code]!.text = links[code] ?? '';
      }
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Quick action links loaded',
        context: {
          'storeCode': storeCode,
          'configuredCount': links.values
              .where((value) => value?.isNotEmpty == true)
              .length,
        },
      );
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'QuickActionAdmin',
        'Quick action links load failed',
        error: error,
        stackTrace: stackTrace,
        context: {'storeCode': storeCode},
      );
      _error = 'Chưa tải được cấu hình. Vui lòng thử lại.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan(String code) async {
    final cameraSupported =
        widget.cameraScannerSupported ??
        barcodeCameraScannerSupported(
          isWeb: kIsWeb,
          platform: defaultTargetPlatform,
        );
    await AppLogger.instance.info(
      'QuickActionAdmin',
      'Quick action link scan started',
      context: {
        'actionCode': code,
        'storeCode': _storeCode,
        'mode': cameraSupported ? 'camera' : 'keyboard-wedge',
      },
    );
    if (!mounted) return;
    if (!cameraSupported) {
      _focusNodes[code]!.requestFocus();
      if (!mounted) return;
      AppToast.show(
        context,
        const SnackBar(
          content: Text(
            'Đã sẵn sàng nhận mã từ máy quét USB. Quét mã rồi nhấn Enter.',
          ),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final label = _adminActionFields[code]!;
    final value =
        await (widget.scanner?.call(context, code, label) ??
            showBarcodeScanner(
              context,
              title: 'Quét liên kết $label',
              instruction: 'Đưa mã QR liên kết vào giữa khung',
              helperText:
                  'Mã cần chứa liên kết bắt đầu bằng http:// hoặc https://',
              parsePhongVuSku: false,
            ));
    if (!mounted) return;
    _restoreLinkFocus(code);
    if (value == null) {
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Quick action link scan cancelled',
        context: {'actionCode': code, 'storeCode': _storeCode},
      );
      return;
    }
    final normalized = value.trim();
    _controllers[code]!
      ..text = normalized
      ..selection = TextSelection.collapsed(offset: normalized.length);
    await AppLogger.instance.info(
      'QuickActionAdmin',
      'Quick action link scan succeeded',
      context: {
        'actionCode': code,
        'storeCode': _storeCode,
        'urlLength': normalized.length,
      },
    );
    setState(() {});
  }

  void _restoreLinkFocus(String code) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controllers[code]!;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      _focusNodes[code]!.requestFocus();
    });
  }

  Future<void> _save() async {
    final storeCode = _storeCode;
    if (storeCode == null || _saving) return;
    final startedAt = DateTime.now();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final links = {
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      };
      await widget.repository.saveAdminLinks(storeCode, links);
      await _refreshQuickActionsAfterSave(storeCode);
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Quick action links save succeeded',
        context: {
          'storeCode': storeCode,
          'configuredCount': links.values
              .where((value) => value.isNotEmpty)
              .length,
          'urlLengths': links.map((key, value) => MapEntry(key, value.length)),
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        AppToast.show(
          context,
          const SnackBar(
            content: Text('Đã lưu mã Thao tác nhanh cho showroom.'),
          ),
        );
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'QuickActionAdmin',
        'Quick action links save failed',
        error: error,
        stackTrace: stackTrace,
        context: {
          'storeCode': storeCode,
          'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
      if (mounted) {
        setState(
          () =>
              _error = 'Chưa lưu được cấu hình. Kiểm tra liên kết rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshQuickActionsAfterSave(String storeCode) async {
    try {
      final payload = await context.read<QuickActionsProvider>().refresh(
        storeCode: storeCode,
        force: true,
      );
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Quick actions refreshed after link save',
        context: {
          'storeCode': storeCode,
          'status': payload == null ? 'failed' : 'succeeded',
          'availableCount': payload?.availableActionCodes.length ?? 0,
        },
      );
    } on ProviderNotFoundException {
      await AppLogger.instance.info(
        'QuickActionAdmin',
        'Quick actions refresh skipped after link save',
        context: {'storeCode': storeCode, 'reason': 'provider_unavailable'},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Quản lý mã',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Cấu hình liên kết riêng cho từng showroom. Để trống một trường rồi lưu để xóa cấu hình.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 20),
          if (_stores.isNotEmpty)
            AppCombobox<String>.single(
              label: 'Showroom',
              value: _storeCode,
              allowClear: false,
              enabled: !_saving,
              options: [
                for (final store in _stores)
                  AppComboboxOption(
                    value: store.storeCode,
                    label: '${store.storeCode} · ${store.storeName}',
                    searchKeywords: [store.storeCode, store.storeName],
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _storeCode = value);
                unawaited(_loadLinks(value));
              },
            ),
          const SizedBox(height: 20),
          if (_loading)
            const AppStatePanel.loading(title: 'Đang tải cấu hình')
          else if (_stores.isEmpty)
            AppStatePanel.empty(
              title: 'Chưa có showroom để quản lý',
              message: _error,
              actionLabel: 'Thử lại',
              onAction: _loadStores,
            )
          else ...[
            for (final entry in _adminActionFields.entries) ...[
              AppTextInput(
                controller: _controllers[entry.key]!,
                focusNode: _focusNodes[entry.key],
                label: 'Liên kết ${entry.value}',
                hintText: 'https://...',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(2048)],
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                suffixIcon: IconButton(
                  tooltip: 'Quét mã ${entry.value}',
                  onPressed: () => _scan(entry.key),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: AppTextStyles.bodyM.copyWith(color: AppColors.error),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 220,
                child: AppPrimaryButton(
                  onPressed: _save,
                  icon: Icons.save_outlined,
                  label: 'Lưu cấu hình',
                  isLoading: _saving,
                  loadingLabel: 'Đang lưu',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
