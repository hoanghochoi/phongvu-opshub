import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_logo.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/utils/email_domain_policy.dart';
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
  List<String> _allowedDomains = const [];
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadDomains();
  }

  Future<void> _loadDomains() async {
    final domains = await EmailDomainPolicy.loadAllowedDomains();
    if (mounted) setState(() => _allowedDomains = domains);
  }

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
                      allowedDomains: _allowedDomains,
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
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
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
          SnackBar(content: Text(message), backgroundColor: Colors.orange[700]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (context.mounted) {
          context.push('/register', extra: _emailController.text.trim());
        }
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
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
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.15),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const AppLogo(size: 88, borderRadius: 28),
        ),
        const SizedBox(height: 18),
        const Text(
          'PhongVu OpsHub',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Kết nối con người. Đồng bộ vận hành.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
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
    required this.allowedDomains,
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
  final List<String> allowedDomains;
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
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            const Text(
              'Đăng nhập',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              EmailDomainPolicy.promptText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: emailController,
              enabled: !isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              decoration: _inputDecoration(
                label: 'Email',
                icon: Icons.alternate_email_rounded,
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!Validators.isValidEmail(email)) {
                  return 'Email không hợp lệ';
                }
                if (!EmailDomainPolicy.isAllowedEmail(email, allowedDomains)) {
                  return EmailDomainPolicy.invalidDomainMessage;
                }
                return null;
              },
            ),
            const SizedBox(height: AppLayoutTokens.formFieldGap),
            TextFormField(
              controller: passwordController,
              enabled: !isLoading,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => isLoading ? null : onSubmit(),
              decoration: _inputDecoration(
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
              ),
              validator: (value) {
                final password = value ?? '';
                return Validators.getPasswordError(password);
              },
            ),
            const SizedBox(height: AppLayoutTokens.formSectionGap),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: isLoading ? null : onSubmit,
                icon: isLoading
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey[600],
                        ),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(
                  isLoading ? 'Đang đăng nhập...' : 'Đăng nhập',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.grey[800],
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppLayoutTokens.formInlineGap),
            TextButton.icon(
              onPressed: isLoading ? null : onForgotPassword,
              icon: const Icon(Icons.lock_reset_rounded),
              label: const Text(
                'Quên mật khẩu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
            TextButton.icon(
              onPressed: isLoading ? null : onRegister,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(
                'Đăng ký',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
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
}
