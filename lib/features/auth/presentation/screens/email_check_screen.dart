import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:phongvu_opshub/app/widgets/app_toast.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_buttons.dart';
import '../../../../app/widgets/app_controls.dart';
import '../../../../app/widgets/app_inputs.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../core/logging/app_logger.dart';
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
  bool _rememberPassword = false;
  bool _rememberedLoginLoading = true;
  bool _rememberedLoginActionLoading = false;
  String? _rememberedLoginError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadRememberedLogin());
    });
  }

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
          child: LoginCard(
            icon: PhosphorIconsRegular.signIn,
            title: 'Đăng nhập',
            subtitle: 'Dùng tài khoản nội bộ để tiếp tục.',
            child: LoginForm(
              formKey: _formKey,
              emailController: _emailController,
              passwordController: _passwordController,
              obscurePassword: _obscurePassword,
              rememberPassword: _rememberPassword,
              rememberPasswordLoading:
                  _rememberedLoginLoading || _rememberedLoginActionLoading,
              rememberPasswordError: _rememberedLoginError,
              isLoading: authProvider.isLoading,
              onTogglePassword: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              onRememberPasswordChanged: _handleRememberPasswordChanged,
              onSubmit: () => _handleLogin(context),
              onForgotPassword: () => context.push('/forgot-password'),
              onRegister: () => context.push('/register'),
              onHelp: () => _openHelp(context),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadRememberedLogin() async {
    final authProvider = context.read<AuthProvider>();
    try {
      final remembered = await authProvider.readRememberedLogin();
      if (!mounted) return;
      final hasUserInput =
          _emailController.text.isNotEmpty ||
          _passwordController.text.isNotEmpty;
      if (remembered != null && !hasUserInput) {
        _emailController.text = remembered.email;
        _passwordController.text = remembered.password;
        _rememberPassword = true;
      }
      setState(() => _rememberedLoginLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rememberedLoginLoading = false;
        _rememberPassword = false;
        _rememberedLoginError =
            'Không đọc được mật khẩu đã lưu. Bạn vẫn có thể đăng nhập bình thường.';
      });
    }
  }

  Future<void> _handleRememberPasswordChanged(bool value) async {
    if (value) {
      setState(() {
        _rememberPassword = true;
        _rememberedLoginError = null;
      });
      unawaited(
        AppLogger.instance.info(
          'Auth',
          'Remembered credential preference enabled',
          context: {'source': 'login'},
        ),
      );
      return;
    }

    setState(() => _rememberedLoginActionLoading = true);
    final cleared = await context.read<AuthProvider>().clearRememberedLogin();
    if (!mounted) return;
    setState(() {
      _rememberedLoginActionLoading = false;
      if (cleared) {
        _rememberPassword = false;
        _rememberedLoginError = null;
      } else {
        _rememberPassword = true;
        _rememberedLoginError =
            'Chưa xóa được mật khẩu đã lưu. Hãy thử lại khi thiết bị sẵn sàng.';
      }
    });
    if (!cleared) {
      AppToast.show(
        context,
        SnackBar(
          content: Text(_rememberedLoginError!),
          backgroundColor: AppColors.errorOf(context),
        ),
      );
    }
  }

  Future<void> _openHelp(BuildContext context) async {
    unawaited(
      AppLogger.instance.info(
        'Auth',
        'Help route opened from login screen',
        context: {'source': 'login'},
      ),
    );
    context.go('/help');
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
      if (_rememberPassword) {
        final saved = await authProvider.saveRememberedLogin(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!saved && context.mounted) {
          setState(() {
            _rememberPassword = false;
            _rememberedLoginError =
                'Đăng nhập thành công nhưng chưa lưu được mật khẩu. Bạn có thể thử lại sau.';
          });
          AppToast.show(
            context,
            SnackBar(
              content: Text(_rememberedLoginError!),
              backgroundColor: AppColors.warningOf(context),
            ),
          );
        }
      }
      if (!context.mounted) return;
      final route = authProvider.user?.needsOrganizationAssignment == true
          ? '/assignment-pending'
          : '/home';
      context.go(route);
    } else if (authProvider.errorMessage != null) {
      final message = authProvider.errorMessage!;
      if (message.contains('chưa tồn tại') ||
          message.contains('chưa có mật khẩu')) {
        AppToast.show(
          context,
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.warningOf(context),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (context.mounted) {
          context.push('/register', extra: _emailController.text.trim());
        }
        return;
      }
      AppToast.show(
        context,
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.errorOf(context),
        ),
      );
    }
  }
}

