import 'package:email_validator/email_validator.dart';

class Validators {
  Validators._();

  static bool isValidEmail(String email) {
    return EmailValidator.validate(email);
  }

  // Password phải có tối thiểu 8 ký tự, 1 chữ hoa, 1 số, 1 ký tự đặc biệt
  static bool isValidPassword(String password) {
    if (password.length < 8) return false;

    // Kiểm tra có ít nhất 1 chữ hoa
    if (!password.contains(RegExp(r'[A-Z]'))) return false;

    // Kiểm tra có ít nhất 1 số
    if (!password.contains(RegExp(r'[0-9]'))) return false;

    // Kiểm tra có ít nhất 1 ký tự đặc biệt
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;

    return true;
  }

  static String? getPasswordError(String password) {
    final errors = <String>[];

    if (password.length < 8) {
      errors.add('• Ít nhất 8 ký tự');
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      errors.add('• Ít nhất 1 chữ HOA');
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      errors.add('• Ít nhất 1 số');
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      errors.add('• Ít nhất 1 ký tự đặc biệt');
    }

    if (errors.isEmpty) return null;

    return 'Password thiếu:\n${errors.join('\n')}';
  }

  static List<String> getPasswordRequirements(String password) {
    return [
      password.length >= 8 ? '✓ Ít nhất 8 ký tự' : '✗ Ít nhất 8 ký tự',
      password.contains(RegExp(r'[A-Z]')) ? '✓ Ít nhất 1 chữ HOA' : '✗ Ít nhất 1 chữ HOA',
      password.contains(RegExp(r'[0-9]')) ? '✓ Ít nhất 1 số' : '✗ Ít nhất 1 số',
      password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))
          ? '✓ Ít nhất 1 ký tự đặc biệt'
          : '✗ Ít nhất 1 ký tự đặc biệt',
    ];
  }

  // Pattern cho SKU + QTY hoặc chỉ SKU
  static final RegExp messagePatternWithQty = RegExp(r'^[^\s]+\s+\d+$');
  static final RegExp messagePatternSkuOnly = RegExp(r'^[^\s]+$');

  static bool isValidMessage(String message) {
    final trimmed = message.trim().toUpperCase();
    return messagePatternWithQty.hasMatch(trimmed) ||
           messagePatternSkuOnly.hasMatch(trimmed);
  }

  static Map<String, String> parseMessage(String message) {
    final trimmed = message.trim().toUpperCase();
    final parts = trimmed.split(RegExp(r'\s+'));

    if (parts.length == 1) {
      // Chỉ có SKU, mặc định qty = 1
      return {
        'sku': parts[0],
        'qty': '1',
      };
    } else if (parts.length == 2) {
      // Có cả SKU và QTY
      return {
        'sku': parts[0],
        'qty': parts[1],
      };
    } else {
      throw const FormatException('Message phải có định dạng: SKU hoặc SKU SỐ_LƯỢNG');
    }
  }
}
