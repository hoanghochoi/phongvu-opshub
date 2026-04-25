import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/feature_card.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class FifoMenuScreen extends StatelessWidget {
  const FifoMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final role = authProvider.user?.role ?? '';
    final isAdmin = role == 'ADMIN' || role == 'SUPER_ADMIN';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: const GradientHeader(title: 'FIFO', showBack: true),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn chức năng',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 20),

            // Check FIFO
            FeatureCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Kiểm tra FIFO',
              description: 'Tra cứu thứ tự FIFO của sản phẩm',
              gradientColors: const [Color(0xFF0277BD), Color(0xFF0288D1), Color(0xFF29B6F6)],
              onTap: () => Navigator.of(context).pushNamed('/chat'),
            ),
            const SizedBox(height: 16),

            // Sắp xếp FIFO
            FeatureCard(
              icon: Icons.swap_vert_rounded,
              title: 'Sắp xếp FIFO',
              description: 'Quét hoặc nhập SKU/BIN để sắp xếp',
              gradientColors: const [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF5C6BC0)],
              onTap: () => Navigator.of(context).pushNamed('/sort'),
            ),

            // Lịch sử FIFO — chỉ hiển thị cho ADMIN/SUPER_ADMIN
            if (isAdmin) ...[
              const SizedBox(height: 16),
              FeatureCard(
                icon: Icons.history_rounded,
                title: 'Lịch sử FIFO',
                description: 'Xem lịch sử kiểm tra & sắp xếp FIFO',
                gradientColors: const [Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                onTap: () => Navigator.of(context).pushNamed('/fifo-history'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
