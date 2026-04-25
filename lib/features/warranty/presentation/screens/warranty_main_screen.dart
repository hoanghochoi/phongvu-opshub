import 'package:flutter/material.dart';
import '../../../../app/widgets/gradient_header.dart';
import '../../../../app/widgets/feature_card.dart';

class WarrantyMainScreen extends StatelessWidget {
  final VoidCallback? onBackToHome;

  const WarrantyMainScreen({
    super.key,
    this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: GradientHeader(
        title: 'Bảo hành / Sửa chữa',
        showBack: onBackToHome == null,
      ),
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

            // Lưu hình ảnh
            FeatureCard(
              icon: Icons.add_photo_alternate_rounded,
              title: 'Lưu hình ảnh',
              description: 'Ghi nhận số biên nhận và hình ảnh sản phẩm BH/SC',
              gradientColors: const [Color(0xFF2E7D32), Color(0xFF43A047), Color(0xFF66BB6A)],
              onTap: () => Navigator.of(context).pushNamed('/warranty'),
            ),
            const SizedBox(height: 16),

            // Xem lại hình ảnh
            FeatureCard(
              icon: Icons.search_rounded,
              title: 'Xem lại hình ảnh',
              description: 'Tìm kiếm và xem lại hình ảnh theo số biên nhận',
              gradientColors: const [Color(0xFF00695C), Color(0xFF00897B), Color(0xFF26A69A)],
              onTap: () => Navigator.of(context).pushNamed('/check-warranty'),
            ),
          ],
        ),
      ),
    );
  }
}
