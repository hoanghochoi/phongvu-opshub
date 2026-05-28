import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_provider.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../data/startup_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StartupSettingsService _startupSettings = StartupSettingsService();

  StartupSettingsSnapshot? _startupSnapshot;
  bool _isLoadingStartup = true;
  bool _isSavingStartup = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _loadStartupSetting();
  }

  Future<void> _loadStartupSetting() async {
    setState(() {
      _isLoadingStartup = true;
      _startupError = null;
    });

    try {
      final snapshot = await _startupSettings.load();
      if (!mounted) return;
      setState(() {
        _startupSnapshot = snapshot;
        _isLoadingStartup = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startupError = 'Không đọc được cài đặt khởi động cùng Windows';
        _isLoadingStartup = false;
      });
    }
  }

  Future<void> _setStartupEnabled(bool enabled) async {
    setState(() {
      _isSavingStartup = true;
      _startupError = null;
    });

    try {
      final snapshot = await _startupSettings.setEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _startupSnapshot = snapshot;
        _isSavingStartup = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Đã bật khởi động cùng Windows'
                : 'Đã tắt khởi động cùng Windows',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _startupError = 'Không cập nhật được cài đặt khởi động cùng Windows';
        _isSavingStartup = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không lưu được cài đặt. Vui lòng thử lại.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientHeader(title: 'Cài đặt', showBack: true),
      body: AppResponsiveScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SettingsSection(
              title: 'Giao diện',
              child: _buildThemeSelector(context),
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Windows',
              child: _buildStartupTile(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartupTile(BuildContext context) {
    final snapshot = _startupSnapshot;
    final isSupported = snapshot?.isSupported ?? true;
    final canToggle = !_isLoadingStartup && !_isSavingStartup && isSupported;
    final isEnabled = snapshot?.isEnabled ?? false;

    return Card(
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
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(_startupSubtitle(snapshot)),
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
    if (!snapshot.isSupported) return 'Chỉ hỗ trợ trên Windows';
    if (snapshot.message != null) return snapshot.message!;
    return snapshot.isEnabled
        ? 'OpsHub sẽ tự mở khi đăng nhập Windows'
        : 'OpsHub không tự mở khi đăng nhập Windows';
  }

  Widget _buildThemeSelector(BuildContext context) {
    final currentMode = context.watch<ThemeProvider>().mode;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Chế độ hiển thị',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkNeutral50
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        onTap: () => themeProvider.setMode(mode),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? Colors.white : colorScheme.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.white : colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
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
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
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
