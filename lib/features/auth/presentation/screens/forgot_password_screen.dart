import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

enum _ResetStep { email, code, password }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _ResetStep _step = _ResetStep.email;
  String? _resetToken;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    switch (_step) {
      case _ResetStep.email:
        await _sendCode(context);
        return;
      case _ResetStep.code:
        await _verifyCode(context);
        return;
      case _ResetStep.password:
        await _resetPassword(context);
        return;
    }
  }

  Future<void> _sendCode(BuildContext context) async {
    final email = _emailController.text.trim();
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.requestPasswordReset(email: email);
    if (!context.mounted) return;
    if (ok) {
      setState(() {
        _step = _ResetStep.code;
        _resetToken = null;
        _codeController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
      });
      _showSnack(
        context,
        'Nếu email hợp lệ, OpsHub đã gửi mã đổi mật khẩu. Mã hết hạn sau 10 phút.',
        success: true,
      );
    } else if (authProvider.passwordResetAccountMissing) {
      await _showMissingAccountDialog(
        context,
        email,
        authProvider.errorMessage,
      );
    } else {
      _showSnack(
        context,
        authProvider.errorMessage ?? 'Không gửi được mã đổi mật khẩu.',
      );
    }
  }

  Future<void> _showMissingAccountDialog(
    BuildContext context,
    String email,
    String? message,
  ) async {
    await AppLogger.instance.warn(
      'Auth',
      'Password reset missing account dialog shown',
      context: {'email': email},
    );
    if (!context.mounted) return;

    final goRegister = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Chưa có tài khoản'),
          content: Text(
            message ??
                'Email này chưa có tài khoản OpsHub. Vui lòng đăng ký tài khoản trước.',
          ),
          actions: [
            AppDialogCancelButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              label: 'Ở lại',
            ),
            AppDialogConfirmButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: Icons.person_add_alt_1_rounded,
              label: 'Đăng ký tài khoản',
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;
    if (goRegister == true) {
      final router = GoRouter.of(context);
      await AppLogger.instance.info(
        'Auth',
        'Password reset missing account register navigation selected',
        context: {'email': email},
      );
      router.go('/register', extra: email);
    } else {
      await AppLogger.instance.info(
        'Auth',
        'Password reset missing account dialog dismissed',
        context: {'email': email},
      );
    }
  }

  Future<void> _verifyCode(BuildContext context) async {
    final email = _emailController.text.trim();
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.verifyPasswordResetCode(
      email: email,
      code: _codeController.text.trim(),
    );
    if (!context.mounted) return;
    if (token != null) {
      setState(() {
        _resetToken = token;
        _step = _ResetStep.password;
      });
    } else {
      _showSnack(
        context,
        authProvider.errorMessage ?? 'Mã xác thực chưa hợp lệ.',
      );
    }
  }

  Future<void> _resetPassword(BuildContext context) async {
    final token = _resetToken;
    if (token == null || token.isEmpty) {
      _showSnack(context, 'Vui lòng xác thực email lại.');
      setState(() => _step = _ResetStep.code);
      return;
    }

    final email = _emailController.text.trim();
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.resetForgottenPassword(
      email: email,
      resetToken: token,
      newPassword: _passwordController.text,
    );
    if (!context.mounted) return;
    if (ok) {
      _showSnack(
        context,
        'Đã đổi mật khẩu. Vui lòng đăng nhập lại.',
        success: true,
      );
      context.go('/login');
    } else {
      _showSnack(
        context,
        authProvider.errorMessage ?? 'Không đổi được mật khẩu.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: GradientHeader.getGradient(context),
        ),
        child: SafeArea(
          child: Consumer<AuthProvider>(
            builder: (context, authProvider, _) {
              return AppResponsiveScrollView(
                maxWidth: AppLayoutTokens.authMaxWidth,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppLayoutTokens.cardRadius,
                      ),
                      border: Border.all(
                        color: AppColors.surface.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lock_reset_rounded,
                            color: AppColors.surface,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.headingL.copyWith(
                              color: AppColors.surface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _subtitle,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyS.copyWith(
                              color: AppColors.surface.withValues(alpha: 0.72),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _emailField(authProvider),
                          if (_step == _ResetStep.code) ...[
                            const SizedBox(
                              height: AppLayoutTokens.formFieldGap,
                            ),
                            _codeField(authProvider),
                          ],
                          if (_step == _ResetStep.password) ...[
                            const SizedBox(
                              height: AppLayoutTokens.formFieldGap,
                            ),
                            _passwordField(authProvider),
                            const SizedBox(
                              height: AppLayoutTokens.formFieldGap,
                            ),
                            _confirmPasswordField(authProvider),
                          ],
                          const SizedBox(
                            height: AppLayoutTokens.formSectionGap,
                          ),
                          _primaryButton(context, authProvider),
                          if (_step == _ResetStep.code) ...[
                            const SizedBox(
                              height: AppLayoutTokens.formInlineGap,
                            ),
                            AppDialogSecondaryButton(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () => _sendCode(context),
                              icon: Icons.refresh_rounded,
                              label: 'Gửi lại mã',
                            ),
                          ],
                          const SizedBox(height: AppLayoutTokens.formInlineGap),
                          AppDialogSecondaryButton(
                            onPressed: authProvider.isLoading
                                ? null
                                : () => context.go('/login'),
                            icon: Icons.arrow_back_rounded,
                            label: 'Quay lại đăng nhập',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _emailField(AuthProvider authProvider) {
    return AppFormTextInput(
      controller: _emailController,
      enabled: !authProvider.isLoading && _step == _ResetStep.email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: _step == _ResetStep.email
          ? TextInputAction.done
          : TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      label: 'Email',
      icon: Icons.alternate_email_rounded,
      validator: (value) {
        final email = value?.trim() ?? '';
        if (!Validators.isValidEmail(email)) return 'Email không hợp lệ';
        return null;
      },
    );
  }

  Widget _codeField(AuthProvider authProvider) {
    return AppFormTextInput(
      controller: _codeController,
      enabled: !authProvider.isLoading,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: 6,
      counterText: '',
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      label: 'Mã xác thực email',
      icon: Icons.verified_user_outlined,
      validator: (value) {
        final code = value?.trim() ?? '';
        if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
          return 'Vui lòng nhập mã xác thực gồm 6 số';
        }
        return null;
      },
    );
  }

  Widget _passwordField(AuthProvider authProvider) {
    return AppFormTextInput(
      controller: _passwordController,
      enabled: !authProvider.isLoading,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      label: 'Mật khẩu mới',
      icon: Icons.lock_rounded,
      suffixIcon: IconButton(
        onPressed: authProvider.isLoading
            ? null
            : () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
        ),
      ),
      validator: (value) => Validators.getPasswordError(value ?? ''),
    );
  }

  Widget _confirmPasswordField(AuthProvider authProvider) {
    return AppFormTextInput(
      controller: _confirmPasswordController,
      enabled: !authProvider.isLoading,
      obscureText: _obscureConfirmPassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      label: 'Nhập lại mật khẩu mới',
      icon: Icons.lock_reset_rounded,
      suffixIcon: IconButton(
        onPressed: authProvider.isLoading
            ? null
            : () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
        icon: Icon(
          _obscureConfirmPassword
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
        ),
      ),
      validator: (value) {
        if (value != _passwordController.text) {
          return 'Mật khẩu nhập lại chưa khớp';
        }
        return null;
      },
    );
  }

  Widget _primaryButton(BuildContext context, AuthProvider authProvider) {
    return AppPrimaryButton(
      onPressed: authProvider.isLoading ? null : () => _submit(context),
      icon: _buttonIcon,
      label: _buttonText,
      isLoading: authProvider.isLoading,
      loadingLabel: 'Đang xử lý...',
    );
  }

  void _showSnack(
    BuildContext context,
    String message, {
    bool success = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  String get _title {
    switch (_step) {
      case _ResetStep.email:
        return 'Quên mật khẩu';
      case _ResetStep.code:
        return 'Xác thực email';
      case _ResetStep.password:
        return 'Mật khẩu mới';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _ResetStep.email:
        return 'Nhập email Phong Vũ để nhận mã đổi mật khẩu.';
      case _ResetStep.code:
        return 'Nhập mã 6 số trong email. Mã hết hạn sau 10 phút.';
      case _ResetStep.password:
        return 'Tạo mật khẩu mới rồi đăng nhập lại vào OpsHub.';
    }
  }

  String get _buttonText {
    switch (_step) {
      case _ResetStep.email:
        return 'Gửi mã đổi mật khẩu';
      case _ResetStep.code:
        return 'Xác thực mã';
      case _ResetStep.password:
        return 'Đổi mật khẩu';
    }
  }

  IconData get _buttonIcon {
    switch (_step) {
      case _ResetStep.email:
        return Icons.mark_email_read_outlined;
      case _ResetStep.code:
        return Icons.verified_outlined;
      case _ResetStep.password:
        return Icons.lock_reset_rounded;
    }
  }
}
