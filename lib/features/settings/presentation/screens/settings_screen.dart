import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
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
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
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
      messenger.showSnackBar(
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

    return AppResponsiveScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHeader(
            themeMode: themeMode,
            startupSnapshot: _startupSnapshot,
            isLoadingStartup: _isLoadingStartup,
            isSavingStartup: _isSavingStartup,
            hasStartupError: _startupError != null,
          ),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns =
                  constraints.maxWidth >= AppLayoutTokens.tabletBreakpoint;
              final sections = [
                _SettingsSection(
                  title: 'Giao diện',
                  child: _buildThemeSelector(context),
                ),
                _SettingsSection(
                  title: 'Windows',
                  child: _buildStartupTile(context),
                ),
              ];

              if (!useTwoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sections.first,
                    const SizedBox(height: AppLayoutTokens.sectionGap),
                    sections.last,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sections.first),
                  const SizedBox(width: AppLayoutTokens.sectionGap),
                  Expanded(child: sections.last),
                ],
              );
            },
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
      padding: EdgeInsets.zero,
      child: SwitchListTile.adaptive(
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
          child: Text(_startupSubtitle(snapshot), style: AppTextStyles.bodyS),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          const Row(
            children: [
              Icon(Icons.palette_outlined, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text('Chế độ hiển thị', style: AppTextStyles.labelM),
            ],
          ),
          const SizedBox(height: AppLayoutTokens.formInlineGap),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkNeutral50
                  : AppColors.neutral200,
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.transparent,
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.surface : inactiveColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyS.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color: isActive ? AppColors.surface : inactiveColor,
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

  const _SettingsHeader({
    required this.themeMode,
    required this.startupSnapshot,
    required this.isLoadingStartup,
    required this.isSavingStartup,
    required this.hasStartupError,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('settings-header'),
      backgroundColor: AppColors.primarySurfaceOf(context),
      borderColor: AppColors.primaryOf(context).withValues(alpha: 0.22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primaryOf(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: Icon(
              Icons.settings_outlined,
              color: AppColors.primaryOf(context),
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cài đặt', style: AppTextStyles.headingM),
                const SizedBox(height: 6),
                Text(
                  'Điều chỉnh giao diện và tuỳ chọn ứng dụng trên thiết bị này.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsStatusChip(
                      icon: Icons.palette_outlined,
                      label: 'Giao diện: ${_themeModeLabel(themeMode)}',
                    ),
                    _SettingsStatusChip(
                      icon: Icons.rocket_launch_outlined,
                      label: 'Windows: ${_startupStatusLabel()}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
  final IconData icon;
  final String label;

  const _SettingsStatusChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryOf(context)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: AppTextStyles.headingS),
        ),
        child,
      ],
    );
  }
}

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
