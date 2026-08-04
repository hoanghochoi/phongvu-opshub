import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_dialogs.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logout_confirmation_dialog.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/network/private_media_headers.dart';
import '../../../../core/utils/validators.dart';
import '../../domain/entities/user.dart';
import '../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _logSource = 'Profile';
  static const _avatarExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  ];

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _firstNameController.text = user?.name ?? '';
    _lastNameController.text = user?.lastName ?? '';
    unawaited(
      AppLogger.instance.info(
        _logSource,
        'Profile screen opened',
        context: {
          'hasUser': user != null,
          'hasAvatar': user?.avatarUrl != null,
        },
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final authProvider = context.read<AuthProvider>();
    await AppLogger.instance.info(_logSource, 'Avatar picker opened');

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _avatarExtensions,
        allowMultiple: false,
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) {
        await AppLogger.instance.info(_logSource, 'Avatar picker cancelled');
        return;
      }

      final path = file.path;
      final bytes = file.bytes;
      if (path == null && bytes == null) {
        await AppLogger.instance.warn(
          'Profile',
          'Avatar picker returned unreadable file',
          context: {'fileName': file.name, 'size': file.size},
        );
        if (mounted) {
          _showMessage('Chưa đọc được file ảnh. Vui lòng chọn ảnh khác.');
        }
        return;
      }

      await AppLogger.instance.info(
        'Profile',
        'Avatar file selected',
        context: {
          'fileName': file.name,
          'size': file.size,
          'hasPath': path != null,
          'hasBytes': bytes != null,
        },
      );
      if (!mounted) return;

      final success = await authProvider.uploadAvatar(
        path: path,
        bytes: bytes,
        fileName: file.name,
      );
      if (!success && mounted) {
        _showMessage(authProvider.errorMessage ?? 'Không cập nhật được avatar');
      }
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        'Profile',
        'Avatar picker crashed',
        error: error,
        stackTrace: stackTrace,
        upload: true,
      );
      if (mounted) {
        _showMessage('Chưa mở được bộ chọn ảnh. Vui lòng thử lại.');
      }
    }
  }

  void _showMessage(String message, {bool success = false}) {
    AppToast.show(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? AppColors.successOf(context)
            : AppColors.errorOf(context),
      ),
    );
  }

  Future<void> _changePassword() async {
    unawaited(
      AppLogger.instance.info(_logSource, 'Change password dialog opened'),
    );
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => const AppDirtyFormGuard(
        source: 'Profile',
        child: _ChangePasswordDialog(),
      ),
    );
    if (!mounted) return;
    if (changed != true) {
      await AppLogger.instance.info(
        _logSource,
        'Change password dialog closed without change',
      );
      return;
    }
    await AppLogger.instance.info(_logSource, 'Change password succeeded');
    if (!mounted) return;
    _showMessage('Đã đổi mật khẩu', success: true);
  }

  Future<void> _save() async {
    final authProvider = context.read<AuthProvider>();
    await AppLogger.instance.info(
      _logSource,
      'Profile save started',
      context: {
        'hasFirstName': _firstNameController.text.trim().isNotEmpty,
        'hasLastName': _lastNameController.text.trim().isNotEmpty,
      },
    );
    final success = await authProvider.updateProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
    );
    if (!mounted) return;
    await AppLogger.instance.info(
      _logSource,
      success ? 'Profile save succeeded' : 'Profile save failed',
      context: {
        'success': success,
        'hasError': authProvider.errorMessage != null,
      },
    );
    if (!mounted) return;
    _showMessage(
      success
          ? 'Đã lưu thông tin cá nhân'
          : authProvider.errorMessage ?? 'Không lưu được',
      success: success,
    );
  }

  Future<void> _logout() async {
    await AppLogger.instance.info(
      _logSource,
      'Profile logout confirmation requested',
    );
    if (!mounted) return;
    final confirmed = await showLogoutConfirmationDialog(context);
    if (!mounted) return;
    if (!confirmed) {
      await AppLogger.instance.info(_logSource, 'Profile logout cancelled');
      return;
    }
    await AppLogger.instance.info(_logSource, 'Profile logout confirmed');
    if (!mounted) return;
    final authProvider = context.read<AuthProvider>();
    await AppLogger.instance.info(_logSource, 'Profile logout started');
    try {
      await authProvider.logout();
      await AppLogger.instance.info(_logSource, 'Profile logout succeeded');
      if (!mounted) return;
      context.go('/login');
    } catch (error, stackTrace) {
      await AppLogger.instance.error(
        _logSource,
        'Profile logout failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showMessage('Chưa đăng xuất được. Vui lòng thử lại.');
    }
  }

  Future<void> _refreshProfile() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.refreshUserData();
    if (!mounted) return;
    final user = authProvider.user;
    setState(() {
      _firstNameController.text = user?.name ?? '';
      _lastNameController.text = user?.lastName ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final avatarUrl = user?.avatarUrl;
    final organizationNodeLabel =
        _nonEmpty(user?.organizationNodeName) ??
        _nonEmpty(user?.organizationNodeId);

    final isLoading = context.watch<AuthProvider>().isLoading;

    return AppResponsiveScrollView(
      padding: _profilePagePadding(context),
      onRefresh: _refreshProfile,
      refreshLogSource: _logSource,
      refreshLogContext: () => {
        'hasUser': user != null,
        'hasAvatar': avatarUrl != null,
      },
      child: Column(
        key: const Key('profile-content'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _profileHeaderHeight(context),
            child: _ProfileHeader(
              user: user,
              avatarUrl: avatarUrl,
              organizationNodeLabel: organizationNodeLabel,
              onPickAvatar: _pickAvatar,
            ),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          SizedBox(
            height: _profileSessionHeight(context),
            child: _ProfileSessionCard(isLoading: isLoading, onLogout: _logout),
          ),
          const SizedBox(height: AppLayoutTokens.cardGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 1000;
              final editCard = SizedBox(
                height: _profileEditHeight(context),
                child: _ProfileEditCard(
                  firstNameController: _firstNameController,
                  lastNameController: _lastNameController,
                  isLoading: isLoading,
                  onChangePassword: _changePassword,
                  onSave: _save,
                ),
              );
              final infoCard = ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: _profileInfoHeight(context),
                ),
                child: _ProfileInfoCard(
                  user: user,
                  organizationNodeLabel: organizationNodeLabel,
                ),
              );

              if (!useTwoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    editCard,
                    const SizedBox(height: AppLayoutTokens.cardGap),
                    infoCard,
                  ],
                );
              }

              const detailsGap = 16.0;
              final infoWidth = constraints.maxWidth >= 1000 ? 430.0 : 0.0;
              final editWidth =
                  constraints.maxWidth -
                  (infoWidth > 0 ? infoWidth + detailsGap : 0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: editWidth, child: editCard),
                  const SizedBox(width: detailsGap),
                  SizedBox(width: infoWidth, child: infoCard),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String? _nonEmpty(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

EdgeInsets _profilePagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= AppLayoutTokens.desktopBreakpoint) {
    return const EdgeInsets.fromLTRB(32, 32, 32, 32);
  }
  return AppLayoutTokens.pagePaddingFor(width);
}

double _profileHeaderHeight(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= AppLayoutTokens.desktopBreakpoint
      ? 114
      : 112;
}

double _profileSessionHeight(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < AppLayoutTokens.compactBreakpoint) return 92;
  if (width >= AppLayoutTokens.desktopBreakpoint) return 80;
  if (width >= AppLayoutTokens.tabletBreakpoint) return 74;
  return 80;
}

double _profileEditHeight(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= AppLayoutTokens.desktopBreakpoint ||
          (width >= AppLayoutTokens.tabletBreakpoint && width < 1200)
      ? 284
      : 292;
}

double _profileInfoHeight(BuildContext context) => 256;

class _ProfileHeader extends StatelessWidget {
  final User? user;
  final String? avatarUrl;
  final String? organizationNodeLabel;
  final VoidCallback onPickAvatar;

  const _ProfileHeader({
    required this.user,
    required this.avatarUrl,
    required this.organizationNodeLabel,
    required this.onPickAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final hasRemoteAvatar =
        avatarUrl != null &&
        (avatarUrl!.startsWith('http://') || avatarUrl!.startsWith('https://'));
    return AppSurfaceCard(
      key: const Key('profile-header'),
      backgroundColor: AppColors.primarySurfaceOf(context),
      borderColor: AppColors.borderOf(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.cardOf(context),
                backgroundImage: hasRemoteAvatar
                    ? NetworkImage(
                        avatarUrl!,
                        headers: privateMediaHeaders(avatarUrl!),
                      )
                    : null,
                onBackgroundImageError: hasRemoteAvatar
                    ? (error, stackTrace) {
                        unawaited(
                          AppLogger.instance.warn(
                            'Profile',
                            'Profile avatar image load failed',
                            context: {
                              'protectedMedia': isProtectedPrivateMediaUrl(
                                avatarUrl!,
                              ),
                              'urlLength': avatarUrl!.length,
                              'errorType': error.runtimeType.toString(),
                            },
                          ),
                        );
                      }
                    : null,
                child: !hasRemoteAvatar
                    ? Text(
                        _profileInitial(user),
                        style: AppTextStyles.headingM.copyWith(
                          color: AppColors.primaryOf(context),
                        ),
                      )
                    : null,
              ),
              _ProfileAvatarAction(onPressed: onPickAvatar),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileDisplayName(user),
                  style: AppTextStyles.headingM,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'Chưa có email',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final chips = [
                      _ProfileStatusChip(
                        label: User.roleDisplayName(user?.role),
                      ),
                      _ProfileStatusChip(
                        label: organizationNodeLabel ?? 'Chưa gán cây tổ chức',
                      ),
                    ];
                    if (constraints.maxWidth < 300) {
                      return Row(
                        children: [
                          Expanded(child: chips[0]),
                          const SizedBox(width: 8),
                          Expanded(child: chips[1]),
                        ],
                      );
                    }
                    return Wrap(spacing: 8, runSpacing: 8, children: chips);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSessionCard extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLogout;

  const _ProfileSessionCard({required this.isLoading, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.errorOf(context);
    final dangerSurface = AppColors.errorSurfaceOf(context);
    return AppSurfaceCard(
      key: const Key('profile-session-card'),
      backgroundColor: dangerSurface,
      borderColor: danger,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copyWidth =
              constraints.maxWidth - AppLayoutTokens.formInlineGap - 116;
          final compactCopy = copyWidth < 400;
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phiên đăng nhập',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelM,
              ),
              const SizedBox(height: 4),
              Text(
                'Đăng xuất khỏi tài khoản trên thiết bị này.',
                maxLines: compactCopy ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (compactCopy
                            ? AppTextStyles.bodyCompact
                            : AppTextStyles.bodyM)
                        .copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
          );
          final logoutButton = _ProfileLogoutButton(
            key: const Key('profile-logout-button'),
            onPressed: isLoading ? null : onLogout,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: copy),
              const SizedBox(width: AppLayoutTokens.formInlineGap),
              SizedBox(width: 116, child: logoutButton),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileEditCard extends StatelessWidget {
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final bool isLoading;
  final VoidCallback onChangePassword;
  final VoidCallback onSave;

  const _ProfileEditCard({
    required this.firstNameController,
    required this.lastNameController,
    required this.isLoading,
    required this.onChangePassword,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('profile-edit-card'),
      child: AppFormColumn(
        spacing: AppLayoutTokens.formInlineGap,
        children: [
          Text('Thông tin hiển thị', style: AppTextStyles.labelL),
          _ProfileInputField(
            controller: firstNameController,
            label: 'Tên',
            icon: Icons.person_outline,
          ),
          _ProfileInputField(
            controller: lastNameController,
            label: 'Họ',
            icon: Icons.badge_outlined,
          ),
          _ProfileActions(
            isLoading: isLoading,
            onChangePassword: onChangePassword,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _ProfileInputField extends StatelessWidget {
  const _ProfileInputField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTextStyles.labelS),
        const SizedBox(height: 8),
        AppTextInput(
          controller: controller,
          label: label,
          icon: icon,
          showLabel: false,
          fixedHeight: 48,
        ),
      ],
    );
  }
}

class _ProfileActions extends StatelessWidget {
  const _ProfileActions({
    required this.isLoading,
    required this.onChangePassword,
    required this.onSave,
  });

  final bool isLoading;
  final VoidCallback onChangePassword;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          width: 138,
          height: 48,
          child: AppSecondaryButton(
            onPressed: isLoading ? null : onChangePassword,
            icon: Icons.lock_reset_outlined,
            label: 'Đổi mật khẩu',
            size: AppButtonSize.medium,
            height: 48,
            expand: true,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          height: 48,
          child: AppPrimaryButton(
            onPressed: isLoading ? null : onSave,
            label: 'Lưu',
            size: AppButtonSize.medium,
            height: 48,
            isLoading: isLoading,
            loadingLabel: 'Lưu',
          ),
        ),
      ],
    );
  }
}

class _ProfileInfoCard extends StatelessWidget {
  final User? user;
  final String? organizationNodeLabel;

  const _ProfileInfoCard({
    required this.user,
    required this.organizationNodeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final storeDetails = user?.assignedStoreDetails.trim();
    return AppSurfaceCard(
      key: const Key('profile-info-card'),
      child: AppFormColumn(
        spacing: AppLayoutTokens.formInlineGap,
        children: [
          Text('Thông tin tài khoản', style: AppTextStyles.labelL),
          _ProfileInfoRow(
            icon: Icons.email_outlined,
            label: 'Email',
            value: user?.email ?? 'Chưa có email',
          ),
          _ProfileInfoRow(
            icon: Icons.verified_user_outlined,
            label: 'Vai trò',
            value: User.roleDisplayName(user?.role),
          ),
          _ProfileInfoRow(
            icon: Icons.account_tree_outlined,
            label: 'Cây tổ chức',
            value: organizationNodeLabel ?? 'Chưa gán cây tổ chức',
          ),
          _ProfileInfoRow(
            icon: Icons.store_outlined,
            label: 'Showroom được gán',
            value: storeDetails?.isNotEmpty == true
                ? storeDetails!
                : 'Chưa được gán Showroom',
          ),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.infoSurfaceOf(context),
            borderRadius: BorderRadius.circular(9),
          ),
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, color: AppColors.primaryOf(context), size: 20),
          ),
        ),
        const SizedBox(width: AppLayoutTokens.formInlineGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.labelS.copyWith(
                  color: AppColors.textMutedOf(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: AppTextStyles.bodyM.copyWith(
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStatusChip extends StatelessWidget {
  final String label;

  const _ProfileStatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.chipBackgroundOf(context),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelS.copyWith(
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}

class _ProfileLogoutButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _ProfileLogoutButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.errorOf(context);
    return AppSecondaryButton(
      onPressed: onPressed,
      icon: Icons.logout_rounded,
      label: 'Đăng xuất',
      foregroundColor: danger,
      borderColor: danger,
      expand: false,
      size: AppButtonSize.medium,
    );
  }
}

class _ProfileAvatarAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileAvatarAction({required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: IconButton(
      tooltip: 'Cập nhật avatar',
      onPressed: onPressed,
      icon: const Icon(Icons.camera_alt_outlined, size: 16),
      color: AppColors.primaryForegroundOf(context),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.primaryOf(context),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
  );
}

String _profileDisplayName(User? user) {
  final parts = [user?.lastName, user?.name]
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (parts.isNotEmpty) return parts.join(' ');
  final email = user?.email.trim();
  if (email != null && email.isNotEmpty) return email;
  return 'Tài khoản OpsHub';
}

String _profileInitial(User? user) {
  final displayName = _profileDisplayName(user);
  return displayName.characters.first.toUpperCase();
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    AppToast.show(
      context,
      SnackBar(
        content: Text(authProvider.errorMessage ?? 'Không đổi được mật khẩu'),
        backgroundColor: AppColors.errorOf(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    return AlertDialog(
      title: const Text('Đổi mật khẩu'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: AppFormColumn(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppFormTextInput(
                  controller: _currentController,
                  enabled: !isLoading,
                  obscureText: _obscureCurrent,
                  label: 'Mật khẩu hiện tại',
                  icon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    onPressed: isLoading
                        ? null
                        : () => setState(
                            () => _obscureCurrent = !_obscureCurrent,
                          ),
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Vui lòng nhập mật khẩu hiện tại'
                      : null,
                ),
                AppFormTextInput(
                  controller: _newController,
                  enabled: !isLoading,
                  obscureText: _obscureNew,
                  label: 'Mật khẩu mới',
                  icon: Icons.lock_reset_outlined,
                  suffixIcon: IconButton(
                    onPressed: isLoading
                        ? null
                        : () => setState(() => _obscureNew = !_obscureNew),
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  validator: (value) =>
                      Validators.getPasswordError(value ?? ''),
                ),
                AppFormTextInput(
                  controller: _confirmController,
                  enabled: !isLoading,
                  obscureText: _obscureConfirm,
                  label: 'Nhập lại mật khẩu mới',
                  icon: Icons.lock_reset_outlined,
                  suffixIcon: IconButton(
                    onPressed: isLoading
                        ? null
                        : () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  validator: (value) => value != _newController.text
                      ? 'Mật khẩu nhập lại chưa khớp'
                      : null,
                  onFieldSubmitted: (_) => isLoading ? null : _submit(),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        AppDialogCancelButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(false),
          label: 'Hủy',
        ),
        AppDialogConfirmButton(
          onPressed: isLoading ? null : _submit,
          label: isLoading ? 'Đang đổi...' : 'Đổi mật khẩu',
          isLoading: isLoading,
        ),
      ],
    );
  }
}
