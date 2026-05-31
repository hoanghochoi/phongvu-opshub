import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/utils/email_domain_policy.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  List<String> _allowedDomains = const [];

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
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.requestPasswordReset(
      email: _emailController.text.trim(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Nếu email hợp lệ, OpsHub đã gửi link đổi mật khẩu.'
              : authProvider.errorMessage ??
                    'Không gửi được email đổi mật khẩu.',
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
    if (ok) context.go('/login');
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
                          const Text(
                            'Quên mật khẩu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nhập email Phong Vũ để nhận link đổi mật khẩu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            enabled: !authProvider.isLoading,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            onFieldSubmitted: (_) => authProvider.isLoading
                                ? null
                                : _submit(context),
                            decoration: _inputDecoration(
                              label: 'Email',
                              icon: Icons.alternate_email_rounded,
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (!Validators.isValidEmail(email)) {
                                return 'Email không hợp lệ';
                              }
                              if (!EmailDomainPolicy.isAllowedEmail(
                                email,
                                _allowedDomains,
                              )) {
                                return EmailDomainPolicy.invalidDomainMessage;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(
                            height: AppLayoutTokens.formSectionGap,
                          ),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () => _submit(context),
                              icon: authProvider.isLoading
                                  ? SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.grey[600],
                                      ),
                                    )
                                  : const Icon(Icons.mark_email_read_outlined),
                              label: Text(
                                authProvider.isLoading
                                    ? 'Đang gửi...'
                                    : 'Gửi link đổi mật khẩu',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.grey[800],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppLayoutTokens.cardRadius,
                                  ),
                                ),
                              ),
                            ),
                          ),
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
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
