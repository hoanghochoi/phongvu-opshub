import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_screen_shell.dart';

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
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        return AuthScreenShell(
          child: AuthCard(
            icon: Icons.login_rounded,
            title: 'Đăng nhập',
            subtitle: 'Dùng tài khoản nội bộ để tiếp tục.',
            child: _LoginCard(
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
          ),
        );
      },
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
    return Form(
      key: formKey,
      child: Column(
        children: [
          AppFormTextInput(
            controller: emailController,
            enabled: !isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
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
    );
  }
}
