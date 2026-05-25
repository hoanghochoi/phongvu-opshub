import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../core/utils/email_domain_policy.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

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
  List<String> _allowedDomains = const [];
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isSendingCode = false;
  bool _loadedRouteEmail = false;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadedRouteEmail) return;
    _loadedRouteEmail = true;
    final routeEmail = ModalRoute.of(context)?.settings.arguments;
    if (routeEmail is String && routeEmail.trim().isNotEmpty) {
      _emailController.text = routeEmail.trim();
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
        decoration: const BoxDecoration(gradient: GradientHeader.gradient),
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
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppLayoutTokens.cardRadius,
                    ),
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
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Đăng ký',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
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
                          controller: _firstNameController,
                          enabled: !authProvider.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.givenName],
                          decoration: _inputDecoration(
                            label: 'Tên hiển thị',
                            icon: Icons.badge_outlined,
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Vui lòng nhập tên hiển thị';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextFormField(
                          controller: _lastNameController,
                          enabled: !authProvider.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.familyName],
                          decoration: _inputDecoration(
                            label: 'Họ hoặc bộ phận (không bắt buộc)',
                            icon: Icons.account_circle_outlined,
                          ),
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextFormField(
                          controller: _emailController,
                          enabled: !authProvider.isLoading && !_isSendingCode,
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
                            if (!EmailDomainPolicy.isAllowedEmail(
                              email,
                              _allowedDomains,
                            )) {
                              return EmailDomainPolicy.invalidDomainMessage;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formInlineGap),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: authProvider.isLoading || _isSendingCode
                                ? null
                                : () => _handleSendVerificationCode(context),
                            icon: _isSendingCode
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.mark_email_read_rounded),
                            label: Text(
                              _isSendingCode
                                  ? 'Đang gửi mã...'
                                  : 'Gửi mã xác thực email',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextFormField(
                          controller: _verificationCodeController,
                          enabled: !authProvider.isLoading && !_isSendingCode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          maxLength: 6,
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
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !authProvider.isLoading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: _inputDecoration(
                            label: 'Mật khẩu',
                            icon: Icons.lock_rounded,
                            suffixIcon: IconButton(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded,
                              ),
                            ),
                          ),
                          validator: (value) {
                            return Validators.getPasswordError(value ?? '');
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formFieldGap),
                        TextFormField(
                          controller: _confirmPasswordController,
                          enabled: !authProvider.isLoading,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => authProvider.isLoading
                              ? null
                              : _handleRegister(context),
                          decoration: _inputDecoration(
                            label: 'Nhập lại mật khẩu',
                            icon: Icons.lock_reset_rounded,
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
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Mật khẩu nhập lại chưa khớp';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppLayoutTokens.formSectionGap),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton.icon(
                            onPressed: authProvider.isLoading
                                ? null
                                : () => _handleRegister(context),
                            icon: authProvider.isLoading
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.grey[600],
                                    ),
                                  )
                                : const Icon(Icons.person_add_alt_1_rounded),
                            label: Text(
                              authProvider.isLoading
                                  ? 'Đang đăng ký...'
                                  : 'Tạo tài khoản',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.grey[800],
                              disabledBackgroundColor: Colors.white.withValues(
                                alpha: 0.7,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
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
                          onPressed: authProvider.isLoading
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text(
                            'Quay lại đăng nhập',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
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
      final route = authProvider.user?.needsStoreSelection == true
          ? '/select-store'
          : '/home';
      Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);
    } else if (authProvider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage!),
          backgroundColor: Colors.red,
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
    if (!EmailDomainPolicy.isAllowedEmail(email, _allowedDomains)) {
      _showError(context, EmailDomainPolicy.invalidDomainMessage);
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
          backgroundColor: Colors.green,
        ),
      );
    } else if (authProvider.errorMessage != null) {
      _showError(context, authProvider.errorMessage!);
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
