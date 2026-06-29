import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../domain/entities/vietqr_transfer.dart';

class QrWithLogo extends StatelessWidget {
  final double size;
  final VietQrTransfer transfer;

  const QrWithLogo({super.key, required this.size, required this.transfer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            QrImageView(
              data: transfer.qrPayload,
              version: QrVersions.auto,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              size: size,
              backgroundColor: AppColors.surface,
            ),
            Container(
              width: size * 0.24,
              height: size * 0.24,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
                child: Image.asset(
                  transfer.qrBrand.logoAsset,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
