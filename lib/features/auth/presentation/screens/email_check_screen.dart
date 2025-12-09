import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

class EmailCheckScreen extends StatefulWidget {
  const EmailCheckScreen({super.key});

  @override
  State<EmailCheckScreen> createState() => _EmailCheckScreenState();
}

class _EmailCheckScreenState extends State<EmailCheckScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _showPasswordField = false;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    // Auto-focus email field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emailFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleEmailSubmit() async {
    if (_formKey.currentState?.validate() ?? false) {
      final email = _emailController.text.trim();
      final authProvider = context.read<AuthProvider>();

      final status = await authProvider.checkEmail(email);

      if (!mounted) return;

      if (status == null) {
        // Error occurred, show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Lỗi kiểm tra email'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('🔵 [EmailCheckScreen] Received status: "$status"');
      print('🔵 [EmailCheckScreen] Status length: ${status.length}');
      print('🔵 [EmailCheckScreen] Status bytes: ${status.codeUnits}');
      print('🔵 [EmailCheckScreen] Mounted: $mounted');

      setState(() {
        _userEmail = email;
      });

      print('🔵 [EmailCheckScreen] After setState, mounted: $mounted');

      // Status is already lowercase from repository
      switch (status) {
        case 'new':
          // Navigate to registration screen
          if (!mounted) return;
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RegisterScreen(email: email),
            ),
          );

          // If registration successful, clear and go back to email screen
          if (result == true && mounted) {
            _emailController.clear();
            _passwordController.clear();
            setState(() {
              _showPasswordField = false;
              _userEmail = null;
            });
          }
          break;

        case 'yes':
          // Show password field for login
          setState(() {
            _showPasswordField = true;
          });
          break;

        case 'no':
          // Show error message
          print('🔴 [EmailCheckScreen] Entered case "no"');
          print('🔴 [EmailCheckScreen] Mounted before dialog: $mounted');
          if (!mounted) {
            print('❌ [EmailCheckScreen] Widget not mounted, cannot show dialog');
            return;
          }
          print('🔴 [EmailCheckScreen] Showing dialog now...');
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Thông báo'),
              content: const Text('Email chưa được xác minh, vui lòng liên hệ Quản lý.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            ),
          );
          print('🔴 [EmailCheckScreen] Dialog shown successfully');
          break;

        default:
          // Unexpected status
          print('⚠️ [EmailCheckScreen] Unexpected status: "$status"');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Trạng thái không hợp lệ: "$status"'),
              backgroundColor: Colors.orange,
            ),
          );
          break;
      }
    }
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.login(
        _userEmail!,
        _passwordController.text,
      );

      if (!mounted) return;

      if (success) {
        // Navigate to home
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Đăng nhập thất bại'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleBack() {
    setState(() {
      _showPasswordField = false;
      _userEmail = null;
      _passwordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đăng nhập'),
        leading: _showPasswordField
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBack,
              )
            : null,
      ),
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 40),

                    // Logo
                    Image.asset(
                      'assets/images/logo.png',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),

                    // App Name
                    Text(
                      'PhongVu OpsHub',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),

                    // Slogan
                    Text(
                      'Kết nối con người. Đồng bộ vận hành.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                    const SizedBox(height: 48),

                    // Email field
                    TextFormField(
                      controller: _emailController,
                      focusNode: _emailFocusNode,
                      enabled: !_showPasswordField && !authProvider.isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'Nhập email công ty',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleEmailSubmit(),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng nhập email';
                        }
                        if (!value.contains('@')) {
                          return 'Email không hợp lệ';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password field (shown only after email check returns 'yes')
                    if (_showPasswordField) ...[
                      TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        enabled: !authProvider.isLoading,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          hintText: 'Nhập mật khẩu',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleLogin(),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Vui lòng nhập mật khẩu';
                          }
                          // Check for Latin characters only
                          final latinOnly = RegExp(r'^[a-zA-Z0-9!@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?]+$');
                          if (!latinOnly.hasMatch(value)) {
                            return 'Mật khẩu chỉ chấp nhận ký tự Latin không dấu';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    if (!_showPasswordField)
                      const SizedBox(height: 24),

                    // Submit button
                    ElevatedButton(
                      onPressed: authProvider.isLoading
                          ? null
                          : (_showPasswordField ? _handleLogin : _handleEmailSubmit),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: authProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_showPasswordField ? 'Đăng nhập' : 'Tiếp tục'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
