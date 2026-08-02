import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_combobox.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../payment_monitor/presentation/providers/payment_monitor_provider.dart';
import '../../data/startup_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final Future<StartupSettingsSnapshot> Function()? loadStartupSetting;
  final Future<StartupSettingsSnapshot> Function(bool enabled)?
  setStartupEnabled;

  const SettingsScreen({
    super.key,
    this.loadStartupSetting,
    this.setStartupEnabled,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _logSource = 'SettingsScreen';

  late final StartupSettingsService _startupSettings;

  StartupSettingsSnapshot? _startupSnapshot;
  bool _isLoadingStartup = true;
  bool _isSavingStartup = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _startupSettings = StartupSettingsService();
    unawaited(AppLogger.instance.info(_logSource, 'Settings screen opened'));
    _loadStartupSetting();
  }

  Future<void> _loadStartupSetting() async {
    await AppLogger.instance.info(
      _logSource,
      'Settings startup setting load started',
    );
    setState(() {
      _isLoadingStartup = true;
      _startupError = null;
    });

    try {
      final snapshot = await _loadStartupSnapshot();
      if (!mounted) return;
      setState(() {
        _startupSnapshot = snapshot;
        _isLoadingStartup = false;
      });
      await AppLogger.instance.info(
        _logSource,
        'Settings startup setting load succeeded',
        context: {
          'supported': snapshot.isSupported,
          'enabled': snapshot.isEnabled,
          'hasStaleEntry': snapshot.hasStaleEntry,
        },
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _startupError = 'Không đọc được cài đặt khởi động cùng Windows';
        _isLoadingStartup = false;
      });
      await AppLogger.instance.error(
        _logSource,
        'Settings startup setting load failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _setStartupEnabled(bool enabled) async {
    await AppLogger.instance.info(
      _logSource,
      'Settings startup toggle started',
      context: {'targetEnabled': enabled},
    );
    setState(() {
      _isSavingStartup = true;
      _startupError = null;
    });

    try {
      final snapshot = await _setStartupSnapshot(enabled);
      if (!mounted) return;
      setState(() {
        _startupSnapshot = snapshot;
        _isSavingStartup = false;
      });
      await AppLogger.instance.info(
        _logSource,
        'Settings startup toggle succeeded',
        context: {
          'targetEnabled': enabled,
          'enabled': snapshot.isEnabled,
          'supported': snapshot.isSupported,
          'hasStaleEntry': snapshot.hasStaleEntry,
        },
      );
      if (!mounted) return;
      AppToast.show(
        context,
        SnackBar(
          content: Text(
            enabled
                ? 'Đã bật khởi động cùng Windows'
                : 'Đã tắt khởi động cùng Windows',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _startupError = 'Không cập nhật được cài đặt khởi động cùng Windows';
        _isSavingStartup = false;
      });
      await AppLogger.instance.error(
        _logSource,
        'Settings startup toggle failed',
        error: error,
        stackTrace: stackTrace,
        context: {'targetEnabled': enabled},
      );
      if (!mounted) return;
      AppToast.show(
        context,
        const SnackBar(
          content: Text('Không lưu được cài đặt. Vui lòng thử lại.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<StartupSettingsSnapshot> _loadStartupSnapshot() {
    final loader = widget.loadStartupSetting;
    return loader != null ? loader() : _startupSettings.load();
  }

  Future<StartupSettingsSnapshot> _setStartupSnapshot(bool enabled) {
    final setter = widget.setStartupEnabled;
    return setter != null
        ? setter(enabled)
        : _startupSettings.setEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;
    final paymentMonitor = context.watch<PaymentMonitorProvider?>();
    final speakerPreset = paymentMonitor?.speakerVoicePreset;

    return AppResponsiveScrollView(
      onRefresh: _loadStartupSetting,
      refreshLogSource: _logSource,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(
            themeMode: themeMode,
            startupSnapshot: _startupSnapshot,
            isLoadingStartup: _isLoadingStartup,
            isSavingStartup: _isSavingStartup,
            hasStartupError: _startupError != null,
            speakerPresetLabel: speakerPreset?.label,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns =
                  constraints.maxWidth >= AppLayoutTokens.tabletBreakpoint;
              final sections = <Widget>[
                _SettingsSection(child: _buildThemeSelector(context)),
                _SettingsSection(child: _buildStartupTile(context)),
                if (paymentMonitor?.canConfigurePaymentSpeaker == true)
                  _SettingsSection(
                    child: _buildSpeakerVoiceSelector(context, paymentMonitor!),
                  ),
              ];

              final itemWidth = useTwoColumns
                  ? (constraints.maxWidth - 16) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final section in sections)
                    SizedBox(width: itemWidth, child: section),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerVoiceSelector(
    BuildContext context,
    PaymentMonitorProvider monitor,
  ) {
    return AppSurfaceCard(
      key: const Key('settings-speaker-voice-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Loa tiền vào', style: AppTextStyles.labelL),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          AppCombobox<String>.single(
            label: 'Giọng đọc trên máy này',
            icon: Icons.record_voice_over_outlined,
            value: monitor.speakerVoicePresetId,
            options: monitor.speakerVoicePresetOptions
                .map(
                  (preset) => AppComboboxOption<String>(
                    value: preset.id,
                    label: preset.label,
                    subtitle: preset.subtitle,
                    searchKeywords: [preset.label, preset.subtitle],
                  ),
                )
                .toList(growable: false),
            emptyLabel: 'Chọn giọng đọc',
            allowClear: false,
            onChanged: (value) {
              if (value == null) return;
              unawaited(monitor.setSpeakerVoicePreset(value));
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Áp dụng cho thông báo mới. Cài đặt chỉ lưu trên máy loa này.',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupTile(BuildContext context) {
    final snapshot = _startupSnapshot;
    final isSupported = snapshot?.isSupported ?? true;
    final canToggle = !_isLoadingStartup && !_isSavingStartup && isSupported;
    final isEnabled = snapshot?.isEnabled ?? false;

    return AppSurfaceCard(
      key: const Key('settings-startup-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Windows', style: AppTextStyles.labelL),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: isEnabled,
            onChanged: canToggle ? _setStartupEnabled : null,
            secondary: _StartupSettingIcon(
              isEnabled: isEnabled,
              isLoading: _isLoadingStartup || _isSavingStartup,
              isSupported: isSupported,
            ),
            title: const Text(
              'Khởi động cùng Windows',
              style: AppTextStyles.labelM,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _startupSubtitle(snapshot),
                style: AppTextStyles.bodyS,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  String _startupSubtitle(StartupSettingsSnapshot? snapshot) {
    if (_isLoadingStartup) return 'Đang kiểm tra trạng thái';
    if (_isSavingStartup) return 'Đang lưu thay đổi';
    if (_startupError != null) return _startupError!;
    if (snapshot == null) return 'Chưa có trạng thái';
    if (snapshot.message != null) return snapshot.message!;
    if (!snapshot.isSupported) return 'Chỉ hỗ trợ trên Windows';
    return snapshot.isEnabled
        ? 'OpsHub sẽ tự mở khi đăng nhập Windows'
        : 'OpsHub không tự mở khi đăng nhập Windows';
  }

  Widget _buildThemeSelector(BuildContext context) {
    final currentMode = context.watch<ThemeProvider>().mode;

    return AppSurfaceCard(
      key: const Key('settings-theme-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Giao diện', style: AppTextStyles.labelL),
          const SizedBox(height: 12),
          const Text('Chế độ hiển thị', style: AppTextStyles.labelM),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkNeutral50
                  : AppColors.neutral50,
              border: Border.all(color: AppColors.subtleBorderOf(context)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _buildThemeOption(
                  context,
                  mode: ThemeMode.light,
                  icon: Icons.light_mode_outlined,
                  activeIcon: Icons.light_mode,
                  label: 'Sáng',
                  isActive: currentMode == ThemeMode.light,
                ),
                _buildThemeOption(
                  context,
                  mode: ThemeMode.dark,
                  icon: Icons.dark_mode_outlined,
                  activeIcon: Icons.dark_mode,
                  label: 'Tối',
                  isActive: currentMode == ThemeMode.dark,
                ),
                _buildThemeOption(
                  context,
                  mode: ThemeMode.system,
                  icon: Icons.settings_brightness_outlined,
                  activeIcon: Icons.settings_brightness,
                  label: 'Hệ thống',
                  isActive: currentMode == ThemeMode.system,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required ThemeMode mode,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
  }) {
    final themeProvider = context.read<ThemeProvider>();
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        key: Key('settings-theme-${mode.name}'),
        onTap: () => themeProvider.setMode(mode),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? AppColors.infoSurface : AppColors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.info : inactiveColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive ? AppColors.info : inactiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsHeader extends StatelessWidget {
  final ThemeMode themeMode;
  final StartupSettingsSnapshot? startupSnapshot;
  final bool isLoadingStartup;
  final bool isSavingStartup;
  final bool hasStartupError;
  final String? speakerPresetLabel;

  const _SettingsHeader({
    required this.themeMode,
    required this.startupSnapshot,
    required this.isLoadingStartup,
    required this.isSavingStartup,
    required this.hasStartupError,
    required this.speakerPresetLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('settings-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tùy chọn thiết bị', style: AppTextStyles.headingS),
        const SizedBox(height: 8),
        Text(
          'Điều chỉnh giao diện và hành vi khởi động theo nền tảng.',
          style: AppTextStyles.bodyS.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SettingsStatusChip(
              label: 'Giao diện: ${_themeModeLabel(themeMode)}',
              tone: _SettingsChipTone.info,
            ),
            _SettingsStatusChip(
              label: 'Windows: ${_startupStatusLabel()}',
              tone: _SettingsChipTone.success,
            ),
            if (speakerPresetLabel != null)
              _SettingsStatusChip(label: 'Loa: $speakerPresetLabel'),
          ],
        ),
      ],
    );
  }

  String _startupStatusLabel() {
    if (isLoadingStartup) return 'Đang kiểm tra';
    if (isSavingStartup) return 'Đang lưu';
    if (hasStartupError) return 'Cần thử lại';
    final snapshot = startupSnapshot;
    if (snapshot == null) return 'Chưa có trạng thái';
    if (!snapshot.isSupported) return 'Không hỗ trợ';
    return snapshot.isEnabled ? 'Đang bật' : 'Đang tắt';
  }
}

class _SettingsStatusChip extends StatelessWidget {
  final String label;
  final _SettingsChipTone tone;

  const _SettingsStatusChip({
    required this.label,
    this.tone = _SettingsChipTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: switch (tone) {
          _SettingsChipTone.info => AppColors.infoSurface,
          _SettingsChipTone.success => AppColors.successSurface,
          _SettingsChipTone.neutral => AppColors.chipBackground,
        },
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelS.copyWith(
            color: switch (tone) {
              _SettingsChipTone.info => AppColors.info,
              _SettingsChipTone.success => AppColors.success,
              _SettingsChipTone.neutral => AppColors.textSecondaryOf(context),
            },
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

enum _SettingsChipTone { neutral, info, success }

class _StartupSettingIcon extends StatelessWidget {
  const _StartupSettingIcon({
    required this.isEnabled,
    required this.isLoading,
    required this.isSupported,
  });

  final bool isEnabled;
  final bool isLoading;
  final bool isSupported;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2.4),
      );
    }

    return Icon(
      isEnabled ? Icons.rocket_launch_rounded : Icons.power_settings_new,
      color: !isSupported
          ? AppColors.neutral300
          : isEnabled
          ? AppColors.success
          : AppColors.neutral500,
    );
  }
}

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Sáng',
    ThemeMode.dark => 'Tối',
    ThemeMode.system => 'Hệ thống',
  };
}