class LoginForm extends StatelessWidget {
  const LoginForm({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.rememberPassword,
    required this.rememberPasswordLoading,
    required this.rememberPasswordError,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onRememberPasswordChanged,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onRegister,
    required this.onHelp,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool rememberPassword;
  final bool rememberPasswordLoading;
  final String? rememberPasswordError;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberPasswordChanged;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Biểu mẫu đăng nhập',
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            children: [
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
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: isLoading ? null : onTogglePassword,
                  icon: Icon(
                    obscurePassword
                        ? PhosphorIconsRegular.eye
                        : PhosphorIconsRegular.eyeSlash,
                    size: 20,
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  return null;
                },
              ),
              AppCheckbox(
                value: rememberPassword,
                label: 'Nhớ mật khẩu',
                tooltip: 'Tự điền thông tin đăng nhập lần sau',
                onChanged: isLoading || rememberPasswordLoading
                    ? null
                    : onRememberPasswordChanged,
              ),
              if (rememberPasswordError != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      rememberPasswordError!,
                      style: AppTextStyles.bodyS.copyWith(
                        color: AppColors.warningOf(context),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppLayoutTokens.formSectionGap),
              AppPrimaryButton(
                onPressed: isLoading ? null : onSubmit,
                icon: PhosphorIconsRegular.signIn,
                label: 'Đăng nhập',
                isLoading: isLoading,
                loadingLabel: 'Đang đăng nhập...',
                height: AppLayoutTokens.authControlHeight,
                radius: AppLayoutTokens.authControlRadius,
              ),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              const _AuthOrDivider(),
              const SizedBox(height: AppLayoutTokens.formInlineGap),
              AuthSecondaryActions(
                isLoading: isLoading,
                onForgotPassword: onForgotPassword,
                onRegister: onRegister,
                onHelp: onHelp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthSecondaryActions extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onForgotPassword;
  final VoidCallback onRegister;
  final VoidCallback onHelp;

  const AuthSecondaryActions({
    super.key,
    required this.isLoading,
    required this.onForgotPassword,
    required this.onRegister,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLinkButton(
                onPressed: isLoading ? null : onForgotPassword,
                icon: PhosphorIconsRegular.lockKey,
                label: 'Quên mật khẩu',
                tooltip: 'Mở luồng đổi mật khẩu',
                compact: true,
              ),
              const _AuthActionDivider(),
              AppLinkButton(
                onPressed: isLoading ? null : onRegister,
                icon: PhosphorIconsRegular.userPlus,
                label: 'Đăng ký',
                tooltip: 'Đăng ký tài khoản OpsHub',
                compact: true,
              ),
              const _AuthActionDivider(),
              AppLinkButton(
                onPressed: isLoading ? null : onHelp,
                icon: PhosphorIconsRegular.bookOpen,
                label: 'Hướng dẫn',
                tooltip: 'Mở hướng dẫn sử dụng',
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthOrDivider extends StatelessWidget {
  const _AuthOrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.subtleBorderOf(context))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'hoặc',
            style: AppTextStyles.bodyS.copyWith(
              color: AppColors.textMutedOf(context),
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.subtleBorderOf(context))),
      ],
    );
  }
}

class _AuthActionDivider extends StatelessWidget {
  const _AuthActionDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: VerticalDivider(
        width: 8,
        thickness: 1,
        color: AppColors.subtleBorderOf(context),
      ),
    );
  }
}
