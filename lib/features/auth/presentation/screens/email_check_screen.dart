import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class EmailCheckScreen extends StatefulWidget {
  const EmailCheckScreen({super.key});

  @override
  State<EmailCheckScreen> createState() => _EmailCheckScreenState();
}

class _EmailCheckScreenState extends State<EmailCheckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                maxWidth: AppLayoutTokens.authMaxWidth,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _LogoHeader(),
                    const SizedBox(height: 24),
                    _LoginCard(
                      formKey: _formKey,
                      emailController: _emailController,
                      passwordController: _passwordController,
                      obscurePassword: _obscurePassword,
                      isLoading: authProvider.isLoading,
                      onTogglePassword: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                      onSubmit: () => _handleLogin(context),
                      onForgotPassword: () => context.push('/forgot-password'),
                      onRegister: () => context.push('/register'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '© 2025 PhongVu OpsHub',
                      style: AppTextStyles.labelS.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!context.mounted) return;

    if (success) {
      final route = authProvider.user?.needsOrganizationAssignment == true
          ? '/assignment-pending'
          : '/home';
      context.go(route);
    } else if (authProvider.errorMessage != null) {
      final message = authProvider.errorMessage!;
      if (message.contains('chưa tồn tại') ||
          message.contains('chưa có mật khẩu')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.warning),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (context.mounted) {
          context.push('/register', extra: _emailController.text.trim());
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }
}

class _LogoHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            boxShadow: [
              BoxShadow(
                color: AppColors.surface.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const AppLogo(size: 88, borderRadius: AppRadius.xxl),
        ),
        const SizedBox(height: 18),
        Text(
          'PhongVu OpsHub',
          style: AppTextStyles.headingXL.copyWith(color: AppColors.surface),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Kết nối con người. Đồng bộ vận hành.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyM.copyWith(
            color: AppColors.surface.withValues(alpha: 0.70),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onRegister,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(
          color: AppColors.surface.withValues(alpha: 0.20),
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
        key: formKey,
        child: Column(
          children: [
            Text(
              'Đăng nhập',
              style: AppTextStyles.headingM.copyWith(color: AppColors.surface),
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
              controller: emailController,
              enabled: !isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              label: 'Email',
              icon: Icons.alternate_email_rounded,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!Validators.isValidEmail(email)) {
                  return 'Email không hợp lệ';
                }
                return null;
              },
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            AppFormTextInput(
              controller: passwordController,
              enabled: !isLoading,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => isLoading ? null : onSubmit(),
              label: 'Mật khẩu',
              icon: Icons.lock_rounded,
              suffixIcon: IconButton(
                onPressed: isLoading ? null : onTogglePassword,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Vui lòng nhập mật khẩu';
                }
                return null;
              },
            ),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            AppPrimaryButton(
              onPressed: isLoading ? null : onSubmit,
              icon: Icons.login_rounded,
              label: 'Đăng nhập',
              isLoading: isLoading,
              loadingLabel: 'Đang đăng nhập...',
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            AppDialogSecondaryButton(
              onPressed: isLoading ? null : onForgotPassword,
              icon: Icons.lock_reset_rounded,
              label: 'Quên mật khẩu',
            ),
            AppDialogSecondaryButton(
              onPressed: isLoading ? null : onRegister,
              icon: Icons.person_add_alt_1_rounded,
              label: 'Đăng ký',
            ),
          ],
        ),
      ),
    );
  }
}
