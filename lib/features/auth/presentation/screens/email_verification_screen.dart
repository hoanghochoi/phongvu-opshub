import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String name;
  final String email;
  final String password;

  const EmailVerificationScreen({
    super.key,
    required this.name,
    required this.email,
    required this.password,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  Timer? _timer;
  int _remainingSeconds = 120; // 2 phút = 120 giây
  bool _isProcessing = true;
  bool _hasResult = false;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _callRegisterAPI();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _timer?.cancel();
          }
        });
      }
    });
  }

  Future<void> _callRegisterAPI() async {
    final authProvider = context.read<AuthProvider>();

    // Gọi register API - sẽ đứng chờ response từ n8n (max 150s)
    final success = await authProvider.register(
      widget.email,
      widget.password,
      widget.name,
    );

    if (!mounted) return;

    _timer?.cancel();

    // Gộp tất cả state changes vào 1 setState
    setState(() {
      _isProcessing = false;
      _hasResult = true;
      if (success) {
        _resultMessage = 'Đăng ký thành công! Vui lòng đăng nhập.';
      } else {
        // Lấy message từ server
        _resultMessage = authProvider.errorMessage ?? 'Đăng ký thất bại';
        print('🔍 Display message to user: $_resultMessage');
      }
    });

    if (success) {
      // Đợi 2 giây rồi chuyển về login
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      });
    } else {
      // Đợi 3 giây rồi quay về register
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xác nhận Email'),
        automaticallyImplyLeading: false, // Không cho back trong lúc processing
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isProcessing) ...[
                  Icon(
                    Icons.email_outlined,
                    size: 100,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Kiểm tra email của bạn',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chúng tôi đã gửi email xác nhận đến:',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.email,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Vui lòng click vào link trong email để xác nhận đăng ký.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _remainingSeconds <= 30
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Thời gian còn lại:',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatTime(_remainingSeconds),
                          style:
                              Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _remainingSeconds <= 30
                                        ? Colors.red
                                        : null,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Đang chờ xác nhận...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Chưa nhận được email? Kiểm tra trong thư mục Spam.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_hasResult) ...[
                  // Không dùng Consumer vì _resultMessage là local state
                  Builder(
                    builder: (context) {
                      final isSuccess = _resultMessage?.contains('thành công') ?? false;
                      print('🎨 Building result UI - isSuccess: $isSuccess, message: $_resultMessage');
                      return Column(
                        children: [
                          Icon(
                            isSuccess ? Icons.check_circle : Icons.error,
                            size: 100,
                            color: isSuccess ? Colors.green : Colors.red,
                          ),
                          const SizedBox(height: 32),
                          Text(
                            isSuccess ? 'Đăng ký thành công!' : 'Đăng ký thất bại',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isSuccess ? Colors.green : Colors.red,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          if (_resultMessage != null)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSuccess
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSuccess
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                _resultMessage!,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: isSuccess ? Colors.green[800] : Colors.red[800],
                                    ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 24),
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            isSuccess
                                ? 'Đang chuyển đến trang đăng nhập...'
                                : 'Đang quay về trang đăng ký...',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
