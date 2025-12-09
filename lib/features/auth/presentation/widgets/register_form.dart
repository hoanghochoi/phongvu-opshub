import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_button.dart';

class RegisterForm extends StatefulWidget {
  final String email;

  const RegisterForm({super.key, required this.email});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Real-time validation state
  String? _passwordError;
  String? _confirmPasswordError;
  bool _hasUppercase = false;
  bool _hasSpecialChar = false;
  bool _hasNumber = false;
  bool _hasMinLength = false;
  bool _passwordFieldFocused = false;

  @override
  void initState() {
    super.initState();
    _passwordFocusNode.addListener(_onPasswordFocusChange);
    // Auto-focus password field when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordFocusNode.removeListener(_onPasswordFocusChange);
    _passwordFocusNode.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordFocusChange() {
    setState(() {
      _passwordFieldFocused = _passwordFocusNode.hasFocus;
      // Initialize validation when field gets focus
      if (_passwordFieldFocused && _passwordController.text.isEmpty) {
        _validatePassword('');
      }
    });
  }

  /// Validate password in real-time
  void _validatePassword(String value) {
    setState(() {
      // Check for non-Latin characters (Vietnamese diacritics, etc.)
      final latinOnly = RegExp(r'^[a-zA-Z0-9!@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?]*$');
      if (!latinOnly.hasMatch(value)) {
        _passwordError = 'Chỉ chấp nhận ký tự Latin không dấu';
        _hasUppercase = false;
        _hasSpecialChar = false;
        _hasNumber = false;
        _hasMinLength = false;
        return;
      }

      // Check individual requirements
      _hasUppercase = RegExp(r'[A-Z]').hasMatch(value);
      _hasSpecialChar = RegExp(r'[!@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?]').hasMatch(value);
      _hasNumber = RegExp(r'[0-9]').hasMatch(value);
      _hasMinLength = value.length > 8;

      // Build error message
      final List<String> errors = [];
      if (!_hasMinLength) errors.add('trên 8 ký tự');
      if (!_hasUppercase) errors.add('1 chữ hoa');
      if (!_hasNumber) errors.add('1 số');
      if (!_hasSpecialChar) errors.add('1 ký tự đặc biệt');

      if (errors.isEmpty) {
        _passwordError = null;
      } else {
        _passwordError = 'Thiếu: ${errors.join(', ')}';
      }

      // Also validate confirm password when password changes
      _validateConfirmPassword(_confirmPasswordController.text);
    });
  }

  /// Validate confirm password in real-time
  void _validateConfirmPassword(String value) {
    setState(() {
      if (value.isEmpty) {
        _confirmPasswordError = null;
      } else if (value != _passwordController.text) {
        _confirmPasswordError = 'Mật khẩu không khớp';
      } else {
        _confirmPasswordError = null;
      }
    });
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState?.validate() ?? false) {
      final password = _passwordController.text;

      final authProvider = context.read<AuthProvider>();

      // Register without name (send empty string)
      final success = await authProvider.register(widget.email, password, '');

      if (!mounted) return;

      if (success) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng ký thành công! Vui lòng đăng nhập.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Wait 2 seconds then return to email screen
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.of(context).pop(true); // Return true to indicate success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Đăng ký thất bại'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Password
          TextFormField(
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: _obscurePassword,
            onChanged: _validatePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              hintText: 'Nhập mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              errorText: _passwordError,
              errorMaxLines: 2,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập mật khẩu';
              }
              // Return current error if exists
              return _passwordError;
            },
          ),

          // Password requirements checklist
          // Show when field is focused OR has text
          if (_passwordFieldFocused || _passwordController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PasswordRequirements(
              hasMinLength: _hasMinLength,
              hasUppercase: _hasUppercase,
              hasNumber: _hasNumber,
              hasSpecialChar: _hasSpecialChar,
            ),
          ],

          const SizedBox(height: 16),

          // Confirm Password
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            onChanged: _validateConfirmPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleRegister(),
            decoration: InputDecoration(
              labelText: 'Xác nhận mật khẩu',
              hintText: 'Nhập lại mật khẩu',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              errorText: _confirmPasswordError,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng xác nhận mật khẩu';
              }
              // Return current error if exists
              return _confirmPasswordError;
            },
          ),
          const SizedBox(height: 24),

          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return LoginButton(
                onPressed: _handleRegister,
                isLoading: authProvider.isLoading,
                text: 'Đăng ký',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Widget to show password requirements checklist
class _PasswordRequirements extends StatelessWidget {
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasNumber;
  final bool hasSpecialChar;

  const _PasswordRequirements({
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasNumber,
    required this.hasSpecialChar,
  });

  @override
  Widget build(BuildContext context) {
    // Build list of unmet requirements only
    final List<Widget> unmetRequirements = [];

    if (!hasMinLength) {
      unmetRequirements.add(_RequirementItem(label: 'Trên 8 ký tự', met: false));
    }
    if (!hasUppercase) {
      unmetRequirements.add(_RequirementItem(label: 'Ít nhất 1 chữ hoa (A-Z)', met: false));
    }
    if (!hasNumber) {
      unmetRequirements.add(_RequirementItem(label: 'Ít nhất 1 số (0-9)', met: false));
    }
    if (!hasSpecialChar) {
      unmetRequirements.add(_RequirementItem(label: 'Ít nhất 1 ký tự đặc biệt (!@#\$...)', met: false));
    }

    // If all requirements met, don't show the box
    if (unmetRequirements.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Còn thiếu:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 4),
          ...unmetRequirements,
        ],
      ),
    );
  }
}

/// Individual requirement item with checkmark
class _RequirementItem extends StatelessWidget {
  final String label;
  final bool met;

  const _RequirementItem({
    required this.label,
    required this.met,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(
            Icons.cancel,
            size: 16,
            color: Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}
