import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/widgets/app_layout.dart';
import '../../../../app/widgets/app_state_widgets.dart';
import '../../../../app/widgets/gradient_header.dart';
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
    return Scaffold(
      appBar: const GradientHeader(
        title: 'Theo d\u00F5i ti\u1EC1n v\u00E0o',
        showBack: true,
      ),
      body: SafeArea(
        child: AppResponsiveScrollView(
          maxWidth: AppLayoutTokens.formMaxWidth,
          child: AppStatePanel(
            icon: Icons.desktop_windows_outlined,
            title: 'Ch\u1EC9 h\u1ED7 tr\u1EE3 Windows',
            message:
                'T\u00EDnh n\u0103ng theo d\u00F5i ti\u1EC1n v\u00E0o c\u1EA7n m\u00E1y Windows \u0111\u1EC3 ph\u00E1t \u00E2m thanh v\u00E0 gi\u1EEF phi\u00EAn c\u1EADp nh\u1EADt \u1ED5n \u0111\u1ECBnh.',
            tone: AppStateTone.warning,
            actionLabel: 'V\u1EC1 trang ch\u1EE7',
            actionIcon: Icons.home_rounded,
            onAction: () => context.go('/home'),
          ),
        ),
      ),
    );
  }
}
