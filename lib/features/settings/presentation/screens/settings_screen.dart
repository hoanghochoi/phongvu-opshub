import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final isWide = viewportWidth >= AppLayoutTokens.desktopBreakpoint;

    return AppResponsiveScrollView(
      onRefresh: _loadStartupSetting,
      refreshLogSource: _logSource,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isWide)
            _SettingsHeader(
              themeMode: themeMode,
              startupSnapshot: _startupSnapshot,
              isLoadingStartup: _isLoadingStartup,
              isSavingStartup: _isSavingStartup,
              hasStartupError: _startupError != null,
              speakerPresetLabel: speakerPreset?.label,
            )
          else
            _SettingsStatusRow(
              themeMode: themeMode,
              startupStatus: _startupStatusLabel(),
              showWindows: viewportWidth >= AppLayoutTokens.compactBreakpoint,
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              // Figma keeps the tablet rail as a single 343 px column. Only
              // the wide Desktop/Web frame uses the 555 px two-column grid.
              final cardWidth = isWide ? 555.0 : 343.0;
              final boundedCardWidth = constraints.maxWidth < cardWidth
                  ? constraints.maxWidth
                  : cardWidth;
              final sections = <Widget>[
                SizedBox(
                  width: boundedCardWidth,
                  height: isWide ? 230 : 188,
                  child: _SettingsSection(child: _buildThemeSelector(context)),
                ),
                SizedBox(
                  width: boundedCardWidth,
                  height: isWide
                      ? 230
                      : (viewportWidth < AppLayoutTokens.compactBreakpoint
                            ? 166
                            : 188),
                  child: _SettingsSection(child: _buildStartupTile(context)),
                ),
                if (paymentMonitor?.canConfigurePaymentSpeaker == true)
                  SizedBox(
                    width: boundedCardWidth,
                    child: _SettingsSection(
                      child: _buildSpeakerVoiceSelector(
                        context,
                        paymentMonitor!,
                      ),
                    ),
                  ),
              ];
              return Wrap(spacing: 16, runSpacing: 16, children: sections);
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
      radius: AppRadius.cardFigma,
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
    final canToggle =
        !_isLoadingStartup &&
        !_isSavingStartup &&
        _startupError == null &&
        isSupported &&
        snapshot != null;
    final isEnabled = snapshot?.isEnabled ?? false;
    final showSwitch = canToggle;

    return AppSurfaceCard(
      key: const Key('settings-startup-card'),
      radius: AppRadius.cardFigma,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Windows',
            style: AppTextStyles.titleEmphasis.copyWith(
              fontSize: 17,
              height: 20 / 17,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showSwitch) ...[
                  _SettingsStartupSwitch(
                    key: const Key('settings-startup-toggle'),
                    value: isEnabled,
                    enabled: canToggle,
                    onChanged: _setStartupEnabled,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khởi động cùng Windows',
                        maxLines: 1,
                        softWrap: false,
                        style: AppTextStyles.labelM.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'OpsHub sẽ tự mở khi đăng nhập Windows',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyS.copyWith(
                          fontSize: 12,
                          height: 18 / 12,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _SettingsStartupStateBadge(
            label: _startupStateBadgeLabel(snapshot),
            tone: _startupStateBadgeTone(snapshot),
          ),
        ],
      ),
    );
  }

  String _startupStateBadgeLabel(StartupSettingsSnapshot? snapshot) {
    if (_isLoadingStartup) return 'Đang tải tùy chọn khởi động...';
    if (_isSavingStartup) return 'Đang lưu thay đổi...';
    if (_startupError != null) return 'Không thể tải tùy chọn. Thử lại.';
    if (snapshot == null || !snapshot.isSupported) {
      return 'Chỉ hỗ trợ trên Windows';
    }
    return snapshot.isEnabled ? 'Đang bật' : 'Đang tắt';
  }

  _SettingsStartupBadgeTone _startupStateBadgeTone(
    StartupSettingsSnapshot? snapshot,
  ) {
    if (_startupError != null) return _SettingsStartupBadgeTone.error;
    if (_isLoadingStartup || _isSavingStartup) {
      return _SettingsStartupBadgeTone.neutral;
    }
    if (snapshot?.isSupported == true) {
      return _SettingsStartupBadgeTone.success;
    }
    return _SettingsStartupBadgeTone.neutral;
  }

  String _startupStatusLabel() {
    if (_isLoadingStartup) return 'Đang tải';
    if (_isSavingStartup) return 'Đang lưu';
    if (_startupError != null) return 'Cần thử lại';
    final snapshot = _startupSnapshot;
    if (snapshot == null) return 'Chưa có trạng thái';
    if (!snapshot.isSupported) return 'Chỉ hỗ trợ trên Windows';
    return snapshot.isEnabled ? 'Đang bật' : 'Đang tắt';
  }

  Widget _buildThemeSelector(BuildContext context) {
    final currentMode = context.watch<ThemeProvider>().mode;

    return AppSurfaceCard(
      key: const Key('settings-theme-card'),
      radius: AppRadius.cardFigma,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giao diện',
            style: AppTextStyles.titleEmphasis.copyWith(
              fontSize: 17,
              height: 20 / 17,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Chế độ hiển thị',
            style: AppTextStyles.bodyS.copyWith(
              fontSize: 13,
              height: 20 / 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.isDark(context)
                  ? AppColors.darkInput
                  : AppColors.neutral50Of(context),
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
          height: 52,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.infoSurfaceOf(context)
                : AppColors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.infoOf(context) : inactiveColor,
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
                    color: isActive ? AppColors.infoOf(context) : inactiveColor,
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
    if (isLoadingStartup) return 'Đang tải';
    if (isSavingStartup) return 'Đang lưu';
    if (hasStartupError) return 'Cần thử lại';
    final snapshot = startupSnapshot;
    if (snapshot == null) return 'Chưa có trạng thái';
    if (!snapshot.isSupported) return 'Chỉ hỗ trợ trên Windows';
    return snapshot.isEnabled ? 'Đang bật' : 'Đang tắt';
  }
}

class _SettingsStatusRow extends StatelessWidget {
  final ThemeMode themeMode;
  final String startupStatus;
  final bool showWindows;

  const _SettingsStatusRow({
    required this.themeMode,
    required this.startupStatus,
    required this.showWindows,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const Key('settings-status-row'),
      spacing: 8,
      runSpacing: 8,
      children: [
        _SettingsStatusChip(
          label: 'Giao diện: ${_themeModeLabel(themeMode)}',
          tone: _SettingsChipTone.info,
        ),
        if (showWindows)
          _SettingsStatusChip(
            label: 'Windows: $startupStatus',
            tone: _SettingsChipTone.success,
          ),
      ],
    );
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
          _SettingsChipTone.info => AppColors.infoSurfaceOf(context),
          _SettingsChipTone.success => AppColors.successSurfaceOf(context),
          _SettingsChipTone.neutral => AppColors.statusSurfaceOf(
            context,
            'neutral',
          ),
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
              _SettingsChipTone.info => AppColors.infoOf(context),
              _SettingsChipTone.success => AppColors.successOf(context),
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

enum _SettingsStartupBadgeTone { neutral, success, error }

class _SettingsStartupStateBadge extends StatelessWidget {
  final String label;
  final _SettingsStartupBadgeTone tone;

  const _SettingsStartupStateBadge({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      _SettingsStartupBadgeTone.neutral => (
        AppColors.statusSurfaceOf(context, 'neutral'),
        AppColors.textSecondaryOf(context),
      ),
      _SettingsStartupBadgeTone.success => (
        AppColors.successSurfaceOf(context),
        AppColors.successOf(context),
      ),
      _SettingsStartupBadgeTone.error => (
        AppColors.errorSurfaceOf(context),
        AppColors.errorOf(context),
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 34),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.captionBold.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _SettingsStartupSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SettingsStartupSwitch({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor = value
        ? AppColors.primaryOf(context)
        : AppColors.borderOf(context);
    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: 'Khởi động cùng Windows',
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: enabled ? trackColor : AppColors.subtleBorderOf(context),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Align(
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
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

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Sáng',
    ThemeMode.dark => 'Tối',
    ThemeMode.system => 'Hệ thống',
  };
}
