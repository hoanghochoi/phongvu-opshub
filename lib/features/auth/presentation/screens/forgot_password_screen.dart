import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Ở lại'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Đăng ký tài khoản'),
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
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        AppLayoutTokens.cardRadius,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lock_reset_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
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
                            TextButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () => _sendCode(context),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Gửi lại mã'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppLayoutTokens.formInlineGap),
                          TextButton.icon(
                            onPressed: authProvider.isLoading
                                ? null
                                : () => context.go('/login'),
                            icon: const Icon(Icons.arrow_back_rounded),
                            label: const Text('Quay lại đăng nhập'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                            ),
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
    return TextFormField(
      controller: _emailController,
      enabled: !authProvider.isLoading && _step == _ResetStep.email,
      keyboardType: TextInputType.emailAddress,
      textInputAction: _step == _ResetStep.email
          ? TextInputAction.done
          : TextInputAction.next,
      autocorrect: false,
      autofillHints: const [AutofillHints.username, AutofillHints.email],
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      decoration: _inputDecoration(
        label: 'Email',
        icon: Icons.alternate_email_rounded,
      ),
      validator: (value) {
        final email = value?.trim() ?? '';
        if (!Validators.isValidEmail(email)) return 'Email không hợp lệ';
        return null;
      },
    );
  }

  Widget _codeField(AuthProvider authProvider) {
    return TextFormField(
      controller: _codeController,
      enabled: !authProvider.isLoading,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: 6,
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      decoration: _inputDecoration(
        label: 'Mã xác thực email',
        icon: Icons.verified_user_outlined,
      ).copyWith(counterText: ''),
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
    return TextFormField(
      controller: _passwordController,
      enabled: !authProvider.isLoading,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.newPassword],
      decoration: _inputDecoration(
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
      ),
      validator: (value) => Validators.getPasswordError(value ?? ''),
    );
  }

  Widget _confirmPasswordField(AuthProvider authProvider) {
    return TextFormField(
      controller: _confirmPasswordController,
      enabled: !authProvider.isLoading,
      obscureText: _obscureConfirmPassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      onFieldSubmitted: (_) => authProvider.isLoading ? null : _submit(context),
      decoration: _inputDecoration(
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
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: authProvider.isLoading ? null : () => _submit(context),
        icon: authProvider.isLoading
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey[600],
                ),
              )
            : Icon(_buttonIcon),
        label: Text(
          authProvider.isLoading ? 'Đang xử lý...' : _buttonText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.grey[800],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        borderSide: BorderSide.none,
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      errorMaxLines: 4,
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
        backgroundColor: success ? Colors.green : Colors.red,
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
