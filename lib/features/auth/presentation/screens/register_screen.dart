import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  final String? initialEmail;
  const RegisterScreen({super.key, this.initialEmail});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSendingCode = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.trim().isNotEmpty) {
      _emailController.text = widget.initialEmail!.trim();
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
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
                maxWidth: AppLayoutTokens.formMaxWidth,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                    border: Border.all(
                      color: AppColors.surface.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: AppColors.surface,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Đăng ký',
                          style: AppTextStyles.headingL.copyWith(
                            color: AppColors.surface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Dùng email được OpsHub chấp nhận và mật khẩu OpsHub',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyS.copyWith(
                            color: AppColors.surface.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 24),
                        AppFormTextInput(
                          controller: _firstNameController,
                          label: 'Tên hiển thị',
                          icon: Icons.badge_outlined,
                          enabled: !authProvider.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.givenName],
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Vui lòng nhập tên hiển thị';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppFormTextInput(
                          controller: _lastNameController,
                          label: 'Họ hoặc bộ phận (không bắt buộc)',
                          icon: Icons.account_circle_outlined,
                          enabled: !authProvider.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.familyName],
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppFormTextInput(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.alternate_email_rounded,
                          enabled: !authProvider.isLoading && !_isSendingCode,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!Validators.isValidEmail(email)) {
                              return 'Email không hợp lệ';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        AppSecondaryButton(
                          onPressed: authProvider.isLoading || _isSendingCode
                              ? null
                              : () => _handleSendVerificationCode(context),
                          icon: Icons.mark_email_read_rounded,
                          label: 'Gửi mã xác thực email',
                          isLoading: _isSendingCode,
                          loadingLabel: 'Đang gửi mã...',
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppFormTextInput(
                          controller: _verificationCodeController,
                          label: 'Mã xác thực email',
                          icon: Icons.verified_user_outlined,
                          enabled: !authProvider.isLoading && !_isSendingCode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          maxLength: 6,
                          counterText: '',
                          validator: (value) {
                            final code = value?.trim() ?? '';
                            if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
                              return 'Vui lòng nhập mã xác thực gồm 6 số';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppFormTextInput(
                          controller: _passwordController,
                          label: 'Mật khẩu',
                          icon: Icons.lock_rounded,
                          enabled: !authProvider.isLoading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          suffixIcon: IconButton(
                            onPressed: authProvider.isLoading
                                ? null
                                : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                            ),
                          ),
                          validator: (value) {
                            return Validators.getPasswordError(value ?? '');
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        AppFormTextInput(
                          controller: _confirmPasswordController,
                          label: 'Nhập lại mật khẩu',
                          icon: Icons.lock_reset_rounded,
                          enabled: !authProvider.isLoading,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => authProvider.isLoading
                              ? null
                              : _handleRegister(context),
                          suffixIcon: IconButton(
                            onPressed: authProvider.isLoading
                                ? null
                                : () => setState(
                                    () => _obscureConfirmPassword =
                                        !_obscureConfirmPassword,
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
                        ),
                        const SizedBox(height: AppLayoutTokens.formSectionGap),
                        AppPrimaryButton(
                          onPressed: authProvider.isLoading
                              ? null
                              : () => _handleRegister(context),
                          icon: Icons.person_add_alt_1_rounded,
                          label: 'Tạo tài khoản',
                          isLoading: authProvider.isLoading,
                          loadingLabel: 'Đang đăng ký...',
                        ),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        AppDialogSecondaryButton(
                          onPressed: authProvider.isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: Icons.arrow_back_rounded,
                          label: 'Quay lại đăng nhập',
                        ),
                      ],
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

  Future<void> _handleRegister(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      verificationCode: _verificationCodeController.text.trim(),
    );

    if (!context.mounted) return;

    if (success) {
      final route = authProvider.user?.needsOrganizationAssignment == true
          ? '/assignment-pending'
          : '/home';
      context.go(route);
    } else if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _handleSendVerificationCode(BuildContext context) async {
    final email = _emailController.text.trim();
    if (!Validators.isValidEmail(email)) {
      _showError(context, 'Email không hợp lệ');
      return;
    }

    setState(() => _isSendingCode = true);
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.sendRegistrationVerificationCode(
      email: email,
    );

    if (!context.mounted) return;
    setState(() => _isSendingCode = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã gửi mã xác thực. Vui lòng kiểm tra email.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (authProvider.errorMessage != null) {
      _showError(context, authProvider.errorMessage!);
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }
}
