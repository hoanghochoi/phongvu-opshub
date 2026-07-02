import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/widgets/app_cards.dart';
import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../core/logging/app_logger.dart';

class PaymentMonitorUnsupportedScreen extends StatefulWidget {
  const PaymentMonitorUnsupportedScreen({super.key});

  @override
  State<PaymentMonitorUnsupportedScreen> createState() =>
      _PaymentMonitorUnsupportedScreenState();
}

class _PaymentMonitorUnsupportedScreenState
    extends State<PaymentMonitorUnsupportedScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_logUnsupportedAccess());
  }

  Future<void> _logUnsupportedAccess() {
    return AppLogger.instance.warn(
      'PaymentMonitor',
      'Payment monitor unsupported platform screen shown',
      context: {'platform': defaultTargetPlatform.name, 'isWeb': kIsWeb},
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppResponsiveScrollView(
      maxWidth: AppLayoutTokens.formMaxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _UnsupportedHeader(),
          const SizedBox(height: AppLayoutTokens.sectionGap),
          AppSurfaceCard(
            key: const Key('payment-monitor-unsupported-card'),
            child: AppStatePanel(
              icon: Icons.web_asset_off_outlined,
              title: 'Chưa hỗ trợ trên web',
              message:
                  'Vui lòng dùng app Android hoặc Windows để theo dõi tiền vào. Riêng đọc loa thanh toán chỉ chạy trên Windows.',
              tone: AppStateTone.warning,
              actionLabel: 'Về trang chủ',
              actionIcon: Icons.home_rounded,
              onAction: () => context.go('/home'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedHeader extends StatelessWidget {
  const _UnsupportedHeader();

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      key: const Key('payment-monitor-unsupported-header'),
      backgroundColor: AppColors.warningSurface.withValues(alpha: 0.72),
      borderColor: AppColors.warning.withValues(alpha: 0.24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.volume_off_outlined, color: AppColors.warning),
            ),
          ),
          const SizedBox(width: AppLayoutTokens.formInlineGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theo dõi tiền vào', style: AppTextStyles.headingM),
                const SizedBox(height: 6),
                Text(
                  'Thiết bị hiện tại chỉ xem được thông báo hạn chế. Luồng loa thanh toán cần chạy trên Windows.',
                  style: AppTextStyles.bodyM.copyWith(
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: AppLayoutTokens.formInlineGap),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _UnsupportedChip(
                      icon: Icons.devices_other_outlined,
                      label: kIsWeb
                          ? 'Web'
                          : defaultTargetPlatform.name.toUpperCase(),
                    ),
                    const _UnsupportedChip(
                      icon: Icons.warning_amber_rounded,
                      label: 'Chưa hỗ trợ loa',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _UnsupportedChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppLayoutTokens.cardRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.warning),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelS.copyWith(
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
