import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/app_layout.dart';
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
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Cài đặt'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: AppResponsiveScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
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
          style: TextStyle(fontWeight: FontWeight.w800),
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
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
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
          ? const Color(0xFF9CA3AF)
          : isEnabled
          ? const Color(0xFF16A34A)
          : const Color(0xFF6B7280),
    );
  }
}
