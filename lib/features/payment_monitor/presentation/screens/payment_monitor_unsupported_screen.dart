import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
      onRefresh: _logUnsupportedAccess,
      refreshLogSource: 'PaymentMonitor',
      refreshLogContext: () => {
        'platform': defaultTargetPlatform.name,
        'isWeb': kIsWeb,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
